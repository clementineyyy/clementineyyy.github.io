---
layout: post
title: AI应用工程师技术学习路线
date: 2026-10-25 11:04:00
description: 本文整理了AI应用工程师的技术学习路线，主要包括AI Agent + Harness Engineering和Java全栈 (后端为主)两个子方向，先广度再深度确定学习路径以实现快速高效学习
tags: methodology java-full-stack agent-harnessing
categories: technology-stack
citation: true
giscus_comments: true
featured: true  # featured posts will be displayed on the homepage
toc: 
  sidebar: left
# thumbnail: assets/img/9.jpg   # 用于显示在文章列表中的缩略图
---

秉持着不能all in agent开发、拓宽岗位投递选择的理念，本文从AI Agent + Harness Engineering和Java全栈 (后端为主)两个子方向出发，先广度再深度确定学习路径以实现快速高效学习。

# 前置知识：Git
简单看文档了解Git的基本概念和常用命令即可，主要是在实际项目和工作中需要经常使用以进行版本控制和多人协作。

## 教程
[菜鸟教程的Git教程](https://www.runoob.com/git/git-tutorial.html)
[Git官方文档](https://git-scm.com/docs)

## 文件路径
* Git安装在C:\Program Files\Git下，可启动git-bash.exe和git-cmd.exe等程序
* C:\Program Files\Git\etc\gitconfig文件：系统中对所有用户都普遍适用的配置。若使用git config时用--system选项，读写的就是这个文件
* C:\Users\用户名\\.git\config文件：当前用户的配置文件。若使用git config时用--global选项，读写的就是这个文件
* 工程项目文件夹下的\\.git文件夹，包含当前项目的Git目录中的配置文件.git\config文件：这里的配置仅仅针对当前项目有效。每一个级别的配置都会覆盖上层的相同配置，所以.git\config里的配置会覆盖\etc\gitconfig中的同名变量
  
## Github Actions
GitHub Actions是GitHub内置的自动化平台，允许你在代码仓库中直接定义并运行自动化流程，无需借助任何外部CI/CD工具。常见的用途包括：代码推送后自动运行测试、合并PR后自动部署到服务器、定时执行数据抓取脚本等。

[菜鸟教程的Github Actions教程](https://www.runoob.com/git/github-actions.html)
[Github Actions官方文档](https://docs.github.com/zh/actions)

# 前置知识：Markdown
简单看文档了解Markdown的基本语法和常用格式即可，主要用于编写文档、博客等文本内容。

[菜鸟教程的Markdown教程](https://www.runoob.com/markdown/md-tutorial.html)

# Part1: Java全栈技术栈 (后端为主)

[优雅ovo的Java后端学习路线](https://www.bilibili.com/video/BV1EQE4zMEpP/?spm_id_from=333.788.videopod.sections&vd_source=4969daf431801d632f64c5d68e1819ff)


[花绿青的Java后端学习路线](https://www.bilibili.com/video/BV15cg96BERq/?spm_id_from=333.788.recommend_more_video.7&trackid=web_related_0.router-related-2479604-5lvcw.1791895379907.134&vd_source=4969daf431801d632f64c5d68e1819ff)


# Part2: AI Agent & Harness Engineering

# 参考文献
[AI应用开发路线B站视频](https://www.bilibili.com/video/BV1MnEa69EmU/?spm_id_from=333.788.videopod.sections&vd_source=4969daf431801d632f64c5d68e1819ff)