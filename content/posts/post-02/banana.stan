// banana.stan
parameters {
  vector[2] theta;
}

model {
  real a = 12.0;
  real b = 0.05;
  target += normal_lpdf(theta[1] | 0.0, a);
  target += normal_lpdf(theta[2] + b * square(theta[1]) - a * b | 0.0, 1.0);
}
