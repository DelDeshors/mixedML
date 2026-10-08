# initialization  ----

#' Prepare the esn_controls
#' esn_controls contains the hyperparameters for the reservoir model.
#'
#' Please see the documentation of ReservoirPy for:
#' - [Reservoir](https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.Reservoir.html)
#' - [Ridge Regression](https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.Ridge.html)
#' @param units Number of reservoir units.
#' @param lr Neurons leak rate. Must be in \eqn{[0,1]}.
#' @param sr Spectral radius of recurrent weight matrix.
#' @param ridge Regularization parameter \eqn{\lambda}.
#' @param input_scaling Input gain. (So far only a float can be used).
#' @param feedback Is readout connected to reservoir through feedback?
#' @param input_to_readout  If True, the input is directly fed to the readout.
#' @param input_connectivity Connectivity (or density) of Win
#' @param rc_connectivity Connectivity (or density) of Wfb
#'
#' @return esn_controls
#' @export
esn_ctrls <- function(
  units = 100,
  lr = 1.0,
  sr = 0.1,
  ridge = 0.0,
  input_scaling = 1.0,
  feedback = FALSE,
  input_to_readout = FALSE,
  input_connectivity = 0.2,
  rc_connectivity =0.2
) {
  stopifnot(is.single.integer(units))
  units <- as.integer(units)
  stopifnot(is.single.numeric(lr))
  stopifnot(is.single.numeric(sr))
  stopifnot(is.single.numeric(ridge))
  stopifnot(is.numeric(input_scaling) && length(input_scaling) == 1 && input_scaling > 0.)
  stopifnot(is.logical(feedback))
  stopifnot(is.logical(input_to_readout))
  stopifnot(is.single.numeric(input_connectivity))
  stopifnot(is.single.numeric(rc_connectivity))
  return(as.list(environment()))
}

#' Prepare the ensemble_controls
#'
#'
#' @param seed_list List of seeds used to generate the Reservoir. Default:  c(1, 2, 3)
#' @param aggregator Function used to aggregate the predictions of each ESN.
#' "mean" or "median". Default: "median"
#' @param scaler scikit-learn scaler to use on the X data.
#' "standard", "robust", "min-max", "max-abs". Default: "standard"
#' @param n_procs Number of processor to use. 1 means no multiprocessing. Default: 1.
#' @param return_individual return predictions for each reservoir (seed). Usefull for random research. Default: FALSE
#' @return ensemble_controls
#' @export
ensemble_ctrls <- function(seed_list = c(1, 2, 3), aggregator = "median", scaler = "standard", n_procs = 1, return_individual = FALSE) {
  stopifnot(is.integer(seed_list))
  seed_list <- as.integer(seed_list) # real integer for reticulate
  stopifnot(is.character(aggregator))
  stopifnot(is.character(scaler))
  stopifnot(is.single.integer(n_procs))
  n_procs <- as.integer(n_procs) # real integer for reticulate
  stopifnot(is.logical(return_individual))
  return(as.list(environment()))
}

# nolint start
#' Prepare the fit_controls
#'
#' Please see the
#' [documentation](https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.ESN.html#reservoirpy.nodes.ESN.fit)
#' of ReservoirPy
#' @param warmup Number of timesteps to consider as warmup and discard at the beginning. Default: 0
#' of each timeseries before training.
#'
#' @return fit_controls
#' @export
# nolint end
fit_ctrls <- function(warmup = 0) {
  stopifnot(is.single.integer(warmup) & (warmup >= 0))
  warmup <- as.integer(warmup)
  return(as.list(environment()))
}


.test_initiate_esn <- function(esn_controls, ensemble_controls, fit_controls) {
  .check_controls_with_function(esn_controls, esn_ctrls)
  .check_controls_with_function(ensemble_controls, ensemble_ctrls)
  .check_controls_with_function(fit_controls, fit_ctrls)
  return()
}

## initialization ----

.initiate_esn <- function(esn_controls, ensemble_controls, fit_controls) {
  .test_initiate_esn(esn_controls, ensemble_controls, fit_controls)
  retipy <- reticulate::import("reservoir_ensemble")
  # enforcing "stateful=TRUE" and "reset=TRUE"
  enforcement <- list(stateful = TRUE, reset = TRUE)
  fit_controls <- c(fit_controls)
  predict_controls <- enforcement

  controls <- c(ensemble_controls,
    list(esn_controls = esn_controls, fit_controls = fit_controls, predict_controls = predict_controls))

  model <- do.call(retipy$JoblibReservoirEnsemble, controls)
  # class for the S3 dispatching
  class(model) <- c("reservoir", class(model))
  return(model)
}

# summary

