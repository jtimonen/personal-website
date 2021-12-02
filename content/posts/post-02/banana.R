library(cmdstanr)
library(ggplot2)
set_cmdstan_path("C:/Users/Juho/Work/Research/STAN/cmdstan")
model <- cmdstan_model(stan_file = "banana.stan")
model$save_hpp_file()
fit <- model$sample(adapt_delta = 0.95, refresh = 1, iter_sampling = 20,
                    iter_warmup = 20)
theta_1 <- as.vector(fit$draws("theta[1]"))
theta_2 <- as.vector(fit$draws("theta[2]"))
lp <- as.vector(fit$draws("lp__"))
df <- data.frame(theta_1, theta_2, lp)
plt <- ggplot(df, aes(x = theta_1, y = theta_2, color = lp)) +
  geom_point(alpha = 0.7) +
  ggtitle("Draws")
plt

out1 <- paste(fit$output()[[1]], collapse = "\n")
out2 <- paste(fit$output()[[2]], collapse = "\n")
out3 <- paste(fit$output()[[3]], collapse = "\n")
out4 <- paste(fit$output()[[4]], collapse = "\n")
