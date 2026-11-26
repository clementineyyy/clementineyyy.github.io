---
layout: post
title: Claude Code系统架构、上下文管理和记忆系统深入解析
date: 2026-11-17 13:54:00
description: 本文结合Claude Code源码，详细分析了Claude Code系统架构、上下文管理和记忆系统的方案设计、选择理由和实现细节。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了本文结合Claude Code源码，详细分析了Claude Code系统架构、上下文管理和记忆系统的方案设计、选择理由和实现细节。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

---

# Agent Loop系统核心主循环
文件：src/query.ts

Claude Code主要是CLI界面，~~没有默认常驻的app server~~，用户请求直接进入核心处理逻辑 (但它也提供了一个可选的HTTP session server可以从外部客户端接受消息，需要显式启动)

loop的关键设计原则是不包含任何业务逻辑，它不知道怎么读文件、怎么改代码、怎么搜索，这些全是工具层的事。引擎层只做三件事：第一，协调，把用户输入、系统指令、历史对话拼在一起，发给大模型；第二，分发，大模型说"我要用某个工具"时，找到对应的工具并执行；第三，决策，根据大模型的返回决定是继续循环还是结束对话。这种设计的好处是：新增能力只需要新增一个工具，循环完全不用改

## 进入循环前的消息
使用<mark>统一的命令队列 (按优先级和FIFO顺序)来承载所有用户输入</mark>：当用户在当前query还没结束时又发来新消息，新消息会被enqueue到队列中等待 (队列优先级：now: 0最高、立即中断当前操作，默认next: 1次高、本轮循环turn结束后处理，later: 2最低、系统通知类)，或者在满足条件时 (如果当前有可中断的工具调用或者新消息优先级为now)<mark>立即中断当前query并优先处理新消息 (是否立即停止取决于工具自身实现，如果工具不配合中断，新消息确实只能在命令队列中等到本轮query循环结束后才处理</mark>)；消息在进入agent loop之前需要经过以下几层处理：

step1. ask：SDK一次性调用的便捷入口，负责接收用户请求、触发处理流程、返回最终结果，在内部新建一个QueryEngine实例

step2. QueryEngine：管这次对话的会话状态 (包括处理斜杠/命令、组装系统提示、注入上下文等)，维护这次对话的消息历史、文件缓存、权限拒绝记录这些跨轮持久化的状态

step3. query：流式包装层/异步生成器，它会一边干活一边吐结果 (流式对外输出)，每完成一件事就立刻把结果抛出去给外面用 (普通函数是干完所有事情、最后一次性return一个结果)，好处就是模型每吐出一个字符、每跑完一个工具，立刻就能流出来给你看，~~不用等模型处理完答案之后一次性才能看到~~

step4. queryLoop真正的循环：准备消息 → 调模型 (流式接收的，模型每吐出一小段内容 (可能是几个字符)，主循环立刻就能拿到，收到的是文字块/tool_use块的一部分；主循环一边收，一边干两件事：<mark>把文字块往上抛出去、让用户能即时看到模型在打字，把tool_use块攒起来准备等会儿执行</mark>) → 判断 → <mark>执行所有工具 (模型还在吐字、工具就开跑了：模型一边流式输出，主循环就一边监听；一旦识别出一个完整的tool_use块，立刻把它丢给后台开始执行，不等模型流完；等模型流完，最早开始执行的那个工具，可能已经回结果了)</mark> → 塞回结果





## ReAct VS Tool-use Loop
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/react.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/toolUseLoop.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/reactVStooluse.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    ReAct和Tool-use Loop的区别
</div>

ReAct Loop: Thought-Action-Observation三步循环
* 模型在每一轮都会先输出一段思考 (有显式的思考过程，引导模型一步步推理)，然后再选择一个工具调用，最后拿到工具调用结果；循环直到模型认为任务完成
* 问题：
  * token浪费：每一轮都要输出一段Thought文本，这些文本要作为上下文的一部分发给API，占用了宝贵的上下文窗口、浪费token。对于编程Agent来说，一次任务可能循环50轮，每轮都写一段“我打算先读取……然后分析……”的思考过程，加起来就是好几万token的浪费
  * 应用层代码太复杂：你需要解析模型的输出，区分哪部分是Thought、哪部分是Action，然后提取Action调用工具，再把Observation拼回去。这个解析过程写起来很麻烦，而且很容易出bug，因为模型输出的格式不一定标准，一崩就全崩了
  * ReAct是为推理能力有限的弱模型设计的：当大模型的推理能力不够强时，用显式的Thought来强迫它一步步思考是有意义的；但Claude Opus这种级别的模型，推理能力已经足够强了，它完全可以在内部完成推理，不需要在输出里显式写出每一步的思考过程

Tool-use Loop：LLM外面没有强制思考，信任模型的推理能力，保持应用层框架尽可能简单
* 模型在内部完成推理，不占用上下文空间，然后直接返回两种结果之一：tool_use工具调用和end_turn返回结果给用户
* 好处：
  * 模型驱动：Claude Code的推理优于手工编码的启发式方法
  * 灵活性：没有僵化的流程限制Claude Code能做的事情

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/benefit.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    claude code使用Tool-use Loop的好处
</div>

## 循环终止条件
<mark>LLM认为结束了，harness可以让它继续；LLM想继续，harness也可以让它停止</mark>：
* LLM输出tool_use会继续循环：表明<mark>本轮LLM请求了工具调用，并在本轮执行了工具调用，但工具调用是否成功未知，需要在下一轮循环查看上下文中的工具调用结果</mark>，会使needsFollowUp === true，继续循环在下一轮中查看工具调用结果；但可能遇上abort工具执行期间用户中断/系统中止、hook_stopped强制停止、max_turns达到最大轮数限制等退出条件从而退出循环，但这样会导致本次对话输出不完整，模型失去了在下一轮基于工具结果生成最终总结或答案的机会
* LLM输出非tool_use (非tool_use不代表循环可以直接结束)：queryLoop不会立即结束，它会进入一系列由queryLoop+Stop Hooks主导的额外检查 (若继续工具调用tool_use则无需这些检查)，这些检查<mark>可以强制继续循环</mark>或强制提前终止；循环的终止不仅由LLM决定，也由harness的Stop Hooks、Token Budget等机制共同决定；LLM只负责产生tool_use或非tool_use的信号，harness在收到非tool_use后，有最终否决权preventContinuation或强制继续权 (blockingErrors处理用户刚补充的要求或尚未处理的错误、token_budget_continuation当前轮次会话级token预算尚未达到90%阈值且非token递减收益，一旦为true就不再判断后续条件、直接允许继续)

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/ccloop.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    claude code agent loop流程。注意，这不是传统意义上的ReAct Loop，而是Tool-use Loop。循环时由LLM每次看到当前的对话上下文后，自主判断“我现在应该读个文件”还是“我应该执行一条命令”还是“我可以回复用户了”
</div>

