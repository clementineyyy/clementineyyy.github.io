---
layout: post
title: AI coding方法论
date: 2026-10-26 09:52:00
description: 本文整理了AI编程的方法论和经验，以帮助读者更高效地使用AI进行编程和开发
tags: methodology ai-coding
categories: technology-stack
citation: true
giscus_comments: true
featured: true  # featured posts will be displayed on the homepage
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文总结了AI编程的方法论和经验，既可以运用在日常AI coding实践中、提升个人能力，也可以用来准备面试提问。

---

# 架构层面
## 核心主旨
* 人设计并和AI讨论 (一开始设计好整个功能和结构如何实现，明确设计方案和约束)、完全交给AI实现 (需要向AI明确一系列编码规则和约束)、AI和人验收校验 (可以在github issue中提QA，让AI自动领取issue并行解决$\rightarrow$工作流比如[sandcastle](https://github.com/mattpocock/sandcastle))。
* 关键是把架构、核心组件和设计原则想清楚，让AI去写代码、跑测试、修bug，人负责最初的设计和最终的验收&code review
* ~~而不是像以前一样遇到需求，自己搜索资料、研究技术，陷入细节中，一边探索一边写代码实现，然后修补。人反而成为了工作流中的瓶颈，阻碍了AI写代码的速度，而且过程非常混乱~~
* tips：
  * 在设计阶段可以先和外部AI讨论方案 (/grill-me或者使用codex的/plan计划模式)，最后输出文档给本地coding agent如codex、opencode，让它们读项目文档并执行，可以更省token
  * 明确功能需求、设计软件架构和实现代码可以分别开一个会话session，省token并避免长上下文压缩$\rightarrow$不同会话session讨论的核心主旨不同
  * AI coding中文档很重要，包括软件功能需求文档、设计架构文档、specs、plan (大任务分解为小任务，明确任务的完成边界、如何测试)等，便于AI查看、约束AI以及人工审核确认review
  * 用思考能力强的模型制定方案，用运行速度快的模型执行方案，这样才能在有限的时间内得到成品而不是半成品

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/cool.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    AI coding工作流。既充分利用AI的能力，又使得工程师可以控制项目的质量
</div>

## insight
* 代码本身就是提示词。清晰，可维护的代码，可以让AI更好地理解软件结构和意图，从而更好地开发新功能，或者修改bug。
* 代码库越有秩序，AI带来的复利越强；代码库越混乱，AI制造技术债的速度越快。
* AI只能延续架构，而不能创造架构。

# 什么问题/情况下使用AI/LLM
1\. 使用场景：
   
  * 解决没有明确处理逻辑/无法用逻辑处理的fuzzy problem模糊问题，给LLM提示词让LLM完成任务[[2]](https://mp.weixin.qq.com/s/w1x8_24ft41au-Q6Pc8uuA)
  * 用AI来解决人力太费时费力的问题：
    * 将无结构的数据 (如文本等)转化为结构化的数据 (如表格、json等)，用来被进一步分析、可视化、研究[[3]](https://www.aihero.dev/what-are-llms-used-for) 
    * 对数据分类/贴标签
  * 非确定性系统：知识问答 (但是需要注意LLM的[Parametric Knowledge](https://www.aihero.dev/ai-coding-dictionary/parametric-knowledgehttps://www.aihero.dev/ai-coding-dictionary/parametric-knowledge)存在[Knowledge Cutoff](https://www.aihero.dev/ai-coding-dictionary/knowledge-cutoff)，而且需要引用外部数据源来提升回答准确度)、多模态生成、Agents操作外部事物

  * 不应该使用AI：有明确处理逻辑、结果是决定性且明确的系统，不需要用AI来处理。
  
2\. 如何使用：不能直接将提示词&要求一股脑全部丢给LLM，这样效果并不好。
   * 先将大的模糊问题拆解成若干步骤。其中有明确处理方式的小步骤可以用逻辑&程序处理，是核心模糊问题的小步骤由LLM解决$\rightarrow$核心是<mark>(长)任务链拆分</mark>
   * 进阶：<mark>尝试不要直接得到产品，而是得到产生产品的工具</mark>，将抽象的生产产品的机制和产品具体内容分开 (类似于设计模式中的工厂方法模式和模板方法模式)。这样既可以避免在直接得到产品的过程中需要处理和考虑的细节问题，也可以简化单个任务的复杂度，让机制产出可以复用并反过来约束具体产品内容的生成
  
3\. 好处：
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/splitBenefits.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    问题分步骤拆分的好处，可以体现个人的抽象能力
</div>

# AI编程规范
1\. 向AI强调不要写过度防御/异常处理/非法检测的代码
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/noDefend.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    拒绝过度防御的代码的原因
</div>

2\. [明确定义成功标准](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests)：
  * 像软件需求分析中要求的一样，设置明确的、可量化、可达成的成功标准，拒绝AI产出概率结果
  * 然后设置尽量自动化的、大量的[评估实验](https://www.aihero.dev/what-are-evals)，如用代码/人工/LLM评估：和科研类似，需要包含各种边界情况、数据具有代表性的数据集datasets
  * data-driven mindset：用来自用户的数据反馈来提升AI-app的效果


# avoid AI code slop
参考[poteto姐的talk](https://www.youtube.com/watch?v=O_zcc6Xl12g)

从low trust的agent writes slop code$\rightarrow$human verifies$\rightarrow$issue found循环到high trust的agent writes good code$\rightarrow$agent verifies$\rightarrow$issue found

<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/loop.png" class="img-fluid rounded z-depth-1" %}
    </div>
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/outerLoop.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    想实现software factory自动化，需要先优化工作流；然后就可以由外部事件触发自动化工作流
</div>


<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/aicoding/prompt.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    从上到下比重越来越低；为了避免code slop，应该着重加强codebase、静态分析和验证测试部分，提示词和human review作用有限
</div>

明确禁止agent不能做什么比告诉agent能做什么更有效：
* 禁止代码注释：因为代码注释也没有用，现在human review也看不过来，还会误导agent、让agent偷懒打补丁而不是找到真正解决问题的方法
* 不让agent写需要细微调整的nuance功能/技术
* 文件结构本身就是一种上下文
* <mark>每发现一个bug，就用lint rules约束agent或者直接禁用来提升codebase，避免这个问题再次出现</mark>
* 形式化验证方法如TLA+ model建模状态机确保所有状态都正确处理、Lean proof


# AI coding提示词技巧
* 避免AI阿谀奉承：[解决办法](https://www.aihero.dev/ai-coding-dictionary/sycophancy)：隐藏个人取向。使用中立的提示词如“帮我review这段代码”而不是“这段代码好吗？”
* 能做什么不能做什么：先给范围再画红线，~~不是一上来就说不能做什么~~，而是<mark>先说具体什么可以做，然后再说具体什么不能做</mark>；因为模型拿到了判断标准，而不是一堆模糊的禁令
* 用具体维度/评价指标把风险分出层次：比如判断一个操作安不安全，~~不看它看起来危不危险 (太宽泛)~~，而是看两件事：这操作能撤回吗？会影响别人吗？改本地代码当然能撤回、只影响自己，直接放行；git push撤不回来、别人能看到
* <mark>不变的静态内容放前面，变化的动态内容放后面</mark>，用分割线隔开：利用<mark>缓存命中</mark>来省钱省token

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

# Useful Skills
## Matt Pocock Skills for ai coding
具体见我的博客[Matt Pocock Skills使用指南](https://clementineyyy.github.io/blog/2026/mattpocockSkills/)，~~已弃用[Superpowers Skills-固定工作流](https://github.com/obra/superpowers)，[原因](https://www.bilibili.com/video/BV1PsN36WE8x/?spm_id_from=333.337.search-card.all.click&vd_source=4969daf431801d632f64c5d68e1819ff)：工作流由人决定，而非全权依赖AI或skills~~

## 前端设计skill
[UI UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)或者Anthropic官方的frontend-design Skill

## Skills for coding agent
1. /resume选择某次会话session。/rewind (codex desktop创建新分支或codex cli中双击esc，可以压缩上下文，因为直接cut context)只回退对话上下文，不会撤销Codex在此之后对代码文件所做的修改。也就是说，对话“穿越”回去了，但磁盘上的代码文件依然停留在最新状态


# 如何改进LLM-based项目
参考[matt pocock的AI Engineering教程-How to improve your LLM-powered app](https://www.aihero.dev/how-to-improve-your-llm-powered-app)

# 参考文献

1. [AI可以帮你写代码，但帮不了你成为架构师](https://www.bilibili.com/video/BV1MPwuzbETf/?spm_id_from=333.337.search-card.all.click&vd_source=4969daf431801d632f64c5d68e1819ff)
2. [AI编程经验微信文章](https://mp.weixin.qq.com/s/w1x8_24ft41au-Q6Pc8uuA)
3. [“大家用AI都太保守了！”Claude Code负责人：我的方法更有野心](https://mp.weixin.qq.com/s/DSkimaN8KLtSRI0UFNFaPA?scene=334)
4. [matt pocock的AI Engineering教程-What are LLMs used for?](https://www.aihero.dev/what-are-llms-used-for)
5. [matt pocock的AI Engineering教程-The AI Engineer Mindset](https://www.aihero.dev/the-ai-engineer-mindset)
6. [Java Guide推荐的skills](https://javaguide.cn/ai-coding/practices/programmer-essential-skills.html)