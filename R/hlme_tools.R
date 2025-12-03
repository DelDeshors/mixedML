# initialization ----

#' Prepare the hlme_controls
#'
#' Please see the [documentation](https://cecileproust-lima.github.io/lcmm/reference/hlme.html)
#' of the `hlme` function of the `lcmm` package.
#' @return hlme_controls
#' @param cor brownian motion ("BM") or autoregressive process ("AR") modeling the correlation
#' between the observations. NOTE that for this tool, the only accepted form is a string (ex: cor="BM(time)"),
#' which is different from the hlme call (ex: cor=BM(time)). NULL is still accepted.
#' @param idiag logical for the structure of the variance-covariance matrix of the random-effects.
#' If FALSE, a non structured matrix of variance-covariance is considered (by default).
#' If TRUE a diagonal matrix of variance-covariance is considered.
#' @param maxiter maximum number of iterations for the Marquardt iterative algorithm.
#' @param nproc the number cores for parallel computation. Default to 1 (sequential mode).
#' @param B_rand random effects "varcov" values to initiate the random effects model
#' @param convB optional threshold for the convergence criterion based on the
#' parameter stability. Used for the final MixedML model. By default, convB=0.0001.
#' @param convL optional threshold for the convergence criterion based on the
#' log-likelihood stability. Used for the final MixedML model. By default, convL=0.0001.
#' @param convG optional threshold for the convergence criterion based on the
#' derivatives. Used for the final MixedML model. By default, convG=0.0001.
#' @param verbose logical indicating if information about computation should be reported. Default to TRUE.
#' @export
hlme_ctrls <- function(
  cor = NULL,
  idiag = FALSE,
  maxiter = 500,
  nproc = 1,
  B_rand = NULL, # nolint
  convB = 0.0001, # nolint
  convL = 0.0001, # nolint
  convG = 0.0001, # nolint
  verbose = FALSE
) {
  cor <- .homogenize_cor(cor)
  return(as.list(environment()))
}


.homogenize_cor <- function(cor) {
  errmsg <- "The \"cor\" parameter does not have an authorized format"
  if (inherits(try(cor, silent = TRUE), "try-error")) {
    # the "cor=AR(time)" notation
    # must be tried first since to avoid crashing the other commands.
    stop(errmsg)
  }
  if (is.character(cor)) {
    return(str2lang(cor))
  }
  if (is.null(cor)) {
    return(cor)
  }
  stop(errmsg)
  return()
}

.check_cor_call <- function(random_spec, var.time, cor) {
  if (is.null(cor)) {
    return()
  }
  errmsg <- paste0(
    "\"cor\" must be specified using \"AR(time)\" or \"BM(time)\", ",
    "with \"time\" begin used in \"random_spec\" and equal to \"var.time\".\n",
    "But it is equal to \"",
    cor,
    "\".\n",
    "If you want to use a variable to define it, you should consider a string or quote notation."
  )
  if (!is.call(cor)) {
    stop(errmsg)
  }
  cor_char <- as.character(cor)
  if (length(cor_char) != 2) {
    stop(errmsg)
  }
  cor_code <- cor_char[[1]]
  if (!(cor_code %in% c("AR", "BM"))) {
    stop(errmsg)
  }
  cor_time <- cor_char[[2]]
  if (!(cor_time %in% .get_x_labels(random_spec, allow_interactions = TRUE))) {
    stop(errmsg)
  }
  if (cor_time != var.time) {
    stop(errmsg)
  }
  return()
}


.test_initiate_random_hlme <- function(random_spec, hlme_controls, var.time) {
  .check_controls_with_function(hlme_controls, hlme_ctrls)
  .check_cor_call(random_spec, var.time, hlme_controls$cor)
  return()
}


.initiate_random_hlme <- function(target_name, random_spec, data, subject, var.time, hlme_controls) {
  .test_initiate_random_hlme(random_spec, hlme_controls, var.time)
  # preparing the hlme formula inputs
  hlme_controls$fixed <- stats::reformulate("1", response = target_name)
  hlme_controls$random <- random_spec
  hlme_controls$data <- data
  hlme_controls$subject <- subject
  hlme_controls$var.time <- var.time
  hlme_controls$na.action <- 1
  # preventing the fixed intercept to be estimated
  hlme_controls$posfix <- c(1)
  # initialization with maxiter = 0
  maxiter_backup <- hlme_controls$maxiter
  hlme_controls$maxiter <- 0
  # … and no B
  b_backup <- hlme_controls$B_rand
  hlme_controls$B_rand <- NULL
  # initialization call
  # "hlme" with "" to keep a clean summary
  random_hlme <- do.call("hlme", hlme_controls)
  random_hlme$call$data <- NULL
  #
  random_hlme$call$maxiter <- maxiter_backup
  # the use of B in hlme is tricky
  # (no default value then 'try(as.numeric(B), silent = TRUE)')
  if (!is.null(b_backup)) {
    idx_varcov <- grepl("^varcov ", names(random_hlme$best))
    n_rand_var <- sum(idx_varcov)
    if (length(b_backup) != n_rand_var) {
      stop(sprintf("B should only contains %d random-effects \"varcov\" values.", n_rand_var))
    }
    random_hlme$best[idx_varcov] <- b_backup
  }
  # forcing the fixed intercept to 0  ( "$" does not work: conversion to list)
  random_hlme$best[["intercept"]] <- 0.
  return(random_hlme)
}


