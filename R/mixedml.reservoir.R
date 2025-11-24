#' Estimation of a mixedML model using Reservoir Computing
#'
#' The function fits a MixedML model which combines an Ensemble of Echo State Networks (Reservoir+Ridge Regression)
#' for the population part (fixed effects) and a linear mixed model for the individual part (random effects)
#' @param fixed_spec two-sided linear formula object for the fixed-effects.
#' The response outcome is on the left of ~ and the covariates are separated by + on the right of ~.
#' (do not used extra formulation such as "x1*x3")
#' @param random_spec one-sided formula for the random-effects in the linear mixed model.
#'  By default, an intercept is included. If no intercept, -1 should be the first term included.
#' @param data dataframe containing the variables named in `fixed_spec`, `random_spec`, `subject` and `time`.
#' @param data_val dataframe used for validation (control of over-training). If present, the earlystopping and
#' aborting procedures will use the MSE on this dataset. Default: NULL (no validation dataset).
#' @param subject name of the covariate representing the grouping structure, given as a string/character.
#' @param time name of the time variable, given as a string/character.
#' @param mixedml_controls controls specific to the MixedML model
#' @param hlme_controls controls specific to the HLME model
#' @param mixedml_controls controls specific to the MixedML model
#' @param esn_controls controls specific to the ESN models
#' @param ensemble_controls controls specific to the Ensemble model
#' @param fit_controls controls specific to the ESN models fit
#' The default use the date at start in the format "mixedML-%y%m%d-%H%M%S"
#' (ex: mixedML-250709-100530)
#' @return fitted MixedML model (best iteration)
#'
#' @example R/mixedml.reservoir.example
#' @export
reservoir_mixedml <- function(
  fixed_spec,
  random_spec,
  data,
  data_val = NULL,
  subject,
  time,
  mixedml_controls = mixedml_ctrls(),
  hlme_controls = hlme_ctrls(),
  esn_controls = esn_ctrls(),
  ensemble_controls = ensemble_ctrls(),
  fit_controls = fit_ctrls()
) {
  call <- match.call()
  fixed_model <- .initiate_esn(esn_controls, ensemble_controls, fit_controls)
  model <- mixedml_training_loop(
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
  )
  return(model)
}
