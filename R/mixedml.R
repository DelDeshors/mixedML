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
  "fixed_model",
  "random_model",
  "loglik_train",
  "loglik_val",
  "mse_train_list",
  "mse_val_list",
  "loglik_train_list",
  "loglik_val_list",
  "call"
)

.get_model <- function() {
  pframe <- as.list(parent.frame())
  stopifnot(all(MIXEDML_COMPONENTS %in% names(pframe)))
  model <- pframe[MIXEDML_COMPONENTS]
  class(model) <- MIXEDML_CLASS
  return(model)
}


.test_is_midexml <- function(model) {
  # can work alone or in a "if" condition
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(setequal(names(model), MIXEDML_COMPONENTS))
  return(TRUE)
}

#' Prepare the mixedml_controls
#'
#'
#' @param patience Number of iterations without improvement before the training is stopped. Default: 2
#' @param conv_thresh Minimal difference of MSE to consider an improvement.
#' `conv_thresh=0.01` means an improvement of at least 1% of the MSE is necessary. Default: 0.01
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

.joblib_from_rds <- function(mixedml_model_rds) {
  return(paste0(mixedml_model_rds, ".joblib"))
}

#' Save a MixedML model
#'
#' @param model Trained MixedML model
#' @param mixedml_model_rds Name of the RDS fileNew data (same format as the one used for training)
#' @export
save_mixedml <- function(model, mixedml_model_rds) {
  .test_is_midexml(model)
  if (.is_python_model(model$fixed_model)) {
    fixed_model_joblib <- .joblib_from_rds(mixedml_model_rds)
    .save_py_object(model$fixed_model, fixed_model_joblib)
    model$fixed_model <- NULL
  }
  saveRDS(model, mixedml_model_rds)
  return(invisible())
}

#' Load a MixedML model
#'
#' @param mixedml_model_rds Name of the RDS fileNew data (same format as the one used for training)
#' @export
#' @return MixedMl model
#' @export
load_mixedml <- function(mixedml_model_rds) {
  model <- readRDS(mixedml_model_rds)
  if (is.null(model$fixed_model)) {
    fixed_model_joblib <- .joblib_from_rds(mixedml_model_rds)
    model$fixed_model <- .load_py_object(fixed_model_joblib)
  }
  return(model)
}


# prediction ----

.test_predict <- function(model, data) {
  .test_is_midexml(model)
  stopifnot(names(data) == names(model$random_model$data))
  .check_sorted_data(data, model$subject, model$time)
  return()
}

#' Predict using a fitted model and new data
#'
#' @param model Trained MixedML model
#' @param data New data (same format as the one used for training)
#' @param all_info_hlme_prediction boolean to choose if all the information
#' (past, present, future) is used for the hlme prediction (TRUE) or if only the past
#' information is used (FALSE). Default: FALSE
#' @return prediction
#' @export
predict <- function(
  model,
  data,
  all_info_hlme_prediction = FALSE
) {
  .test_predict(model, data)
  target_name <- .get_y_label(model$fixed_spec)
  data_rand <- data
  pred_fixed <- .predict_reservoir(
    model$fixed_model,
    data,
    model$fixed_spec,
    model$subject
  )
  data_rand[[target_name]] <- data[[target_name]] - pred_fixed
  pred_rand <- .predict_random_hlme(
    model$random_model,
    data_rand,
    all_info_hlme_prediction
  )
  return(pred_fixed + pred_rand)
}


.plot_train_val_metric <- function(
  metric_train_list,
  metric_val_list,
  metric_name,
  ylog
) {
  stopifnot(is.logical(ylog))
  data_plot <- data.frame(
    iteration = seq_along(metric_train_list),
    METRIC = metric_train_list,
    group = "train"
  )
  if (!is.null(metric_val_list)) {
    data_plot <- rbind(
      data_plot,
      data.frame(
        iteration = seq_along(metric_val_list),
        METRIC = metric_val_list,
        group = "val"
      )
    )
  }
  colnames(data_plot)[2] <- metric_name
  plt <- ggplot2::ggplot(
    data = data_plot,
    aes(x = iteration, y = .data[[metric_name]], color = group)
  ) +
    ggplot2::geom_line() +
    geom_point()
  if (ylog) {
    plt <- plt + scale_y_log10()
  }
  return(plt)
}


#' Plot the (MSE) convergence of the MixedML training and validation
#'
#'
#'
#' @param model Trained MixedML model
#' @param ylog Plot the y-value with a log scale. Default: FALSE
#' @return Convergence plot
#' @export
plot_conv_mse <- function(model, ylog = FALSE) {
  .test_is_midexml(model)
  return(.plot_train_val_metric(
    model$mse_train_list,
    model$mse_val_list,
    metric_name = "MSE",
    ylog = ylog
  ))
}

