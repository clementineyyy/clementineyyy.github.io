---
layout: post
title: Codex工具调用源码深入解析
date: 2026-11-10 21:18:00
description: 本文结合codex源码，详细分析了codex工具调用的方案设计、选择理由和实现细节。
tags: methodology agent-harnessing
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
    源代码中并不是每个工具都有name、description、parameters等字段的原因。
</div>

# 工具分类
文件：codex-rs/tools/src/tool_executor.rs，line 53-82，定义ToolExposure包含以下几种类型
核心思想：并不是所有注册的工具都会直接发给模型，ToolExposure是一个开关：
  * Direct / DirectModelOnly → 模型一开口就能看
  * Deferred / DeferredModelOnly → 模型得先搜索才能发现
  * CodeModeOnly / Hidden → 模型在普通对话中完全看不到

几种工具的区别和使用场景见下面的增量工具模式部分分析。

# 怎么暴露工具？
## 模型可见工具model_visible_specs
文件：codex-rs/core/src/tools/spec_plan.rs，line 662-700
* 遍历注册表里的每一个工具，只保留Direct/DirectModelOnly级别的工具，跳过不直接可见的工具
* 对每个保留的工具，根据代码模式等条件，可能增强它的规范 (比如加上代码模式专用的参数schema)
* 把“托管工具”(hosted specs，如web search)也加进来，并把同名命名空间的工具合并

## 使用<mark>增量工具模式</mark>
只对Responses Lite协议模型 (OpenAI提供的一种轻量版Responses API协议变体) 和Amazon Bedrock模型生效，且还受配置开关控制
* 整体逻辑：&#x2b50;核心文件：codex-rs/core/src/session/turn.rs，line 1842-1885，构建Prompt决定本次turn的tools列表

| 模式 | 暴露给模型的工具 |
| :---: | :---: |
| 增量模式 | 在所有模型可见工具规范model_visible_specs()中只暴露WebSearch工具。<mark>其他工具 (如exec_command、read_file等) 不会放在tools字段里，而是通过对话历史中的AdditionalTools项以增量形式传递 (所以模型一开始只能看到Web Search工具</mark>，其他工具要等模型先调用工具、产生输出后，才通过历史项逐步暴露出来) |
| 普通模式 | 暴露所有模型可见工具规范tool_router.model_visible_specs() 返回的所有工具，一次性全部发给模型 |

* 具体实现细节：文件：codex-rs/core/src/session/world_state.rs，line 61-77
什么是增量模式？$\rightarrow$不再每次turn都重新发完整工具列表，而是只在第一次发完整，之后只发增量 (新增/变更的工具)；如果工具没变，后续请求就不需要重复下发，这样可以节省token
* 关于其他类型的工具： 
  * 在增量模式下，Deferred/DeferredModelOnly工具不在初始工具列表里。但如果模型可见列表里包含tool_search工具，模型可以先调用tool_search去搜索这些延迟工具，发现后再调用。这是一种<mark>按需搜索发现</mark>的机制，避免一次性把几百个工具都塞进prompt消耗token。适合工具数量庞大、大部分时间用不到的场景。(文件：codex-rs/core/src/tools/router.rs，line 211-245)
  * CodeModeOnly：只在代码模式嵌套调用中可见，不在初始列表，不对普通对话模型暴露。这适合那些只应该在代码执行环境内部被调用、不应该直接暴露给模型主动调用的工具。(文件： codex-rs/core/src/tools/spec_plan.rs，line 702-730)
  * Hidden：对模型完全不可见，模型无法直接调用，但它仍然被注册在ToolRegistry里，可被注册表分发 (比如作为某个父工具的子步骤、后台任务、或系统级内部操作)。它的存在是为了让工具能被调度和执行，而不需要模型知道它。适合系统级后台任务、父工具的子步骤、或不希望模型感知的内部操作。

## 把Prompt转成发给模型的API请求ResponsesApiRequest
文件：codex-rs/core/src/client.rs，line 1200-1216，根据模型使用的协议不同tools的放置位置不同：
* 请求顶部：指的是HTTP请求JSON体，即ResponsesApiRequest的顶层字段。文件：codex-rs/core/src/client.rs，line 1298-1321
* 增量模式常用的Responses Lite协议：<mark>工具定义不放在请求顶部tools字段，而是作为一条role: "developer"的AdditionalTypes历史项塞进input数组，工具定义可以像对话历史一样被“缓存”和“复用”。如果prompt.tools为空，就不加这条项$\rightarrow$配合增量工具模式，只有在工具列表真正变化时才重新下发新的工具定义，避免每次都重复传输全部工具</mark>
  * 原因：
  <div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/input.png" class="img-fluid rounded z-depth-1" %}
    </div>
  </div>
  <div class="caption">
      工具定义作为一条role: "developer"的AdditionalTypes历史项塞进input数组的原因
  </div>


  * 缺点：不支持并行工具调用，模型一次只能调用一个工具；而且首次可见工具受限，其他工具 (即使是 Direct 级别) 不会出现在首次请求中，而是通过历史项逐步暴露，这可能导致模型一开始不知道某些工具存在

* 普通协议：工具定义直接作为HTTP请求的顶级tools字段，一次性发给模型，每次请求都带上完整工具列表