# training ----
.fit_random_hlme <- function(random_hlme, data) {
  random_hlme <- stats::update(random_hlme, data = data, B = random_hlme$best)
  return(random_hlme)
}

.fine_tune <- function(random_hlme, data, hlme_controls_final) {
  # 2 objectives:
  # - forcing an explicit "data" value since the call string "data" is stored in the hlme call
  #   but the value of "data" might not be the same in the context where you call update
  #   (Yes I triggered this problem. Of course.)
  # - cleaning the convX values in the updated call (using substitute)
  #   (instead of having hlme_controls_final$convX)
  sub_list <- hlme_controls_final[c("convB", "convL", "convG")]
  sub_list$B <- random_hlme$best
  call_hlme <- substitute(
    stats::update(random_hlme, data = data, B = B, convB = convB, convL = convL, convG = convB),
    sub_list
  )
  random_hlme <- eval(call_hlme)
  return(random_hlme)
}

# convergence check ----
.check_convergence_hlme <- function(hlme_model) {
  stopifnot(is.integer(hlme_model$conv))
  NOT_CONVERGED <- c(2, 4)
  if (hlme_model$conv %in% NOT_CONVERGED) {
    sum_conv <- paste(sprintf("%.3g", hlme_model$gconv), collapse = "/")
    warning(sprintf(
      "The hlme model did not converge (code %s).
       Here are the criterions (stability/likelihood/RDM): %s",
      hlme_model$conv,
      sum_conv
    ))
  }
  return()
}

# prediction ----

## utils ----
.initiate_full_preds <- function(data) {
  full_preds <- rep(NA, nrow(data))
  names(full_preds) <- row.names(data)
  rnames_pred <- row.names(data)
  return(full_preds)
}

.predict_cor <- function(model, data, times) {
  if (is.null(model$call$cor)) {
    return(NULL)
  }
  return(lcmm::predictCor(model, data, times))
}

.predict_y <- function(model, newdata, pred_re, pred_cor) {
  if (is.null(pred_cor)) {
    return(lcmm::predictY(model, newdata, predRE = pred_re))
  } else {
    return(lcmm::predictY(model, newdata, predRE = pred_re, predCor = pred_cor))
  }
}

