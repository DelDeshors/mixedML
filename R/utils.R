# formulas and variable names ----

.get_y_label <- function(spec) {
  stopifnot(rlang::is_bare_formula(spec))
  if (attr(terms(spec), "response") == 0) {
    return(NULL)
  }
  y_label <- as.character(terms(spec)[[2]])
  stopifnot(length(y_label) == 1)
  return(y_label)
}

.get_x_labels <- function(spec, allow_interactions = FALSE) {
  stopifnot(rlang::is_bare_formula(spec))
  orders <- attr(terms(spec), "order")
  if ((!allow_interactions) && max(orders) > 1) {
    stop("Formula with interactions are not allowed for this model.")
  }
  x_labels <- attr(terms(spec), "term.labels")
  return(x_labels)
}

# multiprocessing

#' @import future
.set_future_plan <- function(nproc) {
  if (nproc == future::nbrOfWorkers()) {
    return()
  }
  if (nproc > 1) {
    future::plan(future::multisession, workers = nproc)
  } else {
    future::plan(future::sequential)
  }
  return()
}


# data check ----

.check_sorted_data <- function(data, subject, time) {
  stopifnot(is.data.frame(data))
  stopifnot(is.character(subject))
  stopifnot(subject %in% names(data))
  stopifnot(is.character(time))
  stopifnot(time %in% names(data))
  #
  data <- data[c(subject, time)]
  data <- data[complete.cases(data), ]
  data_order <- order(data[, subject], data[, time])
  if (!all(data_order == seq_along(data_order))) {
    stop("Please sort the data by subject and time beforehand!")
  }
}

is.integer <- function(x) {
  return(is.numeric(x) & (x == round(x)))
}

is.single.integer <- function(x) {
  return(is.integer(x) & length(x) == 1)
}

is.single.numeric <- function(x) {
  return(is.numeric(x) & length(x) == 1)
}

is.named.vector <- function(x) {
  return(is.vector(x) & ((length(x) == 0) | is.character(names(x))))
}

.check_controls_with_function <- function(controls, controls_function) {
  names_controls <- names(controls)
  params_function <- methods::formalArgs(controls_function)
  if (!setequal(names_controls, params_function)) {
    control_name <- as.character(as.list(match.call())[["controls"]])
    function_name <- as.character(as.list(match.call())[["controls_function"]])
    stop(sprintf("\"%s\" should be set with the function \"%s\"\n", control_name, function_name))
  }
}


# reticulate ----

#' Set the Python environment for mixedML
#' @param environement_tool Tool used to managge the environments. Can be one of "venv" or "conda"
#' @param environement_name Name of the environment.
#' @return invisible NULL
#' @export
use_python_environment <- function(environement_tool, environement_name) {
  if (environement_tool == "conda") {
    if (!reticulate::condaenv_exists(environement_name)) {
      stop(sprintf("The conda environment \"%s\" does not exist.", environement_name))
    }
    reticulate::use_condaenv(environement_name)
    message(sprintf("conda environment \"%s\" activated!\n", environement_name))
  } else if (environement_tool == "venv") {
    if (!reticulate::virtualenv_exists(environement_name)) {
      stop("The virtual environment \"%s\" does not exist.", environement_name)
    }
    reticulate::use_virtualenv(environement_name)
    message(sprintf("virtual environment \"%s\" activated!\n", environement_name))
  } else {
    stop("environement_tool should be one of \"venv\" or \"conda\".")
  }
  return(invisible())
}


.activate_environment <- function() {
  name <- "MIXED_ML_PYTHON_ENV"
  value <- Sys.getenv(name)
  if (value == "") {
    # no default environment defined…
    return(invisible())
  }
  message("Value found for MIXED_ML_PYTHON_ENV: ", value)
  splt <- strsplit(value, ":")
  envtype <- splt[[1]][[1]]
  envname <- splt[[1]][[2]]
  use_python_environment(envtype, envname)
  return(invisible())
}


.modify_pypath <- function() {
  # necessary when loading a model saved with joblib
  # also makes importing Python module easier
  PACKAGE_NAME <- "mixedML" # pkgload::pkg_name() does not work with devtools::check
  PYTHON_FOLDER <- "python"
  py_path <- system.file(PYTHON_FOLDER, package = PACKAGE_NAME)
  if (py_path == "") {
    stop(
      "Hi developper friend! Have you just renamed this package?
      Please edit the PACKAGE_NAME variable in .modify_pypath function."
    )
  }
  pysys <- reticulate::import("sys")
  if (!py_path %in% pysys$path) {
    message("Adding ", py_path, " to the reticulate/Python path.")
    pysys$path <- c(pysys$path, py_path)
  }
  return()
}


.set_r_attr_to_py_obj <- function(py_obj, name, r_value) {
  # Specific R objects (like formulas…) will be stored as PyCapsule
  # and might cause problems with pickle.
  # Use `class(reticulate::r_to_py(r_value))` to check it
  reticulate::py_set_attr(py_obj, name, reticulate::r_to_py(r_value))
  return()
}


.get_r_attr_from_py_obj <- function(py_obj, name) {
  return(reticulate::py_to_r(reticulate::py_get_attr(py_obj, name)))
}


.is_python_model <- function(obj) {
  return(inherits(obj, "python.builtin.object") && !reticulate::py_is_null_xptr(obj))
}


R_CLASS <- "R_class"
.save_py_object <- function(obj, filename) {
  stopifnot(.is_python_model(obj))
  if (file.exists(filename)) {
    stop(filename, " already exists!")
  }
  if (R_CLASS %in% names(obj)) {
    stop(
      "The ",
      R_CLASS,
      " attribute is used to save the R class of the Python object,  but this attribute already exists in ",
      obj
    )
  }
  .set_r_attr_to_py_obj(obj, R_CLASS, class(obj))
  joblib <- reticulate::import("joblib")
  joblib$dump(obj, filename)
  reticulate::py_del_attr(obj, R_CLASS)
  return()
}

.load_py_object <- function(filename) {
  stopifnot(file.exists(filename))
  joblib <- reticulate::import("joblib")
  model <- joblib$load(filename)
  class(model) <- c(.get_r_attr_from_py_obj(model, R_CLASS), class(model))
  reticulate::py_del_attr(model, R_CLASS)
  return(model)
}

# covariance matrix ----

.cov_vector_to_cov_matrix <- function(cov_vector, names) {
  covmat <- matrix(0, ncol = length(names), nrow = length(names))
  idx <- upper.tri(covmat, diag = TRUE)
  covmat[idx] <- cov_vector
  idx <- lower.tri(covmat, diag = FALSE)
  covmat[idx] <- t(covmat)[idx]
  colnames(covmat) <- names
  rownames(covmat) <- names
  return(covmat)
}

get_cov_matrix <- function(hlme) {
  cov_vector <- hlme$best[startsWith(names(hlme$best), "varcov ")]
  return(.cov_vector_to_cov_matrix(cov_vector, hlme$Xnames[hlme$idea0 == 1]))
}
