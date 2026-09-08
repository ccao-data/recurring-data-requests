library(quarto)

input_files <- list.files(
  "inputs",
  pattern = "\\.xlsx$",
  recursive = TRUE,
  full.names = TRUE
)

for (f in input_files) {
  message("Rendering: ", f)
  quarto_render(
    "ratio-analysis.qmd",
    execute_params = list(input_file = f)
  )
}
