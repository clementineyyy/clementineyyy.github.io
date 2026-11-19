---
layout: post
title: Claude Code工具调用源码深入解析
date: 2026-11-13 15:29:00
description: 本文结合Claude Code源码，详细分析了Claude Code工具调用的方案设计、选择理由和实现细节。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了本文结合Claude Code源码，详细分析了Claude Code工具调用的方案设计、选择理由和实现细节。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

---
# 三大类工具
## 跑在客户端上的工具
需要客户端来控制循环，每一次工具调用都是一次循环：模型请求调用工具、客户端执行工具、客户端返回工具调用结果、模型继续处理。

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/toolLoop.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    工具调用循环的最经典范式。当stop_reason是tool_use时，继续循环调用工具；当stop_reason是其他原因时，退出循环，由客户端处理成功 (如果stop_reason是end_turn)/报错逻辑
</div>

### 1. 用户定义的工具
对于特定应用的逻辑&专有数据，用户自己写工具定义、工具执行步骤并且返回结果。

工具定义：在API请求的顶层参数tools字段中指定

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/claudeTool.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    用户自定义的工具的定义，包括一些<a href="https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-reference#tool-definition-properties" target="_blank" rel="noopener noreferrer">可选属性</a>
</div>

[工具定义最佳实践](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#best-practices-for-tool-definitions)


#### Anthropic tool runner (SDK)
使用[tool runner](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-runner)~~不再需要手写循环：调用API、检查stop_reason、执行工具调用、append追加工具调用结果、重复~~。tool runner将每个工具定义为一个函数，把消息传给client.beta.messages.tool_runner() (client就是LLM API)，在循环结束后把最终消息返回给客户端。错误处理、结果格式化、上下文消息管理都由tool runner来处理


### 2. Anthropic模式工具
对于常见操作&标准的桌面操作，比如管理剪贴板信息、执行shell命令、编辑文件、控制机器或浏览器等，Anthropic提供了工具定义，但仍由客户端来执行工具

相比于使用用户自定义的同等功能的工具，使用Anthropic模式工具的好处在于：这些工具定义已经被内化到Claude模型中了。Claude模型在这些工具上被优化训练了很多次，所以可以更可靠地调用这些工具、并从错误中恢复

[client toolsets](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-reference#client-toolsets)包括computer use tool和browser use tool：tools中的一个入口声明了固定的一系列工具，这些工具的名称、描述和参数由Anthropic定义，由客户端执行工具调用
* 该入口没有name，因为日期标志的type字段固定了成员名称；其他参数如configs、cache_control和allowed_callers (只接受direct)都是可选的
* configs字段调整每个工具成员：
  * 键key是工具成员的名称，值value只接受enable和defer_loading两个字段
  * 省略的成员保持默认值
  * 未知的成员名称或成员值中的任何其他字段都会被拒绝，禁用所有成员的configs也会被拒绝 (需要改为省略该条目)
  * 被禁用的成员会从Claude接收的工具中移除。如果Claude仍然指名调用它，需要返回一个名为tool_result的错误
* 需要为每一个成员工具设置defer_loading并给每个启用的成员工具相同的值，而不是在入口设置：在工具搜索时，工具集作为一个定义进行加载和展开；当所有启用的成员都延迟加载时，只有本身未被延迟的工具搜索tool_search工具才能呈现该工具集，因此需要在同一请求中声明一个tool_search工具
* 如何处理成员工具的调用：tool_use block中的name字段是成员工具的名称，toolset_name字段是computer或者browser，input字段是成员工具的参数

## 3. 跑在服务器上的工具
对于web_search，web_fetch，code_execution和tool_search，由Anthropic服务器来执行工具调用循环，客户端直接得到结果。客户端一个请求可能导致好几个服务器工具调用，但是服务器工具调用循环是有迭代次数限制的。当模型达到迭代次数限制但是还没有结束循环时，服务器会返回stop_reason: "pause_turn" (意味着工作未完成)而不是"end_turn"，让模型继续处理


# 怎么暴露工具？
取出当前环境下理论上可能出现的全部工具全集，经规则过滤之后将工具子集放入本turn发给LLM的请求体的tools字段中。请求体的tools字段装的是每一个已入选工具的完整schema (name+description+完整的input_schema本质上是该工具的调用参数parameters，src/Tool.ts中Tool接口的绝大部分方法，是Claude Code客户端本地框架内部使用的运行时协议，不会发送给LLM，LLM也完全看不到)

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/available.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    发送给LLM的tools参数中只有name+description+parameters，其他方法只和工具自己本身执行相关，不在LLM调用请求考虑范围内
</div>

## 机制：工具搜索<mark>延迟加载</mark>ToolSearchTool
文件：src/services/api/claude.ts，line 1154-1174
参考文献：[Claude code的tool search tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)

1\. 每次turn的请求体里：
Initially, Claude’s context contains only the tool search tool and any non-deferred tools.

✅ 非deferred工具：都在，带完整schema

✅ ToolSearchTool：在，带完整schema，所以可以发现更多工具

✅ 发现的deferred工具 (defer_loading: true)：都在，带完整schema，所以是延迟加载

❌ 未发现的deferred工具 (defer_loading: true)：不在请求体里，模型完全不可见

2\. 模型调用ToolSearchTool想要的工具，服务端返回包含tool_reference块的结果，这些会被记录进消息历史，在下一次submitMessage时 (依然在同一个turn内，因为是while循环loop，终止了才返回给用户回答)同样经过step1的处理，搜索到的工具就出现在请求体里了，模型就能看到它的完整定义并调用

3\. 如果不使用ToolSearchTool，那么没有被权限或其他前置过滤逻辑排除的deferred工具直接出现在请求体中 (else部分的逻辑)$\rightarrow$所以启用ToolSearchTool的作用是延迟加载deferred工具，避免一次性把所有工具都塞进prompt消耗token

### 如何使用tool_search来进行semantic search语义搜索 {#semanticSearch}
工作原理：比较文本的含义，~~而不是只是搜索关键词~~，因此需要将每个工具的定义 (包括名称、描述、参数)变成一个embedding向量，从而捕捉到它的语义信息。如果两个文本有相似的含义，那么它们的embedding向量在向量空间中会很接近，用余弦相似度来衡量相似程度

step1. 把以结构化JSON格式表示的每个工具的定义 (包括名称、描述、参数)变成一个人类可读的文本表示形式

step2. 使用SentenceTransformer's all-MiniLM-L6-v2 model或其他模型，将这些文本转换为embedding向量

step3. 开始语义搜索。先把LLM以自然语言表示的搜索请求 (比如"I need to check the weather" or "calculate investment returns" )映射到相同的向量空间，再计算请求向量和每个工具向量之间的余弦相似度，排序之后选出最相关的Top-N个工具

## 与codex不同
codex在普通模式下，如果不使用tool_search，模型永远只能看到和调用Direct/DirectModelOnly级别的工具

# 如何判断是否调用工具、调用哪个工具？
一句话总结：由LLM自己决定是否调用工具以及调用哪个工具 (Claude Code会根据任务决定使用哪种工具，这是模型在训练的时候学习到的模式，不存在硬编码的路由)+参数tool_choice和系统提示词的限制

使用可选参数tool_choice：tool_choice中的type字段由程序员决定 (auto放权给LLM、any和tool强制必须使用工具、none强制不使用工具)，不是由LLM决定的。如果不传，默认就是{"type": "auto"}，意味着由模型自己决定：是否要调用工具 (如果请求和某个工具描述的能力相匹配、并且答案不在上下文中)还是直接回复、调用哪个工具、工具参数填什么

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/whentool.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/toolchoice.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    Claude Code的tool_choice参数可以调整LLM调用工具的时机。不过并不是所有模型都支持tool_choice参数中的any和tool选项
</div>

当tool_choice是any或者tool时，需要注意：
* 模型在使用工具前不会输出自然语言回复或解释，尽管模型被显式要求解释。这不会导致模型表现下降，但如果你希望模型在提供自然语言解释的同时使用特定工具，可以设置tool_choice为默认的{"type": "auto"}，并在用户提示词中加入明确指令。比如"What's the weather like in London? Use the get_weather tool in your response."
* 强制工具调用也会导致模型跳过思考。模型输出以tool_use block开始，并且没有thinking block。如果想让模型在调用工具之前思考，也是设置tool_choice为默认的{"type": "auto"}，并在用户提示词中加入明确指令。

也可以由系统提示词来控制模型的工具调用。比如在系统提示词中明确指出"Use the tools to investigate before responding."、"Always call a tool first before responding."

PS. 当在Claude API中调用工具的时候，API会根据工具定义、工具参数和用户特定的系统提示此来构建一个特殊的[系统提示词](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#tool-use-system-prompt)，让模型使用指定工具并提供合适的上下文让工具正确调用

# 如何并行工具调用
## 是否并行-由LLM决定
* 可以在系统提示词和用户提示词中让模型使用并行工具调用，以提升效率
* 也可以[设置tool_choice对象中的disable_parallel_tool_use字段](https://platform.claude.com/docs/en/agents-and-tools/tool-use/parallel-tool-use#disable-parallel-tool-use)
* 每个工具都有一个isConcurrencySafe(input)方法，默认返回false，表示是否允许并行字段。在运行时传入本次工具调用的input来动态判断，据此将同一次模型请求中的工具分批次地分别放入并发分组和串行分组：
  * 相邻的并发安全工具合并成一批batch并发执行，一旦遇到非并发安全工具或中间断开，就新建一个batch；而且并发批次内的工具执行后对会话上下文的修改contextModifier不会立即生效，而是等整个并发批次全部结束后再按顺序应用，这样并发工具之间不会互相干扰上下文；并发可以减少等待时间 (比如同时读多个文件、同时grep/glob)
  * 非并发安全工具每个独占一个batch串行执行 (每个工具必须等上一个完成，一个工具就是一个batch)；避免竞态条件和上下文污染 (比如一个工具改写了文件，另一个工具紧接着读同一个文件，必须按顺序)
  * 批次batch之间也是串行顺序处理的

如果在并行工具调用时，前置工具调用未完成，可以返回is_error字段为true，并用自然语言说明，Claude可以在下一轮中重新解决工具调用问题。为了减少有依赖关系的工具调用一起出现，可以在系统提示词中加入“Only batch tool calls that are independent of each other.”

## 具体实现并行 {#sync}
由Python中的asyncio.gather或JavaScript中的Promise.all来控制

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/ccSync.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/syncDiff.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    asyncio.gather和Promise.all的逻辑；以及它们和codex读写锁的区别
</div>


# Claude code的PTC
[Programmatic tool calling文档](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling)

在code execution容器中写代码，以程序化的方式调用工具

## 怎么实现PTC
step1. 在工具定义中加入allowed_callers:["code_execution_XXX"]，让工具在code execution中可以被调用

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/allowedCallers.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    allowed_callers字段具体定义
</div>

step2. Claude编写代码来调用工具

step3. 把完整的上下文历史信息和工具调用结果发给Claude
注意：携带工具调用结果的user message只能包含tool_result block；传递容器container的ID，否则会被API拒绝；发送和初始原始请求一模一样的tools array，这样才能继续运行暂停的代码

step4. 程序从暂停的地方开始继续执行、处理结果；后续也可以再次暂停程序来执行tool_use block，也可以完成code execution代码执行过程并让Claude继续这个turn (可以根据stop_reason字段来判断当前属于哪种情况)

step5. code execution代码执行过程结束，Claude提供最终回复

# MCP扩展




# 安全机制
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/buildTool.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    buildTool()的默认值策略
</div>

## 是否允许工具执行Tool Permission (应用层逻辑拦截)
文件：src/services/tools/toolExecution.ts的checkPermissionsAndCallTool函数中

step1. Zod schema校验tool.inputSchema.safeParse：硬约束参数类型，这一步只负责“类型是否对”，不负责“值是否合理”。如果失败不会退出系统，而是把错误栈封装成tool_result (is_error: true)返回给 LLM，让模型自行纠正后重试

step2. 每个工具可自行实现独立语义校验validateInput()：即使符合schema，还要确保语义正确。比如FileEditTool要检查新旧字符串是否相等、是否碰到了黑名单目录，FileReadTool要检查文件路径、页码合法性等。若返回result === false，同样返回错误tool_result给LLM重试，不继续执行

step3. Backfill隐式派生依赖：向输入结构深度注射诸如expandPath()类似的钩子依赖，供后续Hooks和canUseTool做安全审计审查。但不改变最终传给tool.call()的输入

step4. PreToolUse Hooks是工具执行之前的自定义拦截点：它既可以修改输入passthrough；也可以直接做权限决策：allow批准执行/deny拒绝工具执行/ask需要用户交互确认，弹出dialog展示给用户，用户手动选择是否允许 (Hook的结果仍受系统settings.json规则约束)；还可以直接叫停工具执行stop。如果拦截发生，程序将停止向该工具发起调用，转向构建并返回异常的UI卡片消息

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/toolHook.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/hook2setting.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    Hook可产生的动作；系统settings.json规则 (denyList/askList+工具自身checkPermissions)是底线，Hook不能绕过这些强制规则，它们分层、共同保证了安全
</div>

## 工具执行环境Sandbox (系统级隔离)
### 什么是沙箱Sandbox？
沙箱对于文件路径和网络域名分别构建白名单和黑名单，圈定了LLM可以直接访问操作的路径
* 白名单：直接写入本地
* 黑名单：在沙箱内表现为只读或不可见，沙箱内的写入要么失败，要么写入临时层 (不反映到宿主)；如~/.claude/settings.json (主配置不被篡改)、.claude/skills技能目录、当前工作目录的.claude/设置文件

默认不把所有工具调用强制放在沙箱里。沙箱是可选的、仅针对部分工具 (主要是Bash/PowerShell)，且默认处于关闭状态。文件写入工具 (FileEditTool等)完全不经过沙箱，直接操作真实本地文件

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/sandbox.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    什么是沙箱sandbox以及claude code的沙箱隔离策略
</div>


# 参考文献
1. [Claude Platform Docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview)
2. [Claude Cookbook：Tool search with embeddings](https://platform.claude.com/cookbook/tool-use-tool-search-with-embeddings)
3. [Github上的claude-code-analysis仓库](https://github.com/liuup/claude-code-analysis/blob/main/analysis/04b-tool-call-implementation.md)