.predict_newdata_ss <- function(
  hlme_model,
  data,
  data_info,
  initiate_full_preds_fn = .initiate_full_preds,
  get_y_label_fn = .get_y_label,
  predict_cor_fn = .predict_cor,
  predict_y_fn = .predict_y
) {
  # NOTE: with this method the observations with no NAs in Xs and NA in Y
  # will get a prediction, which is different from the library original behaviour
  # in model$pred$pred_ss

  # nolint start ----
  # DATA <- data
  # DATA_INFO <- data_info
  # PRED_RE <- lcmm::predictRE(hlme_model, DATA_INFO)
  # FULL_PREDS <- initiate_full_preds_fn(data)
  # nolint end ----
  full_preds <- initiate_full_preds_fn(data)
  subject <- hlme_model$call$subject
  time <- hlme_model$var.time
  x_labels <- hlme_model$Xnames2[hlme_model$Xnames2 != "intercept"]
  y_label <- get_y_label_fn(hlme_model$call$fixed)
  # we need all the Xs to compute the predictions
  data <- data[complete.cases(data[x_labels]), ]
  # we need all the Xs and the Y to compute de random effect and correlation
  data_info <- data_info[complete.cases(data_info[c(x_labels, y_label)]), ]
  # common subjects
  comsubj <- intersect(data[[subject]], data_info[[subject]])
  for (subj in comsubj) {
    # we work by isolating subject, this is how the functions have been designed
    # (trust me I know the dev)
    data_subj <- data[data[[subject]] == subj, ]
    data_info_subj <- data_info[data_info[[subject]] == subj, ]
    times_subj <- unique(data_subj[[time]])
    pred_re <- lcmm::predictRE(hlme_model, data_info_subj)
    pred_cor <- predict_cor_fn(hlme_model, data_info_subj, times_subj)
    pred_y <- predict_y_fn(hlme_model, data_subj, pred_re, pred_cor)
    full_preds[rownames(pred_y$times)] <- pred_y$pred[, 1]
    # nolint start ----
    # DATA_SUBJ <- DATA[DATA[[subject]] == subj, ]
    # PRED_RE_SUBJ <- PRED_RE[PRED_RE[[subject]] == subj, ]
    # PRED_Y <- .predict_y(hlme_model, DATA_SUBJ, PRED_RE_SUBJ, pred_cor)
    # if (
    #   max(abs(pred_y$pred - PRED_Y$pred), na.rm = TRUE) > 1e-8 ||
    #     max(abs(pred_y$times - PRED_Y$times), na.rm = TRUE) > 1e-8
    # ) {
    #   # browser()
    #   stop()
    # }
    # nolint end ----
  }
  # nolint start ----
  # for (subj in PRED_RE[[subject]]) {
  #   # we work by isolating subject, this is how the functions have been designed
  #   # (trust me I know the dev)
  #   DATA_SUBJ <- DATA[DATA[[subject]] == subj, ]
  #   DATA_INFO_SUBJ <- DATA_INFO[DATA_INFO[[subject]] == subj, ]
  #   PRED_RE_SUBJ <- PRED_RE[PRED_RE[[subject]] == subj, ]
  #   TIME_SUBJ_CC <- DATA_SUBJ[complete.cases(DATA_SUBJ[x_labels]), ][[time]]
  #
  #   pred_cor <- .predict_cor(hlme_model, DATA_INFO_SUBJ, TIME_SUBJ_CC)
  #   PRED_Y <- try(
  #     .predict_y(hlme_model, DATA_SUBJ, PRED_RE_SUBJ, pred_cor),
  #     silent = TRUE
  #   )
  #   if (!is.list(PRED_Y)) {
  #     # browser()
  #     warning("check that DATA_SUBJ has NAs or is empty")
  #   } else {
  #     FULL_PREDS[rownames(PRED_Y$times)] <- PRED_Y$pred[, 1]
  #   }
  # }
  # if (max(abs(FULL_PREDS - full_preds), na.rm = TRUE) > 1e-8) {
  #   # browser()
  #   stop()
  # } else {
  #   warning("check 1 is OK !")
  # }
  # ####
  # inter_names <- intersect(rownames(hlme_model$pred), rownames(DATA))
  # if (identical(DATA, DATA_INFO) && length(inter_names) > 0) {
  #   # using all info
  #   # and DATA is train data so is stored in hlme_model$pred
  #   pred1 <- hlme_model$pred[inter_names, "pred_ss"]
  #   pred2 <- full_preds[inter_names]
  #   if (max(abs(pred1 - pred2), na.rm = TRUE) > 1e-8) {
  #     stop()
  #   } else {
  #     warning("check 2 is OK !")
  #   }
  # }
  # nolint end ----
  return(full_preds)
}


## prediction with all information ----
.predict_with_all_info <- function(hlme_model, data) {
  full_preds <- .predict_newdata_ss(hlme_model, data = data, data_info = data)
  return(full_preds)
}


## prediction with past information ----

#' This function computes the predictions of a HLME model using only the past information to compute the random effects
#' and correlation components. The actual X values are of course still used to compute the estimates.
#' @param hlme_model HLME model from the LCMM package
#' @param data Data to be used for the prediction. It must have the same format as the one used to fit the hlme model.
#' @param nproc Number of processes to use. Default: 1
#' @export
#' @importFrom doFuture %dofuture%
#' @importFrom foreach foreach
.predict_with_past_info <- function(hlme_model, data, nproc = 1) {
  full_preds <- .initiate_full_preds(data)
  var.time <- hlme_model$var.time
  time_unq <- sort(unique(data[[var.time]]))
  # trick so the function are available (resolved) when running on several processes
  predict_newdata_ss_fn <- .predict_newdata_ss
  initiate_full_preds_fn <- .initiate_full_preds
  get_y_label_fn <- .get_y_label
  predict_cor_fn <- .predict_cor
  predict_y_fn <- .predict_y
  #
  .set_future_plan(nproc)
  i_time <- NULL # only for `devtool::check`
  times_preds <- foreach(i_time = sample(time_unq[-1])) %dofuture%
    {
      actual_data <- data[data[var.time] == i_time, ]
      prev_data <- data[data[var.time] < i_time, ]
      return(list(
        rownames = rownames(actual_data),
        pred = predict_newdata_ss_fn(
          hlme_model,
          data = actual_data,
          data_info = prev_data,
          initiate_full_preds_fn = initiate_full_preds_fn,
          get_y_label_fn = get_y_label_fn,
          predict_cor_fn = predict_cor_fn,
          predict_y_fn = predict_y_fn
        )
      ))
    }

  for (time_pred in times_preds) {
    full_preds[time_pred$rownames] <- time_pred$pred
  }

  return(full_preds)
}


## global method ----
.predict_random_hlme <- function(hlme_model, data, use_all_info, nproc_hlme) {
  if (use_all_info) {
    return(.predict_with_all_info(hlme_model, data))
  } else {
    return(.predict_with_past_info(hlme_model, data, nproc_hlme))
  }
}