## 统一消息格式
Claude Code内部有一个统一的消息格式，~~但不需要为每个模型提供商单独转换消息格式~~，因为它只支持Anthropic生态内的4个提供商，所有支持的提供商使用同一套Anthropic消息格式，由Anthropic官方维护的对应SDK统一处理；Claude Code的模型访问层是围绕Anthropic生态硬编码的，~~没有针对第三方提供商 (如DeepSeek、OpenAI等)的适配器机制~~，需要自行实现消息格式的转换

## Plan Mode
Tool-use Loop是边想边做，缺点在于浪费模型的精力而且容易跑偏

Plan Mode是一个更精细的两阶段工作流：复杂任务先规划、再执行，避免方向跑偏、浪费精力；它并不是一个独立的框架，而是在同一个Tool-Use Loop中通过EnterPlanMode和ExitPlanMode两个工具实现的

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/planmode.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    Plan Mode的工作流程
</div>

## takeaway
* 流式输出+并行处理：用异步生成器把每个中间事件即时抛出去，工具调用一边执行模型一边继续思考 (不等模型思考玩在处理tool_use工具调用块)，让用户体感响应快
* 错误恢复优先于优雅：工业级的容错，不是报错弹窗，而是用户根本感觉不到出过错 (比如工具执行终端之后，补上tool_result块让模型继续处理，而不是直接触发API规定报错；LLM长输出截断之后，提示LLM把输出变小)


# 上下文工程
## 上下文里有什么
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/content.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    claude code上下文里有什么
</div>

## CLAUDE.md
* 每次开新会话，claude code都会自动把它读进来 (启动加载)，塞进对话的最前面
* 全局配置放在~/.claude/CLAUDE.md，所有项目都会加载，适合写个人偏好，比如“回答用中文”“commit信息别写太长”，启动加载；项目配置放在项目根目录，写这个项目的技术栈、命令、规范，启动加载；放在项目子目录里的CLAUDE.md~~不是启动就加载的~~，而是等 claude读到那个子目录下的文件时才带进来 (按需加载)，可以放各模块的规范
* 


## 系统提示词
system prompt不是一个静态的文本文件，它是动态组装的，由十几个section拼接而成，包括：
* 角色定义与安全红线：
  * 告诉claude code它是谁 (它把自己定位为interactive agent，而不是assistant或chatbot，这从一开始就暗示了模型应该主动采取行动，而不是被动回答)
  * 要求不能乱编URL、遵守Git操作安全协议，然后<mark>先说可以做什么 (如授权的安全测试、CTF挑战)，再划定不能做什么 (如DoS、供应链攻击)；这种先肯定再约束的写法，比纯禁止清单效果好得多，它给了模型清晰的判断依据，而不是一堆模糊的红线</mark>
* 行为准则/怎么做事：比如
  * 要求修改代码前先阅读：因为很多agent会根据用户描述直接生成代码，而不先看看现有代码是什么样的，结果经常和项目风格不一致或者引入重复实现
  * 代码风格要少即是多：因为agent容易修一个bug，结果顺手把整个文件重构了，加了一堆没要求的类型标注和错误处理，这是需要明令禁止的
  * 失败处理要先诊断再换方案：避免agent反复重试/直接放弃，要求agent先搞清楚为什么失败了，再决定是修复还是换方案
* 操作安全：规定什么操作需要用户确认，考虑到操作的可逆性 (one-way door/two-way door)和影响范围 (比如读文件、改本地代码是低风险的，直接放行，因为它们可逆、只影响本地；git push、发Slack消息是高风险的，必须确认，因为它们不可逆、影响他人)，解决权限蔓延的问题 (用户同意了一次push不代表以后都自动push，授权是一次性的、有范围的)
* 工具使用指南：不让模型直接用cat读文件、用sed改代码，原因在于可审查性，用专用工具而不是Bash不仅是体验问题，更是安全问题：
  * 当模型调用Read工具读文件时，UI会清晰地展示“agent正在读取src/index.ts”；但如果模型执行cat src/index.ts，用户看到的只是一条Bash命令和一大坨输出，完全不知道agent在干什么
  * 而且专用工具有专用的权限检查：Read工具会检查文件路径是否在允许范围内，而cat命令就没有这层保护了
* 输出风格约束
* <mark>插入一条__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__来使用/命中缓存</mark>：分割线之上的内容对所有用户都完全一样；分割线之下的内容，每个用户都不同，命中缓存可以省钱
* 环境信息注入：让模型知道自己在哪里，是什么操作系统、什么Shell、什么项目目录
* 最后加上CLAUDE.md文件、记忆系统的记忆、MCP

# 压缩/compact
压缩是自动触发的，不会在每一轮都压缩一次 (因为压缩本身也要烧token调一次模型做摘要，能不压就不压)；还有标志位State.hasAttemptedReactiveCompact<mark>防止同一轮内反复压</mark>，一次压完还是塞不下，就别再压第二次了，避免陷入“压缩 → 还是塞不下 → 再压”的死循环，新一轮开始时这个标志会被重置；压缩流程如下 (压缩代价逐步升高，前3步都是0 API开销，最后2步二选一执行)：

