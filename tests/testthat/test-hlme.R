test_that("hlme_full_use", {
  data <- data_mixedml
  ##########

  model <- .initiate_random_hlme(
    target_name = "ym",
    random_spec = ~ 1 + x1 + x2 + x3 + x1:x3 + time,
    data = data,
    subject = "ID",
    var.time = "time",
    hlme_controls = hlme_ctrls(
      maxiter = 2,
      idiag = TRUE,
      cor = AR(time),
      B_rand = c(1, 2, 3, 4, 5, 6)
    ),
    no_random_value_as = NA
  )
  expect_s3_class(model, "hlme")
  stopifnot(model$best["intercept"] == 0.)
  #########
  k <- 0.5
  model <- .fit_random_hlme(
    random_hlme = model,
    data = data
  )
  expect_s3_class(model, "hlme")
  stopifnot(all(model$pred$pred_m == 0.))
  stopifnot(length(model$full_pred) == nrow(data_mixedml))

  x_labels <- c("x1", "x2", "x3", "time")
  y_label <- "ym"
  stopifnot(
    sum(is.na(model$full_pred)) ==
      sum(!complete.cases(data_mixedml[c(x_labels, y_label)]))
  )
  ##########
  k <- 0.5
  pred <- .predict_random_hlme(
    random_hlme = model,
    data = data
  )
  expect_vector(pred, ptype = NULL, size = nrow(data))
  expect_type(pred, "double")
  stopifnot(length(pred) == nrow(data_mixedml))
})
