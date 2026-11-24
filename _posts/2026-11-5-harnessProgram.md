---
layout: post
title: AgentPortfolio：面向。。。。。。。。
date: 2026-10-26 21:27:00
description: 本文是作者开发的AgentPortfolio项目文档。
tags: agent-harnessing ai-coding
categories: technology-stack
citation: true
giscus_comments: true
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 需要展示在文章列表中的缩略图
---



---

# 项目功能

* 股票范围：目前只支持美国上市股票

# 相关术语
| 术语 | Total Cash | Portfolio Value | Portfolio Allocation | 4-Year Return | Allocation | Returns | SPY | BULL CASE | BEAR CASE |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 字面含义 | 可用资金 | 投资组合当前总价值 | 资产配置情况 | 4年回报 | 资产配置比例 | 收益 (金额+比例) | 标普500ETF | 看涨情景 (正面观点) | 看跌情景 (负面观点) |
| 结果 | 尚未用来买股票的现金余额，加上已经发放的股息现金 (以现金持有，不自动再投资) | 模拟投资结束时，你手里总共值多少钱 (包括持股市值、没花掉的现金、已领取股息) | 投资本金和原始本金的比例 | 扣除本金和剩余现金后的净盈亏。尽管名字叫4-Year，代码里并没有按4年专门计算，而是对回测区间内的总收益做简单差额 | 每只股票占总投入资金的比例，反映集中度 (比如全仓AAPL就是100%集中，平分5只股票就是各20%) | 每只股票赚了或亏了多少钱，以及相对投入金额的涨跌幅 | 市场基准。对比Portfolio曲线和SPY曲线，能看出你的组合是跑赢还是跑输大盘 | LLM生成的正面理由：为什么这只股票/组合可能表现良好 | LLM生成的负面理由：为什么这只股票/组合可能表现不佳 |

数据之间的关系（一句话总结）:
> 你投入多少钱 (投入金额) → 分配给各只股票 (Allocation) → 随时间推移产生持仓市值和股息 → 得到组合总价值 (Portfolio Value) → 与本金比较得出收益 (Returns/4-Year Return) → 同时拿同样的钱买SPY做对照 → LLM再给出看涨/看跌定性分析 (Bull/Bear Case)

# 关于测试
* 根据AGENTS.md的内容，每当agent在一个工作轮次中修改代码、提示词、配置或行为，结束前要运行覆盖该改动的测试或验证 (地址是agent/tests)；是否运行取决于修改内容和agent执行的验证流程


# 项目设计
## 记忆系统
1\. 你的agent项目记忆机制是怎么做的？
  参考我的[Agent Loop、上下文工程和记忆系统学习笔记](https://clementineyyy.github.io/blog/2026/loopContextMemory/)和我的[Claude Code系统架构、上下文管理和记忆系统深入解析](https://clementineyyy.github.io/blog/2026/claudecodeArch/#%E8%AE%B0%E5%BF%86%E7%B3%BB%E7%BB%9F)中的笔记内容

  step1. 先指出LLM是无状态的，本质靠上下文治理管理历史信息

  step2. 指出业界主流方案都有共同短板：滑动窗口、对话摘要、向量检索、分层存储存在的个性问题和共性问题

  step3. 主流coding agent项目如claude code、codex、pi的记忆系统设计思路和优点

  step4. 根据以上记忆系统的优缺点，在我的项目中怎么结合设计的记忆系统、效果怎么样

  step5. 在设计、学习和改进过程中，有什么收获、感悟和思考
2\. 

# 参考文献
1. []()