step1. [提前处理tool_result工具调用返回结果](https://clementineyyy.github.io/blog/2026/claudecodeTools/#%E8%BF%94%E5%9B%9E%E5%B7%A5%E5%85%B7%E8%B0%83%E7%94%A8%E7%BB%93%E6%9E%9C)：单个工具结果限制+单条消息聚合预算

step2. 砍掉远古消息：因为一次长对话可能有上百轮，对话开头那几轮的内容，比如用户最初的探索性提问、模型早期的试探性回答，到了后面几乎完全没用了，但它们仍然占着宝贵的上下文空间
* 删什么：不是写死的规则，而是模型在正常回答的那一回合里，顺手用一个专门的snip工具，按消息id把没用的那几条标记出来，真正的删除动作才在本地完成
* 怎么删：直接把对话开头的一批老消息移除掉，然后插入一个边界标记告诉模型“这之前的内容已经被清理了”，~~不做任何摘要/总结~~，再把本次释放多少token还给token限额，避免接下来的判断继续触发自动压缩

step3. 裁剪老的工具输出：
* 消息、子agent的输出AgentTool、任务状态TaskTool不能直接砍掉，因为可能还有用、而且它们是不可重复的，砍掉就真的丢了；但里面大量的工具输出其实已经过时了：比如30分钟前读的一个文件，现在那个文件可能已经被改过了
* 可以被裁剪的，都是可重新获取的工具：比如Read的结果可以再读一次，Bash的输出可以再执行一次，搜索结果可以再搜一次
* 具体裁剪逻辑：保留最近N个，清理其余的；被裁剪的工具结果会被替换成一个标记，这样模型看到这个标记就知道这里原来有内容但被清理了，如果它后面还需要这些信息，它可以自己决定重新读文件或重新执行命令；而且裁剪的触发跟时间有关，因此叫做时间衰减 (比如距离上一次API调用超过一定时间，默认约60分钟，说明大模型API端的Prompt Cache大概率已经过期了；既然缓存已经没了，那清理旧的工具结果也不会浪费之前的缓存投入)

step4. 读时投影Read-Time Projection：~~不直接修改消息列表，把内容替换掉或删掉~~，而是在调用LLM API的那一刻，动态计算一个压缩视图给模型看，原对话历史在本地完整保留；有2个触发时机：
* 在90%上下文窗口时主动开始分段压缩旧消息，预留缓冲区
* 在95%上下文窗口时紧急压缩更多内容，留足API响应空间

step5. :star:全量摘要：绝对阈值触发自动压缩，<mark>触发阈值 = 有效窗口 (不等于模型原始的窗口大小，还要减去MAX_OUTPUT_TOKENS_FOR_SUMMARY，默认是20k是给给摘要输出预留的位置) - 13K缓冲区 (额外往回缩的一道安全线，让压缩稍微提前一点触发)</mark> (绝对值阈值的好处是可预测：不管模型窗口多大，触发条件不会因为窗口变大就跟着膨胀；如果用80%这种比例，模型窗口越大，剩余预算就越大，但摘要任务实际需要的预算其实没怎么变，那就是浪费)，具体又分为3步：
* <mark>生成摘要：调用当前对话的同一个大模型</mark> (不用小模型的原因：保证摘要质量+Prompt Cache复用、命中缓存来省钱并加快推理速度)，把整段对话总结成一段结构化摘要 (<mark>所有历史消息，不分新旧，全部送进摘要器重新写一份</mark>)：
  * 做之前的预处理 (同step3)：先把对话里占大头的工具调用结果 (包括Read、Bash、Grep、Glob、WebFetch、WebSearch、Edit、Write)清空，只留一个元数据占位符，再把瘦完之后的对话送进摘要器，摘要器的负担也小很多，生成的摘要质量也更高
  * 不参与摘要：
    * CLAUDE.md不被摘要，而是在后续恢复注入：因为CLAUDE.md每一轮都会自动重新加载，不需要塞到压缩后的消息里占地方
    * system prompt：压缩之后重新构造一份新的system prompt，注入最新的工具列表、最新的权限设置、最新的MCP server列表
  * 有一个精心设计的Prompt：
    * 精细的原因是压缩后模型要靠这段摘要来恢复记忆，如果摘要漏掉了关键信息，模型就会忘记这件事
    * 要求模型按多个维度来总结：用户的主要请求和意图、关键技术概念、涉及的文件和代码片段、遇到的错误和修复方案、问题解决过程、用户的所有消息 (不能遗漏任何一条)、待完成的任务、当前工作状态、建议的下一步
    * 摘要时禁止工具调用：因为做摘要的本质是让模型只生成文字，把对话压缩成一段总结，但是模型很容易看到对话里提到“这个文件之前read过”就自己手痒去read一下，或者看到一个bug就想去bash跑一下；但在做摘要时这是大忌，LLM要总结历史，不是要做新动作，一旦它去调工具了，这次摘要就废了，得重新来
    * 规定摘要输出格式：
        > \<analysis\>
        > 
        > [模型的推理草稿，分析对话哪些重要：让模型先想清楚再写。这块最终会被剥离掉，不进入压缩后的对话。它的存在纯粹是为了让模型有个「思考的空间」，写出来的摘要质量更高]
        > 
        > \</analysis\>
        > 
        > \<summary\>
        > 
        > [真正进入对话的结构化摘要，按 9 个清单分块]
        > 
        > \</summary\>
    * 枚举所有用户消息：摘要里必须把所有不是tool result的用户消息列出来，因为用户在对话中可能在第30轮的时候改了一次需求、在第80轮的时候提了一个新约束、在第150轮的时候说之前那个方向放弃吧，这些信号是任务方向变化的关键，摘要里丢了一个，agent接下来可能就走偏了
    * 用最细的颗粒度描述agent当前正在做什么：为了提醒agent刚刚在做什么，避免重新探索一遍上下文，浪费token和时间
  * 递归守卫：摘要任务本质上也是开了一个子agent去调模型生成摘要，这个子agent自己也要消耗token，~~但不会因为消耗多了又触发auto-compact，进入死循环~~，因为源码限制此时不触发子agent压缩
  * 压缩后的四段式结构：
    * 边界标记：一个特殊消息，记录这次压缩是自动还是手动、压缩前token是多少、最后一条消息的ID，等于打个时间戳
    * 摘要消息：主要内容
    * 附件：包括最近读过的文件、当前的计划文件、激活的技能、正在运行的异步任务状态等，是后面另外的恢复通道
    * hook结果：用户配置的hooks在压缩时也会执行，结果一并注入
* 替换旧消息来接上之前的对话：把压缩边界之前的所有消息删掉、替换为刚才生成的摘要，清空各种缓存，同时插入一条边界标记消息，记录压缩前的token数，方便后续追踪
  * 摘要开头告诉模型它不是从头开始的，它是接着干的，让模型顺着摘要的Current Work往下接活
  * 摘要的末尾还会带一个transcript文件路径，如果模型需要查之前对话里的某个具体代码片段或者细节，可以读这个文件兜底
  * <mark>被压缩的旧消息行完整保留在.jsonl文件中，不会被物理删除</mark>，因为文件是append-only的，只是在会话中不可见了
* <mark>压缩后主动恢复最重要的上下文</mark>：包括文件内容、记忆文件如CLAUDE.md、异步任务的状态如子agent/子任务状态 (压缩时必须保住，不然主agent醒来后不知道子任务进展到哪了)：
  * 从文件状态缓存中找出最近访问read过的文件，按最后访问时间排序，挑选最多5个、每个文件最多塞5k token、总共不超过50K Token的文件内容重新注入，同时恢复不超过25K token的活跃的Skill；如果不恢复，模型的第一反应就是重新读一下文件，白白浪费一轮工具调用，主动恢复最近的文件内容，可以让模型无缝继续工作，体验上几乎感觉不到压缩发生过
  * 还有一个<mark>熔断器机制：如果全量摘要连续失败3次 (比如因为API超时)，系统会自动放弃，不会无限重试&请求API</mark>，防止一个失败的压缩操作拖垮整个agent

## 手动压缩和自动压缩的区别
核心压缩函数是同一个，但传入的参数不一样
* 手动压缩：可以传一段自定义指令，告诉摘要器“这次压缩，请特别关注XXX方面”；比如你正在调一个特定bug，希望摘要的时候把这个bug的上下文重点保留
* 自动压缩：不接受用户指令并且摘要里禁止生成需要进一步确认类的问题；因为自动压缩通常发生在agent正在干活的时候，不想压完了对话被一个新问题打断节奏



# 会话持久化
一句话总结：每个会话对应一个独立的JSONL文件作为主transcript，每条消息携带parentUuid形成链式链表；写入时通过appendEntry分流到主transcript/subagent transcript并异步批量落盘，会话级元数据缓存后在退出前回写；恢复时通过沿parentUuid从叶子回溯重建对话链，并把元数据、工作区、代理模式等状态回灌到新进程，让用户能无缝继续之前的对话

## 整体分层结构
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/consistent.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    claude code会话持久化的架构设计
</div>

## 物理存储结构：transcript核心
把transcript当成事件流日志，保留真正影响上下文重建的消息、把高频UI状态从持久化层排除

### 主transcript和subagent transcript
主transcript的命名方式是{sessionId}.jsonl，是当前会话session的主对话记录文件 (<mark>每个session对应一个独立的主transcript</mark>)，格式为JSONL，每行一个JSON entry称为transcript message；主transcript同时承载对话消息和会话级元数据 (具体条目见sessionStorage.ts，只写入主transcript而不写入subagent transcript)，所以每行的JSON entry是对话消息或会话级元数据：

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/transcript.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    对话消息的类型和含义，它们被打上当前sessionId、cwd、gitBranch等session-stamp，写入主transcript
</div>

subagent transcript是由AgentTool产生的子代理subagent独立对话记录文件，不和主transcript混写，而是单独sidechain文件；subagent transcript主要承载子代理的对话消息，不承载会话级元数据

### transcript存储路径
transcript路径不是固定死的，而是依赖sessionProjectDir和当前sessionId (switchSession原子性同时改sessionId和sessionProjectDir，两者不能分离)，同一个会话在resume/branch/switch后仍能落到正确目录：
* 主transcript路径是~/.claude/projects/\<sanitized-project\>/\<sessionId\>.jsonl
* Subagent transcript路径是~/.claude/projects/\<sanitized-project\>/\<sessionId\>/subagents[/\<subdir\>]/agent-\<agentId\>.jsonl
* 项目路径会被sanitize (非字母数字替换为-，超长则加hash后缀)
* sidechain本质上是一条消息的布尔标记isSidechain:boolean，它决定消息走向主文件还是子代理文件；

### transcript的写入策略
主transcript和subagent transcript的写入策略基本相似：

step1. 调用方产生消息：外部调用方 (如query.ts、REPL.tsx、useLogMessages)在<mark>每轮对话结束后</mark>，把新产生的消息批量传入

step2. insertMessageChain构造条目并调用真正的分流器/持久化系统的主入口appendEntry，确定targetFile：
* appendEntry决定一条entry应该：写入主transcript还是sidechain transcript (有agentId就写subagent文件，无agentId就写主transcript)；是否只更新metadata；是否还要同步发到远端ingress
* 主链去重，sidechain保真，远端只跟主链走；解决了两个互相冲突的问题：
  * 主transcript不能重复写同一个UUID否则resume会遇到重复链路和远端409冲突
  * sidechain又必须允许继承消息重复出现，否则fork/subagent恢复时会丢掉继承来的父上下文
  * UUID是每条消息TranscriptMessage和每个会话/子代理的唯一标识字符串，<mark>消息间靠parentUuid构成对话链</mark>：在insertMessageChain中，每条新消息的parentUuid会被设置为前一条参与链的消息的uuid，从而在JSONL中形成一条可回溯的对话链。加载时buildConversationChain会沿parentUuid从叶子消息回溯到根，重建完整对话顺序。因为并行工具调用会产生多个tool_use block，对应不同的assitant message，单链表回溯会丢失兄弟块和对应的tool_result，因此还有recoverOrphanedParallelToolResults做读取后的补齐：按message.id分组，把off-chain的兄弟节点和tool_result放回链中。

step3. 底层异步批量flush：分流后，条目~~并不会立即落盘，也不是每来一条就同步writeFile~~，而是先进入内存队列，100ms后由drainWriteQueue()合并多行、批量入盘。好处就是追加简单、崩溃恢复容易、不要求每次都重写整份 transcript (<mark>追加传入，已写入transcript的旧消息不会被后续新消息修改</mark>)

### 元数据持久化
元数据依然写回transcript：metadata会被周期性重挂到transcript尾部；原因是因为系统有两种读取方式：
* 完整恢复：读取transcript全量内容
* lite列表读取：只读头尾窗口，快速展示session列表、title、tag、firstPrompt；如果title/tag太早写进transcript，后面会被越来越长的对话挤出tail window，列表页就看不到它们，所以它必须反复重挂到EOF

用reAppendSessionMetadata()来实现，先从tail吸收外部SDK改过的新title/tag，避免本地缓存把它覆盖回旧值，然后再append；该机制的意义在于：
* 让渐进式session列表加载能从tail快速读到关键metadata
* 让resume后尚未发送新消息的session，也能在退出时把metadata落盘
* 兼容外部SDK/其他进程对title、tag的修改

### 主transcript的远端ingress副本 (可选)
主transcript不是只有本地文件，还有远端ingress副本 (subagent transcript没有远端ingress副本)。主transcript message在本地append的同时，还可以增量发到远端ingress。<mark>远端ingress不是默认启动的，需要配置条件，因此默认情况下，transcript只落盘到本地.jsonl，不会自动同步到远端</mark>；远端ingress副本是为了解决本地transcript不可用的场景——换机器、本地文件丢失/损坏、或者会话本身在远端守护进程中运行

远端ingress逻辑：
* 每次put一条entry
* 同一个session的远端append必须串行化：会给每个session建一条顺序执行队列，避免同一session并发写远端造成链头竞争；本地允许高频异步批量追加，远端则要求单session串行顺序
* /resume的时候可以反向把远端transcript拉回本地：本地transcript是运行时主副本，远端ingress是可回灌的增量副本

## 逻辑结构：DAG有向无环图
每条TranscriptMessage都携带uuid自身标识和parentUuid指向父消息，通过这两个字段把消息组织成一棵或多棵树，包括：
* 主树：正常对话的主干
* 死分支：/rewind、Ctrl+Z、fork等操作会在JSONL中留下死分支
* Compact boundary切断：在逻辑上截断旧树，成为新子树的根

每棵树的根通常是parentUuid = null的消息 (如会话第一条user消息，或compact boundary之后的第一条消息)；子代理的消息写入独立的agent-\<agentId\>.jsonl且带isSidechain = true和agentId，它们在逻辑上与主会话的树是分离的森林，不与主会话的parentUuid链混合；因为允许分支汇合，节点可有多条进入路径 (因为并行的assistant消息/工具调用tool_call在语义上属于同一轮输出/模型调用、共享message.id，而tool_result又可分别指向不同的并行assistant，最后它们都会汇合到主链)，所以真正的逻辑结构是DAG~~而不是树~~

### 读取时如何从DAG中提取一条线性对话链
虽然底层逻辑是DAG/森林，但LLM消费时需要一条线性的消息序列，转换步骤如下：

step1. 单链回溯：从叶子消息leaf出发，沿parentUuid一路向上回溯到根，再反转；这一步只保留一条主干路径，会丢失兄弟节点

step2. 因为单链回溯会丢弃并行的assistant块和对应的tool_result (N个并行的tool_use会产生N条assistant消息)，系统做读取后补齐使每个tool_result紧跟在其tool_use之后


## /resume的步骤
step1. 从磁盘加载旧消息和元数据，沿parentUuid重建对话链

step2. switchSession改变内存sessionId和sessionProjectDir (原子操作，两者同步修改)，getTranscriptPath()现在指向旧.jsonl

step3. 把旧文件里的title/tag/agent/mode等读入Project内存缓存，清理干净project.sessionFile，使其为null

step4. :star:adoptResumedSessionFile把当前持久化目标绑定到旧transcript，然后立刻用reAppendSessionMetadata重挂metadata (把内存缓存中的元数据追加写入该旧transcript文件的尾部)；解决了用户resume了旧session，改了标题或其他metadata但还没发新消息就退出，导致丢失元数据修改 (因为元数据设计为缓存先行，退出前统一回写，不会立即写盘,避免产生只有元数据的空文件)的问题

## 会话如何分支


# 记忆系统
~~与传统的“用向量数据库，把记忆存成embedding，每次对话时做相似度检索”不同~~

idea：不堆复杂度，把已经成熟的简单组件 (文件系统+LLM)组合出比花哨方案更好用的东西

## 静态CLAUDE.md文件
### 6层架构
因为规则来源不同、可见范围不同、生效范围不同，因此不能全放进一个CLAUDE.md文件中；6层架构中的md文件可以相互引用@，这样就不用复制内容了，只需要在加载的时候自动把那个文件的内容读进来拼上

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/6layers.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/load.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    6层架构具体内容和加载流程
</div>

### 优化设计
#### 按需载入规则
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/path.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    将frontmatter中的paths和当前目标编辑文件的路径进行匹配，匹配成功的规则才会被加载进上下文
</div>


## 动态记忆系统
### 整体结构：多层文件化记忆系统
核心不是“把内容记住”，而是“把不同生命周期、不同作用域、不同可见性的内容分开保存”，每一层各自有独立目录 (以下4种记忆的存储路径不同)、独立prompt、独立更新策略
1. Auto Memory通用持久记忆层：面向整个用户和项目协作过程的长期记忆，存放在统一memory目录中
2. Session Memory当前会话摘要层：面向当前会话的摘要文件，目标是辅助compact和长会话稳定持续运行
3. Agent Memory面向某个agent类型的持久记忆，和agent定义直接绑定
4. Team Memory面向团队共享的repo级知识同步
5. 好处：
  * 透明：所有memory都是文件，用户可以直接打开目录检查、编辑、删除markdown文件，agent运行期也可以随时读写更新
  * 可治理：不同memory可以单独开关、单独同步、单独约束
  * 可组合：Auto/Session/Agent/Team Memory每一层可以同时存在，但职责不同
6. 坏处：
  * 需要治理：错误记忆、过时记忆、重复记忆都会持续污染后续agent行为
  * 路径和权限逻辑变复杂：user/project/local/remote mount都要分别处理
  * prompt构造更重：MEMORY.md每次都要参与prompt生成，虽然有截断保护，但仍有成本
  * 需要模型遵守写入规范：系统已经做了不少规则约束，但最终仍依赖agent正确维护索引和文件

#### 4层架构VS4种数据
它们是两个独立的维度，每个存储层内部都可以包含4种类型的记忆：
* 存储层决定记忆文件放在哪个目录、谁能读写、怎么同步、生命周期如何
* 内容类型决定记忆文件里记录的语义是什么


### 记什么：4种记忆分类 {#four}
只有这4种分类，不能添加新分类；也不存在通用的any类型，避免无约束的记忆迅速膨胀成垃圾堆；逼agent做分类决策，必须考虑清楚每一条记忆属于哪一类

1. User用户画像 (角色、偏好、知识水平)：比如用户说“我是一个写了十年Go的后端工程师，第一次接触React”，agent就应该在解释前端概念时用后端的类比，而不是从零讲起。这类记忆让agent的回答因人而异，而不是千篇一律
2. Feedback行为反馈 (该做什么、不该做什么)：记住用户说过"不要做什么"和"做得好继续保持"，它直接决定了agent下一次的行为对不对。这类记忆的关键在于，它不仅记规则本身，还要求记录Why为什么 (往往包括踩过的坑)和How to apply怎么应用/什么情况下生效 (因为当遇到边缘情况的时候，agent需要根据Why和How来判断这条规则在这个场景下是否适用；否则只是盲目遵守，太死板、不会灵活变通、在不该用的场景也强行套用规则)
3. Project项目动态 (在做什么、截止日期、协作信息、有什么重要决策)：和Feedback一样同时记录事实/决定、Why (这事为什么发生，是哪条约束或截止日期推动的)和How to apply (这件事应该怎么影响agent的建议)；特殊要求是必须把相对日期 (比如周四)转成绝对日期 (具体到明确的年月日)，这样才永远准确
4. Reference外部指针 (去哪能找到什么信息)：价值在于，agent不需要知道外部系统的具体内容，只需要知道去哪里找

明确规定不记什么：核心原则：可以从当前代码推导出来的信息，一律不存 (因为代码随时在改变，而记忆没这么灵活)
* 代码模式、项目架构、文件路径和文件结构：因为这些信息通过grep、git、CLAUDE.md就能获取，而且常常发生修改，存在记忆里反而会导致记忆和代码实际状态不一致，并且加重了记忆负担
* Git历史和最近的改动：git log和git blame才是权威来源，不需要记忆系统再来存一遍
* 调试方案和修复方法也不记忆：因为修复已经在代码里了，commit消息已经记录了上下文
* CLAUDE.md里已经写了的内容也不存，避免重复
* 临时任务状态和当前对话上下文：这些是会话级、短期信息，不需要跨会话保持


### 怎么记&导入加载记忆/底层存储逻辑：文件夹+MEMORY.md索引
系统把MEMORY.md当成入口索引文件，而不是正文存储文件；所有记忆文件和MEMORY.md都在同一个目录下；所以MEMORY.md会链接到4种记忆内容user/feedback/project/reference

设计意图的好处：
* 每条memory单独写成一个markdown文件，独立文件存储每条记忆；文件开头有一段YAML格式的元信息frontmatter (可以理解为这条记忆的身份证，元信息之后才是记忆内容)包括：
  * name是人类可读的标识
  * description是一句话摘要，专门用于检索时的相关性匹配
  * type标记四类型之一： user/feedback/project/reference
* MEMORY.md是一个不超过200行并且小于25KB (同时限定字节数是为了避免一条索引就是一行超长字符串的情况)的轻量目录，只维护索引链接和一行描述；不能太长因为MEMORY.md始终加载进system prompt
* agent/model在prompt里默认只保证看到<mark>MEMORY.md (始终加载到system prompt中)，除session memory外其他3个memory层级都有MEMORY.md</mark>，但4个层级的加载/导入时机不同：
  * <mark>auto memory的MEMORY.md始终载入system prompt</mark>
  * <mark>session memory是按需读取的会话摘要文件</mark>，而~~不是每轮都自动注入的system prompt片段，它没有MEMORY.md和独立记忆文件~~，<mark>只是一个单一文件summary.md在特定场景下被主动读取</mark>
  * agent memory<mark>只加载当前活跃agent配置的scope下的MEMORY.md文件，并赋予agent文件工具权限</mark>
  * team memory<mark>只在启用team memory时加载MEMORY.md且和auto memory合并在同一system prompt段</mark>
* <mark>需要更细节时，再去读具体memory文件 (按需加载独立记忆文件)</mark>：独立记忆文件的按需召回主要发生在 <mark>auto memory及其子目录team memory</mark>，agent memory的独立文件召回需要用户@提及该agent才会触发，~~session memory没有独立记忆文件可召回~~

这比把所有记忆堆在一个大文件里更稳，因为大文件很容易造成：prompt爆炸、占满上下文窗口、浪费token、更新冲突、历史垃圾无法治理、单条错误记忆污染整份上下文

### 记忆是怎么记录/沉淀下来的？
4种记忆层级有各自的记录方式，<mark>记忆的更新和删除</mark>~~并没有走一条独立于沉淀的专用路径~~，<mark>而是与沉淀共享同一套机制，主要是通过模型主动读写文件实现</mark>

#### Auto Memory
包括用户长期偏好、项目外部上下文、非代码内生知识、需要跨会话延续的协作约束。

沉淀方式&时机：auto memory默认开启，只有在特定环境变量或设置下才会关闭；它的更新~~不是靠当前主线程agent每次都手动完成~~，而是在<mark>每轮对话query结束后 (即模型给出最终回复、没有任何tool call了)</mark>，由stopHook钩子<mark>触发后台提取流程extractMemories</mark> (subagent会话通常被排除在auto memory的后台提取之外)，单独跑一个子agent查询循环来抽取记忆，读取新消息并主动更新和新增md记忆文件和MEMORY.md索引文件，写入auto-memory目录 (~/.claude/projects/\<path\>/memory/)：
* 子agent复用主对话的同一个大模型：forked agent，~~而不是从零启动一个新对话~~；这样可以复用主对话的prompt cache，把已经算过的system prompt缓存下来，下次不用重算，也不用重新system prompt，只需要看着对话历史，决定这次有没有值得记的东西就行，不需要额外消耗token
* 子agent抽取记忆逻辑：
  * 扫一遍这一轮对话里用户的反馈、纠正、信息
  * 子agent读取现有记忆清单，然后决定是写新文件、edit现有文件，还是删除文件
  * 跟现有记忆比对，看有没有重复 (<mark>去重完全依赖提取子agent在读取现有记忆清单后，根据prompt指导做出判断，prompt中明确禁止重复</mark>)：主动检测hasMemoryWritesSince，过滤掉它刚刚写过的内容，避免对同一件事反复写记忆
  * 如果有新的值得记的内容，按四种类型user/feedback/project/reference分类，写一个新文件

#### Session Memory
沉淀时机：触发条件才记忆
* 会话没长到一定程度，不启用Session Memory (minimumMessageTokensToInit = 10000)
* 即便已经启用，也不会每轮都更新 (minimumTokensBetweenUpdate = 5000)
* 工具调用次数和token增长都要参与判断 (toolCallsBetweenUpdates = 3)

沉淀方式：注册registerPostSamplingHook，fork一个沙箱化subagent去做摘要。这个subagent权限只有FileEditTool，且只能操作一个精确路径 (createMemoryFileCanUseTool会deny所有其他工具包括FileReadTool/FileWriteTool)；即只允许Edit单个session memory文件，权限比auto memory的extract agent窄得多 (subagent会话通常被排除在session memory之外)

##### Session Memory的加载和召回
session memory~~没有MEMORY.md和其他独立记忆文件~~，<mark>只是一个单一文件summary.md在特定场景下被主动读取</mark>，包含以下两种情况：
* 会话压缩compaction：在compact时读取summary.md内容作为会话摘要，替代传统compaction逻辑；如果session memory不存在或为空模板，则回退到legacy compact行为
* skillify技能在生成skill prompt时，将summary.md的内容作为上下文注入

#### Agent Memory
它不是检索外挂，而是直接改变agent下一次的system prompt起点：agent工作中发现需要记住的信息$\rightarrow$先读MEMORY.md或已有memory文件$\rightarrow$新增/更新memory$\rightarrow$维护MEMORY.md索引$\rightarrow$下次调用同一agent时再次读取同一目录的MEMORY.md文件

主要包含3种信息，且只针对agent memory：
* user：跨项目复用的agent长期记忆
* project：当前项目内共享的agent记忆
* local：当前项目、当前机器或当前挂载环境的本地agent记忆

沉淀方式&时机：<mark>agent memory没有固定的沉淀时机，它完全依赖主agent自己在对话中主动决定什么时候更新/删除。agent运行期间，主agent按自身system prompt的保存指令，主动调用Write/Edit写入MEMORY.md或主题文件</mark>；即主agent主动读写，无后台子agent；而且agent memory的system prompt只会在agent定义中配置了memory scope时才被加载，如果agent没有配置memory scope，主agent的system prompt里没有任何“保存记忆”的指令，它也不会知道自己有一个MEMORY.md可以写，自然不会主动更新记忆


##### 如何加载/导入agent memory？
该做法只针对agent memory，与其他3种memory无直接关系。只要agent定义里带了memory字段 (agent定义和memory字段的说明见下方)，系统都会做两件事：
* 自动把memory prompt拼接到agent system prompt后面 (所以agent从第一轮开始就知道：自己的memory目录在哪里、该怎么写memory、MEMORY.md当前有哪些索引；loadAgentMemoryPrompt()加载agent memory prompt)
* 自动把Write/Edit/Read三个文件工具注入到agent的工具列表里

这两步缺一不可：
* 如果只注入prompt，不注入文件工具，agent看得到规则却没法落盘&实际操作
* 如果只注入文件工具，不注入prompt，agent有写权限却不知道memory的目录和治理方式

agent定义：在codex、claude code这样的coding agent harness中，可以有多个agent类型：内置built-in agents、用户自定义的custom agents和plugin agents。每个agent type都有自己独立的记忆目录和snapshot目录

memory字段：
> export type AgentMemoryScope = 'user' | 'project' | 'local'

表示该agent是否拥有持久化记忆，以及记忆文件存储在哪个作用域 (user/project/local的存储位置各不相同)；如果memory为undefined或none，则该agent不使用agent memory

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/memoryTool.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/agentMemory.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    agent memory的导入/加载方式：将memory的设置和工具暴露联系起来；agent memory的典型使用流程
</div>

##### Agent Memory Snapshot
snapshot的沉淀分为创建 (由外部/产品端，如Claude Code Web界面、agent分享/发布流程、或团队协作后台，产生snapshot目录，在本项目中不存在)和本地应用 (把snapshot读取、复制、应用到agent的本地记忆目录，snapshot的初始化/更新发生在agent定义加载时)两部分

为什么snapshot很重要：因为它把agent memory从“运行时副产物”提升成了“可分发的角色资产”。也就是说，一个项目可以不仅定义agent的prompt，还能一起下发，随项目一起发布和升级：
* 这个agent的初始记忆结构
* 这个agent已经积累好的协作经验
* 这个agent的更新版本

这比单纯shipping一个prompt.md更强，因为：
* 它允许项目把agent逐步养成熟：把agent memory从“运行时副产物”提升为“可分发的角色资产”，可随项目一起发布和升级
* 零成本初始化：新环境或新agent实例可以直接从snapshot获得已有记忆结构，不用从零开始养agent
* 可升级：团队可以给agent memory打版本，本地检测到新版本后提示prompt-update，实现记忆结构的滚动升级
* 解耦会话：记忆不再绑定单次会话，而是绑定agent类型，支持跨会话、跨项目的长期积累

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/snapshot.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    agent memory snapshot的触发条件 (snapshot的初始化/更新发生在agent定义加载时)和处理函数
</div>

#### Team Memory
沉淀方式&时机：<mark>每轮对话query结束后 (即模型给出最终回复、没有任何tool call了</mark>)由extractMemories子agent写入team子目录后或任何工具写入team memory文件时 (先本地写入到磁盘)；监听文件增改删，并通过PostToolUse钩子notifyTeamMemoryWrite()触发，推送到远程服务器 (最后远程推送实现团队共享)

### 记忆怎么注入提示词？
从auto memory、agent memory和team memory (后两者如有，sesson memory的注入见[Session Memory](#session-memory))中的MEMORY.md中加载选中记忆的完整内容，用\<system-reminder\>标签包裹后注入上下文 (顺序是：系统指令system prompt、历史对话、系统提醒system-reminder、当前问题user prompt)。格式如下：

> \<system-reminder\>
This memory was saved 5 days ago. Verify it's still accurate before acting on it. (记忆老化的设计)
> 
> [记忆内容]
\</system-reminder\>


<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/outdate.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    记忆注入时的处理细节：记忆老化；当一条记忆过时了agent不是盲目相信，而是会主动去验证 (比如grep一下、读一下当前文件状态)，发现冲突就更新或忽略它
</div>

### 记忆怎么按需召回？
<mark>模型先天就能在system prompt里看到MEMORY.md，知道有哪些记忆文件存在、它们的标题和简短描述；如果模型基于当前query判断某些记忆可能有用，就会把对应的独立记忆文件按需召回，读取全文作为attachment注入本轮对话</mark>；独立记忆文件的按需召回主要发生在 <mark>auto memory及其子目录team memory</mark>，agent memory的独立文件召回需要用户@提及该agent才会触发，~~session memory没有独立记忆文件可召回，它是一个单一文件summary.md在特定场景下被主动读取~~；sesson memory的注入见[Session Memory](#session-memory)

Relevant Memory Recall的时机：~~不是把所有历史记忆都塞进prompt~~，而是做选择，从几十条记忆里挑出最相关的那几条加载进来；并且也不是每一轮都强制执行，而是由程序自动触发，只要满足守卫条件，每轮query都会在后台异步启动独立记忆文件的扫描与模型选择

#### 做法
用一个廉价的<mark>小模型Sonnet来做记忆检索</mark> (为什么是Sonnet不是Haiku？明明Haiku更便宜。因为Sonnet比Haiku准很多，记忆相关性判错的代价远大于多花的那点钱。一旦把错的记忆塞进上下文，整个回复都会被污染。记忆选择的容错率非常低，所以宁可贵一点也要选准)

step1. 扫描所有记忆文件 (按修改时间倒序，最多扫描200个文件；扫描哪个目录，取决于调用方传入的memoryDir，根据是否有@agent来决定传入auto memory目录还是特定agent的memory目录；auto memory不召回没关系，反正始终进入system prompt)的头部信息：只读每个文件的前30行，即frontmatter区域，不读全文；提取文件开头元信息里的name、description、type；有效控制扫描开销
step2. 所有记忆的头部信息被拼成一个文本清单 (每一行包括[type记忆类型]记忆markdown文件名 (日期))，连同用户提示词一起发给小模型做选择，格式如下：
> Query: 用户当前的问题
> 
> Available memories:
> - user_role.md — 后端工程师，新接触 React
> - feedback_no_mock.md — 测试不要用 mock
> - project_freeze.md — 3 月 5 号开始合并冻结
> ...

step3. 小模型返回的只是一个文件名列表JSON schema (比如["feedback_no_mock.md", "project_auth.md"])，不是记忆内容本身

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/details.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    记忆召回时的处理细节：两层过滤
</div>

如果用户当前正在使用某些工具 (比如正在调用某个MCP工具)，小模型会自动过滤掉该工具的使用文档类记忆，因为模型已经在用这个工具了，它的用法文档此刻是噪声，不是信号；但该工具的已知bug和注意事项类记忆仍然会被选中，正在用的时候，恰恰是最需要知道坑在哪里的时候

#### 性能优化：记忆召回的执行时机
小模型侧查询不是在主模型需要时才触发的，而是在用户提交消息后立刻就开始了，和主模型的API调用并行执行；并且小模型比主模型快得多，所以等主模型响应返回时，记忆召回早就完成了，几乎不增加任何额外延迟

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/parallelMemo.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    记忆召回与主模型处理并行
</div>


### 记忆压缩Memory Compaction
其实属于上下文工程的范畴。为了避免模型的上下文超出上下文窗口大小，需要对记忆进行压缩，有手动/compact指令与自动阈值触发这两种方式

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/compact.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    compact记忆压缩处理的细节
</div>

### 总结/收获/takeaway
1. 结构化优于自由文本：限定[记忆四种类型](#four)user/feedback/project/reference和frontmatter格式$\rightarrow$给记忆定一个schema，强制每条都填齐
2. 索引常驻+内容按需：这个思路不只适用于记忆系统，任何“内容总量大但只有少数需要展开”的场景都可以套：长RAG文档、知识库、tool列表、历史PR、代码片段等
3. 廉价模型做选择题：只要候选集合不大 (几百以内)，用小模型选择 (自然语言判断、可解释、可控、准确度较高)优于向量检索 (数学计算、算力要求高、未必准确)
4. 时间感知+主动验证：记忆系统最大的风险，不是召回不准，而是召回了一条已经过时的记忆，agent盲目相信。这种错误特别隐蔽，因为模型把记忆当ground truth，错也不知道是错。claude code的记忆老化+agent被提醒后主动验证时效性，有效避免记忆过时的问题



# 参考文献
1. [claude-code-analysis仓库](https://github.com/liuup/claude-code-analysis/tree/main)
2. [小林coding的Claude code源码解析](https://xiaolinnote.com/claudecode/source/cc_source.html)
3. [小林coding的Claude Code记忆机制图解](https://xiaolinnote.com/claudecode/source/cc_memory.html)