# formula sides ----

.get_y_label <- function(spec) {
  stopifnot(rlang::is_bare_formula(spec))
  return(all.vars(spec)[attr(terms(spec), "response")])
}

.get_x_labels <- function(spec, allow_interactions = FALSE) {
  stopifnot(rlang::is_bare_formula(spec))
  x_labels <- attr(terms(spec), "term.labels")
  orders <- attr(terms(spec), "order")
  if ((!allow_interactions) && max(orders) > 1) {
    stop("Formula with interactions are not allowed for this model.")
  }
  return(x_labels)
}


# data check ----

.check_sorted_data <- function(data, subject, time) {
  stopifnot(is.data.frame(data))
  stopifnot(is.character(subject))
  stopifnot(subject %in% names(data))
  stopifnot(is.character(time))
  stopifnot(time %in% names(data))
  #
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
    stop(sprintf(
      "\"%s\" should be set with the function \"%s\"\n",
      control_name,
      function_name
    ))
  }
}

# reticulate ----
.activate_environment <- function() {
  name <- "MIXED_ML_PYTHON_ENV"
  value <- Sys.getenv(name)

  err <- function() {
    stop(sprintf(
      'You need to setup the %s environement variable as "venv:name_of_env" or "conda:name_of_env".\n',
      name
    ))
  }
  if (!grepl(":", value)) {
    err()
  }
  splt <- strsplit(value, ":")
  envtype <- splt[[1]][[1]]
  envname <- splt[[1]][[2]]
  if (envtype == "venv" && reticulate::virtualenv_exists(envname)) {
    reticulate::use_virtualenv(envname)
    cat(sprintf("virtual environment \"%s\" activated!\n", envname))
  } else if (envtype == "conda" && reticulate::condaenv_exists(envname)) {
    reticulate::use_condaenv(envname)
    cat(sprintf("conda environment \"%s\" activated!\n", envname))
  } else {
    err()
  }
  return()
}


.set_r_attr_to_py_obj <- function(py_obj, name, r_value) {
  reticulate::py_set_attr(py_obj, name, reticulate::r_to_py(r_value))
  return()
}


.get_r_attr_from_py_obj <- function(py_obj, name) {
  return(reticulate::py_to_r(reticulate::py_get_attr(py_obj, name)))
}


.is_python_model <- function(obj) {
  return(
    inherits(obj, "python.builtin.object") && !reticulate::py_is_null_xptr(obj)
  )
}

.save_py_object <- function(obj, filename) {
  joblib <- reticulate::import("joblib")
  with <- reticulate::import_builtins()$open
  joblib$dump(obj, with(filename, "wb"))
  return()
}

.load_py_object <- function(filename) {
  joblib <- reticulate::import("joblib")
  with <- reticulate::import_builtins()$open
  model <- joblib$load(with(filename, "rb"))
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
