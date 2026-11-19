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

# 记忆系统
业界常见的方案是用向量数据库，把记忆存成embedding，每次对话时做相似度检索$\rightarrow$问题：Agent需要记住的大部分不是“相似的文档片段”，而是“用户说过'不要mock数据库'”这种结构化的行为指令。用向量相似度去检索“不要mock数据库”这句话，效果其实很差，它可能匹配到一堆包含“数据库”关键词的无关内容，真正重要的行为反馈却被淹没了



# 参考文献
1. [小林coding的Claude code源码解析](https://xiaolinnote.com/claudecode/source/cc_source.html)