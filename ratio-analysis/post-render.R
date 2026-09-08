target_path <- readLines(".pdf-target-path")
dir.create(dirname(target_path), recursive = TRUE, showWarnings = FALSE)
file.copy("ratio-analysis.pdf", target_path, overwrite = TRUE)
file.remove(".pdf-target-path")
