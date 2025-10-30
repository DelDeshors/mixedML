#' Synthetic mixed effects dataset
#'
#' This dataset is used to test and study the mixedML package
#' The fixed effects, random effects and corresponding mixed effects (with
#' and without noise) are given.
#' NAs are added in the independent variables and the response
"data_mixedml"

.generate_data <- function() {
  set.seed(666)

  # dataset parameters ----
  n_sub <- 10
  n_stp <- 5
  n_obs <- n_sub * n_stp

  sub <- seq(1, n_sub)
  stp <- seq(0, n_stp - 1)

  grd <- expand.grid(stp, sub)
  time <- grd[, 1]
  ID <- grd[, 2]

  # independent variables ----
  x1 <- rnorm(n_obs, 10., 0.5)
  x2 <- rnorm(n_obs, 100., 3.)
  x3 <- ID %% 2

  # fixed effects ----
  B0 <- 1.
  B1 <- 5.
  B2 <- 0.5
  B3 <- 10.
  yf <- B0 + B1 * x1 + B2 * x2 + B3 * (x3 * x1)

  # random effects ----
  u0i <- rnorm(n_sub, mean = 0., sd = 0.05)[ID]
  u1i <- rnorm(n_sub, mean = 0., sd = 0.5)[ID]
  u2i <- rnorm(n_sub, mean = 0., sd = 0.1)[ID]
  yr <- u0i + u1i * x1 + u2i * x2

  # mixed effects ----
  ym_nonoise <- yf + yr
  ym <- yf + yr + rnorm(n_obs, sd = 0.01 * sd(ym_nonoise, na.rm = TRUE))

  # dataset generation ----
  data_mixedml <- data.frame(ID, time, x1, x2, x3, yf, yr, ym, ym_nonoise)

  # independent variables with NA ----
  data_mixedml[ID == 1 & time == 0, "x1"] <- NA
  data_mixedml[ID == 2 & time == 1, "x2"] <- NA

  # dependent variables with NA ----
  data_mixedml[ID == 3 & time == 0, "ym"] <- NA
  data_mixedml[ID == 4 & time == 1, "ym"] <- NA

  # observation missing ----
  data_mixedml <- data_mixedml[!((ID == 5 & time == 0) | (ID == 6 & time == 1)), ]
  row.names(data_mixedml) <- sample(row.names(data_mixedml))
  # file generation ----
  usethis::use_data(data_mixedml, overwrite = TRUE)
  return()
}
