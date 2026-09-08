library(quarto)

input_files <- list.files(
  "inputs",
  pattern = "\\.xlsx$",
  recursive = TRUE,
  full.names = TRUE
)

for (f in input_files) {
  year <- basename(dirname(f))
  town_name <- sub("^[0-9]+-", "", sub("\\.xlsx$", "", basename(f)))
  out_name <- paste0(town_name, "_ratio_analysis.pdf")
  out_dir <- file.path("output", year)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  message("Rendering: ", f)
  quarto_render(
    "ratio-analysis.qmd",
    execute_params = list(input_file = f),
    output_file = out_name
  )
  file.rename(out_name, file.path(out_dir, out_name))
}
