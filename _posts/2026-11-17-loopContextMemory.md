---
layout: post
title: Agent Loop、上下文工程和记忆系统学习笔记
date: 2026-11-17 20:18:00
description: 本文整理了agent harness中Agent Loop、上下文工程和记忆系统的学习笔记。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了agent harness中工Agent Loop、上下文工程和记忆系统的学习笔记，便于读者将工业级工具调用知识应用到实际项目中。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

---

# 系统整体loop架构
## 业界agent loop实践对比
* 追加输入：harness运行时可以随时添加新输入消息，已经发出去的模型请求不会凭空多出新内容，主循环会在合适的边界取走这条输入，让后续请求看到 (目前知道claude code可以)
* 循环结束/继续条件由harness说了算：
  * 模型继续调用工具，会继续循环，除非遇到异常情况错误退出
  * 模型没有继续调用工具，任务也不一定立刻结束：harness在收到非tool_use后，仍有最终否决权或强制继续权


|  | Codex | Claude Code | Pi |
|:---:|:---:|:---:|:---:|
| 是否有harness内部统一消息格式和model provider各自消息格式的转换和处理机制 | 无，提供商需要自己兼容OpenAI Responses API，或者通过代理来适配 | 无，只支持Anthropic生态内的4个提供商 | 有，翻译器给所有LLM Provider做一层封装、让它们看起来都一样 |
| 是否存在App Server | 有，把用户界面发来的需求转交给核心处理逻辑，再把模型输出、工具进度和审批请求传回界面 | 无 (需显式启动) | 无，本地运行的CLI进程、启动即退出，不存在长驻的后端服务器进程 |
| 每次循环/LLM请求前是否存在快照保存配置、达到固定本次请求上下文的效果？ | 允许<u>配置热更新/配置在请求执行期间刷新</u>，有StepContext | 无，<u>在一次while(true)迭代turn结束、下一次迭代turn开始之前的迭代间隙才支持刷新配置/工具列表</u>(权限规则异步读取、可以是最新的，但是不影响因为LLM看不到权限规则，权限规则只在工具执行时生效)，~~不能在单次callModel请求期间刷新~~ | 允许外部在循环中动态切换下一轮的配置 (如更换模型/思考强度、注入新上下文信息)：prepareNextTurn在工具调用之后、<u>下一轮循环/turn开始前被调用</u> |
| 追加输入 | 新消息先进输入队列，主循环会在合适的边界取走这条输入，让后续请求看到 |  | steering插队 (当前 assistant turn的工具调用全部执行完、下一次LLM调用之前注入)/follow-up排队消息 (没有更多工具调用且没有steer消息时，即整个内层循环结束后) |


# 上下文工程 {#contextEngineering}
## 为什么需要上下文？
上下文是多轮对话系统最基础的能力之一。它至少解决三类问题：
* 多轮会话连续性：让模型知道上一轮说过什么；例如先自我介绍，再追问名字、偏好、之前说过的内容
* 会话个性化&保存当前会话上下文：让模型记住用户在当前会话里提供的信息，如名字、偏好、任务背景；例如用户正在做一份简历、正在学习Python、正在整理某份报告，后续问题不必每轮都重述背景
* 多步任务承接：让模型把前一步结果作为后一步输入，而不是每轮都重新从零开始

没有上下文，聊天系统就只是“连续发了很多次单轮请求”；有了上下文，它才真正开始像“对话”；上下文本质~~不是“模型真的记住了”~~，而是程序把之前的消息保存下来，并在下一轮调用前，再把这些历史消息一并传给模型；所以它更像一种“外部会话状态管理机制”，~~而不是模型参数层面的学习~~

## 业界上下文工程实践对比

|  | Codex | Claude Code | Pi |
|:---:|:---:|:---:|:---:|
| 系统提示词构造 |  | ~~不是一个静态的文本文件~~，而是动态组装的，由十几个section拼接而成 |  |

# 会话持久化
## 概念区分
上下文工程$\neq$持久化历史和状态重建$\neq$记忆系统
* 上下文服务下一次模型请求：agent正在处理当前任务，下一次模型请求需要知道刚才读了什么、改了什么
* 持久化历史服务原会话恢复：你关闭界面，后来重新打开原来的会话，希望继续之前的工作
* 记忆系统/长期记忆尝试把跨任务仍有价值的信息带进新任务：你创建了一个全新的会话，希望过去积累的项目经验仍然能派上用场

## 业界会话持久化实践对比


|  | Codex | Claude Code | Pi |
|:---:|:---:|:---:|:---:|
| 存储结构 | rollout JSONL文件 (权威历史)+SQLite数据库 (可重建快速索引) | JSONL格式的主transcript+subagent transcript | 本地JSONL文件 (物理结构)+<u>session tree</u> (逻辑结构) |
| 写入时机 | 产生新事件 (用户消息、模型响应、工具调用输出等)时 | 在<u>每轮对话</u>结束后，把新产生的消息批量传入 |  |
| 落盘时机 | rolloutItem顺序追加到rollout文件末尾并flush<u>立刻落盘</u> | 底层<u>异步批量flush</u> | <u>会话延迟写入策略：首次assistant消息到达前延迟写入</u>，之后再每次立刻写入 |

