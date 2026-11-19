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
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/ccloop.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    claude code agent loop流程。注意，这不是传统意义上的ReAct Loop，而是Tool-use Loop。循环时由LLM每次看到当前的对话上下文后，自主判断“我现在应该读个文件”还是“我应该执行一条命令”还是“我可以回复用户了”
</div>

loop的关键设计原则是不包含任何业务逻辑，它不知道怎么读文件、怎么改代码、怎么搜索，这些全是工具层的事。引擎层只做三件事：第一，协调，把用户输入、系统指令、历史对话拼在一起，发给大模型；第二，分发，大模型说"我要用某个工具"时，找到对应的工具并执行；第三，决策，根据大模型的返回决定是继续循环还是结束对话。这种设计的好处是：新增能力只需要新增一个工具，循环完全不用改

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
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/benefit.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    claude code使用Tool-use Loop的好处
</div>

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



# 上下文管理
## 上下文里有什么
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/content.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    claude code上下文里有什么
</div>

# 记忆系统
## 整体结构：多层文件化记忆系统
核心不是“把内容记住”，而是“把不同生命周期、不同作用域、不同可见性的内容分开保存”，每一层各自有独立目录、独立prompt、独立更新策略
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

## 记什么：4种记忆分类
只有这4种分类，不能添加新分类；也不存在通用的any类型，避免无约束的记忆迅速膨胀成垃圾堆；逼agent做分类决策，必须考虑清楚每一条记忆属于哪一类

1. User用户画像 (角色、偏好、知识水平)：比如用户说“我是一个写了十年Go的后端工程师，第一次接触React”，agent就应该在解释前端概念时用后端的类比，而不是从零讲起。这类记忆让agent的回答因人而异，而不是千篇一律
2. Feedback行为反馈 (该做什么、不该做什么)：记住用户说过"不要做什么"和"做得好继续保持"。这类记忆的关键在于，它不仅记规则本身，还要求记录Why为什么和How to apply怎么应用 (因为当遇到边缘情况的时候，agent需要根据Why和How来判断这条规则在这个场景下是否适用；否则只是盲目遵守，太死板、不会灵活变通、在不该用的场景也强行套用规则)
3. Project项目动态 (在做什么、截止日期、协作信息、有什么重要决策)：特殊要求是必须把相对日期 (比如周四)转成绝对日期 (具体到明确的年月日)
4. Reference外部指针 (去哪能找到什么信息)：价值在于，agent不需要知道外部系统的具体内容，只需要知道去哪里找

明确规定不记什么：核心原则：可以从当前代码推导出来的信息，一律不存 (因为代码随时在改变，而记忆没这么灵活)
* 代码模式、项目架构和文件结构：因为这些信息通过grep、git、CLAUDE.md就能获取，而且常常发生修改，存在记忆里反而会导致记忆和代码实际状态不一致，并且加重了记忆负担
* Git历史和最近的改动：git log和git blame才是权威来源，不需要记忆系统再来存一遍
* 调试方案和修复方法也不记忆：因为修复已经在代码里了，commit消息已经记录了上下文
* CLAUDE.md里已经写了的内容也不存，避免重复
* 临时任务状态和当前对话上下文：这些是会话级的信息，不需要跨会话保持


## 怎么记/底层存储逻辑：文件夹+MEMORY.md索引
系统把MEMORY.md当成入口索引文件，而不是正文存储文件

设计意图的好处：
* 每条memory单独写成一个markdown文件，独立文件存储每条记忆；文件开头有一段YAML格式的元信息 (可以理解为这条记忆的身份证)包括：
  * name是人类可读的标识
  * description是一句话摘要，专门用于检索时的相关性匹配
  * type标记四类型之一： user/feedback/project/reference
* MEMORY.md是一个不超过200行并且小于25KB的轻量目录，只维护索引链接和一行描述
* agent/model在prompt里默认只保证看到MEMORY.md (始终加载到system prompt中)
* 需要更细节时，再去读具体memory文件 (按需加载独立记忆文件)

这比把所有记忆堆在一个大文件里更稳，因为大文件很容易造成：prompt爆炸、占满上下文窗口、更新冲突、历史垃圾无法治理、单条错误记忆污染整份上下文

## 记忆是怎么沉淀下来的？
### Auto Memory
包括用户长期偏好、项目外部上下文、非代码内生知识、需要跨会话延续的协作约束。

Auto Memory的更新不是靠当前主线程agent每次都手动完成，而是在每轮对话结束后由后台提取流程extractMemories读取新消息并主动写入md记忆文件：复用主对话的同一个大模型（forked agent），通过运行一个子agent查询循环来读取最近消息并写入记忆文件

