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
#' @export
hlme_ctrls <- function(
  cor = NULL,
  idiag = FALSE,
  maxiter = 500,
  nproc = 1
) {
  stopifnot(
    is.null(cor) | (rlang::is_bare_formula(cor) & (cor[0:2] %in% c("AR", "BM")))
  )
  return(as.list(environment()))
}


#' Function to plot something
#'
#' @import lcmm
#'
#' @param random_spec random_spec
#' @param data data
#' @param subject subject
#' @param var.time var.time
#' @param hlme_controls hlme_controls
#' @return description
.initiate_random_hlme <- function(
  random_spec,
  data,
  subject,
  var.time,
  hlme_controls
) {
  .check_controls_with_function(hlme_controls, hlme_ctrls)

  # preparing the hlme formula inputs
  left <- .get_left_side_string(random_spec)
  right <- .get_right_side_string(random_spec)
  hlme_controls$fixed <- stats::as.formula(paste0(left, "~1"))
  hlme_controls$random <- stats::as.formula(paste0("~", right))
  hlme_controls$data <- data
  hlme_controls$subject <- subject
  hlme_controls$var.time <- var.time
  hlme_controls$posfix <- c(1)
  # initialization with maxiter = 0
  maxiter_backup <- hlme_controls$maxiter
  hlme_controls$maxiter <- 1
  random_hlme <- do.call("hlme", hlme_controls)
  random_hlme$best[["intercept"]] <- 0. # "$" does not work (conversion to list)
  random_hlme$call$maxiter <- maxiter_backup
  return(random_hlme)
}


# training ----
.check_fit_random_hlme <- function(random_hlme, data, pred_fixed) {
  stopifnot(class(random_hlme) == "hlme")
  stopifnot(random_hlme$best["intercept"] == 0.)
  stopifnot(is.data.frame(data))
  stopifnot(is.numeric(pred_fixed))
  stopifnot(is.vector(pred_fixed))
  return()
}

.fit_random_hlme <- function(random_hlme, data, pred_fixed) {
  .check_fit_random_hlme(random_hlme, data, pred_fixed)
  # !!! offsetting is not implemented in LCMM
  # BUT for linear models, fitting "f(X)+offset" on Y is equivalent
  # to fitting f(X) on "Y-offset"
  # so that is the method used so far
  target_name <- .get_left_side_string(random_hlme$call$fixed)
  data[target_name] <- data[target_name] - pred_fixed
  random_hlme <- stats::update(random_hlme, data = data, B = random_hlme$best)
  stopifnot(random_hlme$best["intercept"] == 0.)
  return(list(
    "model" = random_hlme,
    "pred_rand" = random_hlme$pred[["pred_ss"]]
  ))
}

# prediction ----

.predict_random_hlme <- function(random_hlme, data) {
  PRED_RAND <- "__PRED_RAND" # temporary column to compute the predictions
  stopifnot(class(random_hlme) == "hlme")
  var.time <- random_hlme$var.time
  subject <- colnames(random_hlme$pred)[1]

  # trick to simplify the RE 'rowSums' calculation
  x_labels <- random_hlme$Xnames
  intercept <- x_labels[1]
  data[intercept] <- 1

  # initialization with the marginal effects
  data[PRED_RAND] <- as.vector(
    lcmm::predictY(random_hlme, newdata = data, marg = TRUE)$pred
  )
  # … but they should be 0
  if (max(abs(data[PRED_RAND])) > 0) {
    stop(
      "The marginal effects are different from 0: ",
      "this is not a 100% random effects model."
    )
  }
  time_unq <- sort(unique(data[[var.time]]))
  for (i_time in time_unq[-1]) {
    prev_data <- data[data[var.time] < i_time, ]
    tryCatch(
      # we let hlme find out if he can predict or not
      {
        ui <- lcmm::predictRE(random_hlme, newdata = prev_data)
        actual_data <- data[data[var.time] == i_time, ]
        for (i_row in rownames(actual_data)) {
          actual_subject <- actual_data[i_row, subject]
          ui_subject <- ui[ui[, subject] == actual_subject, ]
          if (nrow(ui_subject) == 1) {
            reffects <- rowSums(
              actual_data[i_row, x_labels] * ui_subject[, x_labels]
            )
            data[i_row, PRED_RAND] <- data[i_row, PRED_RAND] + reffects
          } else if (nrow(ui_subject) > 1) {
            stop("Problem with method!")
          }
        }
      },
      error = function(e) {
      }
    )
  }
  return(data[[PRED_RAND]])
}
