---
layout: post
title: 工具调用、Skills&MCP学习笔记
date: 2026-11-10 21:18:00
description: 本文整理了agent harness中工具调用的学习笔记。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了agent harness中工具调用tool call/function calling的学习笔记，便于读者将工业级工具调用知识应用到实际项目中。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

---

# 何时需要调用工具？
* 需要进行外部动作并且有产出：比如发邮件、写文件、上传一个记录，模型只能描述这些动作，但是只有工具才能执行动作
* 最新/外部数据：当前价格、今天天气、数据库的内容，任何训练数据之外的信息都需要一个工具来获取
* 结构化输出&使输出的形状有保证：比如需要有特定字段的JSON类来存储信息，而不是一大段文字，工具的参数Schema可以保证输出的结构化
* 和现实实体建立联系：数据库、内部API、文件系统，工具是自然语言请求和实现它们的系统之间的桥梁
* 不需要调用工具的情况：
  * 模型仅通过训练过程就可以回答：比如说总结、翻译、通识问题的回答不需要工具调用
  * 交互是一次性的Q&A，模型不需要有任何产出、也不需要执行/操作任何东西
  * 工具调用带来的延迟远远超过了一次回复的成本：每个工具调用都是一次额外的往返；对于轻量级任务，工具调用带来的开销可能超过任务本身

# 工具调用步骤
1. 定义与注入：应用将<mark>工具的名称、描述和参数Schema</mark>连同用户提示词一起，作为请求发送给模型
2. 模型决策与生成：模型分析上下文，判断是否需要调用工具。如果需要，它会<mark>生成一段结构化的调用指令tool_use block，明确指定要调用的工具名、唯一的id和对应的参数</mark>（例如 {"name": "get_weather", "arguments": {"city": "上海"}}）
3. 应用端执行：应用接收到这段tool_use指令后，解析出工具名和参数，然后在本地或通过API真正执行对应的函数或代码
4. 结果回传：应用将工具的执行结果作为一条新的消息<mark>tool_result block，追加回对话上下文中</mark> (在python中，上下文是一个list，所以直接append就可以；并且assistant的tool_use message和user返回tool_result message之间不可以插入任何其他信息，所以返回的user message中的其他文本信息必须放在所有tool_result的后面)；并且tool_result block中的tool_use_id需要和tool_use block中的id保持一致
5. 模型生成最终回答：模型看到工具返回的结果tool_result后，结合这个新信息，生成最终的自然语言回复给用户

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/flow.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    工具调用的基本流程，以ReActLoop为例。在工具调用前，LLM往往会先回复用户它正在干什么，所以LLM的输出内容中不止有text类型的block，还有tool_use类型的block。如果有多个独立的工具调用请求，那么LLM生成的回复中会包含多个tool_use block并被循环处理、保存调用结果，程序需要在一个user message中返回当前请求中所有工具调用的结果，而不能是在分别的user message中分开返回tool_result
</div>


# 工具如何暴露给LLM？

* 传统做法：全量注入，每次请求都会将所有工具定义序列化成文本，全量塞入每次请求。缺点：
  * token爆炸 (每轮对话固定多出几千token的开销)，成本增加
  * 占用大量上下文，导致上下文窗口不够，模型聪明程度降低
  * 工具选择准确率下降 (模型要在更长的清单里做匹配，注意力被稀释，选错、不选或“瞎选”的概率都会上升)
