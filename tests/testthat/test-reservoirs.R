data_ <- data_mixedml
fixed_spec <- ym ~ x1 + x2 + time
subject <- "ID"
time <- "time"

pred_rand <- rnorm(nrow(data_))

.get_test_model <- function() {
  return(.initiate_esn(
    fixed_spec = fixed_spec,
    subject = subject,
    esn_controls = esn_ctrls(
      units = 10,
      sr = 0.1,
      lr = 0.2,
      ridge = 0.001
    ),
    ensemble_controls = ensemble_ctrls(
      seed_list = c(1L, 2L),
      agg_func = "median",
      n_procs = 2L
    ),
    fit_controls = fit_ctrls(warmup = 2)
  ))
}


test_that("esn works", {
  model <- .get_test_model()
  fit_result <- .fit_reservoir(
    model,
    data_,
    pred_rand
  )
  expect_named(fit_result, c("model", "pred_fixed"))
  expect_vector(fit_result$pred_fixed)
  pred <- .predict_reservoir(fit_result$model, data_, subject = subject)
  expect(all(pred == fit_result$pred_fixed), "predictions should be equal")
})
