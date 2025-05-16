fixed_spec <- y_mixed ~ x1 + x2 + x3
random_spec <- y_mixed ~ x1 + x2
subject <- "subject"
time <- "time"

to_scale <- c("x1", "x2", "x3")
data <- data_mixedml
data <- data[data[subject] < 5, ]
data <- data[data[time] < 3, ]
data[, to_scale] <- scale(data[, to_scale])

test_that("mixedml works", {
  mixed_ml_model <- reservoir_mixedml(
    fixed_spec = fixed_spec,
    random_spec = random_spec,
    data = data,
    subject = subject,
    time = time,
    mixedml_ctrls(conv_ratio_thresh = 0.1, patience = 1),
    hlme_controls = hlme_ctrls(maxiter = 5, idiag = FALSE),
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
    fit_controls = fit_ctrls(warmup = 1),
    predict_controls = predict_ctrls()
  )

  expect_named(
    mixed_ml_model,
    c(
      "subject",
      "time",
      "fixed_spec",
      "random_spec",
      "fixed_model",
      "random_model",
      "mse_list",
      "residuals",
      "call"
    )
  )

  pred <- predict(mixed_ml_model, data)
})
