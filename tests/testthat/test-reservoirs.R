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


test_that("esn works", {
  model <- .get_test_model()
  model <- .fit_reservoir(model, data_, fixed_spec, subject)
  stopifnot(inherits(model, "reservoir_ensemble.JoblibReservoirEnsemble"))
  pred <- .predict_reservoir(model, data_, fixed_spec, subject)
  expect_vector(pred)
  x_labels <- .get_x_labels(fixed_spec)
  stopifnot(nrow(pred) == nrow(data_))
  stopifnot(sum(is.na(pred)) == sum(!complete.cases(data_[x_labels])))
})
