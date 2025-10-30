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
  "mse_train",
  "mse_val",
  "loglik_train",
  "loglik_val",
  "mse_train_list",
  "mse_val_list",
  "loglik_train_list",
  "loglik_val_list",
  "call"
)

.get_model_snapshot <- function() {
  # must only be called in main loop
  # (where the MIXEDML_COMPONENTS variables are defined)
  pframe <- as.list(parent.frame())
  sdiff <- setdiff(MIXEDML_COMPONENTS, names(pframe))
  if (length(sdiff) > 0) {
    # the warning is temporary, while the package is still evolving
    warning(
      "Dev warning: these components defined in MIXEDML_COMPONENTS are ",
      "not present in the execution environment: ",
      paste(sdiff, collapse = ", ")
    )
    pframe[sdiff] <- NA
  }
  #
  model <- pframe[MIXEDML_COMPONENTS]
  class(model) <- MIXEDML_CLASS
  return(model)
}

.update_model_snapshot_lists <- function(model_snapshot, new_model_snapshot) {
  nm <- new_model_snapshot
  for (n in names(nm)) {
    if (is.vector(nm[[n]]) && length(nm[[n]]) > 1) {
      stopifnot(all(model_snapshot[[n]] %in% nm[[n]]))
      model_snapshot[[n]] <- nm[[n]]
    }
  }
  return(model_snapshot)
}


.test_is_midexml <- function(model) {
  # can work alone or in a "if" condition
  stopifnot(inherits(model, MIXEDML_CLASS))
  if (!all(names(model) %in% MIXEDML_COMPONENTS)) {
    warning("Dev warning: the provided model is likely from an older MixedML version!")
  }
  return(TRUE)
}

#' Prepare the mixedml_controls
#'
#' @param earlystopping_controls controls specific to the early stopping criterion. Please see earlystopping_ctrls().
#' @param aborting_controls controls specific to the aborting criterion. Please see aborting_ctrls().
#' @param all_info_hlme_prediction boolean to choose if all the information
#' (past, present, future) is used for the hlme prediction (TRUE) or if only the past
#' information is used (FALSE). Default: TRUE
#' @param convB optional iterations models threshold for the convergence criterion based on the
#' parameter stability. Used during the MixedML iterations to speed up the HLME model training.
#' By default, convB=0.01.
#' @param convL optional threshold for the convergence criterion based on the
#' log-likelihood stability. Used during the MixedML iterations to speed up the HLME model training.
#' By default, convL=0.01.
#' @param convG optional threshold for the convergence criterion based on the
#' derivatives. Used during the MixedML iterations to speed up the HLME model training.
#' By default, convG=0.10.
#' @return mixedml_controls
#' @export
mixedml_ctrls <- function(
  earlystopping_controls = earlystopping_ctrls(),
  aborting_controls = aborting_ctrls(),
  all_info_hlme_prediction = TRUE,
  convB = 0.01, # nolint
  convL = 0.01, # nolint
  convG = 0.01 # nolint
) {
  .check_training_stop_controls(earlystopping_controls, aborting_controls)
  stopifnot(is.logical(all_info_hlme_prediction))
  stopifnot(is.single.numeric(convB) && convB > 0)
  stopifnot(is.single.numeric(convL) && convL > 0)
  stopifnot(is.single.numeric(convG) && convG > 0)
  #
  control <- as.list(environment())
  return(control)
}

#' Prepare the earlystopping controls. The earlystopping controls are used to stop the training
#' when convergence is reached.
#' If no improvement of the MSE greater than `min_mse_gain` is observed during `patience` iterations,
#' then the training is stopped.
#' If a validation dataset is provided, the MSE on the validation dataset is used for the early stopping.
#' Otherwise, the MSE on the training dataset is used.
#' By default, early stopping is disabled.
#' @param patience Number of iterations without improvement before the training is stopped. Default: Inf.
#' @param min_mse_gain Minimal difference of MSE to consider an improvement.
#' `min_mse_gain=1.` means an improvement of at least 1. of the MSE is necessary. Default: 0.
#' @return earlystopping_controls
#' @export
earlystopping_ctrls <- function(patience = Inf, min_mse_gain = 0.) {
  stopifnot(is.single.integer(patience) && 0 <= patience)
  patience <- as.integer(patience)
  stopifnot(is.single.numeric(min_mse_gain))
  stopifnot(0 <= min_mse_gain)
  control <- as.list(environment())
  return(control)
}

