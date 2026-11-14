---
layout: post
title: Codex工具调用源码深入解析
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

本文整理了本文结合codex源码，详细分析了codex工具调用的方案设计、选择理由和实现细节。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

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
  * CodeModeOnly / Hidden → 模型在普通对话中完全看不到

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
  * CodeModeOnly：只在代码模式嵌套调用中可见，不在初始列表，不对普通对话模型暴露。这适合那些只应该在代码执行环境内部被调用、不应该直接暴露给模型主动调用的工具。(文件： codex-rs/core/src/tools/spec_plan.rs，line 702-730)
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

* Responses Lite协议：工具定义不放在请求顶部tools字段 (tools字段始终为None)，而是作为一条role: "developer"的AdditionalTypes历史项塞进input数组。作用是符合OpenAI Responses Lite协议的要求。缺点是不支持并行工具调用，模型一次只能调用一个工具
* 普通协议 (默认)：工具定义直接作为HTTP请求的顶级tools字段，一次性发给模型，每次请求都带上完整工具列表

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