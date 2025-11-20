# fixed-model S3 generics ----
# to implement a new fixed effect model, one must give the new model a class
# and implement the corresponding S3 class
# as a convention this should be done in a fixed_model.class.R file
#
# for example: to define the functions for a reservoirpy model
# 1. we create a "fixed_model.reservoir.R" file
# 2. the model is give the "reservoir" class at the end of its initialization
#    using `class(model) <- c("reservoir", class(model))`
# 3. The `fit_fixed_model.reservoir` is implemented
# 4. The `predict_fixed_model.reservoir` is implemented

fit_fixed_model <- function(model, data, fixed_spec, subject) {
  UseMethod("fit_fixed_model")
  return("Will not be executed")
}

predict_fixed_model <- function(model, data, fixed_spec, subject) {
  UseMethod("predict_fixed_model")
  return("Will not be executed")
}

# check methods ----
# these functions stop with an error message if the checks fail
# the ideal would have been to do these checks at the S3 method level
# but since it is not possible to run any code after the UseMethod() call,
# and we want to have these checks for all S3 methods,
# we have to do these checks in the try_* functions called in the training loop

check_fit_fixed_model <- function(initial_fixed_model, fitted_fixed_model) {
  if (!inherits(fitted_fixed_model, class(initial_fixed_model)[1])) {
    stop(sprintf(
      "The fitted fixed model is of class '%s' instead of the expected class '%s'!",
      class(fitted_fixed_model)[1],
      class(initial_fixed_model)[1]
    ))
  }
}

check_predict_fixed_model <- function(pred, data) {
  if (!is.vector(pred)) {
    stop("The prediction should be a vector!")
  }
  if (!is.numeric(pred)) {
    stop("The prediction vector should be numeric!")
  }
  if (!setequal(names(pred), rownames(data))) {
    stop("The names of the prediction vector should match the rownames of the data!")
  }
}


# try methods ----
# these functions catch errors during fitting/prediction and return NULL in that case
# the training loop can then handle the NULL value accordingly (e.g., aborting the training loop)
try_fit_fixed_model <- function(fixed_model, data_fixed, fixed_spec, subject) {
  fitted_fixed_model <- try(fit_fixed_model(fixed_model, data_fixed, fixed_spec, subject), silent = TRUE)
  if (inherits(fitted_fixed_model, "try-error")) {
    warning("Training of the the ML model failed: aborting the training loop!")
    return(NULL)
  }
  check_fit_fixed_model(fixed_model, fitted_fixed_model)
  return(fitted_fixed_model)
}


try_predict_fixed_model <- function(fixed_model, data_fixed, fixed_spec, subject) {
  pred_fixed <- try(predict_fixed_model(fixed_model, data_fixed, fixed_spec, subject), silent = TRUE)
  if (inherits(pred_fixed, "try-error")) {
    warning("Prediction with the ML model failed: aborting the training loop!")
    return(NULL)
  }
  check_predict_fixed_model(pred_fixed, data_fixed)
  return(pred_fixed)
}
