data_ <- data_mixedml
fixed_spec <- ym ~ x1 + x2 + time
random_spec <- ~ x1 + x2 + time
subject <- "ID"
time <- "time"

test_that("mixedml works", {
  mixed_ml_model <- reservoir_mixedml(
    fixed_spec = fixed_spec,
    random_spec = random_spec,
    data = data_,
    subject = subject,
    time = time,
    mixedml_ctrls(
      conv_ratio_thresh = 0.1,
      patience = 1,
      no_random_value_as = NA
    ),
    hlme_controls = hlme_ctrls(
      maxiter = 5,
      idiag = TRUE,
      cor = AR(time),
      convB = 0.01,
      convL = 0.01,
      convG = 0.01
    ),
    esn_controls = esn_ctrls(
      units = 20,
      lr = 0.1,
      sr = 1.3,
      ridge = 1e-3
    ),
    ensemble_controls = ensemble_ctrls(
      seed_list = c(666, 667),
      aggregator = "median",
      scaler = "standard",
      n_procs = 1
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
  pred <- predict(mixed_ml_model, data_)
  stopifnot(length(pred) == nrow(data_))
  plot_last_iter(mixed_ml_model, subject_nb_or_list = 3)
})
