# formula sides ----

.get_left_side_string <- function(spec) {
  stopifnot(rlang::is_bare_formula(spec))
  return(deparse(spec[[2]]))
}

.get_right_side_string <- function(spec) {
  stopifnot(rlang::is_bare_formula(spec))
  return(deparse(spec[[3]]))
}

.spec_formula_to_labels <- function(spec) {
  left <- .get_left_side_string(spec)
  right <- .get_right_side_string(spec)
  right <- gsub(" ", "", right)
  right <- gsub("\\+*\\b1\\b\\+*", "", right)
  right <- strsplit(right, "+", fixed = TRUE)[[1]]
  return(list(y_label = left, x_labels = right))
}

# array reshaping ----

.reshape_for_rnn <- function(spec, data, subject) {
  # https://reservoirpy.readthedocs.io/en/latest/user_guide/quickstart.html#A-note-on-data-formats
  stopifnot(rlang::is_bare_formula(spec))
  stopifnot(is.data.frame(data))
  stopifnot(is.character(subject))
  #
  labels <- .spec_formula_to_labels(spec)
  x_labels <- labels[["x_labels"]]
  y_label <- labels[["y_label"]]

  # unname so reticulate convert tis as a list (not a dict)
  rnn_data <- unname(split(data, data[subject]))
  # matric so reticulate convert is as a numpy array
  X <- lapply(rnn_data, function(df) {
    return(as.matrix(df[x_labels]))
  })
  y <- lapply(rnn_data, function(df) {
    return(as.matrix(df[y_label]))
  })
  return(list(X = X, y = y))
}

.reshape_pred_of_rnn <- function(pred, data, subject) {
  stopifnot(is.data.frame(data))
  stopifnot(is.character(subject))
  stopifnot(subject %in% names(data))
  stopifnot(is.list(pred) | is.vector(pred))
  stopifnot(length(pred) == length(unique(data[[subject]])))
  #
  names(pred) <- unique(data[[subject]])
  pred <- unsplit(pred, data[[subject]])
  return(unsplit(pred, data[subject]))
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
