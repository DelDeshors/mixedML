.generate_data <- function() {
  set.seed(666)

  n_sub <- 10
  n_stp <- 5
  n_obs <- n_sub * n_stp

  sub <- seq(1, n_sub)
  stp <- seq(0, n_stp - 1)

  grd <- expand.grid(stp, sub)
  time <- grd[, 1]
  ID <- grd[, 2]

  x1 <- rnorm(n_obs, 10., 0.5)
  x2 <- rnorm(n_obs, 100., 3.)
  x3 <- ID %% 2

  B1 <- 5
  B2 <- 0.5
  B3 <- 10

  b1 <- rnorm(n_sub, mean = 0., sd = 0.5)[ID]
  b2 <- rnorm(n_sub, mean = 0., sd = 0.1)[ID]
  b3 <- rnorm(n_sub, mean = 0., sd = 0.8)[ID]

  yf <- B1 * x1 + B2 * x2 + B3 * (x3 * x1)
  # response with NA
  yf[ID == 1 & time == 1] <- NA
  yf[ID == 2 & time == 1] <- NA
  # random effect with less covariates than fixed effects
  yr <- b1 * x1 + b2 * x2 #
  ym <- yf + yr
  # covariates with NA
  x1[ID == 1 & time == 1] <- NA
  x2[ID == 2 & time == 2] <- NA

  data_mixedml <- data.frame(ID, time, x1, x2, x3, yf, ym)

  usethis::use_data(data_mixedml, overwrite = TRUE)
  return()
}
