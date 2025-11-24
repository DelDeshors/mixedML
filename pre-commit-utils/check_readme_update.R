# modification of
# https://github.com/lorenzwalthert/precommit/blob/main/inst/hooks/exported/readme-rmd-rendered.R

readme_md <- "README.md"
readme_rmd <- "README.Rmd"
mixed_rmd <- "vignettes/mixedML.Rmd"

is_newer <- function(file1, file2) {
  if (!file.exists(file1) || !file.exists(file2)) return(FALSE)
  # we use a threshold to avoid false positives when the files are modified when merging with another branch
  return(file.info(file1)$mtime - file.info(file2)$mtime > 0.1)
}

if (is_newer(readme_rmd, readme_md) || is_newer(mixed_rmd, readme_md)) {
  rlang::abort(
    "README.md is out of date; please re-knit README.Rmd or use devtools::build_readme()"
  )
}

file_names_staged <- system2(
  "git",
  c("diff --cached --name-only"),
  stdout = TRUE
)

files <- c(readme_md, readme_rmd, mixed_rmd)
inter <- intersect(files, file_names_staged)

if (length(inter) == 1) {
  rlang::abort(cat("At least one of ", files, "is not staged."))
}
