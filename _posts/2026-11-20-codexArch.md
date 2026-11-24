---
layout: post
title: Codex系统架构、上下文管理和记忆系统深入解析
date: 2026-11-17 13:54:00
description: 本文结合Codex源码，详细分析了Codex系统架构、上下文管理和记忆系统的方案设计、选择理由和实现细节。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了本文结合Codex源码，详细分析了Codex系统架构、上下文管理和记忆系统的方案设计、选择理由和实现细节。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

---

# codex架构
## agent loop循环
* <mark>模型继续调用tool_call，循环会继续</mark>：tool_call会导致needs_follow_up = true，从而使agent loop继续 (去执行工具，把结果喂回模型，下一轮模型看到工具调用执行结果之后再决定下一步)；因为<mark>上一轮循环请求的工具调用，会在当前这个处理流程内立即被派发并执行完成，但执行结果FunctionCallOutput只会在下一次模型采样请求/下一轮LLM调用的输入历史中才能被模型看到</mark>；存在情况导致循环提前终止，用户看到的LLM输出不完整
* <mark>模型不调用tool_call，循环是否结束取决于needs_follow_up标志：模型没有继续调用工具tool_call，任务也不一定立刻结束</mark>，主循环还要确认：有没有用户刚补充的要求、有没有尚未处理的错误、LLM用end_turn表示有没有说完 (在LLM API中由模型提供商返回，harness不自己解析LLM的输出内容来判断话有没有说完，有的模型不提供这个字段)以及停止前的检查是否允许结束；如果用户追加了要求、或者停止前的钩子Stop Hook补入了需要继续处理的内容、或者end_turn表示LLM还没说完，agent可能再执行一轮

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/tool_call.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    agent loop是否继续，取决于needs_follow_up标志
</div>


## App Server接入
App Server解决接入问题，因为codex包含终端CLI、IDE插件和Chatgpt桌面应用，它们使用同一套harness；<mark>App Server把用户界面发来的需求转交给核心处理逻辑，再把模型输出、工具进度和审批请求传回界面</mark>

## StepContext请求级快照
前提：codex允许配置在请求执行期间刷新，即配置热更新；因为codex的配置刷新是通过独立的RPC请求触发的，不需要等待当前的模型采样请求完成。也就是说，模型请求正在飞行时，后台完全可以刷新MCP服务器列表、用户配置等

StepContext在每次需要新的步骤上下文时 (如新一次循环turn/新一次模型请求、模型重试、子agent启动等)被捕获，固定本次请求使用的模型设置、环境视图、MCP 绑定、工具路由、AGENTS.md等 (配置在turn级别或会话session级别变化，而不是在单次sampling请求飞行中变化)；StepContext不可变，不修改旧的StepContext，而是丢弃旧的、重新捕获一个新的

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/stepContext.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    为什么需要StepContext：让本次模型请求发起时可见的工具列表与本次工具调用返回后的分发逻辑保持一致，不会因为中途配置刷新而导致“工具突然找不到”
</div>

## 统一消息格式
codex内部有一套统一的消息格式，提供商需要自己兼容OpenAI Responses API，或者通过代理来适配；codex本身不为每个提供商维护一套不同的消息格式转换逻辑，不需要为每个模型提供商分别把消息改成各自指定的格式


## /goals模式
参考[openai官方博客](https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex)

适用条件：任务有明确的终止/准出条件，但是达成任务的方式不明确或者需要好几轮调查才能完成；发现自己在每一轮都在重复说keep going/again/continue/next；任务的下一个正确动作取决于codex在上一个动作中刚刚学到的知识，即目标是持续的

有持续目标，codex自己循环直到达到停止条件 (如成功完成、暂停、打断、token预算限制、等用户输入)；每一轮结束的时候，codex检查当前证据并判断目标是否满足，如果不满足就接着上一个状态继续执行