#' @method summary_fixed_model reservoir
#' @noRd
#' @export
summary_fixed_model.reservoir <- function(object, ...) {
  model <- object
  cat("\n\n === Reservoir Computing model (ReservoirPy) ===\n")
  cat("ESN ensemble data:\n")
  Nbres = length(seq_along(model$model_list))
  if (Nbres > 1){
    cat("  Number of reservoirs in the ensemble:", Nbres, "\n")
    cat("  Aggregator:", model$aggregator, "\n")
    cat("  Data scaler:", model$scaler, "\n")
    esn <- model$model_list[[1]]
    cat("ESN data:\n")
    cat("  Feedback connection:", esn$feedback, "\n")
    cat("  Input-to-Readout:", esn$input_to_readout, "\n")
  }
  else{
    cat("  Number of reservoirs in the ensemble:", Nbres, "\n")
    cat("  Aggregator:", model$aggregator, "\n")
    cat("  Data scaler:", model$scaler, "\n")
    esn <- model$model_list
    cat("ESN data:\n")
    cat("  Feedback connection:", esn$feedback, "\n")
    cat("  Input-to-Readout:", esn$input_to_readout, "\n")
  }

  rsrvr <- esn$reservoir
  cat("Reservoirs data:\n")
  cat("  Number of reservoir units:", rsrvr$units, "\n")
  cat("  Leak rate:", rsrvr$lr, "\n")
  cat("  Spectral radius:", rsrvr$sr, "\n")
  cat("  Input Scaling:", rsrvr$input_scaling, "\n")

  rout <- esn$readout
  cat("Readout data:\n")
  cat("  Ridge regression parameter:", rout$ridge, "\n")
  return(invisible())
}

#' @method print reservoir
#' @noRd
#' @export
print.reservoir <- function(x, ...) {
  summary_fixed_model.reservoir(x)
  return(invisible())
}

# fitting/training ----

#' @method fit_fixed_model reservoir
#' @noRd
#' @export
fit_fixed_model.reservoir <- function(model, data, fixed_spec, subject) {
  # !!! offsetting is not implemented in LCMM
  # BUT for linear models, fitting "f(X)+offset" on Y is equivalent to
  # fitting f(X) on "Y-offset"
  # so that is the method used so far
  x_labels <- .get_x_labels(fixed_spec)
  y_label <- .get_y_label(fixed_spec)
  ccases <- complete.cases(data[x_labels])
  data <- data[ccases, ]
  #
  controls <- list(X = as.matrix(data[x_labels]), y = as.matrix(data[y_label]), subject_col = as.array(data[[subject]]))
  do.call(model$fit, controls)
  return(model)
}


# prediction ----

#' @method predict_fixed_model reservoir
#' @noRd
#' @export
predict_fixed_model.reservoir <- function(model, data, fixed_spec, subject, return_individual) {
  x_labels <- .get_x_labels(fixed_spec)
  ccases <- complete.cases(data[x_labels])
  rname <- rownames(data)
  data <- data[ccases, ]
  controls <- list(X = as.matrix(data[x_labels]), subject_col = as.array(data[[subject]]))
  if (return_individual) {
    controls$return_individual <- TRUE
  }

  pred_fixed <- do.call(model$predict, controls)

  # ---------------------------------------------------------
  # Cas normal : une seule prédiction agrégée
  # ---------------------------------------------------------
  if (!return_individual) {
    stopifnot(ncol(pred_fixed) == 1)
    stopifnot(all(!is.na(pred_fixed[, 1])))
    pred_final <- rep(NA, length(ccases))
    pred_final[ccases] <- pred_fixed[, 1]
    names(pred_final) <- rname
    return(pred_final)
  }

  # ---------------------------------------------------------
  # Cas individuel : une prédiction par seed
  # ---------------------------------------------------------
  if (!is.list(pred_fixed)) {
    pred_fixed <- list(pred_fixed)
  }

  pred_individual <- lapply(pred_fixed, function(pred) {

    stopifnot(ncol(pred) == 1)
    stopifnot(all(!is.na(pred[, 1])))

    pred_final <- rep(NA, length(ccases))
    pred_final[ccases] <- pred[, 1]
    names(pred_final) <- rname

    return(pred_final)
    }
  )

  names(pred_individual) <- seq_along(pred_individual)

  return(pred_individual)
}


#' Evaluate the reservoir separately for each seed
#'
#' Computes the validation MSE for each reservoir initialization
#' and the mean MSE across all reservoir initializations.
#'
#' @param model Trained MixedML model.
#' @param data Validation data.
#'
#' @return A list containing:
#' \itemize{
#'   \item \code{predictions}: predictions for each reservoir;
#'   \item \code{mse_by_seed}: MSE for each reservoir;
#'   \item \code{mean_mse}: mean MSE across reservoirs.
#' }
#'
#' @noRd
#' @export
evaluate_reservoir_seeds <- function(model, data, fixed_spec, subject) {

  x_labels <- .get_x_labels(fixed_spec)
  y_label <- .get_y_label(fixed_spec)

  ccases <- complete.cases(data[x_labels])
  data_cc <- data[ccases, ]

  controls <- list(X = as.matrix(data_cc[x_labels]), subject_col = as.array(data_cc[[subject]]), return_individual = TRUE)

  pred_list <- do.call(model$predict, controls)

  mse_list <- lapply(pred_list, function(pred) {
      pred <- pred[, 1]
      mean((data_cc[[y_label]] - pred)^2,na.rm = TRUE)
    }
  )

  mse <- unlist(mse_list)

  list(mse_by_seed = mse, mean_mse = mean(mse), sd_mse = sd(mse))
}
