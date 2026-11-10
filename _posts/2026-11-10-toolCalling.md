---
layout: post
title: 工具调用学习笔记
date: 2026-11-10 21:18:00
description: 本文整理了agent harness中工具调用的学习笔记。
tags: methodology agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文整理了agent harness中工具调用tool call/function calling的学习笔记，便于读者将工业级工具调用知识应用到实际项目中。

---

# 教程资源
[工具调用菜鸟教程](https://www.runoob.com/ai-agent/ai-agent-function-calling.html)
[工具调用github仓库教程](https://github.com/didilili/ai-agents-from-zero/blob/main/17-Tools%E5%B7%A5%E5%85%B7%E8%B0%83%E7%94%A8.md#17---tools-%E5%B7%A5%E5%85%B7%E8%B0%83%E7%94%A8)

# 工具调用步骤
1. 定义与注入：应用将工具的名称、描述和参数格Schema连同用户提示词一起，作为请求发送给模型
2. 模型决策与生成：模型分析上下文，判断是否需要调用工具。如果需要，它会<mark>生成一段结构化的调用指令，明确指定要调用的工具名和对应的参数</mark>（例如 {"name": "get_weather", "arguments": {"city": "上海"}}）
3. 应用端执行：应用接收到这段指令后，解析出工具名和参数，然后在本地或通过API真正执行对应的函数或代码
4. 结果回传：应用将工具的执行结果作为一条新的消息，追加回对话上下文中
5. 模型生成最终回答：模型看到工具返回的结果后，结合这个新信息，生成最终的自然语言回复给用户。

# Further Questions
## 工具如何暴露给LLM？
* 传统做法：全量注入，每次请求都会将所有工具定义序列化成文本，全量塞入模型的上下文窗口。缺点：token爆炸 (每轮对话固定多出几千token的开销)，成本增加，上下文窗口不够，工具选择准确率下降 (模型要在更长的清单里做匹配，注意力被稀释，选错、不选或“瞎选”的概率都会上升)
* 业界做法：
  * 渐进式披露Progressive Tool Exposure：初始只给模型看一个很小的“加载器Loader”工具集。模型在需要时，可以主动调用一个“加载更多工具”的元工具，来动态地把新的工具定义添加进当前的对话上下文中
  * 工具检索Tool Retrieval：当工具库非常庞大 (例如数十上百个)时，会先用一个轻量级的检索步骤 (结合关键词BM25和语义Embeddings)，从全量工具库中筛选出最相关的Top-N候选工具 (例如20个)，然后再把这Top-N个工具的定义交给模型做最终选择

## LLM如何根据提示词判断该调用哪个工具？

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/learningRoute/tools1.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    LLM如何根据提示词判断该调用哪个工具？
</div>

