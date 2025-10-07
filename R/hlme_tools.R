# initialization ----

#' Prepare the hlme_controls
#'
#' Please see the [documentation](https://cecileproust-lima.github.io/lcmm/reference/hlme.html)
#' of the `hlme` function of the `lcmm` package.
#' @return hlme_controls
#' @param cor brownian motion or autoregressive process modeling the correlation
#' between the observations. "BM" or "AR" should be specified, followed by the time variable between brackets.
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
  # the use of cor in lcmm is very tricky…
  cor <- substitute(cor)
  return(as.list(environment()))
}


.check_cor_spec <- function(random_spec, var.time, cor) {
  # this should move into lcmm
  if (is.null(cor)) return()
  #
  cor_code <- as.character(cor)[1]
  if (!cor_code %in% c("AR", "BM")) {
    stop(sprintf('Please use one of %s to define \"cor\"', c("AR", "BM")))
  }
  cor_time <- as.character(cor)[2]
  #
  if (!(cor_time %in% .get_x_labels(random_spec, allow_interactions = TRUE))) {
    stop("the time value defined in \"cor\", should be used in \"random_spec\"")
  }
  if (!(cor_time == var.time)) {
    stop(
      "the time value defined in \"cor\", should equal to the one defined in \"time\""
    )
  }
  return()
}

.test_initiate_random_hlme <- function(random_spec, hlme_controls, var.time) {
  .check_controls_with_function(hlme_controls, hlme_ctrls)
  .check_controls_with_function(hlme_controls, hlme_ctrls)
  .check_cor_spec(random_spec, var.time, hlme_controls$cor)
  return()
}


