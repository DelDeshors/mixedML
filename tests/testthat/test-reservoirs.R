data_ <- data_mixedml
fixed_spec <- ym ~ 1 + x1 + x2 + time
subject <- "ID"
time <- "time"

.get_test_model <- function() {
  return(.initiate_esn(
    esn_controls = esn_ctrls(units = 10, sr = 0.1, lr = 0.2, ridge = 0.001),
    ensemble_controls = ensemble_ctrls(seed_list = c(1L, 2L), aggregator = "median", scaler = "standard", n_procs = 2L),
    fit_controls = fit_ctrls(warmup = 0)
  ))
}


.pipeline <- function() {
  model <- .get_test_model()
  model <- .fit_reservoir(model, data_, fixed_spec, subject)
  stopifnot(inherits(model, "reservoir_ensemble.JoblibReservoirEnsemble"))
  pred <- .predict_reservoir(model, data_, fixed_spec, subject)
  expect_vector(pred)
  x_labels <- .get_x_labels(fixed_spec)
  stopifnot(nrow(pred) == nrow(data_))
  stopifnot(sum(is.na(pred)) == sum(!complete.cases(data_[x_labels])))
  return()
}


test_that("esn works", {
  # works with default parameters
  expect_no_error(.initiate_esn())
  expect_error(.initiate_esn(esn_controls = "nimp"))
  expect_error(.initiate_esn(fit_controls = "nimp"))
  expect_error(.initiate_esn(ensemble_controls = "nimp"))

  expect_no_error(.pipeline())
})
