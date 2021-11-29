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