# 记忆系统
## Preliminary: LLM本身无状态
LLM本身根本记不住任何东西，它是彻头彻尾无状态的：每次对话query都从头把系统提示词、所有历史对话、当前问题重新看一遍

记忆本身分为两类：
* 短期记忆/上下文窗口本身：回到[上下文工程](#contextEngineering)这一段查看
* 长期记忆/持久化存到磁盘&跨会话：包括
  * 静态的AGENTS.md或CLAUDE.md文件：本质是声明式指令，你写好放那里，agent启动时全量加载；这一层解决的是“我们怎么协作”“这个项目要遵守什么规则”这种确定性的事情 (但是AGENTS.md或CLAUDE.md得自己主动写，而不会自动记录)
  * 动态的记忆系统：本质是学习式偏好，agent在互动的过程中，把它认为“值得记下来的事”自动写成记忆文件存到磁盘上，下次对话再按需检索；这一层解决的是“我从跟你的互动中学到了什么”这种不确定的事情 (而且能实现自动记录沉淀)



## 做法
### 业界主流做法
#### 滑动窗口
把最近N轮对话原样保留，超过N轮的就丢掉

问题：丢掉的早期记忆并不一定是没用的 (比如用户在第1轮对话query中提到自己的身份等用户画像、规则)，滑动窗口把关键信息和过期的无关信息/噪声一起丢掉了

#### LLM总结记忆
定期把旧对话用LLM总结一下，把摘要塞回上下文

问题：
* 压缩时精度/粒度不够，可能会丢失重要细节 (比如用户在20轮前说过一句“我们的API gateway用的是Kong，不是nginx”。LLM做摘要的时候觉得这句不太重要，就压成了“讨论了一些技术栈细节”。等下一次你问“我们的API gateway怎么排查502”，agent完全不知道你用的是Kong，按nginx给你答了一通)
* LLM做摘要需要消耗token、有延迟，每隔几轮就总结一次的成本不低

#### 向量检索:fire:
这是目前最热的方案。用向量数据库，把记忆存成embedding (给每段文字在一个高维空间里标一个坐标，意思相近的两段话，坐标也会靠得近)，每次对话时做相似度检索：先把用户当前的问题query也转成向量，然后跟数据库里所有记忆比一比坐标远近，召回最相似的前K条 (top-K)塞回上下文


问题：Agent需要记住的大部分不是“相似的文档片段”，而是“用户说过'不要mock数据库'”这种结构化的行为指令。用向量相似度去检索“不要mock数据库”这句话，效果其实很差，它可能匹配到一堆包含“数据库”关键词的无关内容，真正重要的行为反馈却被淹没了

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/database.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    向量数据库检索的问题 (召回不准、遗漏、噪音，效果不稳定)
</div>

#### 分层存储
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/layer.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    分层存储记忆系统的原理和问题 (设计复杂、调参和维护成本高)
</div>

#### 共同问题
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/drawbacks.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    业界主流记忆系统做法的共同问题
</div>

### Claude Code的做法
见我的[Claude Code系统架构、上下文管理和记忆系统深入解析](https://clementineyyy.github.io/blog/2026/claudecodeArch/#%E8%AE%B0%E5%BF%86%E7%B3%BB%E7%BB%9F)

### 业界记忆系统实践对比
相同点：
* 每一条记忆都是大模型LLM自己总结提炼出来的
* 记忆召回框架是先.md文件导入system prompt，再按需搜索

|  | Codex | Claude Code | Pi |
|:---:|:---:|:---:|:---:|
| 物理存储结构 | 阶段一SQLite数据库+阶段二文件系统 | 文件系统：MEMORY.md+独立记忆文件 |  |
| 记忆时机 | 一系列触发条件，包括空闲时间够久，所以不是立刻记忆 | auto memory和team memory每轮对话query结束后记忆、session memory有触发条件、agent memory由agent自己决定 |  |
| 记忆内容 | session memory以及基于该thread的用户请求、反复要求事项、被中断纠正、约束、偏好证据，以及文件/命令/错误等引用 | 4种存储层次+4种记忆分类 |  |
| 记忆沉淀方式 | 两阶段分别沉淀，<u>记忆的删除需要额外判断</u> | extractMemories+不同存储层次不同沉淀方式 (<u>记忆的更新和删除~~并没有走一条独立于沉淀的专用路径~~，而是与沉淀共享同一套机制</u>) |  |
| 记忆加载方式 | 只加载memory_summary.md到system prompt | auto memory、agent memory和team memory (后两者如有)的MEMORY.md始终加载到system prompt |  |
| 记忆召回方式 | <u>关键词字符串匹配搜索，只返回命中行前后context_lines行的小片段</u> | 扫描最近记忆文件的frontmatter拼成文本清单，由廉价<u>小模型Sonnet选择并返回文件名列表JSON schema</u> |   |




# 参考文献
1. [小林coding的Claude code源码解析](https://xiaolinnote.com/claudecode/source/cc_source.html)
2. [小林coding的Claude Code记忆机制图解](https://xiaolinnote.com/claudecode/source/cc_memory.html)