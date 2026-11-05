---
layout: post
title: Matt Pocock Skills使用教程
date: 2026-11-01 16:23:00
description: 本文整理了Matt Pocock开发的Skills的使用教程，帮助读者理清如何高效使用这些Skills进行AI coding实践
tags: methodology ai-coding
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

本文总结了Matt Pocock开发的Skills的使用教程，便于读者进行高效的软件工程AI coding实践。Matt Pocock说过：“用任何skill之前都应该通读一遍”，所以读SKILL.md目前是有益的。

官方资源：
[代码仓库](https://github.com/mattpocock/skills)、[官方文档](https://www.aihero.dev/skills)、[名词解析](https://www.aihero.dev/ai-coding-dictionary)

---
# 基本工作流
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/mattpocockSkills/workflow.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    Matt Pocock Skills的基本工作流。大部分skills由用户自己调用。(1) 如果只是简单修bug、做小功能，且不超过150K所有的smart zone时，可以在一个会话session内从grill直接到implement-spec，省略to-spec和to-tickets的步骤；如果任务大到一个会话session无法完成，就需要用to-spec (2) 尽量在同一个上下文窗口内完成grill、to-spec和to-tickets，保证LLM建立在相同的思考基础上 (有/rewind、/handoff等方法省上下文，但不要/clear更不要/compact)；implement可以新开一个会话session来实现每一个ticket
</div>

# 深入分析
## /ask-matt
随时/ask-matt，了解如何根据当前场景来使用skills安排工作流。具体不同情况下的工作流见[仓库的~\skills\engineering\ask-matt\SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/ask-matt/SKILL.md)

## /grill-with-docs & /wayfinder & /grill-me
### 使用哪种grilling skills
* /wayfinder：你也不知道具体要做什么、就是有个灵感、但不了解相关知识，<mark>需求不明确</mark>
  * 它会将模糊的需求拆成好几个方向，用类似/to-tickets的思路拆出好几个decision tickets来 (如果执行/setup-matt-pocock-skills的时候选择用github管理issue tracker的话，那他们会有issue的#编号)，然后这个wayfinder会话任务就结束了
  * 你只需要再去开一个个新会话，每个都再执行一次/wayfinder \#n认领对应的decision tickets，每个会话解决一个ticket，这样就不会一次占用太多上下文了
  * 所有decision tickets都被这几个新的wayfinder认领并且拷问完之后，你就可以再开一个会话执行/to-spec #<map_issue>和/to-tickets，然后再开新会话去用/implement \#n认领ticket去让agent实现代码就可以了
* /grill-me：清楚需求、知道自己想做什么、但不知道怎么实现、给你选项也选不出来、缺背景知识
  * 先开一个不写文档的grill-me。在这里面你可以随便问问，先把项目的各种方案和原理了解差不多之后，再开个会话正式开始，用grill-with-docs，决策完写文档记录下来。
  
| 技能 | 主要用途 | 提问围绕什么 | 典型结果 |
| :---: | :---: | :---: | :---: |
| /wayfinder | 1. 为<mark>较大的项目或功能 (一个会话session内放不下，上下文会超出150K的smart zone)</mark>找出下一步，并拆解工作<br>2. <mark>从零开始的全新greenfield项目</mark>，没有历史代码、技术债务或遗留系统的约束 | 项目目标、未决问题、依赖、阻塞、先做哪项 | 一张持续维护的工作地图，以及<mark>可领取的子任务</mark> |
| /grill-me | 压力测试一个想法或方案，<mark>此时不在项目工作目录下</mark> | 假设、取舍、边界情况、失败模式、成功标准 | 更清楚、经受过质疑的决策或方案 |
| /grilling | 对想法进行深入追问 (一般是被其他skill使用的reference skill) | 你提出的计划或判断是否自洽、有哪些薄弱处	 | 经过追问后修订的想法；它更像一种讨论方式，不一定产出项目任务地图，不留下文档 |
| /grill-with-docs | 结合现有仓库或文档 (没有文档也可以)审视想法或计划、<mark>可以在一个会话session内解决</mark> | 文档中的事实、约束与计划之间是否一致，哪里缺证据或有冲突 (结合DDD领域驱动设计) | 基于文档的澄清和修订方向，<mark>留下记录文档和词汇表，如ADR架构决策记录Architecture Decision Record</mark> |

### 如何正确使用grilling skills
避免在grilling时产生无尽的questions

1\. 区分问题的复杂程度：
* 对于低保真度low fidelity的问题 (用户甚至不需要呈现就能做出决策)：grilling可以直接解决
* 对于高保真度high fidelity的问题 (需要呈现高保真原型、图片、demo，用户才能做出下一步决策)：无法在grilling的过程中解决。Matt Pocock的做法是：
    * 使用/handoff总结第一个会话session的结果，得到文档传到新开的第二个会话session中
    * 让AI在第二个会话session中使用/prototype或其他skills制作出高保真原型供用户/AI决策使用
    * 再将第二个对话中的结果用/handoff总结，传回第一个会话session继续grilling
<div class="row mt-3">
    <div class="col-12 mt-3 mt-md-0">
        {% include figure.liquid loading="eager" path="assets/img/mattpocockSkills/handoff.png" class="img-fluid rounded z-depth-1" %}
    </div>
</div>
<div class="caption">
    解决高保真度high fidelity的问题的工作流。核心是将高保真度high fidelity的问题通过demo的方式，变成低保真度low fidelity的问题
</div>

2\. 区分问题的规模：
  * 对于规模scope小的问题：可以在一个会话session内grilling完毕，而不会超过上下文、从而触及模型的dumb zone
  * 对于规模scope大的问题：可以将其拆分为多个小规模scope的问题，在多个会话session中进行grilling

3\. 人在对话中是消极passive还是积极active：
  * 人需要引导对话、搞清方向、让对话不跑偏
  * 既不能太被动，也不能太固执、钻牛角尖、执着于某些低保真low fidelity的问题、迟迟不动手写代码 (该问题可以通过构建原型/demo看看效果来解决)
  
4\. grilling阶段使用SOTA模型，利用它的参数来提出好的idea

5\. 并行：开多个会话session，分别grilling (但不是grill同一个问题)，分以下几个应用场景：
   * 两个方案对比：从不同的方向出发一起grill，最后出两个方案，选中哪个方案，就让哪个方案写context.md文件
   * 方向定下来了，就是想grill加速进度，不想一直干等着它思考：比如一个问后端的设计，另一个做前端设计稿
   * 两个不同的项目同时分不同会话session grill


## /to-spec
* 作用：如果任务无法在一段会话session内完成 (使用前提)，就记录下当前的思路和决策，生成spec文档，方便在其他会话session中继续工作。
* 关于生成的spec文档：
  * 大部分是给agent读的。人需要关注其中的seams和out-of-scope section，在这两个段落中最容易提早发现错误决策。
  * spec文档是你当下认知的记录，因此会随着实现implementation的进展而过时。它在工作启动之后是可抛弃的，而GLOSSARY.md和ADRs才是应该持续保存的文件。

## /to-tickets
* 作用：沿着DAG图上的一条<mark>路径，竖着穿过每一水平层，当该tickets完成后可以立刻测试</mark>，无需等待所有层集成之后再测试。并且该tickets小到可以在一个会话session的smart zone内完成
* 使用：
  * /to-tickets也可以在不使用/to-spec的情况下使用，计划包含在对话conversation中

## /triage
* 作用：issue分流，推荐匹配的标签和状态
* 使用：
  * 已经使用过/to-spec和/to-tickets之后，不需要再自行调用/triage。因为/to-tickets已经把任务标签都设置为ready-for-agent，等待agent下一步直接实现代码
  * 因此/triage只针对非用户自己创建的、<mark>外部</mark>的issue。它是外部入口匝道on-ramp，而不是工作流workflow中必不可少的一环
* 实现细节：
  * 5个标签和状态：见~\docs\agents\triage-labels.md的映射表，将skill内部的规范canonical角色名翻译成实际issue tracker中使用的标签字符串 (用户可以创建自定义标签)
  * 状态转换规则在[仓库的~\skills\engineering\triage\SKILL.md的Roles部分最后](https://github.com/mattpocock/skills/blob/main/skills/engineering/triage/SKILL.md)


# 参考文献
1. [Matt Pocock的Youtube频道](https://www.youtube.com/@mattpocockuk)
2. [Matt Pocock的X主页](https://x.com/mattpocockuk)
3. [评论区答疑-高效使用](https://www.bilibili.com/video/BV1SmNE6DE8v/?spm_id_from=333.788.videopod.sections&vd_source=4969daf431801d632f64c5d68e1819ff)
4. [如何正确使用grilling skills](https://www.bilibili.com/video/BV1zn396mEfz?spm_id_from=333.788.videopod.sections&vd_source=4969daf431801d632f64c5d68e1819ff)
5. [分析matt pocock skills](https://www.bilibili.com/video/BV1dH3K6rEQZ/?spm_id_from=333.337.search-card.all.click&vd_source=4969daf431801d632f64c5d68e1819ff)