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
  stopifnot(length(.get_y_label(random_spec)) == 0)
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
  hlme_controls,
  no_random_value_as
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
  random_hlme$no_random_value_as <- no_random_value_as
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
  no_random_value_as <- random_hlme$no_random_value_as
  random_hlme <- stats::update(random_hlme, data = data, B = random_hlme$best)
  random_hlme$no_random_value_as <- no_random_value_as
  #
  preds <- rep(random_hlme$no_random_value_as, nrow(data))
  names(preds) <- row.names(data)
  rnames_pred <- row.names(random_hlme$pred)
  stopifnot(length(setdiff(rnames_pred, names(preds))) == 0)
  preds[rnames_pred] <- random_hlme$pred$pred_ss
  random_hlme$full_pred <- preds
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

.product_random_effects <- function(modmat, ui) {
  cols <- sub("\\(Intercept\\)", "intercept", colnames(modmat))
  ui_ordered <- ui[cols]
  return(modmat[,] %*% as.numeric(ui_ordered)) # nolint
}


.predict_random_hlme <- function(random_hlme, data) {
  #
  var.time <- random_hlme$var.time
  subject <- colnames(random_hlme$pred)[1]
  randspec <- as.formula(random_hlme$call$random)
  modmat <- model.matrix(as.formula(random_hlme$call$random), data)
  preds <- rep(0., nrow(data))
  names(preds) <- rownames(data)
  time_unq <- sort(unique(data[[var.time]]))
  for (i_time in time_unq[-1]) {
    actual_data <- data[data[var.time] == i_time, ]
    prev_data <- data[data[var.time] < i_time, ]
    ui <- lcmm::predictRE(random_hlme, newdata = prev_data)
    for (rname in rownames(actual_data)) {
      actual_subject_data <- actual_data[rname, ]
      actual_subject <- actual_subject_data[[subject]]
      ui_subject <- ui[ui[, subject] == actual_subject, ]
      stopifnot(nrow(ui_subject) <= 1)
      if (nrow(ui_subject) == 1) {
        actual_subject_modmat <- model.matrix(randspec, actual_subject_data)
        stopifnot(nrow(actual_subject_modmat) <= 1)
        if (nrow(actual_subject_modmat) == 1) {
          stopifnot(preds[rname] == 0.)
          reffects <- .product_random_effects(actual_subject_modmat, ui_subject)
          preds[rname] <- reffects
        }
      }
    }
  }
  return(preds)
}
