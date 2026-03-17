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


#' This function captures the current model state in the training loop
#' the names of the saved variables is defined in MIXEDML_COMPONENTS
.get_model_snapshot <- function() {
  # must only be called in main loop
  # (where the MIXEDML_COMPONENTS variables are defined)
  pframe <- as.list(parent.frame())
  sdiff <- setdiff(MIXEDML_COMPONENTS, names(pframe))
  if (length(sdiff) > 0) {
    warning(
      "Dev warning: these components defined in MIXEDML_COMPONENTS are ",
      "not defined in mixedml_training_loop",
      paste(sdiff, collapse = ", ")
    )
  }
  pframe[sdiff] <- NA
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
#' By default, convG=0.01.
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
  test1 <- is.finite(earlystopping_controls$patience) && earlystopping_controls$min_mse_gain > 0
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


# summary ----

#' @method summary MixedML_Model
#' @export
summary.MixedML_Model <- function(object, ...) {
  model <- object
  .test_is_midexml(model)
  cat("\n\n == MixedML model ==\n")
  cat("  Type of the fixed effect model:", class(model$fixed_model)[1], "\n")
  cat("  Number of iterations:", length(model$mse_train_list), "\n")
  iter <- match(model$mse_train, model$mse_train_list)
  cat("  Best iteration:", iter, "\n")
  cat("    MSE-train:", model$mse_train, "\n")
  if (!is.null(model$mse_val)) {
    cat("    MSE-val:", model$mse_val, "\n")
  }
  cat("    loglik-train:", model$loglik_train, "\n")
  if (!is.null(model$loglik_val)) {
    cat("    loglik-val:", model$loglik_val, "\n")
  }
  #
  summary_fixed_model(model$fixed_model)
  cat("\n\n == Random HLME model ==\n")
  summary(model$random_model)
  return()
}


# model backups ----

.joblib_from_rds <- function(mixedml_model_rds) {
  return(paste0(mixedml_model_rds, ".joblib"))
}

#' Save a MixedML model
#'
#' @param model Trained MixedML model
#' @param mixedml_model_rds Name of the RDS fileNew data (same format as the one used for training)
#' @param overwrite Overwrite file if it exists? Default: FALSE
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
.test_predict <- function(model, data, all_info_hlme_prediction, nproc_hlme_past) {
  .test_is_midexml(model)
  .check_sorted_data(data, model$subject, model$time)
  stopifnot(is.logical(all_info_hlme_prediction))
  stopifnot(is.single.integer(nproc_hlme_past) && nproc_hlme_past > 0)
  if (all_info_hlme_prediction && nproc_hlme_past > 1) {
    message("nproc_hlme_past has no effect with all_info_hlme_prediction=TRUE")
  }
  return()
}

#' Predict using a fitted model and new data
#'
#' @param model Trained MixedML model
#' @param data New data (same format as the one used for training)
#' @param all_info_hlme_prediction boolean to choose if all the information
#' (past, present, future) is used for the hlme prediction (TRUE) or if only the past
#' information is used (FALSE). Default: FALSE
#' @param nproc_hlme_past number of processes to use for the past information prediction with the hlme modes. Default: 1
#' @return prediction
#' @export
predict <- function(model, data, all_info_hlme_prediction = FALSE, nproc_hlme_past = 1) {
  .test_predict(model, data, all_info_hlme_prediction, nproc_hlme_past)
  target_name <- .get_y_label(model$fixed_spec)
  data_rand <- data
  pred_fixed <- predict_fixed_model(model$fixed_model, data, model$fixed_spec, model$subject)
  data_rand[[target_name]] <- data[[target_name]] - pred_fixed
  pred_rand <- .predict_random_hlme(model$random_model, data_rand, all_info_hlme_prediction, nproc_hlme_past)
  return(pred_fixed + pred_rand)
}


.test_get_loglik <- function(model, data) {
  .test_is_midexml(model)
  stopifnot(names(data) == names(model$random_model$data))
  .check_sorted_data(data, model$subject, model$time)
  return()
}


#' Return the negative log-likelihood of the model regarding new data
#'
#' @param model Trained MixedML model
#' @param data New data (same format as the one used for training)
#' @return Negative log-likelihood of the HLME model
#' @export
get_loglik <- function(model, data) {
  # (might be refactored with predict)
  .test_get_loglik(model, data)
  target_name <- .get_y_label(model$fixed_spec)
  data_rand <- data
  pred_fixed <- predict_fixed_model(model$fixed_model, data, model$fixed_spec, model$subject)
  data_rand[[target_name]] <- data[[target_name]] - pred_fixed
  random_model <- update(model$random_model, data = data_rand, B = model$random_model$best, maxiter = 0)
  return(random_model$loglik)
}

# plotting ----

## convergence ----

.plot_train_val_metric <- function(metric_train_list, metric_val_list, metric_name, ylog) {
  stopifnot(is.logical(ylog))
  data_plot <- data.frame("iteration" = seq_along(metric_train_list), METRIC = metric_train_list, "group" = "train")
  if (!is.null(metric_val_list)) {
    data_plot <- rbind(
      data_plot,
      data.frame(iteration = seq_along(metric_val_list), METRIC = metric_val_list, group = "val")
    )
  }
  colnames(data_plot)[2] <- metric_name
  plt <- ggplot(data = data_plot, aes(x = .data[["iteration"]], y = .data[[metric_name]], color = .data[["group"]])) +
    geom_line() +
    geom_point()
  if (ylog) {
    plt <- plt + scale_y_log10()
  }
  return(plt)
}


#' Plot the MSE and loglikelihood convergence of the MixedML training and validation
#'
#' @param model Trained MixedML model
#' @param ylog_mse Plot the y-value with a log scale. Default: FALSE
#'
#' @return Convergence plot
#' @export
plot_convergence <- function(model, ylog_mse = FALSE) {
  .test_is_midexml(model)
  mse <- .plot_train_val_metric(model$mse_train_list, model$mse_val_list, metric_name = "MSE", ylog = ylog_mse)
  mse <- mse + guides(color = "none")
  loglik <- .plot_train_val_metric(model$loglik_train_list, model$loglik_val_list, metric_name = "loglik", ylog = FALSE)
  return(mse + loglik)
}


## predictions ----

#' Plot individual predictions beside the corresponding true/target values
#'
#' @param model Trained MixedML model.
#' @param data_pred Dataframe used to compute the predictions. It will be used to get the true/target value.
#' @param list_preds Named list of predictions to plot beside the true/target value. The names will be used in the
#' legend. Each prediction must be either a named vector or a single column dataframe, whose name/rowname must
#' correspond to the rownames of data_pred
#' @param ncols Numbre of columns to use for the grid plot. Default: 2
#' @export
plot_predictions <- function(model, data_pred, list_preds, ncols = 2) {
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(is.data.frame(data_pred))
  stopifnot(is.named.list(list_preds) || is.data.frame(list_preds) && ncols(list_preds) == 1)
  stopifnot(all(is.named.vector(list_preds)))
  stopifnot(is.single.integer(ncols))
  #
  if (is.data.frame(list_preds)) {
    new_preds <- list_preds[, 1]
    names(new_preds) <- rownames(list_preds)
    list_preds <- new_preds
  }
  #
  subject <- model$subject
  time <- model$time
  x_labels <- union(.get_x_labels(model$fixed_spec), .get_x_labels(model$random_spec))
  y_label <- .get_y_label(model$fixed_spec)
  #
  pred_type <- "pred_type" # "random" column name
  #
  data_tmp <- data_pred
  data_tmp[[pred_type]] <- "true"
  data_tmp[["linetype"]] <- "solid"
  data_plot <- data_tmp
  #
  for (i in seq_along(list_preds)) {
    name_pred <- names(list_preds)[[i]]
    pred <- list_preds[[i]]
    data_tmp <- data_pred
    data_tmp[[pred_type]] <- name_pred
    data_tmp[["linetype"]] <- "blank"
    data_tmp[y_label] <- NA
    data_tmp[names(pred), y_label] <- pred
    data_plot <- rbind(data_plot, data_tmp)
  }
  #
  data_plot <- data_plot[complete.cases(data_plot[x_labels]), ]
  #
  subj_tmin <- aggregate(data_plot[[time]], by = list(data_plot[[subject]]), FUN = function(x) min(x, na.rm = TRUE))
  subj_tmax <- aggregate(data_plot[[time]], by = list(data_plot[[subject]]), FUN = function(x) max(x, na.rm = TRUE))
  tmin <- min(subj_tmin$x)
  tmax <- max(subj_tmax$x)
  #
  subj_ymin <- aggregate(data_plot[[y_label]], by = list(data_plot[[subject]]), FUN = function(x) min(x, na.rm = TRUE))
  subj_ymax <- aggregate(data_plot[[y_label]], by = list(data_plot[[subject]]), FUN = function(x) max(x, na.rm = TRUE))
  subj_yspan <- subj_ymax$x - subj_ymin$x
  span <- max(subj_yspan)
  #
  list_plots <- NULL
  for (subj in unique(data_pred[[subject]])) {
    data_plot_subj <- data_plot[data_plot[[subject]] == subj, ]
    subj_ymin <- min(data_plot_subj[[y_label]], na.rm = TRUE)
    subj_ymax <- max(data_plot_subj[[y_label]], na.rm = TRUE)
    subj_center <- (subj_ymin + subj_ymax) / 2
    gleg_sub <- guide_legend(title = paste0("ID: ", subj))
    plot <- ggplot(
      data_plot_subj,
      aes(
        x = .data[[time]],
        y = .data[[y_label]],
        color = .data[[pred_type]],
        shape = .data[[pred_type]],
        linetype = .data[["linetype"]]
      )
    ) +
      geom_point(size = 3, na.rm = TRUE) +
      geom_line(na.rm = TRUE) +
      scale_linetype_manual(values = c(solid = "solid", blank = "blank")) +
      guides(color = gleg_sub, shape = gleg_sub, linetype = "none") +
      xlim(tmin, tmax) +
      ylim(subj_center - span / 1.9, subj_center + span / 1.9)

    list_plots <- c(list_plots, plot)
  }
  return(wrap_plots(list_plots, ncol = ncols))
}


#' Plot the predictions of a MixedML model (with all or past informations) beside the corresponding true/target values.
#'
#' @param model Trained MixedML model.
#' @param subject_list List of subjects to plot (amongst the train/val dataset). If NULL, the predictions of all
#' individuals will be printed. Default: NULL
#' @param ncols Number of columns for the grid plot. Default: 2
#' @return Predictions plot of the model.
#' @export
plot_predictions_check <- function(model, subject_list = NULL, ncols = 2) {
  stopifnot(inherits(model, MIXEDML_CLASS))
  stopifnot(is.null(subject_list) || is.vector(subject_list) && all(is.integer(subject_list)))
  stopifnot(is.single.integer(ncols))
  #
  subject <- model$subject
  #
  if (is.null(subject_list)) {
    data_ <- rbind(model$data, model$data_val)
    subject_list <- unique(data_[[subject]])
  }

  list_plots <- NULL
  #
  data <- model$data
  data <- data[data[[subject]] %in% subject_list, ]
  if (nrow(data) != 0) {
    patchwrk <- plot_predictions(
      model,
      data,
      list(
        preds_all_info = predict(model, data, all_info_hlme_prediction = TRUE),
        preds_past_info = predict(model, data, all_info_hlme_prediction = FALSE)
      ),
      ncols = 2
    )
    patchwrk_plots <- as.list(patchwrk)
    patchwrk_plots[[1]] <- patchwrk_plots[[1]] + ggtitle("Training Set")
    list_plots <- c(list_plots, patchwrk_plots)
  }
  if (!is.null(model$data_val)) {
    data <- model$data_val
    data <- data[data[[subject]] %in% subject_list, ]
    if (nrow(data) != 0) {
      patchwrk <- plot_predictions(
        model,
        data,
        list(
          preds_all_info = predict(model, data, all_info_hlme_prediction = TRUE),
          preds_past_info = predict(model, data, all_info_hlme_prediction = FALSE)
        ),
        ncols = 2
      )
      patchwrk_plots <- as.list(patchwrk)
      patchwrk_plots[[1]] <- patchwrk_plots[[1]] + ggtitle("Validation Set")
      if (length(list_plots) %% 2 == 1) {
        list_plots <- c(list_plots, plot_spacer())
      }
      list_plots <- c(list_plots, patchwrk_plots)
    }
  }
  return(wrap_plots(list_plots, ncol = ncols))
}


# training loop ----
.test_training_loop <- function(
  fixed_model,
  fixed_spec,
  random_spec,
  data_train,
  data_val,
  subject,
  time,
  mixedml_controls,
  hlme_controls,
  call
) {
  # many extra-tests are done in the sub-functions called here
  .check_sorted_data(data_train, subject, time)
  stopifnot(all(.get_x_labels(fixed_spec) %in% colnames(data_train)))
  stopifnot(.get_y_label(fixed_spec) %in% colnames(data_train))
  #
  stopifnot(is.null(.get_y_label(random_spec)))
  stopifnot(all(.get_x_labels(random_spec) %in% colnames(data_train)))
  #
  if (!is.null(data_val)) {
    .check_sorted_data(data_val, subject, time)
    stopifnot(setequal(colnames(data_val), colnames(data_train)))
    stopifnot(length(intersect(rownames(data_val), rownames(data_train))) == 0)
  }
  .check_controls_with_function(mixedml_controls, mixedml_ctrls)
  # we have to call it here since we change the convergence criterions in the training loop:
  .check_controls_with_function(hlme_controls, hlme_ctrls)
  stopifnot(is.call(call))
  return()
}


mixedml_training_loop <- function(
  fixed_model,
  fixed_spec,
  random_spec,
  data,
  data_val,
  subject,
  time,
  mixedml_controls,
  hlme_controls,
  call
) {
  data_train <- data
  .test_training_loop(
    fixed_model,
    fixed_spec,
    random_spec,
    data_train,
    data_val,
    subject,
    time,
    mixedml_controls,
    hlme_controls,
    call
  )
  # please see .get_model_snapshot to understand the choice of the variables names
  # since it uses parent.frame() to generate the snapshot
  target_name <- .get_y_label(fixed_spec)
  # hlme model initialization ----
  # we change the convergence criterions for faster iterations
  # the original criterions will be used to adjust the final model
  hlme_controls_final <- hlme_controls
  hlme_controls_iter <- hlme_controls
  hlme_controls_iter$convB <- mixedml_controls$convB
  hlme_controls_iter$convL <- mixedml_controls$convL
  hlme_controls_iter$convG <- mixedml_controls$convG
  random_model <- .initiate_random_hlme(target_name, random_spec, data_train, subject, time, hlme_controls_iter)

  #
  #mse_eps <- mixedml_controls$convergence_controls$mse_eps
  #loglik_eps <- mixedml_controls$convergence_controls$loglik_eps
  #
  eastop_gain <- mixedml_controls$earlystopping_controls$min_mse_gain
  eastop_patience <- mixedml_controls$earlystopping_controls$patience
  eastop_mse <- Inf
  eastop_loglik <- -Inf
  loglik_gain <- 1e-2
  #
  abort_mse <- mixedml_controls$aborting_controls$mse_value
  abort_iter <- mixedml_controls$aborting_controls$check_iter
  #
  data_fixed <- data_train
  data_rand <- data_train
  pred_rand <- rep(0, nrow(data_train))
  istep <- 1
  mse_train_list <- c()
  mse_val <- NULL
  mse_val_list <- c()
  loglik_train_list <- c()
  loglik_val <- NULL
  loglik_val_list <- c()
  mse_min <- Inf #improvment test
  loglik_max <- -Inf #me
  mse_prev <- Inf #me
  loglik_prev <- -Inf #me
  count_loglik <- 0
  # confusing name, might need to change:
  n_na_full <- .check_na_combinaison(data_train, fixed_spec, random_spec, target_name)
  backup <- tempfile(fileext = ".Rds")
  do_val <- !is.null(data_val)
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
    #browser()
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
    message(sprintf("\tloglik-train = %.4g", loglik_train))
    loglik_train_list <- c(loglik_train_list, loglik_train)
    # val residuals/mse and loglik ----
    if (do_val) {
      tmp_model <- .get_model_snapshot()
      pred_val <- predict(tmp_model, data_val, mixedml_controls$all_info_hlme_prediction)
      residuals_val <- data_val[, target_name] - pred_val
      ccases_resid <- complete.cases(residuals_val)#added
      mse_val <- mean(residuals_val[ccases_resid]**2, na.rm = TRUE)
      message(sprintf("\tMSE-val = %.4g", mse_val))
      mse_val_list <- c(mse_val_list, mse_val)
      #
      hlme_val <- stats::update(random_model, data = data_val, B = random_model$best, maxiter = 0)
      loglik_val <- hlme_val$loglik
      loglik_val_list <- c(loglik_val_list, loglik_val)
    }

    # convergence tests ----
    # if (do_val) {
    #   mse_conv <- mse_val
    # } else {
    #   mse_conv <- mse_train
    # }
    if (do_val) {
      mse_conv <- mse_val
      loglik_conv <- loglik_val
    } else {
      mse_conv <- mse_train
      loglik_conv <- loglik_train
    }

    delta_mse <- abs(mse_prev - mse_conv)
    delta_loglik <- abs(loglik_conv - loglik_prev)
    message(sprintf("\tΔMSE = %.4g", delta_mse))
    message(sprintf("\tΔlogLik = %.4g", delta_loglik))
    if (delta_mse < 1e-2 && delta_loglik < 1e-2) {
      message("Convergence reached (MSE and logLik stabilized)")
      break
    }
    mse_prev <- mse_conv
    loglik_prev <- loglik_conv

    ## improvement test ----
    if (mse_conv < mse_min && loglik_conv > loglik_max) {
      message("\t(saving best model)")
      mse_min <- mse_conv
      loglik_max <- loglik_conv
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


    ## improving / early stopping test ----
    # early stopping on MSE ----
    if (mse_conv < eastop_mse - 0.1) {
      message("\t(improvement)")
      eastop_mse <- mse_conv
      count_conv <- 0
    } else {
      count_conv <- count_conv + 1
      message(sprintf("\t(no improvement MSE #%d)", count_conv))
    }

    ## stagnation test on loglik ----
    if (loglik_conv > eastop_loglik + 0.1) {
      eastop_loglik <- loglik_conv
      count_loglik <- 0
    } else {
      count_loglik <- count_loglik + 1
      message(sprintf("\t(no improvement loglik #%d)", count_loglik))
    }

    if (count_conv >= eastop_patience && count_loglik >= eastop_patience) {
      warning("Conditions defined in early_stopping: aborting training loop!")
      break()
    }


    ## aborting test ----
    if (istep == abort_iter) {
      if (mse_conv > abort_mse) {
        warning("Conditions defined in aborting_controls: aborting training loop!")
        break()
      }
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
  fine_tune <- try(.fine_tune(best_model$random_model, best_data_rand, hlme_controls_final))
  if (inherits(fine_tune, "try-error")) {
    warning(
      "Could not fine-tune the best model with better convergence threshold: ",
      "keeping the model converged during the loop"
    )
    best_model$random_model <- best_model$random_model
  } else {
    best_model$random_model <- .fine_tune(best_model$random_model, best_data_rand, hlme_controls_final)
  }
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
