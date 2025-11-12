# Condo Characteristics Prep

## Description

For the last few years, we've collaborated with the Field team to create a
database of unit-level characteristics for condos. Now we're refining that
database by providing excel spreadsheets of condo units that we think warrant
review. We start with the universe of "existing data" columns of the previous
collected data per PIN (PIN, including address, unit chars, etc.), which lives
in `ccao.pin_condo_char`.

We append the following "flag" columns of data points that might be good proxies
for needing a characteristics update:

- QC flag for possible issues as identified by our intern's work
- permit data
- PIN status
- sales data -- sales val outlier flag, if PIN sold in 2022 or later

As an example for the permit column, if there's a permit, we show the relevant
text from the permit; if no permit exists, that column is blank.

This exports one excel file for the desired triad with a tab per town. Each
contains the above "existing data" and "flag" columns as well as "correct data"
columns for Field to note changes.

## Parameters

- `tri`  - Set the triad for which you'd like to export condos.

- `min_year` - Oldest year for which to include sales and permits.

---
Example output here: `O:\CCAODATA\recurring-data-requests\condo-chars-prep\output\south_condo_review_2025.xlsx`