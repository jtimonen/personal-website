---
title: Understanding the Stan codebase (Part 1)
description: Overview of the different libraries related to Stan and their organization, and finding and entry point to the internal C++ code.
toc: true
authors: []
tags: []
categories: []
series: [Stan C++]
date: 2021-11-29T03:01:05+02:00
lastmod: 2021-11-29T03:01:05+02:00
featuredVideo:
keywords: Stan, C++
draft: false
---


## Introduction

So, you have your Stan model written and are doing inference for it, but something weird is happening? Or maybe you want to extend Stan but don't know where to start because the source code repositories look daunting. These are some of the possible reasons why someone might want to study the internals of Stan, and what is actually happening under the hood. I have for various reasons for a long time wanted to just see what is happening line-by-line. In this post this is just what I will do.


### Code organization

<img src="/images/post-01/stan-structure.png" alt="Stan Organization" width=560>

Relationships between diffent libraries and interfaces related to Stan are visualized in the above diagram. The C++ core that we study in this post is organized in three repos.

- [CmdStan](https://github.com/stan-dev/cmdstan): A command line interface to Stan
- [Stan](https://github.com/stan-dev/stan): The MCMC and optimization algorithms
- [Stan Math](https://github.com/stan-dev/math): Mathematical functions and their gradients (automatic differentiation)

Many higher-level interfaces, like [CmdStanR](https://mc-stan.org/cmdstanr/) and [CmdStanPy](https://github.com/stan-dev/cmdstanpy), call CmdStan internally. In this post, we are going to look at how a typical program excecution travels though all the different libraries using CmdStanR as the starting point.

## Starting point

In the very beginning we have nothing but our Stan code, in a file called **mymodel.stan**. For simplicity, we assume that it doesn't have a data block. Our R code for sampling the model is

{{< highlight R >}}
library(cmdstanr)
model <- cmdstan_model(stan_file = "mymodel.stan")
model$save_hpp_file()
fit <- model$sample(adapt_delta = 0.95, init = 0)
{{< / highlight >}}

The first thing we look at is `cmdstan_model(stan_file = "mymodel.stan")`. This does two interesting things.

- Transpiles the Stan model to C++ code using `stanc`.
- Compiles the C++ code into an executable file **mymodel.exe** (without the **.exe** file suffix on Mac or Linux). 

Here we used `model$save_hpp_file()` to save the model C++ code into **mymodel.hpp** so that we can look at it later. This is not the only C++ code that has goes into the executable though, as also a lot of CmdStan, Stan, and Stan Math code will be packed into it. The call `model$sample(adapt_delta = 0.95, init = 0)` calls the executable, and here the equivalent command line call is

```
mymodel.exe sample adapt delta=0.95 init=0
```

Next we wish to find the entry point in the CmdStan code that is started with this call.

## CmdStan

Inside the **cmdstan** source code repository, we go to **cmdstan/src/cmdstan**. 

### main.cpp

We find a [main.cpp](https://github.com/stan-dev/cmdstan/blob/develop/src/cmdstan/main.cpp), which looks promising. It actually includes an 

{{< highlight cpp>}}
int main(int argc, const char *argv[]) {
  // ...
}
{{< / highlight >}}

function which is the starting point of any C++ program. Based on our command line arguments, at this point `argc` (number of commmand line arguments) should be 5 and `argv` should be something like `{"mymodel.exe", "sample", "adapt", "delta=0.95", "init=0"}`. We see that `main` just calls `cmdstan::command(argc, argv)`, which is defined in [command.hpp](https://github.com/stan-dev/cmdstan/blob/develop/src/cmdstan/command.hpp).

### command.hpp
Here, the command line arguments are parsed and several things initialized. Among other things, a model instance is created.

{{< highlight cpp>}}
// Instantiate model
  stan::model::model_base &model
      = new_model(*var_context, random_seed, &std::cout);
{{< / highlight >}}

We will go to the branch

{{< highlight cpp>}}
if (user_method->arg("sample")) {
  // ...
} 
{{< / highlight >}}

because our `method` argument was `sample`. Finally, because the default algorithm is NUTS with adaptation engaged and default metric is diagonal (and we haven't supplied the metric), we will execute the branch

{{< highlight cpp>}}
 else if (engine->value() == "nuts" && metric->value() == "diag_e"
                 && adapt_engaged == true && metric_supplied == false) {
        // ...
        return_code = stan::services::sample::hmc_nuts_diag_e_adapt(
            model, num_chains, init_contexts, random_seed, id, init_radius,
            num_warmup, num_samples, num_thin, save_warmup, refresh, stepsize,
            stepsize_jitter, max_depth, delta, gamma, kappa, t0, init_buffer,
            term_buffer, window, interrupt, logger, init_writers,
            sample_writers, diagnostic_writers);
      }
{{< / highlight >}}

This means that we call an algorithm from Stan, hooray. We will therefore now jump to the Stan repository.

## Stan

Inside the **stan** source code repository, we go to **stan/src/stan**. 

### hmc_nuts_diag_e_adapt.hpp

In **services/sample** we find [hmc_nuts_diag_e_adapt.hpp](https://github.com/stan-dev/stan/blob/develop/src/stan/services/sample/hmc_nuts_diag_e_adapt.hpp) which contains
the function that we called from CmdStan. There we have

{{< highlight cpp>}}
std::vector<double> cont_vector = util::initialize(
      model, init, rng, init_radius, true, logger, init_writer);
{{< / highlight >}}

where the parameter values are initialized. By default this would try at most 100 random initial points, until it finds a point where log probability and its gradient can be evaluated successfully. Now as we set `init=0`, it will just check that it can evaluate them at zero. At the end we find

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
initializes the stepsize and is defined in [mcmc/hmc/base_hmc.hpp](https://github.com/stan-dev/stan/blob/develop/src/stan/mcmc/hmc/base_hmc.hpp). This already involves a bit of Hamiltonian computations and evolving the Leapfrog integrator. We might look at this part in more detail in a future post. After this, the only thing that remains is to generate the MCMC transitions using the sampler. This is done in two phases with calls to
{{< highlight cpp>}}
  util::generate_transitions();
{{< / highlight >}}
 and in the first one we have adaptation engaged. We will look at `generate_transitions()` in the next blog post.
