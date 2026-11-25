---
layout: post
title: 多智能体协作、安全机制 (钩子护栏与沙箱)深入解析
date: 2026-11-24 16:55:00
description: 本文详细分析了agent多智能体协作、安全机制 (钩子护栏与沙箱)的方案设计、选择理由和实现细节。
tags: agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了agent多智能体协作、安全机制 (钩子护栏与沙箱)的方案设计、选择理由和实现细节。

---

# 多智能体协作
避免大量中间信息污染上下文窗口

什么任务适合多智能体协作：
* 过程重、任务轻：比如大范围搜索、日志分析、专项审查
* 不能拆需要连续对话上下文的任务：比如反复讨论的方案


# Hooks
由程序在固定时机自动执行动作 (如测试、格式化和安全扫描)，将动作绑定到任务的生命周期节点上，当任务运行到某个节点时，agent会自动调用预先配置的handler，不需要用户再次发送提示词；handler执行完成后，再通过退出码或JSON结果告诉agent是继续运行、停止当前动作，还是把新的上下文交回给模型

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/hooks.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    hooks的配置参数：PreToolUse能做拦截，检查这次操作合不合规，不合规直接不让执行；PostToolUse做善后，比如改完文件自动跑格式化
</div>

