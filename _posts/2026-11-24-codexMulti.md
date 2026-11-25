---
layout: post
title: Codex多智能体协作、安全机制 (钩子&沙箱与护栏)深入解析
date: 2026-11-24 16:24:00
description: 本文结合Codex源码，详细分析了Codex系多智能体协作、安全机制 (钩子&沙箱与护栏)的方案设计、选择理由和实现细节。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了本文结合Codex源码，详细分析了Codex多智能体协作、安全机制 (钩子&沙箱与护栏)的方案设计、选择理由和实现细节。其中所有代码参考位置均对应笔者fork仓库，而非项目原始仓库。

---

# 多智能体协作

主agent处理大任务时，搜索结果和中间资料很快就会挤占主上下文；subagent可以把小任务拆到独立上下文中并行完成，主agent负责分工、收集结果和整理结论，中间过程则留在各自的子任务里，多智能体协作的流程如下：

step1. 拆分：主agent找出可以独立处理的子任务

step2. 派发：主agent为每个subagent指定目标、边界和输出格式

step3. 执行：各个subagent在自己的上下文中使用模型和工具完成任务
* <mark>subagent默认继承主任务的权限模式，并在当前工作区内使用工具：因此，代码探索、资料整理、测试和问题归类这类互相独立的任务，很适合并行</mark>。多个subagent同时修改同一批文件时，则可能产生冲突 (可以在codex中分别创建多个顶层任务，并为它们选择独立worktree提供文件层面的隔离，subagent提供上下文和分工层面的拆分，两者层次不同)

step4. 回传：subagent把结论和必要证据返回主agent

step5. 合并：主agent等待各路结果，再去重并生成最终回答；subagent产生中间结果不需要全部堆进主上下文，<mark>主agent最后拿到的是整理过的结论</mark>，~~而不是子任务的全部过程~~


## 子agent
subagent是codex临时派出去执行某个子任务的独立线程$\neq$自定义agent是可以反复使用的岗位模板：普通的并行任务，不创建任何配置也能直接派subagent；只有某类分工经常出现时，才值得把职责写进.codex/agents/，以后重复使用。

# 参考文献
1. [小林coding的codex笔记](https://xiaolinnote.com/codex/basics/codex_engineering.html)