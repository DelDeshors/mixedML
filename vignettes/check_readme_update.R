readme_md <- "README.md"
readme_rmd <- "README.Rmd"
mixed_rmd <- "vignettes/mixedML.Rmd"

is_newer <- function(file1, file2) {
  if (!file.exists(file1) || !file.exists(file2)) return(FALSE)
  return(file.info(file1)$mtime > file.info(file2)$mtime)
}

if (is_newer(readme_rmd, readme_md) || is_newer(mixed_rmd, readme_md)) {
  message(
    "README.md is out of date; please re-knit README.Rmd or use evtools::build_readme()"
  )
  quit(status = 1)
}

quit(status = 0)
