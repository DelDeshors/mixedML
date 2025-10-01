library(ggplot2)

# initialization ----

MIXEDML_CLASS <- "MixedML_Model"

MIXEDML_COMPONENTS <- c(
  "data",
  "data_val",
  "subject",
  "time",
  "fixed_spec",
  "random_spec",
  "best_fixed_model",
  "best_random_model",
  "best_loglik_train",
  "best_loglik_val",
  "mse_train_list",
  "mse_val_list",
  "loglik_train_list",
  "loglik_val_list",
  "call"
)

.get_model <- function() {
  pframe <- parent.frame()
  stopifnot(all(MIXEDML_COMPONENTS %in% names(pframe)))
  model <- as.list(pframe)[MIXEDML_COMPONENTS]
  class(model) <- MIXEDML_CLASS
  return(model)
}


.test_is_midexml <- function(model) {
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(setequal(names(model), MIXEDML_COMPONENTS))
  return()
}

#' Prepare the mixedml_controls
#'
#'
#' @param patience Number of iterations without improvement before the training is stopped. Default: 2
#' @param conv_thresh Minimal difference of MSE to consider an improvement.
#' `conv_thresh=0.01` means an improvement of at least 1% of the MSE is necessary. Default: 0.01
#' @param no_random_value_as value to use during the training of the mixedML model
#' when a prediction of the random model is not possible (NA or 0).
#' This does not affect the prediction.
#' Default: NA
#' @param all_info_hlme_prediction boolean to choose if all the information
#' (past, present, future) is used for the hlme prediction (TRUE) or if only the past
#' information is used (FALSE). Default: TRUE
#' @param convB optional iterations models threshold for the convergence criterion based on the
#' parameter stability. Used during the MixedML iterations.
#' By default, convB=0.01.
#' @param convL optional threshold for the convergence criterion based on the
#' log-likelihood stability. Used during the MixedML iterations.
#' By default, convL=0.01.
#' @param convG optional threshold for the convergence criterion based on the
#' derivatives. Used during the MixedML iterations.
#' By default, convG=0.10.
#' @return mixedml_controls
#' @export
mixedml_ctrls <- function(
  patience = 2,
  conv_thresh = 0.01,
  no_random_value_as = NA,
  all_info_hlme_prediction = TRUE,
  convB = 0.01, # nolint
  convL = 0.01, # nolint
  convG = 0.01 # nolint
) {
  stopifnot(is.single.integer(patience) & 0 <= patience)
  patience <- as.integer(patience)
  stopifnot(is.single.numeric(conv_thresh))
  stopifnot(0 < conv_thresh)
  #
  stopifnot(length(no_random_value_as) == 1)
  stopifnot(is.na(no_random_value_as) || (no_random_value_as == 0))
  #
  control <- as.list(environment())
  return(control)
}


.check_na_combinaison <- function(data, fixed_spec, random_spec, target_name) {
  # can be moved into a function
  # !!! need to be adapted for ML model that have constraints on both X and Y
  x_labels_fixed <- .get_x_labels(fixed_spec)
  ccases_fixed <- complete.cases(data[x_labels_fixed])
  n_na_fixed <- sum(!ccases_fixed)
  #
  x_labels_rand <- .get_x_labels(random_spec)
  ccases_rand <- complete.cases(data[c(x_labels_rand, target_name)])
  n_na_rand <- sum(!ccases_rand)
  #
  ccases_target <- complete.cases(data[target_name])
  n_na_target <- sum(!ccases_target)
  #
  ccases_full <- ccases_fixed & ccases_rand & ccases_target
  n_na_full <- sum(!ccases_full)
  warning(sprintf(
    "
         %d incomplete cases for the ML models
         %d incomplete cases for the HLME model
         %d NA values in target
         => %d/%d observations could not be used to train (either no fixed preds, random preds or target).",
    n_na_fixed,
    n_na_rand,
    n_na_target,
    n_na_full,
    nrow(data)
  ))
  return(n_na_full)
}


# model backups ----
.save_backup <- function(fixed_model, random_model, output_dir, iteration_num) {
  if (.is_python_model(fixed_model)) {
    .save_py_object(
      fixed_model,
      sprintf("%s/%03d_fixed_model.joblib", output_dir, iteration_num)
    )
  } else {
    saveRDS(
      random_model,
      sprintf("%s/%03d_fixed_model.Rds", output_dir, iteration_num)
    )
  }
  saveRDS(
    random_model,
    sprintf("%s/%03d_random_model.Rds", output_dir, iteration_num)
  )
  return()
}


load_backup <- function(fixed_model_rds_or_joblib, random_model_rds) {
  if (endsWith(fixed_model_rds_or_joblib, ".joblib")) {
    fixed_model <- .load_py_object(fixed_model_rds_or_joblib)
  } else if (endsWith(fixed_model_rds_or_joblib, ".Rds")) {
    fixed_model <- readRDS(fixed_model_rds_or_joblib)
  } else {
    stop("Incorrect extension for fixed_model_rds_or_joblib argument.")
  }
  output <- list(
    fixed_model = fixed_model,
    random_model = readRDS(random_model_rds)
  )
  class(output) <- MIXEDML_CLASS
  .test_is_midexml(output)
  return(output)
}


