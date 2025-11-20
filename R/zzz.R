.onLoad <- function(libname, pkgname) {
  # NOTE TO DEV: when calling `devtools::install`, the environment variable defined in MIXED_ML_PYTHON_ENV
  # is still available… but not the corresponding Python environement
  # so it's activation will fail.
  # One just needs to delete this environment variable to make the install work
  # => `Sys.unsetenv(MIXED_ML_PYTHON_ENV)`
  .activate_environment()
  .modify_pypath()
}
