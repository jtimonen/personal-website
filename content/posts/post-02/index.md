---
title: "Understanding the Stan codebase - Part 2: Samplers"
description: Studying the C++ code of the NUTS algorithm of Stan.
toc: true
authors: []
tags: []
categories: []
series: [Stan C++]
date: 2021-12-02T12:00:00+02:00
lastmod: 2021-12-03T12:00:00+02:00
featuredImage:
featuredVideo:
keywords: Stan, C++
draft: true
---

## Introduction

### Recap of Part 1
We pick up from where we left off in [Part 1](https://jtimonen.github.io/posts/post-01/). We started with a CmdStan command-line call like
```
mymodel.exe id=1 method=sample algorithm=hmc engine=nuts adapt engaged=1
```
and found out that CmdStan calls the Stan services in `cmdstan::command()`. There, the
command-line arguments are parsed and consequently based on them,

1. the called service is `stan::services::sample::hmc_nuts_diag_adapt()`
2. which then calls `stan::services::util::run_adaptive_sampler()`
3. which calls `stan::services::util::generate_transitions()`.

### Starting point for Part 2
We find `generate_transitions()` in [generate_transitions.hpp](https://github.com/stan-dev/stan/blob/develop/src/stan/services/util/generate_transitions.hpp).
Here and throughout this post, comments starting with `...` indicate parts of code that have been left out.

{{< highlight cpp >}}
void generate_transitions(stan::mcmc::base_mcmc& sampler, int num_iterations,
                          ..., stan::mcmc::sample& init_s, Model& model, ...) {
  for (int m = 0; m < num_iterations; ++m) {
    // ... callbacks and progress printing
    init_s = sampler.transition(init_s, logger);
    // ... writing to output
  }
}
{{< / highlight >}}

Among other things it takes as input the sampler, model, and initial point, all of which have been created by now. The function is basically just a loop that calls `sampler.transition()` repeatedly for `num_iterations` times.
The interesting part to us is how a transition is performed, and this is defined by `sampler.transition()`. As we will see, different sampler classes define the transition differently. Also whether we are doing adaptation or not is an *attribute* of `sampler`. 

We will therefore now jump from the `stan::services` namespace to [`stan::mcmc`](https://github.com/stan-dev/stan/tree/develop/src/stan/mcmc), where the different samplers and their transitions are defined.

## Sampler classes

We see in `generate_transitions()` that `sampler` has to have type `base_mcmc`. However, in `hmc_static_diag_e_adapt()`, where `sampler`
is instantiated, it has (templated) type `adapt_diag_e_static_hmc`. So what is going on? 

<center><img src="/images/post-02/sampler_class_inheritance.png" alt="Sampler Classes" width=790></center>

It appears that `adapt_diag_e_static_hmc` is a class that *derives* from `base_mcmc` through multiple levels of inheritance
as can be seen from the above diagram.

### base_mcmc

 This is just an *interface* for all MCMC samplers, as it doesn't contain any function bodies.

{{< highlight cpp >}}
class base_mcmc {
 public:
  base_mcmc() {}

  virtual ~base_mcmc() {}

  virtual sample transition(sample& init_sample, callbacks::logger& logger) = 0;

  virtual void get_sampler_param_names(std::vector<std::string>& names) {}

  virtual void get_sampler_params(std::vector<double>& values) {}

  //... other virtual functions without body

};
{{< / highlight >}}

The class member functions are all *virtual* (except the constructor, which never should be), meaning that deriving classes can override them. We see that `transition()` is *pure virtual* (declared with `= 0`), meaning that any deriving class *must* override it. 



### base_hmc

This is a base for all Hamiltonian samplers, and derives from `base_mcmc`.

{{< highlight cpp >}}
template <class Model, template <class, class> class Hamiltonian,
          template <class> class Integrator, class BaseRNG>
class base_hmc : public base_mcmc {
 public:
  base_hmc(const Model& model, BaseRNG& rng)
      : base_mcmc(),
        z_(model.num_params_r()),
        integrator_(),
        hamiltonian_(model),
        rand_int_(rng),
        rand_uniform_(rand_int_),
        nom_epsilon_(0.1),
        epsilon_(nom_epsilon_),
        epsilon_jitter_(0.0) {}

  // ...

  void seed(const Eigen::VectorXd& q) { z_.q = q; }

  void init_hamiltonian(callbacks::logger& logger) {
    this->hamiltonian_.init(this->z_, logger);
  }

  void init_stepsize(callbacks::logger& logger) {
    ps_point z_init(this->z_);

    // Skip initialization for extreme step sizes
    if (this->nom_epsilon_ == 0 || this->nom_epsilon_ > 1e7
        || std::isnan(this->nom_epsilon_))
      return;

    this->hamiltonian_.sample_p(this->z_, this->rand_int_);
    this->hamiltonian_.init(this->z_, logger);

    // Guaranteed to be finite if randomly initialized
    double H0 = this->hamiltonian_.H(this->z_);

    this->integrator_.evolve(this->z_, this->hamiltonian_, this->nom_epsilon_,
                             logger);

    double h = this->hamiltonian_.H(this->z_);
    if (std::isnan(h))
      h = std::numeric_limits<double>::infinity();

    double delta_H = H0 - h;

    int direction = delta_H > std::log(0.8) ? 1 : -1;

    while (1) {
      this->z_.ps_point::operator=(z_init);

      this->hamiltonian_.sample_p(this->z_, this->rand_int_);
      this->hamiltonian_.init(this->z_, logger);

      double H0 = this->hamiltonian_.H(this->z_);

      this->integrator_.evolve(this->z_, this->hamiltonian_, this->nom_epsilon_,
                               logger);

      double h = this->hamiltonian_.H(this->z_);
      if (std::isnan(h))
        h = std::numeric_limits<double>::infinity();

      double delta_H = H0 - h;

      if ((direction == 1) && !(delta_H > std::log(0.8)))
        break;
      else if ((direction == -1) && !(delta_H < std::log(0.8)))
        break;
      else
        this->nom_epsilon_ = direction == 1 ? 2.0 * this->nom_epsilon_
                                            : 0.5 * this->nom_epsilon_;

      if (this->nom_epsilon_ > 1e7)
        throw std::runtime_error(
            "Posterior is improper. "
            "Please check your model.");
      if (this->nom_epsilon_ == 0)
        throw std::runtime_error(
            "No acceptably small step size could "
            "be found. Perhaps the posterior is "
            "not continuous?");
    }

    this->z_.ps_point::operator=(z_init);
  }

  // ...

  typename Hamiltonian<Model, BaseRNG>::PointType& z() { return z_; }

  const typename Hamiltonian<Model, BaseRNG>::PointType& z() const noexcept {
    return z_;
  }

  // ... setters and getters for the protected properties

  void sample_stepsize() {
    this->epsilon_ = this->nom_epsilon_;
    if (this->epsilon_jitter_)
      this->epsilon_
          *= 1.0 + this->epsilon_jitter_ * (2.0 * this->rand_uniform_() - 1.0);
  }

 protected:
  typename Hamiltonian<Model, BaseRNG>::PointType z_;
  Integrator<Hamiltonian<Model, BaseRNG> > integrator_;
  Hamiltonian<Model, BaseRNG> hamiltonian_;

  BaseRNG& rand_int_;

  // Uniform(0, 1) RNG
  boost::uniform_01<BaseRNG&> rand_uniform_;

  double nom_epsilon_;
  double epsilon_;
  double epsilon_jitter_;
};
{{< / highlight >}}


## Example

We have written a Stan model in **banana.stan**. It specifies a two-dimensional version of the distribution is discussed in [Haario et. al (1999)](https://link.springer.com/article/10.1007/s001800050022).

```
// banana.stan
parameters {
  vector[2] theta;
}

model {
  real a = 10.0;
  real b = 0.03;
  target += normal_lpdf(theta[1] | 0.0, a);
  target += normal_lpdf(theta[2] + b * square(theta[1]) - a * b | 0.0, 1.0);
}
```

Here is our R code for sampling from the distribution.

{{< highlight R >}}
library(cmdstanr)
library(ggplot2)
model <- cmdstan_model(stan_file = "banana.stan")
model$save_hpp_file()
fit <- model$sample(adapt_delta = 0.95, init = 0)
theta_1 <- as.vector(fit$draws("theta[1]"))
theta_2 <- as.vector(fit$draws("theta[2]"))
df <- data.frame(theta_1, theta_2)
plt <- ggplot(df, aes(x = theta_1, y = theta_2)) +
  geom_point(alpha = 0.5, col = "firebrick") +
  ggtitle("Draws")
plt
{{< / highlight >}}

We plot the draws to give an idea what the distribution looks like.

<center><img src="/images/post-02/draws.jpeg" alt="Draws" width=560></center>

## References

Haario, H., Saksman, E., and Tamminen, J. (1999). **Adaptive proposal distribution for random
walk Metropolis algorithm.** Computational Statistics, 14:375–395.