.get_model <- function(cor) {
  # since it is called using an intermediate function
  # we can check using a variable to define "cor" (whcih is a very annoying parameter in hlme)
  return(.initiate_random_hlme(
    target_name = "ym",
    random_spec = ~ 1 + x1 + x2 + x3 + x1:x3 + time,
    data = data_mixedml,
    subject = "ID",
    var.time = "time",
    hlme_controls = hlme_ctrls(maxiter = 2, idiag = TRUE, cor = cor, B_rand = c(1, 2, 3, 4, 5, 6))
  ))
}


.full_pipeline <- function(cor) {
  x_labels <- c("x1", "x2", "x3", "time")
  y_label <- "ym"

  # our prediction method is not limited by NAs for Y
  ccases <- complete.cases(data_mixedml[c(x_labels)])

  # initialization ----
  model <- .get_model(cor)
  expect_s3_class(model, "hlme")
  stopifnot(model$best["intercept"] == 0.)

  # fitting ----
  model <- .fit_random_hlme(random_hlme = model, data = data_mixedml)
  expect_s3_class(model, "hlme")
  stopifnot(all(model$pred$pred_m == 0.))

  # prediction with all info ----
  pred <- .predict_with_all_info(hlme_model = model, data = data_mixedml)
  expect_vector(pred, ptype = NULL, size = nrow(data_mixedml))
  expect_type(pred, "double")
  stopifnot(length(pred) == nrow(data_mixedml))
  stopifnot(sum(is.na(pred)) == sum(!ccases))

  # prediction with past info ----
  pred <- .predict_with_past_info(hlme_model =  model, data = data_mixedml)
  stopifnot(length(pred) == nrow(data_mixedml))
  expect_vector(pred, ptype = NULL, size = nrow(data_mixedml))
  expect_type(pred, "double")
  stopifnot(length(pred) == nrow(data_mixedml))
  return()
}


test_that("hlme_full_use", {
  expect_no_error(.initiate_random_hlme(
    target_name = "ym",
    random_spec = ~ 1 + x1 + x2 + x3 + x1:x3 + time,
    data = data_mixedml,
    subject = "ID",
    var.time = "time",
    hlme_controls = hlme_ctrls(maxiter = 2, idiag = TRUE, cor = "AR(time)", B_rand = c(1, 2, 3, 4, 5, 6))
  ))
  expect_no_error(.initiate_random_hlme(
    target_name = "ym",
    random_spec = ~ 1 + x1 + x2 + x3 + x1:x3 + time,
    data = data_mixedml,
    subject = "ID",
    var.time = "time",
    hlme_controls = hlme_ctrls(maxiter = 2, idiag = TRUE, cor = NULL, B_rand = c(1, 2, 3, 4, 5, 6))
  ))
  expect_no_error(.get_model(cor = "AR(time)"))
  expect_no_error(.get_model(cor = NULL))

  expect_error(.initiate_random_hlme(
    target_name = "ym",
    random_spec = ~ 1 + x1 + x2 + x3 + x1:x3 + time,
    data = data_mixedml,
    subject = "ID",
    var.time = "time",
    hlme_controls = hlme_ctrls(maxiter = 2, idiag = TRUE, cor = AR(time), B_rand = c(1, 2, 3, 4, 5, 6))
  ))
  expect_error(.get_model(cor = AR(time)))
  #
  expect_error(.intermediate_initialisation(cor = "AR(X1)"))
  expect_error(.intermediate_initialisation(cor = "lala(time)"))
  #
  expect_no_error(.full_pipeline(NULL))
})
