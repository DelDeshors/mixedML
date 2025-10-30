.test_reservoir_mixedml <- function(fixed_spec, random_spec, data, data_val, subject, time, mixedml_controls) {
  stopifnot(all(.get_x_labels(fixed_spec) %in% colnames(data)))
  stopifnot(.get_y_label(fixed_spec) %in% colnames(data))
  #
  stopifnot(is.null(.get_y_label(random_spec)))
  stopifnot(all(.get_x_labels(random_spec) %in% colnames(data)))
  #
  .check_sorted_data(data, subject, time)
  if (!is.null(data_val)) {
    stopifnot(setequal(colnames(data_val), colnames(data)))
    stopifnot(length(intersect(rownames(data_val), rownames(data))) == 0)
    .check_sorted_data(data_val, subject, time)
  }

  .check_controls_with_function(mixedml_controls, mixedml_ctrls)
  return()
}


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
#' The default use the date at start in the format "mixedML-%y%m%d-%H%M%S"
#' (ex: mixedML-250709-100530)
#' @return fitted MixedML model (best iteration)
#' @export
reservoir_mixedml <- function(
  fixed_spec,
  random_spec,
  data,
  data_val = NULL,
  subject,
  time,
  mixedml_controls = mixedml_ctrls(),
  hlme_controls = hlme_ctrls(),
  esn_controls = esn_ctrls(),
  ensemble_controls = ensemble_ctrls(),
  fit_controls = fit_ctrls()
) {
  # please see .get_model_snapshot to understand the choice of the variables names
  call <- match.call()
  .test_reservoir_mixedml(fixed_spec, random_spec, data, data_val, subject, time, mixedml_controls)
  do_val <- (!is.null(data_val))
  #
  target_name <- .get_y_label(fixed_spec)
  # we change the convergence criterions for faster iterations
  # the original criterions will be used to adjust the final model
  hlme_controls_final <- hlme_controls
  hlme_controls_iter <- hlme_controls
  hlme_controls_iter$convB <- mixedml_controls$convB
  hlme_controls_iter$convL <- mixedml_controls$convL
  hlme_controls_iter$convG <- mixedml_controls$convG
  # initialization ----
  random_model <- .initiate_random_hlme(target_name, random_spec, data, subject, time, hlme_controls_iter)
  fixed_model <- .initiate_esn(esn_controls, ensemble_controls, fit_controls)
  #
  min_mse_gain <- mixedml_controls$earlystopping_controls$min_mse_gain
  patience <- mixedml_controls$earlystopping_controls$patience
  estop_thesh <- Inf
  #
  abort_mse <- mixedml_controls$aborting_controls$mse_value
  abort_iter <- mixedml_controls$aborting_controls$check_iter
  #
  data_train <- data
  data_fixed <- data
  data_rand <- data
  pred_rand <- rep(0, nrow(data))
  istep <- 1
  mse_train_list <- c()
  mse_val_list <- c()
  loglik_train_list <- c()
  loglik_val_list <- c()
  mse_min <- Inf
  # confusing name, might need to change:
  n_na_full <- .check_na_combinaison(data_train, fixed_spec, random_spec, target_name)
  backup <- tempfile(fileext = ".Rds")
  # convergence loop ----
  while (TRUE) {
    start <- format(Sys.time(), "%H:%M:%S")
    message(sprintf("step#%d", istep))
    # fitting fixed effects -----
    message("\tfitting fixed effects...")
    data_fixed[[target_name]] <- data_train[[target_name]] - pred_rand
    fitted_fixed_model <- try_fit_fixed_model(fixed_model, data_fixed, fixed_spec, subject)
    if (is.null(fitted_fixed_model)) {
      break() # the "break" must stay in the loop
    }
    pred_fixed <- try_predict_fixed_model(fixed_model, data_fixed, fixed_spec, subject)
    if (is.null(pred_fixed)) {
      break() # the "break" must stay in the loop
    }
    # fitting random effects -----
    message("\tfitting random effects...")
    data_rand[[target_name]] <- data_train[[target_name]] - pred_fixed
    random_model <- try(.fit_random_hlme(random_model, data_rand), silent = FALSE)
    if (inherits(random_model, "try-error")) {
      warning("Training of the HLME model failed: aborting the training loop!")
      break()
    }
    .check_convergence_hlme(random_model)
    pred_rand <- try(
      .predict_random_hlme(random_model, data_rand, mixedml_controls$all_info_hlme_prediction),
      silent = FALSE
    )
    if (inherits(pred_rand, "try-error")) {
      warning("Prediction with the HLME model failed: aborting the training loop!")
      break()
    }
    # train residuals/mse and loglik----
    residuals_train <- data_train[, target_name] - (pred_fixed + pred_rand)
    ccases_resid <- complete.cases(residuals_train)
    stopifnot(n_na_full == sum(!ccases_resid))
    mse_train <- mean(residuals_train[ccases_resid]**2)
    message(sprintf("\tMSE-train = %.4g", mse_train))
    mse_train_list <- c(mse_train_list, mse_train)
    #
    loglik_train <- random_model$loglik
    loglik_train_list <- c(loglik_train_list, loglik_train)
    # val residuals/mse and loglik ----
    if (do_val) {
      tmp_model <- .get_model_snapshot()
      pred_val <- predict(tmp_model, data_val, mixedml_controls$all_info_hlme_prediction)
      residuals_val <- data_val[, target_name] - pred_val
      mse_val <- mean(residuals_val[ccases_resid]**2, na.rm = TRUE)
      message(sprintf("\tMSE-val = %.4g", mse_val))
      mse_val_list <- c(mse_val_list, mse_val)
      #
      hlme_val <- stats::update(random_model, data = data_val, B = random_model$best, maxiter = 0)
      loglik_val <- hlme_val$loglik
      loglik_val_list <- c(loglik_val_list, loglik_val)
    }
    # convergence tests ----
    if (do_val) {
      mse_conv <- mse_val
    } else {
      mse_conv <- mse_train
    }
    ## aborting test ----
    if (istep == abort_iter) {
      if (mse_conv > abort_mse) {
        warning("Conditions defined in aborting_controls: aborting training loop!")
        break()
      }
    }
    ## improving / early stopping test ----
    if (mse_conv < estop_thesh - min_mse_gain) {
      message("\t(improvement)")
      estop_thesh <- mse_conv
      count_conv <- 0
    } else {
      count_conv <- count_conv + 1
      message(sprintf("\t(no improvement #%d)", count_conv))
      if (count_conv == patience) {
        warning("Conditions defined in early_stopping: aborting training loop!")
        break()
      }
    }
    ## improvement test ----
    if (mse_conv < mse_min) {
      message("\t(saving best model)")
      mse_min <- mse_conv
      # must save it since we have a reference to the Python model
      # so we cannot use `best_fixed_model <- fixed_model`
      # (`best_fixed_model` points to the model that keeps being updated)
      save_mixedml(.get_model_snapshot(), backup, overwrite = TRUE)
      best_random_model <- random_model
      # saving for fine tuning
      best_data_rand <- data_rand
      # nolint start ----
      # best_pred_fixed <- pred_fixed
      # best_data_fixed <- data_fixed
      # nolint end ----
    }
    istep <- istep + 1
  }
  #
  if (!file.exists(backup)) {
    stop("The model could not be trained or could not predict at all!")
  }
  #
  best_model <- load_mixedml(backup)
  best_model <- .update_model_snapshot_lists(best_model, .get_model_snapshot())
  # final model with saved convergence criteria ----
  message("Final convergence of HLME with strict convergence criterions.")
  best_model$random_model <- .fine_tune(best_model$random_model, best_data_rand, hlme_controls_final)
  .check_convergence_hlme(best_model$random_model)
  # NOTE: after updating the random model, the stored MSE/loglik could also be updated
  # It is likely a matter 0.01% difference but it could confuse the user (it confused me!)
  # This should not be done before a refactoring to isolate the fixed>residual>random operation in a specific function
  #
  # nolint start ----
  # xlab <- .get_x_labels(fixed_spec)
  #
  # A1 <- best_data_fixed[xlab]
  # A2 <- data_train[xlab]
  # stopifnot(identical(A1, A2))
  #
  # A1 <- best_data_fixed[xlab]
  # A2 <- data_train[xlab]
  # stopifnot(identical(A1, A2))
  #
  # PRED_FIXED <- .predict_reservoir(
  #   best_model$fixed_model,
  #   data_fixed,
  #   fixed_spec,
  #   subject
  # )
  #
  # A1 <- PRED_FIXED
  # A2 <- best_pred_fixed
  # stopifnot(identical(A1, A2))
  #
  # A1 <- data_train[[target_name]] - PRED_FIXED
  # A2 <- best_data_rand[[target_name]]
  # stopifnot(identical(A1, A2))
  # nolint end ----
  return(best_model)
}
