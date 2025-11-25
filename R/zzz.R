PACKAGE_NAME <- "mixedML" # pkgload::pkg_name() does not work with devtools::check
PYTHON_FOLDER <- "python"

.onLoad <- function(libname, pkgname) {
  # use the requirements.txt file to declare to reticulate the needed libraries with `py_require` to
  .py_require_from_requirements()

  # modifying the PYTHONPATH so the modules defined in inst/python are easily imported
  # and the Python models are recognized when they are loaded
  py_path <- system.file(PYTHON_FOLDER, package = PACKAGE_NAME)
  if (py_path == "") {
    stop(
      "Hi developper friend! Have you just renamed this package?
      Please edit the PACKAGE_NAME variable in the zzz.R file."
    )
  }
  Sys.setenv(PYTHONPATH = py_path)
}


.py_require_from_requirements <- function() {
  requirefile <- system.file(paste(PYTHON_FOLDER, "requirements.txt", sep = "/"), package = PACKAGE_NAME)
  lines <- readLines(requirefile)
  lines <- lines[lines != "" & !grepl("^#", lines)]
  # first pass to find python
  python_ver <- NULL
  for (line in lines) {
    grp <- grep("^python[ <=>]", line, perl = TRUE)
    if (length(grp) > 0) {
      python_ver <- sub("^python *", "", line)
      break
    }
  }
  # second pass for the py_require
  for (line in lines) {
    grp <- grep("^python[ <=>]", line, perl = TRUE)
    if (length(grp) > 0) {
      next
    }
    reticulate::py_require(package = line, python_version = python_ver)
  }
  return()
}

.onUnload <- function(libpath) {
  # clean up the PYTHONPATH modification
  Sys.unsetenv("PYTHONPATH")
}
