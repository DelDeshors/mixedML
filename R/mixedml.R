library(ggplot2)

# initialization ----

MIXEDML_CLASS <- "MixedML_Model"

#' Prepare the mixedml_controls
#'
#'
#' @param patience Number of iterations without improvement before the training is stopped. Default: 2
#' @param conv_ratio_thresh Ratio of improvement of the MSE to consider an improvement.
#' `conv_ratio_thresh=0.01` means an improvement of at least 1% of the MSE is necessary. Default: 0.01
#' @param no_random_value_as value to use during the training of the random model
#' when the prediction is not possible (NA or 0). This does not affect the prediction.
#' Default: NA
#' @return mixedml_controls
#' @export
mixedml_ctrls <- function(
  patience = 2,
  conv_ratio_thresh = 0.01,
  no_random_value_as = NA
) {
  stopifnot(is.single.integer(patience) & 0 <= patience)
  patience <- as.integer(patience)
  stopifnot(is.single.numeric(conv_ratio_thresh))
  stopifnot(0 < conv_ratio_thresh & conv_ratio_thresh < 1)
  #
  stopifnot(length(no_random_value_as) == 1)
  stopifnot(is.na(no_random_value_as) || (no_random_value_as == 0))
  #
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
  .check_sorted_data(data, subject, time)
  .check_controls_with_function(mixedml_controls, mixedml_ctrls)
  return()
}


# recipe: HLME/Reservoir ----

#' MixedML model with Reservoir Computing
#'
#' Generate and fit a MixedML model using an Ensemble of Echo State Networks (Reservoir+Ridge Regression)
#' to fit the fixed effects.
#' @param fixed_spec two-sided linear formula object for the fixed-effects.
#' The response outcome is on the left of ~ and the covariates are separated by + on the right of ~.
#' (do not used extra formulation such as "x1*x3")
#' @param random_spec one-sided formula for the random-effects in the linear mixed model.
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
  target_name <- .get_y_label(fixed_spec)
  random_model <- .initiate_random_hlme(
    target_name,
    random_spec,
    data,
    subject,
    time,
    hlme_controls,
    mixedml_controls$no_random_value_as
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
  data_fixed <- data
  data_rand <- data
  pred_rand <- rep(0, nrow(data))
  istep <- 0
  mse_list <- c()
  mse_min <- Inf
  msg <- TRUE
  #
  while (TRUE) {
    cat(sprintf("step#%d\n", istep))
    cat("\tfitting fixed effects...\n")
    data_fixed[[target_name]] <- data[[target_name]] - pred_rand
    fixed_model <- .fit_reservoir(fixed_model, data_fixed)
    pred_fixed <- .predict_reservoir(fixed_model, data)
    cat("\tfitting random effects...\n")
    # !!! offsetting is not implemented in LCMM
    # BUT for linear models, fitting "f(X)+offset" on Y is equivalent
    # to fitting f(X) on "Y-offset"
    # so that is the method used so far
    data_rand[[target_name]] <- data[[target_name]] - pred_fixed
    random_model <- .fit_random_hlme(random_model, data_rand)
    pred_rand <- random_model$full_pred
    #
    residuals <- pred_fixed + pred_rand - data[, target_name]
    ccases <- complete.cases(residuals)
    if (msg && sum(!ccases) > 0) {
      msg <- FALSE
      warning(sprintf(
        "%d observations could not be uses to train (either no fixed preds, random preds or target).",
        sum(!ccases)
      ))
    }
    mse <- mean(residuals[ccases]**2)
    cat(sprintf("\tMSE = %.4g\n", mse))
    mse_list <- c(mse_list, mse)
    if (mse < (1 - conv_ratio_thresh) * mse_min) {
      count_conv <- 0
      best <- list(
        "pred_fixed" = pred_fixed,
        "pred_rand" = pred_rand,
        "fixed_model" = fixed_model,
        "random_model" = random_model
      )
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
  .check_convergence_hlme(best$random_model)
  output <- c(
    list(
      "data" = data,
      "subject" = subject,
      "time" = time,
      "fixed_spec" = fixed_spec,
      "random_spec" = random_spec,
      "mse_list" = mse_list,
      "call" = match.call()
    ),
    best
  )
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
#' @param model Trained MixedML model
#' @param data New data (same format as the one used for training)
#' @return prediction
#' @export
predict <- function(model, data) {
  .test_predict(model, data)
  pred_fixed <- .predict_reservoir(model$fixed_model, data)
  pred_rand <- .predict_random_hlme(model$random_model, data)
  return(pred_fixed + pred_rand)
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
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(is.logical(ylog))
  return(plot(
    seq_along(model$mse_list),
    model$mse_list,
    type = "o",
    xlab = "iterations",
    ylab = "MSE",
    ylog = ylog
  ))
}


#' Plot the prediction of a MixedML model
#'
#' @param model Trained MixedML model.
#' @param subject_nb_or_list Number of subjects to plot (randomly selected) or
#' list of subjects to plot.
#' @param ylog Plot the y-value with a log scale. Default: TRUE.
#' @return Prediction plot of the model.
#' @export
plot_last_iter <- function(model, subject_nb_or_list, ylog = FALSE) {
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(
    is.single.integer(subject_nb_or_list) | is.vector(subject_nb_or_list)
  )
  stopifnot(is.logical(ylog))
  #
  subject <- model$subject
  time <- model$time
  target <- .get_y_label(model$fixed_spec)
  #
  model$data[[subject]] <- as.factor(model$data[[subject]])
  #
  type <- "type"
  type1 <- "target"
  data_ <- model$data
  data_[[type]] <- type1
  #
  type2 <- "pred."
  data_tmp <- model$data
  data_tmp[[type]] <- type2
  data_tmp[[target]] <- model$pred_fixed + model$pred_rand
  data_ <- rbind(data_, data_tmp)
  if (is.single.integer(subject_nb_or_list)) {
    subject_nb_or_list <- sample(
      unique(data_[[subject]]),
      subject_nb_or_list
    )
    message("Subjects selected randomly: use set.seed to change the selection.")
  } else {
    stopifnot(all(subject_nb_or_list %in% data_true[[subject]]))
  }
  #
  idx_keep <- data_[[subject]] %in% subject_nb_or_list
  data_ <- data_[idx_keep, ]

  return(
    ggplot(
      data_,
      aes(
        x = .data[[time]],
        y = .data[[target]],
        group = interaction(.data[[subject]], .data[[type]]),
        color = .data[[subject]],
        linetype = .data[[type]],
        shape = .data[[type]]
      )
    ) +
      geom_line() +
      geom_point(size = 4)
  )
}
