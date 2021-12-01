---
title: Understanding the Stan codebase (Part 1)
description: Overview of the different libraries related to Stan and their organization, and finding and entry point to the internal C++ code.
toc: true
authors: []
tags: []
categories: []
series: [Stan C++]
date: 2021-11-29T09:00:00+02:00
lastmod: 2021-12-01T09:00:00+02:00
featuredVideo:
keywords: Stan, C++
draft: false
---


## Introduction

So, you have your [Stan](https://mc-stan.org/) model written and are doing inference for it, but something weird is happening? Or maybe you want to extend Stan but don't know where to start because the source code repositories look daunting. These are some of the possible reasons why someone might want to study the internals of Stan, and what is happening under the hood. I have for various reasons for a long time wanted to just see what is happening line-by-line. In this post, I am going to look at how a typical program execution starts to travel through all the different libraries related to Stan, using CmdStanR as the starting point.

### Code organization

<img src="/images/post-01/stan-structure.png" alt="Stan Organization" width=560>

Relationships between different libraries and various interfaces related to Stan are visualized in the above diagram. The C++ core that we study in this post is organized into three parts.

- [CmdStan](https://github.com/stan-dev/cmdstan): A command-line interface to Stan
- [Stan](https://github.com/stan-dev/stan): The MCMC and optimization algorithms
- [Stan Math](https://github.com/stan-dev/math): Mathematical functions and their gradients (automatic differentiation)

Many higher-level interfaces, like [CmdStanR](https://mc-stan.org/cmdstanr/) and [CmdStanPy](https://github.com/stan-dev/cmdstanpy), call CmdStan internally. [RStan](https://mc-stan.org/users/interfaces/rstan) and [PyStan](https://pystan.readthedocs.io/en/latest/) employ different strategies that do not rely on CmdStan. A benefit of CmdStan is that it is always released simultaneously with Stan with the same version number, which means that CmdStan is always up to date. In this, post we study the most recent Stan version 2.28.2, and if the source code structure doesn't experience dramatic changes in the near future, this post might stay relevant for future versions too.


## Starting point (CmdStanR)

In the very beginning, we have nothing but our Stan code, in a file called **mymodel.stan**. For simplicity, we assume that it doesn't have a data block, but otherwise we are not interested in what the model actually is like. We investigate what happens when we run the following R code:

{{< highlight R >}}
library(cmdstanr)
model <- cmdstan_model(stan_file = "mymodel.stan")
fit <- model$sample(adapt_delta = 0.95, refresh = 100)
{{< / highlight >}}

### Creating the executable
The first thing we look at is `cmdstan_model(stan_file = "mymodel.stan")`. This does two interesting things.

- Transpiles the Stan model to C++ code using [stanc3](https://github.com/stan-dev/stanc3)
- Compiles the C++ code into an executable file **mymodel.exe** (without the **.exe** file suffix on Mac or Linux). 

We could have used `model$save_hpp_file()` to save the model C++ code into **mymodel.hpp** if we wanted to look at that. However, we are now interested in the C++ code that doesn't depend on the model. I would imagine that also a lot of this model-independent code has to go into the executable. 

### Running the executable
The call `model$sample(adapt_delta = 0.95, refresh = 100)` [creates four processes](https://github.com/stan-dev/cmdstanr/blob/master/R/run.R) (because the default number of chains is four) that each run the executable. For example, the first process creates the command-line call

```
mymodel.exe id=1 random seed=660816326 output file=<opath>.csv refresh=100 profile_file=<ppath>.csv method=sample save_warmup=0 algorithm=hmc engine=nuts adapt delta=0.95 engaged=1
```

where `<opath>` and `<ppath>` are paths to some temporary CSV files on the computer. Arguments `delta=0.95` and `refresh=100` are things that we specified and others are defaults created by CmdStanR. You can find explanations for the command-line arguments in the [CmdStan User's Guide](https://mc-stan.org/docs/2_28/cmdstan-guide/command-line-interface-overview.html). 

For other processes the `id` argument is 2, 3, and 4. From now on we study only one chain (the one with `id=1`) and next try to find the entry point in the CmdStan code that is started with the above command-line instruction.

## CmdStan

Inside the **cmdstan** source code repository, we go to **cmdstan/src/cmdstan**. 

### main.cpp

We find a [main.cpp](https://github.com/stan-dev/cmdstan/blob/develop/src/cmdstan/main.cpp), which looks promising. It actually includes an 

{{< highlight cpp>}}
int main(int argc, const char *argv[]) {
  // ...
}
{{< / highlight >}}

function which is the starting point of any C++ program. Based on our command-line arguments, at this point `argc` (number of commmand line arguments) should be 15, `argv[0]` should be `"mymodel.exe"`, `argv[1]` should be `"id=1"` and so on. We see that `main` just calls `cmdstan::command(argc, argv)`, which is defined in [command.hpp](https://github.com/stan-dev/cmdstan/blob/develop/src/cmdstan/command.hpp).

### command.hpp

Inside the `command()` function is a huge if-else parade which is quite difficult to read. So here is a high-level summary of the control flow
inside it.

{{< highlight cpp>}}
int command(int argc, const char *argv[]) {

  // ... parse the arguments
  // ... initialize model
  // ... initialize writers

  if (user_method->arg("generate_quantities")) {
    // ...
  } else if (user_method->arg("diagnose")) {
    // ...
  } else if (user_method->arg("optimize")) {
    // ...
  } else if (user_method->arg("sample")) {
    // ...
    if (model.num_params_r() == 0 || algo->value() == "fixed_param") {
      // ...
    } else if (algo->value() == "hmc") {
      // ...
      if (adapt_engaged == true && num_warmup == 0) {
        // ... error
      } else if (engine->value() == "nuts" && metric->value() == "dense_e"
                 && adapt_engaged == false && metric_supplied == false) {
        // ... 
      } else if (engine->value() == "nuts" && metric->value() == "dense_e"
                 && adapt_engaged == false && metric_supplied == true) {
        // ...
      } else if (engine->value() == "nuts" && metric->value() == "dense_e"
                 && adapt_engaged == true && metric_supplied == false) {
        // ...
      } else if (engine->value() == "nuts" && metric->value() == "dense_e"
                 && adapt_engaged == true && metric_supplied == true) {
        // ...
      } else if (engine->value() == "nuts" && metric->value() == "diag_e"
                 && adapt_engaged == false && metric_supplied == false) {
        // ...
      } else if (engine->value() == "nuts" && metric->value() == "diag_e"
                 && adapt_engaged == false && metric_supplied == true) {
        // ...
      } else if (engine->value() == "nuts" && metric->value() == "diag_e"
                 && adapt_engaged == true && metric_supplied == false) {
        // ... WE END UP HERE
        return_code = stan::services::sample::hmc_nuts_diag_e_adapt(
            model, num_chains, init_contexts, random_seed, id, init_radius,
            num_warmup, num_samples, num_thin, save_warmup, refresh, stepsize,
            stepsize_jitter, max_depth, delta, gamma, kappa, t0, init_buffer,
            term_buffer, window, interrupt, logger, init_writers,
            sample_writers, diagnostic_writers);
      } else if (engine->value() == "nuts" && metric->value() == "diag_e"
                 && adapt_engaged == true && metric_supplied == true) {
        // ...
      } else if (engine->value() == "nuts" && metric->value() == "unit_e"
                 && adapt_engaged == false) {
        // ...
      } else if (engine->value() == "nuts" && metric->value() == "unit_e"
                 && adapt_engaged == true) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "dense_e"
                 && adapt_engaged == false && metric_supplied == false) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "dense_e"
                 && adapt_engaged == false && metric_supplied == true) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "dense_e"
                 && adapt_engaged == true && metric_supplied == false) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "dense_e"
                 && adapt_engaged == true && metric_supplied == true) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "diag_e"
                 && adapt_engaged == false && metric_supplied == false) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "diag_e"
                 && adapt_engaged == false && metric_supplied == true) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "diag_e"
                 && adapt_engaged == true && metric_supplied == false) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "diag_e"
                 && adapt_engaged == true && metric_supplied == true) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "unit_e"
                 && adapt_engaged == false) {
        // ...
      } else if (engine->value() == "static" && metric->value() == "unit_e"
                 && adapt_engaged == true) {
        // ...
      }
    }
  } else if (user_method->arg("variational")) {
    // ...
  }
  // ...
  return return_code;
}

{{< / highlight >}}

In most of the branches, the left-out part `// ...` ends up calling something from `stan::services`. This is also the case in our example, and because our `method` argument is `sample`,the default algorithm is NUTS with adaptation engaged and the default metric is diagonal (and we haven't supplied the metric), we will call `stan::services::sample::hmc_nuts_diag_e_adapt()`. We will therefore now jump from CmdStan to Stan. Hooray!

## Stan

Inside the **stan** source code repository, we go to **stan/src/stan**. 

### hmc_nuts_diag_e_adapt.hpp

In **services/sample** we find [hmc_nuts_diag_e_adapt.hpp](https://github.com/stan-dev/stan/blob/develop/src/stan/services/sample/hmc_nuts_diag_e_adapt.hpp) which contains the function that we called from CmdStan. But wait, it is actually overloaded with four different versions of it with the same name. Not to mention each of these are templated. We will not stop here to think much about why these all versions of `hmc_nuts_diag_e_adapt()` are needed. A very valid print debugging approach reveals that in our case, we call the fourth one, which calls the second one, which then calls the first one. There we have

{{< highlight cpp>}}
std::vector<double> cont_vector = util::initialize(
      model, init, rng, init_radius, true, logger, init_writer);
{{< / highlight >}}

where the parameter values are initialized. In `initialize()`, which is defined in [initialize.hpp](https://github.com/stan-dev/stan/blob/develop/src/stan/services/util/initialize.hpp), we try most 100 random initial points, until a point where log probability and its gradient can be evaluated successfully. In our case the first try is successful. Therefore we can now think that we exist somewhere in the (unconstrained) parameter space, at a point stored in `cont_vector`. The next step is to call

{{< highlight cpp>}}
  util::run_adaptive_sampler(
      sampler, model, cont_vector, num_warmup, num_samples, num_thin, refresh,
      save_warmup, rng, interrupt, logger, sample_writer, diagnostic_writer);
{{< / highlight >}}

which we will look at next.

### run_adaptive_sampler.hpp

So we are now at [run_adaptive_sampler.hpp](https://github.com/stan-dev/stan/blob/develop/src/stan/services/util/run_adaptive_sampler.hpp) which is in **services/util**. There we have three interesting parts.

- 1. Initializing stepsize
- 2. Generating transitions, adaptation engaged (warmup)
- 3. Generating transitions, adaptation disengaged (sampling)

The part
{{< highlight cpp>}}
sampler.init_stepsize(logger)
{{< / highlight >}}
initializes the stepsize and is defined in [mcmc/hmc/base_hmc.hpp](https://github.com/stan-dev/stan/blob/develop/src/stan/mcmc/hmc/base_hmc.hpp). This already involves a bit of Hamiltonian computations and evolving the Leapfrog integrator. After this, we start to actually generate MCMC transitions using the sampler. This is done in two phases with calls to
{{< highlight cpp>}}
  util::generate_transitions();
{{< / highlight >}}
 and in the first one we have adaptation engaged. We will look at `generate_transitions()` in the next blog post. Spoiler alert: `sampler.init_stepsize()` will be called there again so we will also look at it more.

## Resources

I have forks of CmdStan and Stan that print more verbose information about the program status than normally.

* CmdStan: https://github.com/jtimonen/cmdstan/tree/understanding_stan_cpp
* Stan: https://github.com/jtimonen/stan/tree/understanding_stan_cpp