#' Initiate the HLME model
#'
#' @import lcmm
#'
#' @param random_spec random_spec
#' @param data data
#' @param subject subject
#' @param var.time var.time
#' @param hlme_controls hlme_controls
#' @return HLME model
.initiate_random_hlme <- function(
  target_name,
  random_spec,
  data,
  subject,
  var.time,
  hlme_controls
) {
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
  random_hlme <- do.call("hlme", hlme_controls)
  #
  random_hlme$call$maxiter <- maxiter_backup
  # the use of B in hlme is tricky
  # (no default value then 'try(as.numeric(B), silent = TRUE)')
  if (!is.null(b_backup)) {
    idx_varcov <- grepl("^varcov ", names(random_hlme$best))
    n_rand_var <- sum(idx_varcov)
    if (length(b_backup) != n_rand_var) {
      stop(sprintf(
        "B should only contains %d random-effects \"varcov\" values.",
        n_rand_var
      ))
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
  # - forcing an explicit "data" value to avoid since "data" is stored in the hlme call
  #   but the value of "data" might not be the same in the context where you call update
  #   (Yes I triggered this problem. Of course.)
  # - cleaning the convX values in the updated call (using substitute)
  #   (instead of having hlme_controls_final$convX)
  sub_list <- hlme_controls_final[c("convB", "convL", "convG")]
  sub_list$B <- random_hlme$best
  call_hlme <- substitute(
    stats::update(
      random_hlme,
      data = data,
      B = B,
      convB = convB,
      convL = convL,
      convG = convB
    ),
    sub_list
  )
  random_hlme <- eval(call_hlme)
  return(random_hlme)
}

# convergence check ----
.check_convergence_hlme <- function(random_hlme) {
  stopifnot(is.integer(random_hlme$conv))
  NOT_CONVERGED <- c(2, 4)
  if (random_hlme$conv %in% NOT_CONVERGED) {
    sum_conv <- paste(sprintf("%.3g", random_hlme$gconv), collapse = "/")
    warning(sprintf(
      "The hlme model did not converge (code %s).
       Here are the criterions (stability/likelihood/RDM): %s",
      random_hlme$conv,
      sum_conv
    ))
  }
  return()
}

# prediction ----

## utils ----
.initiate_full_preds <- function(data, no_random_value_as) {
  full_preds <- rep(no_random_value_as, nrow(data))
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
    return(
      lcmm::predictY(
        model,
        newdata,
        predRE = pred_re
      )
    )
  } else {
    return(
      lcmm::predictY(
        model,
        newdata,
        predRE = pred_re,
        predCor = pred_cor
      )
    )
  }
}

.predict_newdata_ss <- function(
  random_hlme,
  data,
  data_info,
  no_random_value_as
) {
  # nolint start
  DATA <- data
  DATA_INFO <- data_info
  PRED_RE <- lcmm::predictRE(random_hlme, DATA_INFO)
  FULL_PREDS <- .initiate_full_preds(data, no_random_value_as)
  # nolint end

  # NOTE: with this method the observations with no NAs in Xs and NA in Y
  # will get a prediction, which is different from the library original behaviour
  # in model$pred$pred_ss
  full_preds <- .initiate_full_preds(data, no_random_value_as)
  # we work by subject to avoid the predictY error
  # predRE should contain as many rows as latent classes error
  # (number of rows > 1)
  subject <- random_hlme$call$subject
  time <- random_hlme$var.time
  x_labels <- random_hlme$Xnames2[random_hlme$Xnames2 != "intercept"]
  y_label <- .get_y_label(random_hlme$call$fixed)
  # we need all the Xs to compute the predictions
  data <- data[complete.cases(data[x_labels]), ]
  # we need all the Xs and the Y to compute de random effect and correlation
  data_info <- data_info[complete.cases(data_info[c(x_labels, y_label)]), ]
  # common subject
  comsubj <- intersect(data[[subject]], data_info[[subject]])
  for (subj in comsubj) {
    # we work by isolating subject, this is how the functions have been designed
    # (trust me I know the dev)
    data_subj <- data[data[[subject]] == subj, ]
    data_info_subj <- data_info[data_info[[subject]] == subj, ]
    times_subj <- unique(data_subj[[time]])
    pred_re <- lcmm::predictRE(random_hlme, data_info_subj)
    pred_cor <- .predict_cor(random_hlme, data_info_subj, times_subj)
    pred_y <- .predict_y(random_hlme, data_subj, pred_re, pred_cor)
    full_preds[rownames(pred_y$times)] <- pred_y$pred[, 1]
    # nolint start
    # DATA_SUBJ <- DATA[DATA[[subject]] == subj, ]
    # PRED_RE_SUBJ <- PRED_RE[PRED_RE[[subject]] == subj, ]
    # PRED_Y <- .predict_y(random_hlme, DATA_SUBJ, PRED_RE_SUBJ, pred_cor)
    # if (!identical(pred_y, PRED_Y)) {
    #   browser()
    # }
    # nolint end
  }
  # nolint start
  for (subj in PRED_RE[[subject]]) {
    # we work by isolating subject, this is how the functions have been designed
    # (trust me I know the dev)
    DATA_SUBJ <- DATA[DATA[[subject]] == subj, ]
    DATA_INFO_SUBJ <- DATA_INFO[DATA_INFO[[subject]] == subj, ]
    PRED_RE_SUBJ <- PRED_RE[PRED_RE[[subject]] == subj, ]
    TIME_SUBJ_CC <- DATA_SUBJ[complete.cases(DATA_SUBJ[x_labels]), ][[time]]

    pred_cor <- .predict_cor(random_hlme, DATA_INFO_SUBJ, TIME_SUBJ_CC)
    PRED_Y <- try(
      .predict_y(random_hlme, DATA_SUBJ, PRED_RE_SUBJ, pred_cor),
      silent = TRUE
    )
    if (!is.list(PRED_Y)) {
      # browser()
      # happens when DATA_SUBJ has NAs or is empty
    } else {
      FULL_PREDS[rownames(PRED_Y$times)] <- PRED_Y$pred[, 1]
    }
  }
  if (!identical(FULL_PREDS, full_preds)) {
    # browser()
  } else {
    message("The 2 methods for predictY give the same results <3")
  }
  # nolint end
  return(full_preds)
}


## prediction with all information ----

.predict_with_all_info <- function(
  random_hlme,
  data,
  no_random_value_as
) {
  full_preds <- .predict_newdata_ss(
    random_hlme,
    data = data,
    data_info = data,
    no_random_value_as
  )
  return(full_preds)
}


## prediction with past information ----
.predict_with_past_info <- function(random_hlme, data, no_random_value_as) {
  full_preds <- .initiate_full_preds(data, no_random_value_as)
  var.time <- random_hlme$var.time
  time_unq <- sort(unique(data[[var.time]]))
  for (i_time in time_unq[-1]) {
    actual_data <- data[data[var.time] == i_time, ]
    prev_data <- data[data[var.time] < i_time, ]
    full_preds[rownames(actual_data)] <- .predict_newdata_ss(
      random_hlme,
      data = actual_data,
      data_info = prev_data,
      no_random_value_as
    )
  }
  return(full_preds)
}


## global method ----
.predict_random_hlme <- function(
  random_hlme,
  data,
  no_random_value_as,
  use_all_info
) {
  if (use_all_info) {
    return(.predict_with_all_info(
      random_hlme,
      data,
      no_random_value_as
    ))
  } else {
    return(.predict_with_past_info(random_hlme, data, no_random_value_as))
  }
}
