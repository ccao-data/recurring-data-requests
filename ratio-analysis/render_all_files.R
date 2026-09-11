# This file runs the ratio_analysis.qmd report for all files
# stored in the  O drive in
# O:/CCAODATA/recurring-data-requests/provisional-ratio-curves/. Since
# that isn't accessible from the server they need to be copied locally or run
# from a local machine. They MUST be named according to the current naming
# scheme, and there must be PIN and Desk Review Value columns

library(quarto)

library(assessr)
library(ccao)
library(DBI)
library(dplyr)
library(ggplot2)
library(ggspatial)
library(glue)
library(grid)
library(knitr)
library(noctua)
library(openxlsx)
library(patchwork)
library(readr)
library(scales)
library(sf)
library(tidyr)

data_path <- "O:/CCAODATA/recurring-data-requests/provisional-ratio-curves"
year <- Sys.getenv("ANALYSIS_YEAR")
input_path <- file.path(data_path, "input", year)
output_path <- file.path(data_path, "output", year)

input_files <- list.files(input_path, pattern = "\\.xlsx$", full.names = TRUE)
# This is a test to make sure that the township number is valid
town_codes <- substr(basename(input_files), 1, 2)
if (!all(town_codes %in% ccao::town_dict$township_code)) {
  stop("One or more township codes in the input files are not valid.")
}

dir.create(output_path, recursive = TRUE, showWarnings = FALSE)

for (f in input_files) {
  # Grab the town code for the file that we are processing.
  # The files in the folder must be named in the structure of
  # ##-township.xlsx
  town_code <- substr(basename(f), 1, 2)
  town_name <- tolower(town_convert(town_code))
  out_name <- paste0(town_name, "_ratio_analysis.pdf")
  message("Rendering PDF report for ", town_name)
  # Render the report with the name of township_ratio_analysis.pdf
  quarto_render(
    "ratio-analysis.qmd",
    execute_params = list(input_file = f),
    output_file = out_name
  )
  file.rename(out_name, file.path(output_path, out_name))
  # Output the .xlsx file with all PIN values
  xlsx_name <- paste0(town_name, ".xlsx")
  file.rename(xlsx_name, file.path(output_path, xlsx_name))
}
