# https://github.com/reservoirpy/reservoirR/blob/main/tests/testthat/tests.R

# initialization ----

MIXEDML_CLASS <- "MixedML_Model"

#' Prepare the mixedml_controls
#'
#'
#' @param patience Number of iterations without improvement before the training is stopped. Default: 2
#' @param conv_ratio_thresh Ratio of improvement of the MSE to consider an improvement.
#' `conv_ratio_thresh=0.01` means an improvement of at least 1% of the MSE is necessary. Default: 0.01
#' @return mixedml_controls
#' @export
mixedml_ctrls <- function(patience = 2, conv_ratio_thresh = 0.01) {
  patience <- .fix_integer(patience)
  stopifnot(is.single.integer(patience) & 0 <= patience)
  stopifnot(
    is.single.numeric(conv_ratio_thresh) &
      0 < conv_ratio_thresh &
      conv_ratio_thresh < 1
  )
  control <- as.list(environment())
  return(control)
}


.test_reservoir_mixedml <- function(
  fixed_spec,
  random_spec,
  data,
  subject,
  time,
  mixedml_controls,
  hlme_controls,
  esn_controls,
  ensemble_controls,
  fit_controls
) {
  stopifnot(rlang::is_bare_formula(fixed_spec))
  stopifnot(rlang::is_bare_formula(random_spec))
  stopifnot(
    .get_left_side_string(fixed_spec) == .get_left_side_string(random_spec)
  )
  stopifnot(is.data.frame(data))
  stopifnot(is.character(subject))
  stopifnot(subject %in% names(data))
  stopifnot(is.character(time))
  stopifnot(time %in% names(data))
  .check_controls_with_function(mixedml_controls, mixedml_ctrls)
  .check_controls_with_function(hlme_controls, hlme_ctrls)
  .check_controls_with_function(esn_controls, esn_ctrls)
  .check_controls_with_function(ensemble_controls, ensemble_ctrls)
  .check_controls_with_function(fit_controls, fit_ctrls)
  .check_sorted_data(data, subject, time)
  return()
}


# recipe: HLME/Reservoir ----

#' MixedML model with Reservoir Computing
#'
#' Generate and fit a MixedML model using an Ensemble of Echo State Networks (Reservoir+Ridge Regression)
#' to fit the fixed effects.
#' @param fixed_spec two-sided linear formula object for the fixed-effects.
#' The response outcome is on the left of ~ and the covariates are separated by + on the right of ~.
#' @param random_spec two-sided formula for the random-effects in the linear mixed model.
#'  The response outcome is on the left of ~ and the covariates are separated by + on the right of ~.
#'  By default, an intercept is included. If no intercept, -1 should be the first term included.
#' @param data dataframe containing the variables named in `fixed_spec`, `random_spec`, `subject` and `time`.
#' @param subject name of the covariate representing the grouping structure, given as a string/character.
#' @param time name of the time variable, given as a string/character.
#' @param mixedml_controls controls specific to the MixedML model
#' @param hlme_controls controls specific to the HLME model
#' @param mixedml_controls controls specific to the MixedML model
#' @param esn_controls controls specific to the ESN models
#' @param ensemble_controls controls specific to the Ensemble model
#' @param fit_controls controls specific to the ESN models fit
#' @return fitted MixedML model
#' @export
reservoir_mixedml <- function(
  fixed_spec,
  random_spec,
  data,
  subject,
  time,
  mixedml_controls = mixedml_ctrls(),
  hlme_controls = hlme_ctrls(),
  esn_controls = esn_controls(),
  ensemble_controls = ensemble_controls(),
  fit_controls = fit_controls()
) {
  .test_reservoir_mixedml(
    fixed_spec,
    random_spec,
    data,
    subject,
    time,
    mixedml_controls,
    hlme_controls,
    esn_controls,
    ensemble_controls,
    fit_controls
  )
  #
  random_model <- .initiate_random_hlme(
    random_spec,
    data,
    subject,
    time,
    hlme_controls
  )
  fixed_model <- .initiate_esn(
    fixed_spec,
    subject,
    esn_controls,
    ensemble_controls,
    fit_controls
  )
  conv_ratio_thresh <- mixedml_controls[["conv_ratio_thresh"]]
  patience <- mixedml_controls[["patience"]]
  ##
  target_name <- .get_left_side_string(fixed_spec)
  pred_rand <- rep(0, nrow(data))
  istep <- 0
  mse_list <- c()
  mse_min <- Inf
  while (TRUE) {
    cat(sprintf("step#%d\n", istep))
    cat("\tfitting fixed effects...\n")
    fixed_results <- .fit_reservoir(fixed_model, data, pred_rand)
    fixed_model <- fixed_results$model
    pred_fixed <- fixed_results$pred_fixed
    #
    cat("\tfitting random effects...\n")
    random_results <- .fit_random_hlme(random_model, data, pred_fixed)
    random_model <- random_results$model
    pred_rand <- random_results$pred_rand
    #
    residuals <- pred_fixed + pred_rand - data[[target_name]]
    mse <- mean(residuals**2)
    cat(sprintf("\tMSE = %.4g\n", mse))
    mse_list <- c(mse_list, mse)

    if (mse < (1 - conv_ratio_thresh) * mse_min) {
      count_conv <- 0
    } else {
      count_conv <- count_conv + 1
      if (count_conv > patience) {
        break
      }
    }
    if (mse < mse_min) {
      mse_min <- mse
    }
    istep <- istep + 1
  }

  output <- (list(
    "subject" = subject,
    "time" = time,
    "fixed_spec" = fixed_spec,
    "random_spec" = random_spec,
    "fixed_model" = fixed_model,
    "random_model" = random_model,
    "mse_list" = mse_list,
    "residuals" = residuals,
    "call" = match.call()
  ))
  class(output) <- MIXEDML_CLASS
  return(output)
}

# prediction ----

.test_predict <- function(model, data) {
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(names(data) == names(model$random_model$data))
  return()
}


#' Predict using a fitted model and new data
#'
#'
#'
#' @param model Trained MixedML model
#' @param data New data (same format as the one used for training)
#' @return prediction
#' @export
predict <- function(model, data) {
  .test_predict(model, data)
  #
  pred_fixed <- .predict_reservoir(
    model$fixed_model,
    data,
    model$subject,
  )
  pred_mixed <- .predict_random_hlme(model$random_model, data)
  return(pred_fixed + pred_mixed)
}

#' Plot the (MSE) convergence of the MixedML training
#'
#'
#'
#' @param model Trained MixedML model
#' @param ylog Plot the y-value with a log scale. Default: TRUE.
#' @return Convergence plot
#' @export
plot_conv <- function(model, ylog = TRUE) {
  return(plot(
    seq_along(model$mse_list),
    model$mse_list,
    type = "o",
    xlab = model$time,
    ylab = "MSE",
    ylog = ylog
  ))
}
