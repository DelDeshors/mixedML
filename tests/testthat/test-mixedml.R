fixed_spec <- ym ~ 1 + x1 + x2 + time
random_spec <- ~ 1 + x1 + x2 + time
subject <- "ID"
time <- "time"

data_train <- data_mixedml[data_mixedml$ID < 9, ]
data_val <- data_mixedml[data_mixedml$ID >= 9, ]


normal_execution <- function() {
  mixed_ml_model <- reservoir_mixedml(
    fixed_spec = fixed_spec,
    random_spec = random_spec,
    data = data_train,
    data_val = data_val,
    subject = subject,
    time = time,
    mixedml_controls = mixedml_ctrls(
      conv_thresh = 0.1,
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
  pred <- predict(mixed_ml_model, data_val)
  stopifnot(length(pred) == nrow(data_val))
  plot_conv_mse(mixed_ml_model)
  plot_conv_loglik(mixed_ml_model)
  plot_prediction_check(mixed_ml_model, subject_nb_or_list = 3)
  return()
}


test_that("mixedml works", {
  expect_no_error(normal_execution())
})