#' Plot the log-likelihood of the random effect hlme during training
#'
#'
#'
#' @param model Trained MixedML model
#' @return Log-likelihood plot
#' @export
plot_conv_loglik <- function(model) {
  .test_is_midexml(model)
  return(.plot_train_val_metric(
    model$loglik_train_list,
    model$loglik_val_list,
    metric_name = "loglik",
    ylog = FALSE
  ))
}


#' Plot the prediction of a MixedML model beside the true/target values
#'
#' @param model Trained MixedML model.
#' @param subject_nb_or_list Number of subjects to plot (randomly selected) or
#' list of subjects to plot (amongst the train/val dataset).
#' @param ylog Plot the y-value with a log scale. Default: TRUE.
#' @return Prediction plot of the model.
#' @export
plot_prediction_check <- function(model, subject_nb_or_list, ylog = FALSE) {
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(is.integer(subject_nb_or_list))
  stopifnot(is.logical(ylog))
  #
  subject <- model$subject
  time <- model$time
  target <- .get_y_label(model$fixed_spec)
  #
  type <- "type"
  type1 <- "target"
  data_tgt <- model$data
  if (!is.null(model$data_val)) {
    data_tgt <- rbind(data_tgt, model$data_val)
  }
  data_tgt[[type]] <- type1
  #
  type2 <- "pred."
  data_pred <- data_tgt
  data_pred[[type]] <- type2
  data_pred[[target]] <- predict(
    model,
    data_pred,
    all_info_hlme_prediction = TRUE
  )
  data_plot <- rbind(data_tgt, data_pred)
  if (length(subject_nb_or_list) == 1) {
    subject_nb_or_list <- sample(
      unique(data_plot[[subject]]),
      subject_nb_or_list
    )
    message("Subjects selected randomly: use set.seed to change the selection.")
  } else {
    stopifnot(all(subject_nb_or_list %in% model$data[[subject]]))
  }
  #
  idx_keep <- data_plot[[subject]] %in% subject_nb_or_list
  data_plot <- data_plot[idx_keep, ]
  data_plot[[subject]] <- as.factor(data_plot[[subject]])
  return(
    ggplot(
      data_plot,
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
  esn_controls = esn_controls(),
  ensemble_controls = ensemble_controls(),
  fit_controls = fit_controls()
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
  fixed_model <- .initiate_esn(esn_controls, ensemble_controls, fit_controls)
  conv_thresh <- mixedml_controls[["conv_thresh"]]
  patience <- mixedml_controls[["patience"]]
  # initialization (some are for .get_model to work) ----
  data_train <- data
  data_fixed <- data
  data_rand <- data
  pred_rand <- rep(0, nrow(data))
  istep <- 0
  mse_train_list <- c()
  mse_val_list <- c()
  loglik_train <- NULL
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
    fixed_model <- .fit_reservoir(fixed_model, data_fixed, fixed_spec, subject)
    pred_fixed <- .predict_reservoir(
      fixed_model,
      data_fixed,
      fixed_spec,
      subject
    )
    # fitting random effects -----
    cat("\tfitting random effects...\n")
    data_rand[[target_name]] <- data_train[[target_name]] - pred_fixed
    random_model <- .fit_random_hlme(random_model, data_rand)
    .check_convergence_hlme(random_model)
    pred_rand <- .predict_random_hlme(
      random_model,
      data_rand,
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
        mixedml_controls$all_info_hlme_prediction
      )
      residuals_val <- data_val[, target_name] - pred_val
      mse_val <- mean(residuals_val[ccases_resid]**2, na.rm = TRUE)
      cat(sprintf("\tMSE-val = %.4g\n", mse_val))
      mse_val_list <- c(mse_val_list, mse_val)
      #
      hlme_val <- stats::update(
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
      best_data_rand <- data_rand
    }
    istep <- istep + 1
  }
  # final model with saved convergence criteria ----
  cat("Final convergence of HLME with strict convergence criterions.")
  best_random_model <- .fine_tune(
    best_random_model,
    best_data_rand,
    hlme_controls_final
  )
  .check_convergence_hlme(best_random_model)
  # updating with best iteartion values ----
  fixed_model <- best_fixed_model
  random_model <- best_random_model
  loglik_train <- best_loglik_train
  loglik_val <- best_loglik_val
  model <- .get_model()
  return(model)
}
