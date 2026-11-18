# Clean MyDec sale files for iasWorld upload

The script in this directory prepares sale files extracted from IDOR's MyDec
service for upload to iasWorld. The script:

1. Reads one or more pipe-delimited `.txt` sale files from `input/`
2. Keeps only `S` (sale) and `A` (additional PIN) records and removes duplicates
3. Optionally drops records that are already in `iasworld.sales`, matching both
   `S` and `A` records on document number and PIN (this behavior is controlled
   by a flag defined at the top of the script)
4. Truncates `VARCHAR` fields in `S` records to the maximum length of the
   iasWorld column they map to, so they don't cause errors during upload
   (`A` records aren't changed)
5. Writes a single consolidated sale file plus an Excel report that summarizes
   the deduplication, exclusion, and truncation steps

We run this script on demand when our sales ingest stakeholders ask us to,
usually once a month, typically early in the month.

## Project structure

```text
sale-ingest-cleaning/
├── sale-ingest-cleaning.R     # Main script
├── oracle_query.sql           # Query used to generate `metadata/cv_length.csv`
├── input/                     # IDOR MyDec `.txt` sale files (not version controlled)
├── metadata/                  # Field mapping metadata (not version controlled)
│   ├── cv_length.csv
│   └── idor_to_iasworld_field_mapping.xlsx
├── output/                    # Cleaned sale files and reports (not version controlled)
├── renv.lock                  # Pinned R package versions
└── .Rprofile                  # Activates renv when R starts in this directory
```

## Input files

None of the input or metadata files are committed to this repository, so copy
them into the `input/` and `metadata/` directories before you run the script.

### Sale files (`input/`)

Copy the pipe-delimited IDOR MyDec `.txt` extracts from the O Drive to `input/`.
Our stakeholders typically share the O Drive location with us when they request
that we run the script. The script reads every `.txt` file in `input/` and
combines them, so you can include more than one file if necessary.

### Metadata (`metadata/`)

Copy these files from the corresponding O Drive location in the
`recurring-data-requests` directory into `metadata/`:

- `idor_to_iasworld_field_mapping.xlsx`: Maps IDOR record fields to iasWorld
  tables and columns. The script reads the
  `S - PTAX-203, A, B & ADD - test` sheet.
- `cv_length.csv`: Data type and maximum length of each column in the iasWorld
  `CVTRAN` and `CVLEG` tables. If you need to regenerate this file, run
  `oracle_query.sql` against the iasWorld Oracle database and export the
  results as CSV with the columns `ias_table`, `ias_col`, `data_type`, and
  `data_length`.

These metadata files rarely change, so you should only have to copy them once
when you first run the script.

## Installation

Install R dependencies with renv:

```r
renv::restore()
```

You will need access to the CCAO Athena data lake if the
`EXCLUDE_EXISTING_IAS_SALES` flag is enabled. Make sure
your [AWS
credentials](https://github.com/ccao-data/wiki/blob/master/How-To/Setup-the-AWS-Command-Line-Interface-and-Multi-factor-Authentication.md)
are configured and authenticated before you run the script.

## Usage

From this directory, run:

```bash
Rscript sale-ingest-cleaning.R
```

You can also open the project in RStudio or Positron and source
`sale-ingest-cleaning.R`.

To keep sales that are already in iasWorld and skip the Athena query, set
`EXCLUDE_EXISTING_IAS_SALES <- FALSE` at the top of the script.

## Output

The script writes two files to `output/`, where `YYYY-MM-DD` is the date
of the run:

- `cleaned_sales_YYYY-MM-DD.txt`: Cleaned, deduplicated, pipe-delimited `S`
  and `A` records in their original order, ready for upload
- `cleaned_sales_YYYY-MM-DD_report.xlsx`: Report to share with stakeholders,
  with two sheets:
  - `summary`: Record counts at each step (e.g. input lines, non-`S`/`A` lines
    dropped, duplicates removed, records already in iasWorld, etc.), broken out
    by `S` and `A` record type, plus counts of truncated records and fields
  - `truncation`: The number of `S` records that were truncated for each IDOR
    field, with the iasWorld table, column, and max length, along with notes
    explaining expected truncations

The script also prints the summary and truncation tables to the console, along
with a check confirming that no `A` records changed.
