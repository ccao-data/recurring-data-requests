This folder runs a ratio analysis comparing desk review values against model values for residential PINs, either for a single township or for every township at once. 
Each input file must be an xlsx named ##-township.xlsx (e.g., 17-berwyn.xlsx) with PIN and Desk Review Value columns.

To run a single township, render ratio-analysis.qmd in Quarto with the input_file parameter pointing to that township's xlsx file.
Example:

library(quarto)
quarto_render(
  "ratio-analysis.qmd",
  execute_params = list(input_file = "input/2026/17-berwyn.xlsx"),
  output_file = "berwyn_ratio_analysis.pdf"
)

This produces berwyn_ratio_analysis.pdf in the current working directory. You can also render from a terminal instead:

quarto render ratio-analysis.qmd -P input_file:input/2026/17-berwyn.xlsx --output berwyn_ratio_analysis.pdf

To run every township at once, place each township's input file in input/<year>/ and run render_all_files.R.
The analysis year is controlled by the ANALYSIS_YEAR variable in a .Renviron file. Make sure this file is updated at the beginning of the new modeling year.