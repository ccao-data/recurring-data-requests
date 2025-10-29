# Ratio Curve Analysis

We run `provisional-ratio-curves.R` every time valuations finishes desk review for a town
that's about to mail and sends us their provisional values. All they need to
provide us is an excel sheet with two columns: `PIN` and `Desk Review Value`.
- The sheet can contain more columns than that, they'll just be ignored.
- Before running the R script make sure the excel workbook is
in `O:\CCAODATA\recurring-data-requests/provisional-ratio-curves\input`, labeled using the
established schema in that folder (`town_code-town_name.xlsx`), and that there
are in fact `PIN` and `Desk Review Value` columns or the script will throw an
error.
- Run the script in a local installation of RStudio, rather than on the server,
since the script needs to read from the O Drive and write to it
  - If you can't run the script locally, you can also just edit the input and output
  paths as defined in the script to write to a relative path, and then copy the input
  and output files between your machine and the server
- Output will show up in `O:\CCAODATA\recurring-data-requests/provisional-ratio-curves\output`
