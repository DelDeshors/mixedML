# reticulate ----
.load_package <- function() {
  .activate_environment()
  package <- "mixedML" # pkgload::pkg_name() does not work with devtools::check
  pyfolder <- "python"
  module <- "reservoir_ensemble"
  pypath <- system.file(pyfolder, package = package, mustWork = TRUE)
  stopifnot(file.exists(sprintf("%s/%s.py", pypath, module)))
  retipy <- reticulate::import_from_path(module, pypath, convert = TRUE)
  return(retipy)
}


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
#' @param feedback Is readout connected to reservoir through feedback?
#' @return esn_controls
#' @export
esn_ctrls <- function(
  units = 100,
  lr = 1.0,
  sr = 0.1,
  ridge = 0.0,
  feedback = FALSE
) {
  units <- .fix_integer(units)
  stopifnot(is.single.integer(units))
  stopifnot(is.single.numeric(lr))
  stopifnot(is.single.numeric(sr))
  stopifnot(is.single.numeric(ridge))
  stopifnot(is.logical(feedback))
  return(as.list(environment()))
}

#' Prepare the ensemble_controls
#'
#'
#' @param seed_list List of seeds used to generate the Reservoir. Default:  c(1, 2, 3)
#' @param agg_func Function used to aggregate the predictions of each ESN.
#' "mean" or "median". Default: "median"
#' @param n_procs Number of processor to use. 1 means no multiprocessing. Default: 1.
#' @return ensemble_controls
#' @export
ensemble_ctrls <- function(
  seed_list = c(1, 2, 3),
  agg_func = "median",
  n_procs = 1
) {
  seed_list <- .fix_integer(seed_list)
  n_procs <- .fix_integer(n_procs)
  stopifnot(is.integer(seed_list))
  stopifnot(is.character(agg_func))
  stopifnot(is.single.integer(n_procs))
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
  warmup <- .fix_integer(warmup)
  stopifnot(is.single.integer(warmup))
  stopifnot(warmup >= 0)
  return(as.list(environment()))
}


# recipes  ----
.initiate_esn <- function(
  fixed_spec,
  subject,
  esn_controls = esn_ctrls(),
  ensemble_controls = ensemble_ctrls(),
  fit_controls = fit_ctrls()
) {
  retipy <- .load_package()
  .check_controls_with_function(esn_controls, esn_ctrls)
  .check_controls_with_function(ensemble_controls, ensemble_ctrls)
  .check_controls_with_function(fit_controls, fit_ctrls)

  # enforcing "stateful=TRUE" and "reset=TRUE"
  enforcement <- list(stateful = TRUE, reset = TRUE)
  fit_controls <- c(fit_controls, enforcement)
  predict_controls <- enforcement

  controls <- c(list(esn_controls = esn_controls), ensemble_controls)
  model <- do.call(retipy$get_esn_ensemble, controls)
  # Adding the remaining attributes to the model so we can use them for fit and predict
  .set_r_attr_to_py_obj(model, "fixed_spec", fixed_spec)
  .set_r_attr_to_py_obj(model, "subject", subject)
  .set_r_attr_to_py_obj(model, "fit_controls", fit_controls)
  .set_r_attr_to_py_obj(model, "predict_controls", predict_controls)
  return(model)
}


# fitting/training ----
.fit_reservoir <- function(model, data, pred_rand) {
  # !!! offsetting is not implemented in LCMM
  # BUT for linear models, fitting "f(X)+offset" on Y is equivalent to
  # fitting f(X) on "Y-offset"
  # so that is the method used so far
  fixed_spec <- .get_r_attr_from_py_obj(model, "fixed_spec")
  subject <- .get_r_attr_from_py_obj(model, "subject")
  target_name <- .get_left_side_string(fixed_spec)
  data[target_name] <- data[target_name] - pred_rand
  data_reshaped <- .reshape_for_rnn(fixed_spec, data, subject)
  #
  controls <- c(
    data_reshaped,
    list(fit_controls = .get_r_attr_from_py_obj(model, "fit_controls"))
  )
  do.call(model$fit, controls)
  pred_fixed <- .predict_reservoir(model, data, subject, data_reshaped)
  return(list("model" = model, "pred_fixed" = pred_fixed))
}


# prediction ----
.predict_reservoir <- function(
  model,
  data,
  subject,
  data_reshaped = NULL
) {
  if (is.null(data_reshaped)) {
    fixed_spec <- .get_r_attr_from_py_obj(model, "fixed_spec")
    data_reshaped <- .reshape_for_rnn(fixed_spec, data, subject)
  } else {
    # shortcut to avoid redoing this operation if already done in "fit"
    stopifnot(setequal(names(data_reshaped), c("X", "y")))
  }
  #
  controls <- c(
    data_reshaped["X"],
    list(predict_controls = .get_r_attr_from_py_obj(model, "predict_controls"))
  )
  pred_fixed <- do.call(model$predict, controls)
  pred_fixed <- .reshape_pred_of_rnn(pred_fixed, data, subject)
  return(pred_fixed)
}