# prediction ----

.test_predict <- function(model, data) {
  .test_is_midexml(model)
  stopifnot(names(data) == names(model$random_model$data))
  return()
}

#' Predict using a fitted model and new data
#'
#' @param model Trained MixedML model
#' @param data New data (same format as the one used for training)
#' @param no_random_value_as value to use during the training of the mixedML model
#' when a prediction of the random model is not possible (NA or 0).
#' This does not affect the prediction. Default: 0.
#' @param all_info_hlme_prediction boolean to choose if all the information
#' (past, present, future) is used for the hlme prediction (TRUE) or if only the past
#' information is used (FALSE). Default: FALSE
#' @return prediction
#' @export
predict <- function(
  model,
  data,
  no_random_value_as = 0.,
  all_info_hlme_prediction = FALSE
) {
  if (!is.null(model$random_model$call$cor)) {
    warning(
      "The prediction does not yet take into account the correlation relation in hlme"
    )
  }
  .test_predict(model, data)
  target_name <- .get_y_label(model$fixed_spec)
  data_rand <- data
  pred_fixed <- .predict_reservoir(model$fixed_model, data)
  data_rand[[target_name]] <- data[[target_name]] - pred_fixed
  pred_rand <- .predict_random_hlme(
    model$random_model,
    data_rand,
    no_random_value_as,
    all_info_hlme_prediction
  )
  return(pred_fixed + pred_rand)
}

#' Plot the (MSE) convergence of the MixedML training and validation
#'
#'
#'
#' @param model Trained MixedML model
#' @param ylog Plot the y-value with a log scale. Default: TRUE.
#' @return Convergence plot
#' @export
plot_conv <- function(model, ylog = TRUE) {
  .test_is_midexml(model)
  stopifnot(is.logical(ylog))
  data_plot <- data.frame(
    iteration = seq_along(model$mse_train_list),
    MSE = model$mse_train_list,
    group = "train"
  )
  if (!is.null(model$mse_val_list)) {
    data_plot <- rbind(
      data_plot,
      data.frame(
        iteration = seq_along(model$mse_val_list),
        MSE = model$mse_val_list,
        group = "val"
      )
    )
  }
  plt <- ggplot2::ggplot(
    data = data_plot,
    aes(x = iteration, y = MSE, color = group)
  ) +
    ggplot2::geom_line() +
    geom_point()
  if (ylog) {
    plt <- plt + scale_y_log10()
  }
  return(plt)
}

#' Plot the log-likelihood of the random effect hlme during training
#'
#'
#'
#' @param model Trained MixedML model
#' @param ylog Plot the y-value with a log scale. Default: TRUE.
#' @return Log-likelihood plot
#' @export
plot_loglik <- function(model, ylog = TRUE) {
  .test_is_midexml(model)
  stopifnot(is.logical(ylog))
  return(plot(
    seq_along(model$loglik_train_list),
    model$loglik_train_list,
    type = "o",
    xlab = "iterations",
    ylab = "log-likelihood (hlme)",
    ylog = ylog
  ))
}


#' Plot the prediction of a MixedML model (best iteration)
#'
#' @param model Trained MixedML model.
#' @param subject_nb_or_list Number of subjects to plot (randomly selected) or
#' list of subjects to plot.
#' @param ylog Plot the y-value with a log scale. Default: TRUE.
#' @return Prediction plot of the model.
#' @export
plot_best_iter <- function(model, subject_nb_or_list, ylog = FALSE) {
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(is.integer(subject_nb_or_list))
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
  if (length(subject_nb_or_list) == 1) {
    subject_nb_or_list <- sample(
      unique(data_[[subject]]),
      subject_nb_or_list
    )
    message("Subjects selected randomly: use set.seed to change the selection.")
  } else {
    stopifnot(all(subject_nb_or_list %in% model$data[[subject]]))
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
        shape = .data[[type]],
      )
    ) +
      # geom_line() +
      geom_point(size = 3) +
      scale_shape_manual(
        name = "Y value",
        values = c(3, 4)
      )
  )
}


# recipe: HLME/Reservoir ----

