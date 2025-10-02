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
  warning(
    "The predictions made by hlme on new data do not yet take into account the correlation"
  )
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

.predict_newdata_ss <- function(
  random_hlme,
  data,
  data_re,
  no_random_value_as
) {
  # NOTE: with this method the observations with no NAs in Xs and NA in Y
  # will get a prediction, which is different from the library original behaviour
  # in model$pred$pred_ss
  full_preds <- .initiate_full_preds(data, no_random_value_as)
  # predictRE calls the training of the model with iteration 0 in order to
  # access model$pred_ss
  # so the data which raise an error for training
  # will also raise an error for predictRE
  # Erreur dans matYXord[, 4 + ng] : nombre de dimensions incorrect
  try_predict_re <- try(
    lcmm::predictRE(random_hlme, data_re),
    silent = TRUE
  )
  if (is.data.frame(try_predict_re)) {
    # we work by subject to avoid the
    # predRE should contain as many rows as latent classes error
    # (number of rows > 1)
    subject <- colnames(try_predict_re)[1]
    for (subj in try_predict_re[[subject]]) {
      # isolating data_subj makes it easier to "merge" later with full_pred
      # the results are the same (there can be micro-tiny numerical difference)
      data_subj <- data[data[[subject]] == subj, ]
      ui_subj <- try_predict_re[try_predict_re[[subject]] == subj, ]
      # we can still have the
      # "predRE should contain as many rows as latent classes" error
      # (number of rows == 0 because of NAs)
      try_predict_y <- try(
        lcmm::predictY(
          random_hlme,
          newdata = data_subj,
          predRE = ui_subj
        ),
        silent = TRUE
      )
      if (is.list(try_predict_y)) {
        full_preds[rownames(try_predict_y$times)] <- try_predict_y$pred[, 1]
      }
    }
  }

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
    data_re = data,
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
      data_re = prev_data,
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