#' Prepare the aborting controls. The aborting controls are used to stop the training of unpromising models.
#' If the MSE is still above `mse_value` value at iteration `check_iter` then the training is stopped.
#' @param mse_value Value to compare the MSE to. Default: Inf.
#' @param check_iter Iteration at which the check is done. Default: Inf.
#' @return aborting_controls
#' @export
aborting_ctrls <- function(mse_value = Inf, check_iter = Inf) {
  stopifnot(is.single.numeric(mse_value) && mse_value >= 0)
  stopifnot(is.single.integer(check_iter) && check_iter >= 0)
  control <- as.list(environment())
  return(control)
}


.check_training_stop_controls <- function(earlystopping_controls, aborting_controls) {
  .check_controls_with_function(earlystopping_controls, earlystopping_ctrls)
  .check_controls_with_function(aborting_controls, aborting_ctrls)
  # at least one stopping criterion must be enabled
  test1 <- is.finite(earlystopping_controls$patience)
  test2 <- all(is.finite(c(aborting_controls$mse_value, aborting_controls$check_iter)))
  if (!(test1 || test2)) {
    stop("Both earlystopping_controls and aborting_controls are disabled: the training loop will run indefinitely!")
  }
  return()
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
  if (n_na_full > 0) {
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
  }
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
save_mixedml <- function(model, mixedml_model_rds, overwrite = FALSE) {
  .test_is_midexml(model)
  if (.is_python_model(model$fixed_model)) {
    fixed_model_joblib <- .joblib_from_rds(mixedml_model_rds)
    if (file.exists(fixed_model_joblib) && overwrite) {
      file.remove(fixed_model_joblib)
    }
    .save_py_object(model$fixed_model, fixed_model_joblib)
    model$fixed_model <- NULL
  }
  if (file.exists(mixedml_model_rds) && overwrite) {
    file.remove(mixedml_model_rds)
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
predict <- function(model, data, all_info_hlme_prediction = FALSE) {
  .test_predict(model, data)
  target_name <- .get_y_label(model$fixed_spec)
  data_rand <- data
  pred_fixed <- predict_fixed_model(model$fixed_model, data, model$fixed_spec, model$subject)
  data_rand[[target_name]] <- data[[target_name]] - pred_fixed
  pred_rand <- .predict_random_hlme(model$random_model, data_rand, all_info_hlme_prediction)
  return(pred_fixed + pred_rand)
}


#' Return the negative log-likelihood of the model regarding new data
#'
#' @param model Trained MixedML model
#' @param data New data (same format as the one used for training)
#' @return Negative log-likelihood of the HLME model
#' @export
get_loglik <- function(model, data) {
  # (might be refactored with predict)
  .test_predict(model, data)
  target_name <- .get_y_label(model$fixed_spec)
  data_rand <- data
  pred_fixed <- predict_fixed_model(model$fixed_model, data, model$fixed_spec, model$subject)
  data_rand[[target_name]] <- data[[target_name]] - pred_fixed
  random_model <- update(model$random_model, data = data_rand, B = model$random_model$best, maxiter = 0)
  return(random_model$loglik)
}


.plot_train_val_metric <- function(metric_train_list, metric_val_list, metric_name, ylog) {
  stopifnot(is.logical(ylog))
  data_plot <- data.frame(iteration = seq_along(metric_train_list), METRIC = metric_train_list, group = "train")
  if (!is.null(metric_val_list)) {
    data_plot <- rbind(
      data_plot,
      data.frame(iteration = seq_along(metric_val_list), METRIC = metric_val_list, group = "val")
    )
  }
  colnames(data_plot)[2] <- metric_name
  plt <- ggplot2::ggplot(data = data_plot, aes(x = iteration, y = .data[[metric_name]], color = group)) +
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
  return(.plot_train_val_metric(model$mse_train_list, model$mse_val_list, metric_name = "MSE", ylog = ylog))
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
  return(.plot_train_val_metric(model$loglik_train_list, model$loglik_val_list, metric_name = "loglik", ylog = FALSE))
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
  data_pred[[target]] <- predict(model, data_pred, all_info_hlme_prediction = TRUE)
  data_plot <- rbind(data_tgt, data_pred)
  if (length(subject_nb_or_list) == 1) {
    subject_nb_or_list <- sample(unique(data_plot[[subject]]), subject_nb_or_list)
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
      scale_shape_manual(name = "Y value", values = c(3, 4))
  )
}