.test_reservoir_mixedml <- function(
  fixed_spec,
  random_spec,
  data,
  data_val,
  subject,
  time,
  mixedml_controls,
  hlme_controls,
  esn_controls,
  ensemble_controls,
  fit_controls
) {
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
#' @param output_dir folder path where the models and log will be saved.
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
  esn_controls = esn_controls(),
  ensemble_controls = ensemble_controls(),
  fit_controls = fit_controls(),
  output_dir = paste0("mixedML-", format(Sys.time(), "%y%m%d-%H%M%S"))
) {
  call <- match.call()
  .test_reservoir_mixedml(
    fixed_spec,
    random_spec,
    data,
    data_val,
    subject,
    time,
    mixedml_controls,
    hlme_controls,
    esn_controls,
    ensemble_controls,
    fit_controls
  )
  do_val <- (!is.null(data_val))
  #
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  #
  target_name <- .get_y_label(fixed_spec)
  # we change the convergence criterions for faster iterations
  # the original criterions will be used to adjust the final model
  hlme_controls_final <- hlme_controls
  hlme_controls_iter <- hlme_controls
  hlme_controls_iter$convB <- mixedml_controls$convB
  hlme_controls_iter$convL <- mixedml_controls$convL
  hlme_controls_iter$convG <- mixedml_controls$convG
  random_model <- .initiate_random_hlme(
    target_name,
    random_spec,
    data,
    subject,
    time,
    hlme_controls_iter
  )
  fixed_model <- .initiate_esn(
    fixed_spec,
    subject,
    esn_controls,
    ensemble_controls,
    fit_controls
  )
  conv_thresh <- mixedml_controls[["conv_thresh"]]
  patience <- mixedml_controls[["patience"]]
  ##
  data_train <- data
  data_fixed <- data
  data_rand <- data
  pred_rand <- rep(0, nrow(data))
  istep <- 0
  mse_train_list <- c()
  mse_val_list <- c()
  loglik_train_list <- c()
  loglik_val <- NULL
  loglik_val_list <- c()
  mse_min <- Inf
  # confusing name, might need to change:
  n_na_full <- .check_na_combinaison(
    data_train,
    fixed_spec,
    random_spec,
    target_name
  )
  # convergence loop ----
  while (TRUE) {
    start <- format(Sys.time(), "%H:%M:%S")
    cat(sprintf("step#%d\n", istep))
    # fitting fixed effects -----
    cat("\tfitting fixed effects...\n")
    data_fixed[[target_name]] <- data_train[[target_name]] - pred_rand
    fixed_model <- .fit_reservoir(fixed_model, data_fixed)
    pred_fixed <- .predict_reservoir(fixed_model, data_fixed)
    # fitting random effects -----
    cat("\tfitting random effects...\n")
    data_rand[[target_name]] <- data_train[[target_name]] - pred_fixed
    random_model <- .fit_random_hlme(random_model, data_rand)
    .check_convergence_hlme(random_model)
    pred_rand <- .predict_random_hlme(
      random_model,
      data_rand,
      mixedml_controls$no_random_value_as,
      mixedml_controls$all_info_hlme_prediction
    )
    # train residuals/mse and loglik----
    residuals_train <- data_train[, target_name] - (pred_fixed + pred_rand)
    ccases_resid <- complete.cases(residuals_train)
    stopifnot(n_na_full == sum(!ccases_resid))
    mse_train <- mean(residuals_train[ccases_resid]**2)
    cat(sprintf("\tMSE-train = %.4g\n", mse_train))
    mse_train_list <- c(mse_train_list, mse_train)
    #
    loglik_train <- random_model$loglik
    loglik_train_list <- c(loglik_train_list, loglik_train)
    # val residuals/mse and loglik ----
    if (do_val) {
      tmp_model <- .get_model()
      pred_val <- predict(
        tmp_model,
        data_val,
        mixedml_controls$no_random_value_as,
        mixedml_controls$all_info_hlme_prediction
      )
      residuals_val <- data_val[, target_name] - pred_val
      mse_val <- mean(residuals_val[ccases_resid]**2, na.rm = TRUE)
      cat(sprintf("\tMSE-val = %.4g\n", mse_val))
      mse_val_list <- c(mse_val_list, mse_val)
      #
      hlme_val <- update(
        random_model,
        data = data_val,
        B = random_model$best,
        maxiter = 0
      )
      loglik_val <- hlme_val$loglik
      loglik_val_list <- c(loglik_val_list, loglik_val)
    }
    # convergence tests ----
    if (do_val) {
      mse_conv <- mse_val
    } else {
      mse_conv <- mse_train
    }
    if (mse_conv < mse_min - conv_thresh) {
      count_conv <- 0
    } else {
      count_conv <- count_conv + 1
      if (count_conv > patience) {
        break
      }
    }
    if (mse_conv < mse_min) {
      mse_min <- mse_conv
      best_fixed_model <- fixed_model
      best_random_model <- random_model
      best_loglik_train <- loglik_train
      best_loglik_val <- loglik_val
    }
    .save_backup(fixed_model, random_model, output_dir, istep)
    istep <- istep + 1
  }
  # final model with saved convergence criteria
  cat("Final convergence of HLME with strict convergence criterions.")
  best_random_model <- stats::update(
    best_random_model,
    B = best_random_model$best,
    convB = hlme_controls_final$convB,
    convL = hlme_controls_final$convL,
    convG = hlme_controls_final$convG
  )
  .check_convergence_hlme(best_random_model)
  model <- .get_model()
  return(model)
}
