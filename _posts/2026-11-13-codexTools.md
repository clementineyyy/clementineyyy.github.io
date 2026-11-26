---
layout: post
title: Codex工具调用&skills源码深入解析
date: 2026-11-13 15:29:00
description: 本文结合codex源码，详细分析了codex工具调用的方案设计、选择理由和实现细节。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了本文结合codex源码，详细分析了codex工具调用&skills的方案设计、选择理由和实现细节。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

---
# 工具定义
文件：codex-rs/tools/src/tool_spec.rs，line 25-67，ToolSpec告诉模型这个工具叫什么、接受什么参数、返回什么。5种变体：function/namespace/tool_search/web_search/custom
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/toolDefine.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    源代码中并不是每个工具都有name、description、parameters等字段的原因
</div>

# 工具分类
文件：codex-rs/tools/src/tool_executor.rs，line 53-82，定义ToolExposure包含以下几种类型
核心思想：并不是所有注册的工具都会直接发给模型，ToolExposure是一个开关：
  * Direct / DirectModelOnly → 模型一开口就能看
  * Deferred / DeferredModelOnly → 模型得先搜索才能发现
  * CodeModeOnly / Hidden → 模型在普通对话中完全看不到，在[PTC/CodeMode](https://clementineyyy.github.io/blog/2026/toolCalling/)中被调用

几种工具的区别和使用场景见下面的分析

# 怎么暴露工具？
<mark>一句话总结：请求体tools字段存储模型直接可见的工具，若需要调用其他工具，则采用tool_search工具来搜索发现</mark>

## 模型可见工具model_visible_specs
文件：codex-rs/core/src/tools/spec_plan.rs，line 662-700
* 遍历注册表里的每一个工具，只保留Direct/DirectModelOnly模型可见级别的工具，跳过不直接可见的工具
* 对每个保留的工具，根据代码模式等条件，可能增强它的规范 (比如加上代码模式专用的参数schema)
* 把“托管工具”(hosted specs，如web search)也加进来，并把同名命名空间的工具合并

## 增量工具模式 VS 普通模式
只对Responses Lite协议模型 (OpenAI提供的一种轻量版Responses API协议变体) 和Amazon Bedrock模型生效，且还受配置开关控制，因此一般情况下不触发增量工具模式
* 整体逻辑：&#x2b50;核心文件：codex-rs/core/src/session/turn.rs，line 1842-1885，构建Prompt决定本次turn的tools列表

| 模式 | 暴露给模型的工具 |
| :---: | :---: |
| 增量模式 | 在所有模型可见工具规范model_visible_specs()中只保留暴露WebSearch工具。只有WebSearch工具始终作为role: "developer"的AdditionalTools项新增插到input数组开头，其他工具都不可见、不可调用 |
| 普通模式 (默认) | 暴露所有模型可见工具规范tool_router.model_visible_specs()返回的所有工具，即irect/DirectModelOnly模型可见级别的工具，一次性全部发给模型 |

* 具体实现细节：文件：codex-rs/core/src/session/world_state.rs，line 61-77，什么是增量模式？$\rightarrow$不再每次turn都重新发完整工具列表，而是只在第一次发完整，之后只发增量 (新增/变更的工具)；如果工具没变，后续请求就不需要重复下发，这样可以节省token
* 关于其他类型的工具：都只能在普通模式下被调用
  * Deferred/DeferredModelOnly工具不在初始工具列表里。但如果模型可见列表model_visible_specs里包含tool_search工具，那么模型可以先调用tool_search去搜索这些延迟工具，发现后再调用。这是一种<mark>按需搜索发现</mark>的机制，避免一次性把几百个工具都塞进prompt消耗token。适合工具数量庞大、大部分时间用不到的场景。(文件：codex-rs/core/src/tools/router.rs，line 211-245)
  * CodeModeOnly：只在代码模式嵌套调用 ([PTC/CodeMode](https://clementineyyy.github.io/blog/2026/toolCalling/))中可见，不在初始列表，不对普通对话模型暴露。这适合那些只应该在代码执行环境内部被调用、不应该直接暴露给模型主动调用的工具。(文件： codex-rs/core/src/tools/spec_plan.rs，line 702-730)
  * Hidden：对模型完全不可见，模型无法直接调用，但它仍然被注册在ToolRegistry里，可被注册表分发 (比如作为某个父工具的子步骤、后台任务、或系统级内部操作)。它的存在是为了让工具能被调度和执行，而不需要模型知道它。适合系统级后台任务、父工具的子步骤、或不希望模型感知的内部操作

## Responses Lite协议 VS 普通协议
把Prompt转成发给模型的API请求ResponsesApiRequest
文件：codex-rs/core/src/client.rs，line 1200-1216，根据模型使用的协议不同tools的放置位置不同：
* 请求顶部：HTTP请求JSON体，即ResponsesApiRequest的顶层字段。文件：codex-rs/core/src/client.rs，line 1298-1321
* input数组：完整的对话历史快照，包含系统指令、用户消息、模型回复、工具调用记录、工具输出等所有类型的条目

incremental_tools (是否增量模式)和use_responses_lite (是否使用Lite协议)是两个独立的维度，四种组合都有可能。但是<mark>默认使用普通模式+普通协议，模型可以直接看到并调用所有可见的Direct工具，再通过tool_search工具调用Deferred/DeferredModelOnly工具</mark>

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/default.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    codex默认工具调用步骤流程
</div>

* Responses Lite协议：<mark>工具定义 (name、description、parameters等)</mark>不放在请求顶部tools字段 (tools字段始终为None)，而是作为一条role: "developer"的AdditionalTypes历史项塞进input数组。作用是符合OpenAI Responses Lite协议的要求。缺点是不支持并行工具调用，模型一次只能调用一个工具
* 普通协议 (默认)：<mark>工具定义 (name、description、parameters等)</mark>直接作为HTTP请求的顶级tools字段，一次性发给模型，每次请求都带上完整工具列表

## tool_search工具搜索机制
### 使用条件
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/toolsearch.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    使用tool_search工具所必须满足的条件
</div>
在普通模式下，如果不使用tool_search，模型永远只能看到和调用Direct/DirectModelOnly级别的工具。[与Claude Code的不同](#diff)

### tool_search过程
1. 搜索：self.search(query, limit)会根据模型指定的文本查询关键词query，(基于BM25算法)在注册表中查找所有符合条件的Deferred/DeferredModelOnly工具，返回最多limit个工具的完整定义，包括名称、描述、参数Schema等
2. 处理：搜索到的工具定义LoadableToolSpec被序列化为JSON，放入ResponseItem::ToolSearchOutput中，作为一次工具调用的输出加入对话历史
3. 调用：在同一个turn的while循环中，模型会读取input 数组里的tool_search_output消息，里面包含了搜索到的工具完整定义 (名称、描述、参数Schema)。模型基于这些信息，可以输出针对这些工具的调用。(搜索到的工具只以tool_search_output历史消息的形式存在，不会出现在HTTP请求顶层的tools字段，也不会出现在input的AdditionalTools项中)

### 与Claude Code不同 {#diff}
如果不使用tool_search，Claude Code的deferred工具直接出现在请求体中，依然可以被LLM调用

# 如何判断是否调用工具、调用哪个工具？
由LLM自己决定是否调用工具以及调用哪个工具+参数tool_choice+系统提示词的限制

# 如何判断工具能否真正执行？
agent可以在可用工具列表中看见某个工具，也能生成对它的调用请求；但在实际执行时，会被<mark>Guardian策略审批和用户交互式审批</mark>拦截。若权限/风险评分不足，或用户未批准 (比如文件修改和命令执行工具)，工具不会被真正执行，而是标记为Declined拒绝执行/Failed超时不执行，或进入等待用户通过thread/approveGuardianDeniedAction批准的状态，只有Approved状态的工具才会被真正执行

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/checkTools.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    需要经过以上两种审批批准后才能执行的工具
</div>

根据当前策略判断是否需要审批之后，再选择合适的<mark>沙箱</mark>方式运行。审批回答“这个动作要不要额外获得许可” (用户批准某个动作，不代表进程自动获得无限资源)，沙箱限制“进程能够接触哪些资源”

# 返回工具调用结果
因为<mark>工具调用结果放在上下文中才能被LLM看到</mark>，~~不是直接把工具调用结果返回给LLM~~，所以要限制每次工具结果的长度，避免一份特别长的工具调用结果就占掉大量上下文空间：
* 单个工具结果限制：工具结果写进模型返回请求体时，立即应用限长策略裁剪；把字节/token预算平分给左右两端，<mark>两头都保留、中间截断</mark>，最终输出格式：头部prefix+截断标记marker+尾部suffix；<mark>LLM后续请求再也无法通过常规历史看到完整原始结果</mark>，虽然rollout有更完整的版本，但是不会重新给LLM看到
* 单条消息聚合预算：每轮queryLoop开始时，当即将发送给模型的那条消息里的所有旧工具调用结果完整的序列化大小 (整个请求对象包括工具调用文本结果、系统指令、工具定义等一切字段的JSON字节数)的总和超过预算 (应$\neq 15MB$)时，会根据元数据 (1个工具调用结果对应1个tool_result_metadata，可存储如openai/resource_access资源访问证据、provider、工具结果来源如文件/MCP等主机侧记录的信息)大小从大到小排序、<mark>优先裁剪占用空间最大的若干个元数据条目 (不处理tool_result纯文本内容</mark>)，一旦聚合总和回到预算内，立即停止，不动剩下的小条目；以避免一个超大结果把其他小结果都挤掉
  * 针对元数据都很小、纯文本很大，总和超过15MB的情况，只尝试裁剪元数据，不动普通文本；如果元数据全部清空后，消息整体仍然>15MB因为纯文本本身就超了，直接发送请求给LLM，不再裁剪；清空元数据不影响LLM推理，因为LLM消费的是纯文本或多模态内容项中的工具调用结果，但元数据对系统层面有影响，用于资源访问证据、来源溯源、会话恢复、审计、Guardian审批展示等
* <mark>写入rollout的版本：不同截断阈值 (通常更宽松)，但也会截断</mark>；Rollout trace目录中的单独runtime_payload文件保留了完整的原始内容 



# codex如何并行工具调用？
ResponsesApiRequest请求中的parallel_tool_calls字段表示支持并行，模型自己决定一次回复里返回几个tool_calls (即是否并行)。但工具能否真正并行，还受每个工具的supports_parallel_tool_calls配置限制

## 具体实现并行
文件：codex-rs/core/src/tools/parallel.rs

每个tool call被tokio::spawn成独立异步任务，在不同的tokio task里并发调度，通过一个RwLock做并发管控，执行完释放锁，后续工具可进入 (工具能否并行，由工具注册时的声明决定，存在是否允许并行字段/方法)：

* 支持并行的工具：获取RwLock读锁；多个读锁可以同时存在，因此多个支持并行的工具可以真正并发执行
* 不支持并行的工具：获取RwLock写锁；写锁是独占的，该工具运行期间会阻塞其他所有工具 (读或写)，实现串行化

每个工具调用完成后，产生一个独立的ResponseItem::FunctionCallOutput或 CustomToolCallOutput，携带call_id关联之前的 FunctionCall。这些输出项被收集到input数组中 (不存在message和tool_result block的嵌套关系)，下一轮请求把整个input数组发回给模型。模型通过call_id把每个结果对应到之前的tool_call


# 长调用工具的交互
短工具调用可以一次等待结束，但是长工具调用需要在运行中观察新输出、与交互式进程继续通信，因此不能等到进程退出再返回
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/longrun.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    长工具调用的交互
</div>

# Skills
按需加载

## skills使用
skill的核心是SKILL.md，也可以携带脚本、参考资料、模板和其他资源；codex会根据SKILL.md中的description字段来判断什么时候应该使用skill，所以要写清skill做什么、什么时候用、产出什么

codex启动时先看每个skill的名称和描述，当用户任务与描述匹配，或者用户显式斜杠命令调用某个skill时，它才读取完整正文，正文里引用的长资料和脚本，也可以继续按需读取或执行

## 创建skills
Codex里内置了/skill-creator，加上用户提示词可以直接创建skill

## skills加载策略-上下文工程相关
* 单条skill结果限制：包括SKILL.md主要提示内容上限 (超出会截断并发出警告"Skill ... exceeded the main prompt context limit")、目录中技能描述上限、技能名称和路径上限
* 整份skill清单结果限制：有元数据预算 (占上下文窗口比例/token/字符)上限，超预算的skill会被省略，不进入模型可见清单
* 如果skill太多占满上下文窗口/放不下：按scope优先级排序 (system>admin>repo>user>none，优先级高的排在前面、优先保留)，先保留最小成本的无描述 (只有名称和定位符)条目，剩余预算按描述字符分配，超限不够描述的直接省略描述但保留名称、并在清单末尾提示省略数量
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/args.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    截断可配置选项参数
</div>


# MCP扩展



# 参考文献
1. [小林coding的Codex Harness架构图解](https://xiaolinnote.com/codex/source/codex_harness.html#_04-%E5%B7%A5%E5%85%B7%E8%B0%83%E7%94%A8%E6%80%8E%E4%B9%88%E6%89%A7%E8%A1%8C)