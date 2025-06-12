test_that("hlme_full_use", {
  data <- lcmm::data_hlme
  ##########
  model <- .initiate_random_hlme(
    random_spec = Y ~ X1 + X2 + X3 + Time,
    data = data,
    subject = "ID",
    var.time = "Time",
    hlme_controls = hlme_ctrls(maxiter = 10, idiag = TRUE, cor = AR(Time))
  )
  expect_type(model, "list")
  expect_s3_class(model, "hlme")
  #########
  k <- 0.5
  results0 <- .fit_random_hlme(
    random_hlme = model,
    data = data,
    pred_fixed = k * data[["Y"]]
  )
  expect_type(results0, "list")
  expect_named(results0, c("model", "pred_rand"))
  expect_s3_class(results0$model, "hlme")
  expect_vector(results0$pred_rand)
  #########
  k <- 0.8
  results1 <- .fit_random_hlme(
    random_hlme = results0$model,
    data = data,
    pred_fixed = k * data[["Y"]]
  )
  expect_true(
    mean(abs(
      results1$model$best - results0$model$best
    )) >
      0.001
  )
  ##########
  k <- 0.5
  results3 <- .predict_random_hlme(
    random_hlme = results0$model,
    data = data
  )
  expect_vector(results3, ptype = NULL, size = nrow(data))
  expect_type(results3, "double")
})
