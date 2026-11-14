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
# 怎么暴露工具？
取出当前环境下理论上可能出现的全部工具全集，经规则过滤之后将工具子集放入本turn发给LLM的请求体的tools字段中。请求体的tools字段装的是每一个已入选工具的完整schema (name+description+完整的input_schema本质上是该工具的调用参数parameters)

## 机制：工具搜索<mark>延迟加载</mark>ToolSearchTool
文件：src/services/api/claude.ts，line 1154-1174

1\. 每次turn的请求体里：
✅ 非deferred工具：都在，带完整schema
✅ ToolSearchTool：在，带完整schema，所以可以发现更多工具
✅ 发现的deferred工具：都在，带完整schema，所以是延迟加载
❌ 未发现的deferred工具：不在请求体里，模型完全不可见

2\. 模型调用ToolSearchTool想要的工具，服务端返回包含tool_reference块的结果，这些会被记录进消息历史，在下一次submitMessage时 (依然在同一个turn内，因为是while循环loop，终止了才返回给用户回答)同样经过step1的处理，搜索到的工具就出现在请求体里了，模型就能看到它的完整定义并调用

3\. 如果不使用ToolSearchTool，那么没有被权限或其他前置过滤逻辑排除的deferred工具直接出现在请求体中 (else部分的逻辑)$\rightarrow$所以启用ToolSearchTool的作用是延迟加载deferred工具，避免一次性把所有工具都塞进prompt消耗token

## 与codex不同
codex在普通模式下，如果不使用tool_search，模型永远只能看到和调用Direct/DirectModelOnly级别的工具

# 程序化工具调用PTC