#' MixedML model with Reservoir Computing
#'
#' Generate and fit a MixedML model using an Ensemble of Echo State Networks (Reservoir+Ridge Regression)
#' to fit the fixed effects.
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
#' @examples
#' model_reservoir <- reservoir_mixedml(#' data_train <- data_mixedml[data_mixedml$ID < 9, ]
#' data_val <- data_mixedml[data_mixedml$ID >= 9, ]
#'
#' model_reservoir <- reservoir_mixedml(
#'   fixed_spec = ym ~ x1 + x2 + x3,
#'   random_spec = ~ x1 + x2,
#'   data = data_train,
#'   data_val = data_val,
#'   subject = "ID",
#'   time = "time",
#'   # parameters for MixedML method
#'   mixedml_controls = mixedml_ctrls(
#'     earlystopping_controls = earlystopping_ctrls(min_mse_gain = 0.1, patience = 1),
#'     aborting_controls = aborting_ctrls(check_iter = 5, mse_value = 100),
#'     all_info_hlme_prediction = TRUE
#'   ),
#'   # controls (extra-parameters) for the hlme model
#'   hlme_controls = hlme_ctrls(maxiter = 50, idiag = TRUE),
#'   # controls (extra-parameters) for the ML model
#'   esn_controls = esn_ctrls(units = 20, ridge = 1e-5),
#'   ensemble_controls = ensemble_ctrls(seed_list = c(1, 2, 3, 4, 5)),
#'   fit_controls = fit_ctrls(warmup = 1)
#' )
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
