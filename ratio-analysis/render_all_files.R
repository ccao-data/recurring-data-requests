library(quarto)

data_path <- "."
year <- format(Sys.Date(), "%Y")
input_path <- file.path(data_path, "input", year)
output_path <- file.path(data_path, "output", year)

input_files <- list.files(input_path, pattern = "\\.xlsx$", full.names = TRUE)

dir.create(output_path, recursive = TRUE, showWarnings = FALSE)

for (f in input_files) {
  town_name <- sub("^[0-9]+-", "", sub("\\.xlsx$", "", basename(f)))
  out_name <- paste0(town_name, "_ratio_analysis.pdf")
  message("Rendering: ", f)
  quarto_render(
    "ratio-analysis.qmd",
    execute_params = list(input_file = f),
    output_file = out_name
  )
  file.rename(out_name, file.path(output_path, out_name))
}
