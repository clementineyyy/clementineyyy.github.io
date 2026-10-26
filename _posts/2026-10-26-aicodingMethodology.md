---
layout: post
title: AI coding方法论
date: 2026-10-26 09:52:00
description: 本文整理了AI编程/vibe coding的方法论和经验，以帮助读者更高效地使用AI进行编程和开发
tags: methodology vibe-coding
categories: technology-stack
citation: true
giscus_comments: true
featured: true  # featured posts will be displayed on the homepage
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文总结了AI编程/vibe coding的方法论和经验，既可以运用在日常AI coding实践中、提升个人能力，也可以用来准备面试提问。

# 架构层面
## 核心主旨
* 人设计 (一开始设计好整个功能和结构如何实现，明确设计方案和约束)、完全交给AI实现、AI和人验收校验。
* 关键是把架构、核心组件和设计原则想清楚，让AI去写代码、跑测试、修bug，人负责最初的设计和最终的验收&code review
* ~~而不是像以前一样遇到需求，自己搜索资料、研究技术，陷入细节中，一边探索一边写代码实现，然后修补。人反而成为了工作流中的瓶颈，阻碍了AI写代码的速度，而且过程非常混乱~~

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/cool.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    AI coding工作流。既充分利用AI的能力，又使得工程师可以控制项目的质量
</div>

## insight
* 代码本身就是提示词。清晰，可维护的代码，可以让AI更好地理解软件结构和意图，从而更好地vibe coding新功能，或者修改bug。
* 代码库越有秩序，AI带来的复利越强；代码库越混乱，AI制造技术债的速度越快。
* AI只能延续架构，而不能创造架构。

# 什么问题/情况下使用AI/LLM
1. 使用场景：解决没有明确处理逻辑/无法用逻辑处理的fuzzy problem模糊问题，给LLM提示词让LLM完成任务[[2]](https://mp.weixin.qq.com/s/w1x8_24ft41au-Q6Pc8uuA)。
2. 如何使用：不能直接将提示词&要求一股脑全部丢给LLM，这样效果并不好。
   * 先将大的模糊问题拆解成若干步骤。其中有明确处理方式的小步骤可以用逻辑&程序处理，是核心模糊问题的小步骤由LLM解决$\rightarrow$核心是<mark>(长)任务链拆分</mark>
   * 进阶：<mark>尝试不要直接得到产品，而是得到产生产品的工具</mark>，将抽象的生产产品的机制和产品具体内容分开 (类似于设计模式中的工厂方法模式和模板方法模式)。这样既可以避免在直接得到产品的过程中需要处理和考虑的细节问题，也可以简化单个任务的复杂度，让机制产出可以复用并反过来约束具体产品内容的生成
3. 好处：
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/splitBenefits.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    问题分步骤拆分的好处，可以体现个人的抽象能力
</div>

# AI编程规范
1. 向AI强调不要写过度防御/异常处理/非法检测的代码
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/noDefend.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    拒绝过度防御的代码的原因
</div>
2. 


# AI coding提示词技巧
## 给AI提出更有野心的目标
### 高度：提高任务的抽象层次
关注最终想实现的结果，而不是一个个具体任务。
例如：从要求AI完成一个具体任务 (如写文档、PPT、填表)，到让AI理解业务 (是什么？为什么？怎么做？下一步怎么办？)，发现问题并作出决策 (决策是什么？展开分析并列出理由)，最后重构工作流/工作机制


### 深度：像顶尖专家一样思考任务
进一步深入底层的数据、工具和问题
* 坚持使用行业顶尖人士所用的工具 (LLM通常知道专家使用的工具)，~~而不是只是换了一套专业词汇，实际方法却没有变~~
* 设定看似不合理/难以达成/不可能的目标，再向模型强调它们非常合理，它需要继续尝试
* 挑战你已经认定的结论：让模型接触原始信息和数据，带着质疑的态度检验那些假设，然后找出新的知识
* 引入外部评判 (一种模型可以自行运行、并立即获得反馈的工具，比如说某量化指标)，~~而不要让模型自己评价自己~~

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/prompt.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    让AI深度探索问题并思考的提示词参考
</div>

### 广度：从多个领域寻找解决问题的思路
把平时不会接触的知识、工具和方法也用起来，从不同领域的视角审视自己的工作。
* 试着把名词换成动词来描述交给AI的动作：比如把“做一份PPT”改成“在30分钟内，让一群忙碌的人信服一套关于事情前因后果的解释，并在不确定的情况下作出决策”，更能表达出用户对产出的需求
* 让AI按照不同领域专家的方法研究任务，~~但是注意不要将该方法演变为角色扮演而并没有提升实际成果~~

# 参考文献

1. [AI可以帮你写代码，但帮不了你成为架构师](https://www.bilibili.com/video/BV1MPwuzbETf/?spm_id_from=333.337.search-card.all.click&vd_source=4969daf431801d632f64c5d68e1819ff)
2. [AI编程经验微信文章](https://mp.weixin.qq.com/s/w1x8_24ft41au-Q6Pc8uuA)
3. [“大家用AI都太保守了！”Claude Code负责人：我的方法更有野心](https://mp.weixin.qq.com/s/DSkimaN8KLtSRI0UFNFaPA?scene=334)