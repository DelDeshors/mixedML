spec_formula <- Y ~ X1 + X2 + X3

to_scale <- c("X1", "X2", "X3")
data <- lcmm::data_hlme
data[, to_scale] <- scale(data[, to_scale])


data_comp <- data
data_comp$Y <- data_comp$Y + rnorm(length(data_comp$Y), 1, 2)

pred_rand <- rnorm(nrow(data))

.get_test_model <- function() {
  return(.initiate_esn(
    fixed_spec = spec_formula,
    subject = "ID",
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
    data,
    pred_rand
  )
  expect_named(fit_result, c("model", "pred_fixed"))
  expect_vector(fit_result$pred_fixed)
  pred <- .predict_reservoir(fit_result$model, data, "ID")
  expect(all(pred == fit_result$pred_fixed), "predictions should be equal")
  #
  model_comp <- .get_test_model()
  fit_result_comp <- .fit_reservoir(
    model,
    data_comp,
    pred_rand
  )
  pred_comp <- .predict_reservoir(fit_result_comp$model, data, "ID")
  expect(all(pred != pred_comp), "predictions should differ")
})
