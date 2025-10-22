# controls ----

#' Prepare the esn_controls
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
#' @return esn_controls
#' @export
esn_ctrls <- function(
  units = 100,
  lr = 1.0,
  sr = 0.1,
  ridge = 0.0,
  input_scaling = 1.0,
  feedback = FALSE,
  input_to_readout = FALSE
) {
  stopifnot(is.single.integer(units))
  units <- as.integer(units)
  stopifnot(is.single.numeric(lr))
  stopifnot(is.single.numeric(sr))
  stopifnot(is.single.numeric(ridge))
  stopifnot(is.numeric(input_scaling) && length(input_scaling) == 1 && input_scaling > 0.)
  stopifnot(is.logical(feedback))
  stopifnot(is.logical(input_to_readout))
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
#' @return ensemble_controls
#' @export
ensemble_ctrls <- function(seed_list = c(1, 2, 3), aggregator = "median", scaler = "standard", n_procs = 1) {
  stopifnot(is.integer(seed_list))
  seed_list <- as.integer(seed_list) # real integer for reticulate
  stopifnot(is.character(aggregator))
  stopifnot(is.character(scaler))
  stopifnot(is.single.integer(n_procs))
  n_procs <- as.integer(n_procs) # real integer for reticulate
  return(as.list(environment()))
}

# nolint start
#' Prepare the fit_controls
#'
#' Please see the
#' [documentation](https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.ESN.html#reservoirpy.nodes.ESN.fit)
#' of ReservoirPy
#' @param warmup Number of timesteps to consider as warmup and discard at the beginning. Defalut: 0
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


# recipes  ----
.initiate_esn <- function(
  esn_controls = esn_ctrls(),
  ensemble_controls = ensemble_ctrls(),
  fit_controls = fit_ctrls()
) {
  .test_initiate_esn(esn_controls, ensemble_controls, fit_controls)
  # sys.path is modified when activating the Python environment
  # so the import is simply:
  retipy <- reticulate::import("reservoir_ensemble")
  # enforcing "stateful=TRUE" and "reset=TRUE"
  enforcement <- list(stateful = TRUE, reset = TRUE)
  fit_controls <- c(fit_controls, enforcement)
  predict_controls <- enforcement

  controls <- c(
    ensemble_controls,
    list(esn_controls = esn_controls, fit_controls = fit_controls, predict_controls = predict_controls)
  )
  model <- do.call(retipy$JoblibReservoirEnsemble, controls)
  return(model)
}


# fitting/training ----
.fit_reservoir <- function(model, data, fixed_spec, subject) {
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
.predict_reservoir <- function(model, data, fixed_spec, subject) {
  x_labels <- .get_x_labels(fixed_spec)
  ccases <- complete.cases(data[x_labels])
  data <- data[ccases, ]
  controls <- list(X = as.matrix(data[x_labels]), subject_col = as.array(data[[subject]]))
  pred_fixed <- do.call(model$predict, controls)
  stopifnot(ncol(pred_fixed) == 1)
  stopifnot(all(!is.na(pred_fixed[, 1])))
  pred_final <- rep(NA, length(ccases))
  pred_final[ccases] <- pred_fixed[, 1]
  return(pred_final)
}