* 业界做法：
    * [工具检索Tool Search](#semanticSearch)：先用一个轻量级的检索步骤/检索工具 (结合关键词BM25&语义Embeddings或regex)，从全量工具库中筛选出最相关的Top-N候选工具，然后再把这Top-N个工具的定义交给模型做最终选择$\rightarrow$工具披露可以不是一次性配置：记录搜索命中率、最终调用率、误选率和工具描述占用的token之后，可以发现哪些工具应该默认出现并提供完整声明 (高频、低风险、输入稳定的工具)、哪些工具更适合按需加载 (低频、高风险、描述很长的工具)
    * 好处：节省上下文的消耗
    * 可改进空间：
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/improve.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    tool_search语义搜索的改进方向
</div>

## 使用tool_search来进行semantic search语义搜索 {#semanticSearch}
参考[Claude Cookbook：Tool search with embeddings](https://platform.claude.com/cookbook/tool-use-tool-search-with-embeddings)以及我的[Claude Code工具调用源码深入解析的怎么暴露工具-工具搜索延迟加载-semantic search部分](https://clementineyyy.github.io/blog/2026/claudecodeTools/)

# LLM如何判断是否调用工具、调用哪个工具？
见我的[Claude Code工具调用源码深入解析的如何判断是否调用工具、调用哪个工具部分](https://clementineyyy.github.io/blog/2026/claudecodeTools/)

# 如何判断工具能否真正执行？
见[Codex工具调用源码深入解析](https://clementineyyy.github.io/blog/2026/codexTools/)、[Claude Code工具调用源码深入解析](https://clementineyyy.github.io/blog/2026/claudecodeTools/)和[Pi Agent工具调用源码深入解析](https://clementineyyy.github.io/blog/2026/piTools/)的对应部分

# Skills

## 渐进式披露
将技能信息分为三个层次，智能体按需逐步加载，既确保必要时不遗漏细节，又避免一次性将过多内容塞入上下文窗口

step1. 元数据Metadata：每个技能都存放在一个独立的文件夹中，核心是一个名为SKILL.md的Markdown文件，这个文件必须以YAML格式的Frontmatter开头，定义技能的基本信息；当<mark>智能体启动时，它会扫描所有已安装的技能文件夹，仅读取每个SKILL.md的frontmatter部分，将这些元数据加载到系统提示词中；而MCP实现中，当客户端连接到一个服务器时，通常会通过tools/list请求获取所有可用工具的完整工具定义JSON Schema (一次性加载全部)</mark>

step2. 指令instructions：当智能体通过分析用户请求，判断某个技能与当前任务高度相关时，会读取该技能的完整SKILL.md文件内容，将详细的指令、注意事项、示例等加载到上下文中

step3. 脚本与参考Scripts&References：对于更复杂的技能，SKILL.md可以引用同一文件夹下的其他文件：脚本、配置文件、参考文档等，智能体仅在需要时才加载这些资源；这样设计的好处：
* 无限的知识容量：通过脚本和外部文件，技能可以"携带"远超上下文限制的知识。例如，一个数据分析技能可以附带一个1GB的数据文件和一个查询脚本，智能体通过执行脚本来访问数据，而无需将整个数据集加载到上下文中
* 确定性执行：复杂的计算、数据转换、格式解析等任务交给代码执行，避免了LLM生成过程中的不确定性和幻觉问题

## Skills撰写技巧
* 渐进式披露/按需读取：SKILL.md只写高频主干流程，把低频的、超长的细节拆到references目录，正文里留一句指路的话就行
* 如果skill里有一步是固定的机械操作，比如某种固定格式的转换，与其在正文里教模型“第一步第二步第三步”，不如直接写个脚本放进scripts目录，正文里一句“执行这个脚本”

## Skills VS MCP
两者是互补而非竞争关系：
* skill给的是领域专业知识和流程，提供了操作手册或SOP (标准作业程序)，教导智能体在特定场景下如何正确组合使用这些工具、告诉LLM该怎么做
* MCP给的是工具：提供标准化的访问接口，让智能体能够够得着外部世界的数据和工具
* 两者的加载方式也不同：读取每个SKILL.md的frontmatter部分，将这些元数据加载到系统提示词中 (按需加载)；而MCP实现中，当客户端连接到一个服务器时，通常会通过tools/list请求获取所有可用工具的完整工具定义JSON Schema (一次性加载全部)
* Skills和MCP组合架构的优势在于：
  * 关注点分离：MCP专注于能力，Skills专注于智慧
  * 成本优化：Skills渐进式加载大幅降低token消耗
  * 可维护性：业务逻辑Skills与基础设施MCP解耦
  * 复用性：同一个MCP服务器可以被多个Skills使用

# MCP扩展
MCP (Model Context Protocol)提供了一套统一的通信规则，让agent可以用相同的方式发现和调用不同的外部工具，~~而不需要每接入一个外部系统，都要单独定义工具说明、参数格式和返回结果~~；MCP (理解为充电转换器)给AI (理解为手机)和外部工具 (理解为各国不同型号电源)之间定一个统一的插口，工具方照着协议实现一个MCP Server，任何支持MCP的AI应用都能直接插上用，不用再各家单独适配；外部服务通过MCP告诉agent自己能提供什么数据和操作，agent再根据当前任务选择对应的能力

## 暴露工具
当客户端连接到一个服务器时，通常会通过tools/list请求<mark>获取所有可用工具的完整工具定义JSON Schema (一次性加载全部)</mark>


# 业界工具调用实践对比

相同点：
* 工具定义可见范围：LLM都会看到<mark>工具定义 (仅包括名称、描述、参数</mark>，由服务器端发给LLM)，这样才能写出包含name和parameters的tool_use block
* 工具并行执行：客户端允许并行执行之后，模型自己决定要不要并行 (这只是决定模型能否在一次回复里输出多个tool_use，只是允许模型并发提出多个工具调用，并不代表客户端一定会同时执行它们)；模型输出多个tool_use后，客户端在真正执行前，还会查每个工具的是否允许并行字段/方法 (堵死了任意调用的后患)
* LLM只能<mark>在上下文中看到工具调用结果</mark>，~~工具调用结果不是直接单独返回给LLM的~~

|  | Codex | Claude Code | Pi |
|:---:|:---:|:---:|:---:|
| 怎么暴露工具？ | 请求体tools字段存储模型直接可见的工具；若需要调用其他工具，则采用tool_search工具来搜索发现并保留工具定义在<u>input数组</u>中 | 请求体tools字段存储经规则过滤后模型可直接调用的工具；若需要调用其他工具，则采用<mark>延迟加载</mark>ToolSearchTool工具来搜索发现并将工具定义加入<u>请求体tools字段</u> | 根据一系列规则筛选工具，将其与system message累计的历史增量做差分增量声明，与历史system message总结出完整工具列表供LLM调用；LLM可工具搜索发现system message之外的工具并将其加入toolsAdded和<u>system message</u>中 |
| 决定是否调用工具、调用什么工具 | tool_choice参数+提示词+LLM自行判定 | tool_choice参数+提示词+LLM自行判定 | 提示词+LLM自行判定 |
| 工具可见但拒绝执行的拦截机制 | Guardian策略审批和用户交互式审批 | hasPermissionsToUseTool：运行时权限检查 | 默认不实现beforeToolCall钩子接口，需要开发者自行实现；因此默认工具一旦可见，模型就能看到并生成调用 |
| 工具并行执行的实现 | 实际由读写锁来控制 | 工具分成并行分组和串行分组，由Python中的asyncio.gather或JavaScript中的Promise.all来控制并行 | 任务调度器scheduler+allSettled连接策略等待全部完成才汇总返回+每个tool_call一个独立任务、独立运行 |
| 工具调用结果返回截断方式 | 单个工具结果限制+单条消息聚合预算 (只针对元数据) | 单个工具结果限制+单条消息聚合预算 (针对完整工具调用结果) | 无 |
| 工具调用结果返回截断持久化存储 | rollout保存到工具调用结果也经过截断，但比返回给LLM的截断规则更宽松 | transcript保留的工具调用结果和发给LLM的请求体记录的工具调用结果一致 | 无 | 
| 工具调用结果返回形式 | 每个工具调用完成后，产生一个独立的ResponseItem::FunctionCallOutput追加到input数组后面返回给LLM (不会嵌套在一个返回消息中)；工具调用结果的顺序和工具调用请求的顺序保持一致 (FuturesOrdered保证) | <u>多个tool_result block存放在同一个message中</u>，添加到上下文后面返回给LLM；<u>工具调用结果的顺序和工具调用请求的顺序不必保持一致</u> | 工具调用结果按照toolCallId调用的顺序，独立追加在上下文后面 (不会嵌套在一个返回消息中)，即<u>工具调用结果的顺序和工具调用请求的顺序保持一致</u> |


具体见[Codex工具调用源码深入解析](https://clementineyyy.github.io/blog/2026/codexTools/)、[Claude Code工具调用源码深入解析](https://clementineyyy.github.io/blog/2026/claudecodeTools/)和[Pi Agent工具调用源码深入解析](https://clementineyyy.github.io/blog/2026/piTools/)

# 进阶：程序化工具调用PTC
本段落参考[Henry Li的文章](https://my.feishu.cn/wiki/CYANw7pSNiEhVckqaNXcCS8inAh)，并加以个人理解、分析、整理汇总


## 什么是PTC？
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/vs.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    ReActLoop VS CodeActLoop
</div>

ReActLoop流程：
* 模型读取用户请求，选择一个tool，等待结果，把结果放进下一轮context，再选择下一个tool
* 适用场景：
  * 每一步都需要模型重新根据前一步判断/思考的任务，因为每个结果都会改变下一步的语义判断
  * 每次把调用展示给用户

PTC流程：用程序编排工具调用
* 模型自己生成一段程序 (~~不是程序员自己设定好的程序~~)，程序在受控运行时可以并行调用多个Tool；当调用工具时，暂停code execution、API返回一个tool_use block；工具执行、返回工具调用结果、code execution继续。程序把中间结果留在自己的执行环境中，在本地完成过滤、聚合和排序，压缩后只返回一份经过筛选的结构化结果
* 适用场景：步骤很多、多工具调用、控制流却很稳定且清晰的任务 (在这种情况下如果依然使用ReActLoop，模型每次都要重新判断下一步要调用哪个工具，会把大量中间结果送进context window，并且错误地把本来由程序完成的判断交给了模型)
  * 数据计算与数据分析：比如计算一组指标 (模型可以直接在文本里计算，但设计大量大数据时，代码更适合做精细运算、分组、排序和校验，避免大数据很快达到模型上下文窗口)
  * 并行查询多个信息源，再合并同一组字段：比如读取多个文件后生成一份表格 (需要查询多个来源时，程序可以同时发起请求；某个来源失败，程序可以记录错误并继续处理其他来源)
  * 对列表做去重、排序、过滤和分页 (ReActLoop可能让模型反复读取文件、解释每一段结果、再请求下一步处理，但PTC可以先调用读取工具，把数据交给程序完成字段统一、分组和异常筛选，只把异常行和必要的统计值交给模型)
  * 按固定先后顺序调用多个tool，并对暂时性错误做有限重试
  * 将稳定的HTML、Markdown或JSON模板填入新数据
* 好处：
  * (核心收益&#x2b50;) 中间结果留在程序里：大量原始搜索结果、表格行和重复字段不必全部进入模型上下文context，减少了中间往返、中间数据处理、上下文搬运带来的token消耗和多工具调用的端到端延迟 (工具调用次数本身并不一定减少)
  * 并发关系变得明确：避免顺序执行带来的额外不必要等待
  * 数据变换更稳定准确：数据处理步骤可以写成代码
  * 错误处理有了固定位置：代码可以区分超市、空结果、部分失败和权限错误等，再决定重试、降级还是交给模型判断
  * 执行过程可以回放：代码、工具参数、返回结果和版本都能记录，出现问题时可以重放同一条路径

## 怎么做PTC？特别适用Personal Agent
针对每天都会发生、每次又有一点变化的工作$\rightarrow$下一次遇到相似任务时，直接复用代码/作为新的轨迹样本继续改进

## 步骤
1. [类似我的Ai Coding文章中的观点](https://clementineyyy.github.io/blog/2026/aicodingMethodology/#%E4%BB%80%E4%B9%88%E9%97%AE%E9%A2%98%E6%83%85%E5%86%B5%E4%B8%8B%E4%BD%BF%E7%94%A8aillm)：将大任务分解为若干个小任务，把可预测、有固定处理逻辑的部分交给代码完成
2. PTC执行留下的轨迹/日志记录，作为RSI (Recursive Self-Improvement递归自我改进)的输入：先收集证据，再生成候选改动 (比如合并经常一起出现、输入输出边界相同且稳定的代码为一个工具)，使用历史输入回放，最后用evals和小范围发布确认改动提升了质量

## 参考架构
pi-codemode



# 参考文献
1. [工具调用菜鸟教程](https://www.runoob.com/ai-agent/ai-agent-function-calling.html)
2. [工具调用github仓库教程](https://github.com/didilili/ai-agents-from-zero/blob/main/17-Tools%E5%B7%A5%E5%85%B7%E8%B0%83%E7%94%A8.md#17---tools-%E5%B7%A5%E5%85%B7%E8%B0%83%E7%94%A8)
3. [codex源码](https://github.com/openai/codex)
4. [一文读懂OpenAI Codex源码的原理、架构与未来](https://www.cnblogs.com/smartloli/p/20684447)
5. [小林coding解读Codex](https://xiaolinnote.com/codex/source/codex_harness.html)
6. [PTC参考Henry Li的文章](https://my.feishu.cn/wiki/CYANw7pSNiEhVckqaNXcCS8inAh)
7. [Claude Cookbook：Tool search with embeddings](https://platform.claude.com/cookbook/tool-use-tool-search-with-embeddings)
8. [Claude Platform Docs的Tools部分](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview)
9. [DataWhale的Hello-Agents笔记](https://github.com/datawhalechina/hello-agents/blob/main/Extra-Chapter/Extra05-AgentSkills%E8%A7%A3%E8%AF%BB.md#agent-skills-%E4%B8%8E-mcp%E6%99%BA%E8%83%BD%E4%BD%93%E8%83%BD%E5%8A%9B%E6%89%A9%E5%B1%95%E7%9A%84%E4%B8%A4%E7%A7%8D%E8%8C%83%E5%BC%8F)