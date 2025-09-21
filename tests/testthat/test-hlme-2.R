use_only_past_info <- TRUE

# here we use `mixedML::.predict_random_hlme` for the post-fit predictions
# in this case we get NA only when there are NA in the Xs
# (we use `complete.cases(data_mixedml[c(x_labels)])`)

test_that("hlme_full_use", {
  data <- data_mixedml
  model <- .initiate_random_hlme(
    target_name = "ym",
    random_spec = ~ x1 + x2 + x3 + time,
    data = data,
    subject = "ID",
    var.time = "time",
    hlme_controls = hlme_ctrls(
      maxiter = 2,
      idiag = TRUE,
      cor = AR(time),
      B_rand = c(1, 2, 3, 4, 5)
    ),
    no_random_value_as = NA,
    use_only_past_info = use_only_past_info
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

  x_labels <- .get_x_labels(model$call$random)
  y_label <- .get_y_label(model$call$fixed)
  stopifnot(
    sum(is.na(model$full_pred)) ==
      sum(!complete.cases(data_mixedml[c(x_labels)]))
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
