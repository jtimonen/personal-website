---
title: "lgpr: an interpretable non-parametric method for inferring covariate effects from longitudinal data"
date: 2021-01-21
pubtype: "Article"
featured: true
description: "J Timonen, H Mannerström, A Vehtari, and H Lähdesmäki. Bioinformatics (2021)."
tags: ["Gaussian Processes","Bayesian Methods", "Bioinformatics", "R", "Stan"]
link: "https://doi.org/10.1093/bioinformatics/btab021"
weight: 500
sitemap:
  priority : 0.8
---

![lgpr](/img/lgpr_overview.png)

## Abstract
### Motivation
Longitudinal study designs are indispensable for studying disease progression. Inferring covariate effects from longitudinal data, however, requires interpretable methods that can model complicated covariance structures and detect non-linear effects of both categorical and continuous covariates, as well as their interactions. Detecting disease effects is hindered by the fact that they often occur rapidly near the disease initiation time, and this time point cannot be exactly observed. An additional challenge is that the effect magnitude can be heterogeneous over the subjects.

### Results
We present *lgpr*, a widely applicable and interpretable method for non-parametric analysis of longitudinal data using additive Gaussian processes. We demonstrate that it outperforms previous approaches in identifying the relevant categorical and continuous covariates in various settings. Furthermore, it implements important novel features, including the ability to account for the heterogeneity of covariate effects, their temporal uncertainty, and appropriate observation models for different types of biomedical data. The *lgpr* tool is implemented as a comprehensive and user-friendly [R](https://www.r-project.org/)-package.

### Availability and implementation
*lgpr* is available at [jtimonen.github.io/lgpr-usage](jtimonen.github.io/lgpr-usage) with documentation, tutorials, test data and code for reproducing the experiments of this article.

### Supplementary information
Supplementary data are available at Bioinformatics online.