### Session Memory
记忆条件：触发条件才记忆
* 会话没长到一定程度，不启用Session Memory (minimumMessageTokensToInit = 10000)
* 即便已经启用，也不会每轮都更新 (minimumTokensBetweenUpdate = 5000)
* 工具调用次数和token增长都要参与判断 (toolCallsBetweenUpdates = 3)

沉淀方式：注册registerPostSamplingHook，fork一个沙箱化subagent去做摘要。这个subagent权限只有FileEditTool，且只能操作一个精确路径 (createMemoryFileCanUseTool会deny所有其他工具包括FileReadTool/FileWriteTool)
  

### Agent Memory
它不是检索外挂，而是直接改变agent下一次的system prompt起点：agent工作中发现需要记住的信息$\rightarrow$先读MEMORY.md或已有memory文件$\rightarrow$新增/更新memory$\rightarrow$维护MEMORY.md索引$\rightarrow$下次调用同一agent时再次读取同一目录的MEMORY.md文件

主要包含3种信息：
* user：跨项目复用的agent长期记忆
* project：当前项目内共享的agent记忆
* local：当前项目、当前机器或当前挂载环境的本地agent记忆

沉淀方式：agent运行期间，主agent按自身system prompt的保存指令，调用Write/Edit写入MEMORY.md或主题文件

#### 如何加载记忆？
只要agent定义里带了memory字段，系统都会做两件事：
* 自动把memory prompt拼接到agent system prompt后面 (所以agent从第一轮开始就知道：自己的memory目录在哪里、该怎么写memory、MEMORY.md当前有哪些索引；loadAgentMemoryPrompt()加载agent memory prompt)
* 自动把Write/Edit/Read三个文件工具注入到agent的工具列表里

这两步缺一不可：
* 如果只注入prompt，不注入文件工具，agent看得到规则却没法落盘&实际操作
* 如果只注入文件工具，不注入prompt，agent有写权限却不知道memory的目录和治理方式

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/memoryTool.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/agentMemory.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    Agent Memory的沉淀方式：将memory的设置和工具暴露联系起来；agent memory的典型使用流程
</div>

#### Agent Memory Snapshot
snapshot的初始化/更新发生在agent定义加载时

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
    agent memory snapshot的触发条件和处理函数
</div>

### Team Memory


## 记忆怎么进入提示词？怎么召回？
Relevant Memory Recall：不是把所有历史记忆都塞进prompt，而是做选择，从几十条记忆里挑出最相关的那几条加载进来

做法：用一个廉价的小模型Sonnet来做记忆检索

step1. 扫描所有记忆文件 (按修改时间倒序，最多扫描200个文件)的头部信息：只读每个文件的前30行，即frontmatter区域，不读全文；提取文件开头元信息里的name、description、type
step2. 所有记忆的头部信息被拼成一个文本清单 (每一行包括[type记忆类型]记忆markdown文件名 (日期))，连同用户提示词一起发给小模型做选择，小模型返回的只是一个文件名列表 (比如["feedback_no_mock.md", "project_auth.md"])，不是记忆内容本身
step3. 加载选中记忆的完整内容，作为\<system-reminder\>注入上下文

### 细节
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/outdate.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    记忆召回时的处理细节
</div>

如果用户当前正在使用某些工具 (比如正在调用某个MCP工具)，小模型会自动过滤掉该工具的使用文档类记忆，因为模型已经在用这个工具了，它的用法文档此刻是噪声，不是信号；但该工具的已知bug和注意事项类记忆仍然会被选中，正在用的时候，恰恰是最需要知道坑在哪里的时候


### 性能优化：记忆召回的执行时机
小模型侧查询不是在主模型需要时才触发的，而是在用户提交消息后立刻就开始了，和主模型的API调用并行执行；并且小模型比主模型快得多，所以等主模型响应返回时，记忆召回早就完成了，几乎不增加任何额外延迟

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/parallelMemo.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    记忆召回与主模型处理并行
</div>



## 记忆压缩Memory Compaction
为了避免模型的上下文超出上下文窗口大小，需要对记忆进行压缩，有手动/compact指令与自动阈值触发这两种方式

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/compact.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    compact记忆压缩处理的细节
</div>

# 参考文献
1. [claude-code-analysis仓库](https://github.com/liuup/claude-code-analysis/tree/main)
2. [小林coding的Claude code源码解析](https://xiaolinnote.com/claudecode/source/cc_source.html)