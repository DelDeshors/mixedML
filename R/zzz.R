.onLoad <- function(libname, pkgname) {
  # if reticulate/Python is used, we force the user to create an environment and explicitely declare it to reticulate
  Sys.setenv(RETICULATE_USE_MANAGED_VENV = "no")

  # modifying the PYTHONPATH so the modules defined in inst/python are easily imported
  # and the Python models are recognized when they are loaded
  PACKAGE_NAME <- "mixedML" # pkgload::pkg_name() does not work with devtools::check
  PYTHON_FOLDER <- "python"
  py_path <- system.file(PYTHON_FOLDER, package = PACKAGE_NAME)
  if (py_path == "") {
    stop(
      "Hi developper friend! Have you just renamed this package?
      Please edit the PACKAGE_NAME variable in the zzz.R file."
    )
  }
  Sys.setenv(PYTHONPATH = py_path)
}