# 上下文工程
## 压缩/compact
### 自动压缩的2个位置/时机
真正决定上下文压力的~~不是消息数量 (因为一条工具结果可能比几十轮普通对话还长)~~，而是token用量；codex会维护当前上下文的token使用状态，优先采用服务端反馈，必要时再根据历史估算，然后把当前用量和自动压缩阈值 (可提前设置，<mark>不会等上下文窗口彻底塞满才处理</mark>)进行比较，当历史继续增长并达到阈值，才轮到真正的上下文压缩：

* 新轮次开始前：压缩不能只发生在两轮对话之间，因为如果只在新轮次开始前检查，那么某次工具调用突然带回大量日志的情况就漏掉考虑
* 轮次运行中，工具结果把上下文推到阈值后：codex干活干到一半，也可能先整理上下文腾出空间，再接着往下做

### 怎么压缩
codex会<mark>根据配置和模型服务能力选择压缩方式：启用token 预算策略时，达到预算后直接建立新窗口，不再生成摘要；否则，服务端支持远程压缩就交给服务端处理，不支持才使用本地总结</mark>

压缩结果还会作为恢复点checkpoint写入rollout，之后恢复任务/会话时，可以从最近一次有效checkpoint接上后续记录，见[会话持久化的会话如何恢复部分](#会话如何恢复)

#### 本地总结路径
step1. 把当前历史连同一条专门的压缩指令交给模型，让它先整理一份供后续请求使用的<mark>交接摘要</mark>，覆盖当前进度、关键决定、用户偏好和限制、剩余工作以及继续任务所需的重要数据，必须继续回答最后选了哪个方案、为什么、哪些文件已经改过、测试还差哪一步、哪条路已经证明走不通，让模型在处理后续请求时知道任务做到哪一步、接下来还要做什么

step2. <mark>本地压缩并不是只留一段摘要，还会保留一部分用户原话</mark>，能保留多少取决于可用的token空间；空间有限时，优先保留最近的消息，再把交接摘要接在后面；尤其是明确的需求和约束，用户原话通常比模型的二次转述更值得保留；~~旧工具调用、旧工具结果和大量中间过程不会继续完整占据当前窗口~~，这些过程最后得出的结果，会写进交接摘要

step3. 摘要可能漏掉项目规则，这些规则codex会单独提供：基础指令本来就随每次请求发送，项目规则、开发者要求和环境信息也会重新补上；即使摘要没提到某条规则，模型仍然能看到它




# 会话持久化
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/restore.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    会话恢复的大致流程
</div>

## 会话如何存储？
### rollout JSONL文件 (权威历史)
<mark>原始对话历史 (用户消息、模型输出、工具调用、事件和上下文变化等)不逐条写入数据库，而是持久化为磁盘上的rollout JSONL文件</mark>，即名为rollout文件，以JSONL格式存储；一个thread_id对应一个活跃的rollout JSONL，因为一个session_id下可以有多个thread_id (根线程、fork出的子线程、subagent等)；但一个thread_id不一定只对应一个rollout文件，因为执行thread/revert后，thread_id保持不变，但会话会切换到一个新的rollout文件。此时同一个thread_id对应多个rollout文件 (旧的作为历史快照，新的作为当前活跃文件)，同一个thread_id可以指向不同日期目录下的不同rollout文件，光靠文件名无法判断哪个是当前选中的

rollout文件的路径：
> $CODEX_HOME/sessions/YYYY/MM/DD/rollout-\<YYYY-MM-DDThh-mm-ss\>-\<thread_id\>.jsonl

rollout JSONL文件的内容包括：
* 首行：SessionMetaLine会话元数据 (会话id、线程 id、时间戳、cwd、模型提供商、source、历史模式、base instructions、git信息等)
* 后续行：按时间序排列的rolloutItem，包括用户消息事件、模型响应ResponseItem、工具调用输出、turn上下文、token用量、压缩标记compacted等

rollout JSONL记录的~~并不是和会话相关的全部内容~~，而是只记录可回放的历史事件序列。某些展示/查询用元数据 (如preview、title/name、section、section_position、archived_at、recency_at等)主要存储在SQLite中，作为可重建的查询索引

### SQLite数据库 (可丢失、可重建) {#sqlite-index}
为什么需要SQLite数据库：
* 因为rollout JSONL文件每次只能顺序追加，不适合做“列出所有会话”“按XXX字段 (如section)筛选/排序””这类查询。如果没有SQLite，做list_threads或read_thread时，代码必须扫描整个$CODEX_HOME/sessions/目录，逐个打开JSONL读取首行SessionMeta，才能拼出会话列表，会话多了之后，这次全盘扫描的代价很高；SQLite把这些元数据做成索引行，查询即可返回，不需要触碰磁盘上的大量JSONL文件
* 路径里包含日期目录，光有thread_id无法直接构造路径：路径里带thread_id解决的是“已知完整路径时如何读取文件”的问题；SQLite解决的是“只知道thread_id如何快速找到文件”以及“如何高效列表/筛选会话”的问题
* 归档、压缩、移动会导致物理路径变化：会话可以被归档 (移到archived_sessions/)，也可以被压缩 (后缀变成.jsonl.zst)，此时原始的sessions/YYYY/MM/DD/...路径就不再准确；<mark>SQLite里的rollout_path会在sync_materialized_rollout_path中更新，始终指向当前当前活跃的rollout路径，而不是历史所有文件，而JSONL文件名本身不能可靠反映这些状态变更</mark>

SQLite数据库充当可重建的查询索引和元数据缓存 (SQLite里的数据即使丢了，也可以从JSONL重建，所以它不是历史权威，只负责快速索引)，核心作用：
* 建立thread_id → rollout文件完整绝对物理路径的映射 (尽管rollout文件名反应了和thread_id的关系，但是使用SQLite读取线程元数据，可以快速定位rollout路径，避免全盘扫描sessions/目录)；SQLite执行get_thread(thread_id)时，直接返回完整路径，代码不需要自己拼日期目录
* SQLite里的ThreadMetadata还缓存preview、title、cwd、model、recency_at、archived_at、section等字段，供list_threads/read_thread快速查询：这些值确实不会频繁变成版本记录，但它们会被反复读取 (如列表页、会话卡片、排序)。把它们缓存在SQLite里，是为了避免每次都去解析JSONL，属于典型的“读多写少”的索引场景；而且读取元数据不需要解析整个JSONL文件，直接从数据库行返回，速度远快于解析JSONL


## 会话如何写入？
<mark>产生新事件 (用户消息、模型响应、工具调用输出等)时</mark>，每条事件是一个rolloutItem，序列化为JSONL一行，顺序追加到rollout文件末尾并flush立刻落盘，~~而不是等到shutdown才一次性落盘~~

rolloutItem包括：
* RolloutItem::ResponseItem：模型响应或用户消息
* RolloutItem::TurnContext：轮次上下文
* RolloutItem::EventMsg：TurnStarted/TurnComplete等事件
* 其他元数据项：工具调用、Token使用等通过ResponseItem承担

## 会话如何恢复？
step1. 找到该会话对应的rollout文件，解析rollout路径

step2. 从rollout JSONL重建历史/模型可见上下文，决定要回放哪些RolloutItem：
* 历史不只有在rollout文件中，调用方/上层业务层可以在内存中持有history并传入，原因包括：
  * 上层可能已经读取并缓存过该会话的历史，不想重复读盘
  * 在fork或某些跨进程/跨会话场景下，希望复用之前已构造的历史快照
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/rollout.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    历史来源的几种情况
</div>

* 两种回放方式：

| 对比维度 | Legacy模式 | Paginated模式 |
| :---: | :---: | :---: |
| 读取方向 | 从文件开头顺序读 | 从文件末尾反向扫描 |
| 读取范围 | 全部rolloutItem | 最新合法compaction及之后新增的消息和工具结果suffix；若找不到合法compaction，则退化为读全部 (因为压缩发生时，codex还会额外写入一条压缩记录compactedItem，保存替代历史以及恢复这个上下文窗口所需的元数据；压缩不是偷偷改完内存就算了，它会留下一个明确的恢复点) |
| 适用场景 | 历史较短，需要完整重放 | 历史很大，只需加载最近模型可见上下文，避免每次resume读数GB的JSONL |

step3. 历史加载完成后，打开已有的rollout文件 (而不是新建文件)准备继续append_items追加rolloutItem到文件末尾

step4. 顺序回放这些rollout项、重建状态，包括：
* 会话元数据：SessionMeta包括cwd、模型、历史模式等
* 对话历史：用户消息、模型响应、工具调用、turn边界等
* 模型可见上下文：用于后续采样
回放完成后就处于与会话中断前一致的状态，可以继续处理新的用户输入



# 记忆系统
## 记忆存储结构
使用<mark>SQLite数据库</mark>存储会话元数据 (参考上面[会话持久化](#sqlite-index)部分)、任务租约状态和模型提炼后的记忆产出，对应数据库表：
* threads表：字段包括id, rollout_path, updated_at_ms, source, memory_mode等，一行=一个 thread，存的是会话元数据
* jobs表：用于租约抢占、重试、成功水位
* 记忆产出表stage1_outputs表：存每个thread提炼后的raw_memory阶段一模型生成的原始记忆文本、rollout_summary阶段一模型生成的详细任务历史摘要等 (<mark>都是阶段一产出，阶段二产出不在数据库</mark>)，因此~~不是每一条历史都记录在数据库中 (那是历史权威，存储在rollout JSONL里)~~，<mark>只有满足筛选条件的线程才会进入数据库</mark>；一行=一个thread的stage-1提炼产出$\rightarrow$所以<mark>记忆内容相当于是session memory</mark>
  * raw_memory是面向未来复用的结构化记忆素材，解释下一次agent需要做什么去节约用户时间 (在记忆管线版本V2中删除，但默认使用V1)：按任务分组写Preference signals用户偏好证据、Reusable knowledge已验证事实、过程快捷方式、失败防护、Failures and how to do differently、References命令、路径、错误串等可直接复用的检索句柄；
  * rollout_summary是该会话的“发生了什么”记录：它保留足够细节，让未来agent无需重新打开原始rollout就能理解本次会话；采用任务优先结构 (outcome、preference signals、key steps、failures、reusable knowledge、references)；内容可以比较详细，因为它是未来agent回顾此次具体会话的参考文物
  * <mark>stage1_outputs表里的raw_memory/rollout_summary只是阶段一的中间产出，供阶段二消费，不是最终记忆加载/召回的对象</mark>

原始对话历史 (消息、工具调用等)不逐条写入数据库，而是持久化为磁盘上的rollout JSONL文件 (参考上面[会话持久化](#rollout-jsonl文件-权威历史)部分)


## 记忆怎么沉淀？
### 沉淀前提
当前App Server (连接客户端和agent运行核心，负责传递用户请求与执行事件)会在带输入的新轮次成功启动、运行环境准备好后，尝试调度后台记忆任务。真正启动前，还要确认长期记忆功能已经开启、当前会话不是临时会话或子agent会话、状态数据库可用，账号剩余调用量高于系统设置的阈值、有可以处理的候选历史。任一条件不满足，这次后台记忆任务就直接跳过。所以长期记忆不是每轮结束立即保存的固定步骤，也不能假定每个安装都默认启用；记忆系统是异步的：前台任务可以继续执行，后台流程在条件满足时处理符合要求的旧历史

### 沉淀过程
step1. (阶段一)后台流程不会拿到一条历史 (<mark>指一个完整的会话thread</mark>)就~~立刻提炼~~，而是<mark>先按会话来源、时间、空闲状态、记忆配置和数量限制筛选候选，再通过任务租约抢占处理资格</mark>$\rightarrow$阶段一的作用是积累候选、过滤无效历史、对单个thread做初步总结：
* 不是每一条历史都会被记忆，过滤规则包括：
  * 会话来源 (来源白名单)：只处理交互式会话来源 (包括原始CLI会话、VS Code会话、Atlas来源和Chatgpt来源)，不在白名单里的历史 (例如某些非交互式/内部会话)直接被数据库过滤掉，不会进入候选
  * 记忆配置开关：每条线程级的开关memory_mode = 'enabled'，只有用户开启了记忆的会话才会被考虑
  * 排除“当前正在进行”的会话：正在跑的当前线程本身不作为记忆提取的来源，避免对未完成历史做提炼
  * 时间窗口既不能太旧，也不能太新 (必须空闲足够久)：历史<mark>必须“已经结束并空闲了一段时间”</mark>，刚结束不久的 (所以不是立刻记忆)、或几年前的会话都不会被这次处理
  * 排序与数量限制：最多扫scan_limit (5000)条，最终最多认领max_claimed (默认2)条
  * 丢新检查：若stage1_outputs里已有该thread的输出且其source_updated_at$\ge$当前来源时间就不再重复提炼；所以同一个thread不会因为多次启动而重复产生阶段一记忆，避免了同一会话内的无谓追加
* 任务租约抢占处理资格，原子性地抢占数据库中的任务行：对于有处理资格的历史记录，租约相当于一把有时间限制的锁，抢到之后才会真正读取rollout、调模型LLM做提炼；一个后台任务拿到以后，其他后台任务暂时不能处理同一份历史；即使任务中途异常退出，锁到期后也会自动释放，材料仍能被后续任务接手
* 优缺点：不用等记忆整理完，当前任务就能继续 (因为不是立刻记忆)；刚做完的任务也会先放一放，避免结论还在变化，就急着记下来 (空闲不够久的历史不记忆)；但是刚积累的新经验也不会马上出现在长期记忆里

step2. 候选选中后，<mark>模型从这次任务中提炼结构化的原始记忆和任务摘要 (所以每一条记忆是大模型LLM总结提炼出来的</mark>，调用配置的模型提供者，向LLM发起1次请求，记忆提炼可以和主agent用同一个模型，也可以单独配置一个不同的模型)，目标是留下可复用偏好、有效步骤、失败教训等信息；如果这次任务没有值得长期保留的内容，也允许没有产出

step3. (阶段二)跨thread (即跨任务)整理记忆&全局记忆合并：把多个不同thread中阶段一产生的记忆产出汇总到一起，再做<mark>跨会话/跨任务的去重、压缩和重写$\rightarrow$阶段二的记忆才是模型最终加载/召回的记忆</mark>，阶段二目的是沉淀可用记忆：
* 整理的原因：阶段一作用有限+单任务记忆只是材料，还不是一份容易使用的知识；同一项目在不同任务/thread中可能重复记录同一条命令，也可能保留已经变化的项目约定 (e.g.同一个项目可能在三项任务里都提到测试命令；一项任务说旧命令可用，另一项任务后来发现它已经失效；用户对表达风格的要求，也可能经过几次纠正才逐渐稳定)；如果把这些材料按时间不断追加，模型下次会读到大量重复甚至互相冲突的内容。阶段二产出的才是可复用的记忆
* 整理过程：
  * 先取得<mark>全局租约，给整个整理过程加锁 (锁住的不是某一段历史，而是整份共享记忆，因此同一时间只允许一个整理agent改写</mark>)
  * 先<mark>选择数据库的stage1_outputs表产出 (包含先前选择的历史信息和总结摘要)，同步到磁盘上的记忆工作区文件/.md文件，并用git diff比较内容是否发生变化</mark> (把同步后的记忆工作区文件，与上一次Phase 2完成后建立的Git baseline初始提交做对比，看工作区里的文件有无增删改)，<mark>agent可以编辑记忆文件</mark>
  * 需要更新时，spawn agent启动一个专门的独立的整理agent实例；没有变化且现有产物通过检查，就可以跳过本次整理；整理agent本身还是临时内部任务，会关闭再次生成和读取记忆、递归协作等能力，避免整理过程再次触发自己
  * 所以阶段二的产出不存回数据库的stage1_outputs表，阶段二读取数据库的stage1_outputs表作为输入，将结果写入文件系统的内存工作区 (.md文件)；阶段二产出的记忆工作区中的文件包括：
    * memory_summary.md：阶段二最终输出的高密度索引汇总记忆，记忆加载时直接读取此文件、<mark>注入到system prompt中</mark>
    * MEMORY.md：耐用的检索导向手册，比memory_summary.md更详细、更具体，但比raw_memories.md更精炼
    * raw_memories.md：阶段二同步阶段从数据库写入工作区的中间/输入文件，把多个thread的raw_memory合并写入的中间文件，供consolidation agent参考
    * rollout_summaries/\<thread_id\>.md：阶段二同步阶段从数据库写入工作区的中间/输入文件，每个选中thread的rollout_summary独立写入的文件，供consolidation agent参考


### 记忆内容
记忆内容相当于是session memory，~~不是user全局用户画像/agent/team档案~~，但会保留具体任务里的用户请求 (但只能作为某个具体task里的证据存在，必须附着在该task的上下文中，不能独立成一个全局用户画像)、反复要求事项、被中断纠正、约束、偏好证据，以及文件/命令/错误等引用，~~没有面向“整个用户和项目协作过程”的长期记忆表或全局知识库结构~~



## 记忆怎么加载/导入&召回？
记忆加载/导入的条件：记忆读取功能启用，而且已经存在非空摘要

记忆加载/导入的内容：不直接查数据库stage1_outputs表，而是只读取阶段二沉淀到记忆工作区里的文件memory_summary.md (尽管阶段二沉淀到记忆工具区的文件有很多)

记忆加载/导入的流程：渐进式读取

step1. 摘要先行：把<mark>memory_summary.md始终注入system prompt</mark>；memory_summary.md里的\#\#What's in Memory部分充当静态索引，告诉agent某个项目的细节在MEMORY.md的哪个Task Group，某个技术细节在rollout_summaries/xxx.md；agent读到这个索引后，可以主动调用memory_search工具去定位，再用memory_read工具把详细内容读进来；模型先看到过去大概有哪些经验，判断是否与当前任务相关

step2. 按需搜索：需要细节时，再通过专用工具搜索详细记忆，继续读取任务摘要和可复用步骤；当前本地搜索主要按照<mark>文字/字符串匹配，找到以后只返回命中行前后context_lines行的小片段</mark>，~~没有语义理解或向量嵌入~~；agent读到这个片段后，如果需要更多细节，可以再调用memory_read工具，指定line_offset和max_lines继续按行读取，这样不用把整份记忆都读进来
* 字符串匹配的优缺点：精确、可解释，但如果两段话意思相近、用词却不同，就可能搜不到
* 后续处理：模型在依赖记忆回答时附带结构化引用，例如记录使用了MEMORY.md的哪几行，以及这些记忆来自哪个rollout；codex会根据来源任务ID更新记忆的使用次数和最近使用时间，这些信号再参与后续材料选择

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/memoryTools.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/codexMem.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    记忆搜索使用的工具；召回请求和返回结果的数据结构
</div>

## 记忆怎么更新/删除？
结合每条记忆的使用情况 (被使用的次数)、距离上一次使用的时间 (越久越不保留)和记忆总量不超过设定上限，按照综合得分来选择要保留的记忆，清理未被保留的记忆 (~~不是立刻删除~~)：从第一阶段提炼的经验记录中筛出仍在保留期内的记录，再参考使用次数和最近使用时间，选出一部分交给第二阶段整理；那些长期没用、上一轮整理也没选中的经验记录，会被分批清理，但删掉这些原始材料，不会立即改动MEMORY.md和memory_summary.md，要等下一次整理，这两份供模型查阅的文件才会更新



# 参考文献
1. [小林coding的Codex Harness 架构图解](https://xiaolinnote.com/codex/source/codex_harness.html)