---
title: Understanding the Stan codebase
description: Understanding the Stan codebase
toc: true
authors: []
tags: []
categories: []
series: []
date: 2021-11-29T03:01:05+02:00
lastmod: 2021-11-29T03:01:05+02:00
featuredVideo:
keywords: Stan, C++
draft: true
---

So, you have your Stan model written and are doing inference for it, but something weird is happening? Or maybe you want to extend Stan but don't know where to start because the source code repositories look daunting. These are some of the possible reasons why someone might want to study the internals of Stan, and what is actually happening under the hood. I have for various reasons for a long time wanted to just see what is happening line-by-line. and in this post this is just what I will do.

<!--more-->

## Codebase structure

{{< figure "stan-structure.png" >}}

Relationships between diffent libraries and interfaces related to Stan are visualized in the above diagram. The C++ core that we study in this post is organized in three repos.

- [CmdStan](https://github.com/stan-dev/cmdstan): A command line interface to Stan
- [Stan](https://github.com/stan-dev/stan): The MCMC and optimization algorithms
- [Stan Math](https://github.com/stan-dev/math): Mathematical functions and their gradients (automatic differentiation)

Many higher-level interfaces, like CmdStanR and CmdStanPy, call CmdStan internally. In this post, we are going to look at how a typical program excecution travels though all the different libraries using CmdStan as the starting point.

## Starting point

We have

- CmdStan installed
- A Stan program written in `mymodel.stan`
- A data file ready in `mydata.json`