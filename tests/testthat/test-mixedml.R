fixed_spec <- y_mixed ~ x1 + x2 + time
random_spec <- y_mixed ~ x1 + x2 + time
subject <- "subject"
time <- "time"

to_scale <- c("x1", "x2")
data <- data_mixedml
data <- data[data[subject] < 5, ]
data <- data[data[time] < 3, ]
data[1, "y_mixed"] <- NA
data[, to_scale] <- scale(data[, to_scale])

test_that("mixedml works", {
  mixed_ml_model <- reservoir_mixedml(
    fixed_spec = fixed_spec,
    random_spec = random_spec,
    data = data,
    subject = subject,
    time = time,
    mixedml_ctrls(conv_ratio_thresh = 0.1, patience = 1),
    hlme_controls = hlme_ctrls(maxiter = 5, idiag = TRUE, cor = AR(time)),
    esn_controls = esn_ctrls(
      units = 20,
      lr = 0.1,
      sr = 1.3,
      ridge = 1e-3
    ),
    ensemble_controls = ensemble_ctrls(
      seed_list = c(666, 667),
      agg_func = "median",
      n_procs = 2
    ),
    fit_controls = fit_ctrls(warmup = 1)
  )

  expect_named(
    mixed_ml_model,
    c(
      "data",
      "subject",
      "time",
      "fixed_spec",
      "random_spec",
      "mse_list",
      "call",
      "pred_fixed",
      "pred_rand",
      "fixed_model",
      "random_model"
    )
  )

  pred <- predict(mixed_ml_model, data)
})
