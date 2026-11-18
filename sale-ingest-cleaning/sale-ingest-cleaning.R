# Script that reads one or more pipe-delimited sale files extracted from IDOR's
# MyDec service, filters for only `S` (sale) and `A` (additional PIN) records,
# and cleans those records by deduplicating them and truncating string fields
# that exceed the field's character length limit.
#
# Reads `.txt` files from `input/`, and writes a consolidated `.txt` file to
# `output/`.
#
# Expects to find metadata files in `metadata/`, but these files are not kept
# under version control since they represent draft work. Before you run the
# script, copy over those files from the corresponding O Drive location.
library(DBI)
library(dplyr)
library(glue)
library(openxlsx)
library(purrr)
library(readr)
library(stringr)
library(noctua)
library(tibble)
library(tidyr)

# Whether to drop records already present in iasworld
EXCLUDE_EXISTING_IAS_SALES <- TRUE

# Metadata files to help us truncate fields properly
CV_LENGTH_FILE <- file.path("metadata", "cv_length.csv")
IDOR_TO_IASWORLD_FIELD_MAPPING_FILE <- file.path(
  "metadata",
  "idor_to_iasworld_field_mapping.xlsx"
)

# Fail fast if any metadata files are missing
missing_metadata <- c(CV_LENGTH_FILE, IDOR_TO_IASWORLD_FIELD_MAPPING_FILE)
missing_metadata <- missing_metadata[!file.exists(missing_metadata)]
if (length(missing_metadata) > 0) {
  stop(
    "Missing required metadata file(s): ",
    paste(missing_metadata, collapse = ", "),
    ". Copy them from the corresponding O Drive location.",
    call. = FALSE
  )
}

# Ingest pipe-delimited IDOR sale files from IT
sales <- list.files(
  path = "input", full.names = TRUE, pattern = ".txt"
) %>%
  map(\(file) {
    readLines(file) %>%
      data.frame("all_data" = .)
  }) %>%
  bind_rows() %>%
  filter(substr(all_data, 1, 1) %in% c("S", "A")) %>%
  distinct()

# Optionally exclude records already in ias. We match both S and A records to
# ias sales on document number (IDOR field 4) and PIN (IDOR field 14 for S
# records, field 6 for A records). Matching on PIN rather than excluding whole
# document numbers matters because an earlier upload may have been cut off
# partway through a multi-PIN sale, so only some of its PINs may have made it
# in.
n_ias_excluded <- c(total = 0L, S = 0L, A = 0L)
if (EXCLUDE_EXISTING_IAS_SALES) {
  conn <- dbConnect(noctua::athena(), rstudio_conn_tab = FALSE)
  existing_doc_pins <- dbGetQuery(
    conn,
    "SELECT DISTINCT
      instruno,
      parid
    FROM iasworld.sales
    WHERE cur = 'Y'
      AND deactivat IS NULL
      AND instruno IS NOT NULL
      AND parid IS NOT NULL"
  ) %>%
    transmute(
      key = paste(
        # Doc numbers that have trailing "D" characters should match, regardless
        # of whether the trailing "D" is present on one side
        str_remove(toupper(trimws(instruno)), "D+$"),
        str_remove_all(parid, "[^0-9]")
      )
    ) %>%
    distinct()
  dbDisconnect(conn)

  n_before <- nrow(sales)
  type_before <- table(factor(substr(sales$all_data, 1, 1), c("S", "A")))
  sales <- sales %>%
    mutate(
      type = substr(all_data, 1, 1),
      pin = if_else(
        type == "S",
        str_split_i(all_data, fixed("|"), 14),
        str_split_i(all_data, fixed("|"), 6)
      ),
      key = paste(
        str_remove(
          toupper(trimws(str_split_i(all_data, fixed("|"), 4))),
          "D+$"
        ),
        str_remove_all(pin, "[^0-9]")
      ),
      exclude = key %in% existing_doc_pins$key
    )
  excluded_s <- sales %>%
    filter(exclude, type == "S") %>%
    transmute(
      saledt = as.Date(str_split_i(all_data, fixed("|"), 18), "%m%d%Y"),
      recorded = as.Date(str_split_i(all_data, fixed("|"), 3), "%m%d%Y")
    )
  sales <- sales %>%
    filter(!exclude) %>%
    select(all_data)

  type_after <- table(factor(substr(sales$all_data, 1, 1), c("S", "A")))
  n_ias_excluded <- c(
    total = n_before - nrow(sales),
    S = as.integer(type_before[["S"]] - type_after[["S"]]),
    A = as.integer(type_before[["A"]] - type_after[["A"]])
  )

  message(glue(
    "Excluded {n_before - nrow(sales)} records already in iasworld.sales"
  ))
  if (nrow(excluded_s) > 0) {
    message(glue(
      "Excluded sale dates range from ",
      "{min(excluded_s$saledt)} to {max(excluded_s$saledt)}"
    ))
    message(glue(
      "Excluded sale recording dates range from ",
      "{min(excluded_s$recorded)} to {max(excluded_s$recorded)}"
    ))
    message()
  }
}

# Truncate fields to prevent them from causing errors during upload. We use two
# reference files: One to map IDOR fields to ias, and one to determine max field
# lengths based on table metadata in the Oracle DB. Note that we are only
# truncating varchar fields for now.
idor_sheet <- read.xlsx(
  IDOR_TO_IASWORLD_FIELD_MAPPING_FILE,
  sheet = "S - PTAX-203, A, B & ADD - test"
)

# The sheet holds two stacked tables: S records first, then A records. The A
# table begins at a repeat of the header row, i.e. a row whose first column is
# "Field #", the same label as the sheet's header cell (A1). Keep only the S
# table, which is everything above that row.
FIELD_NUM_LABEL <- "Field #"
header_rows <- which(trimws(idor_sheet[[1]]) == FIELD_NUM_LABEL)
if (length(header_rows) == 0) {
  stop(
    "Could not find the A-record header row ('", FIELD_NUM_LABEL,
    "') in the field mapping sheet.",
    call. = FALSE
  )
}
idor_map <- idor_sheet[seq_len(header_rows[1] - 1), ] %>%
  filter(str_detect(`iasw.table`, "CVLEG|CVTRAN")) %>%
  select(
    idor_field_num = `Field.#`,
    ias_table = `iasw.table`,
    ias_col = `CV411ILCOO.Mapping.-.iasw.field`
  ) %>%
  mutate(
    idor_field_num = paste0("all_data_", idor_field_num),
    ias_col = toupper(str_replace_all(trimws(ias_col), " ", "_")),
    ias_table = str_extract(ias_table, "CVTRAN|CVLEG")
  )

# Join the IDOR mappings to their associated column lengths as a named vector
col_maps <- idor_map %>%
  left_join(
    # See oracle_query.sql for source of the following data.
    read_csv(CV_LENGTH_FILE, col_types = "ccci"),
    by = c("ias_table", "ias_col")
  ) %>%
  filter(data_type == "VARCHAR2") %>%
  select(idor_field_num, data_length) %>%
  deframe()

# We split the data in two since A and S records have a different number of
# fields and won't map to a single dataframe. We make sure to record the row of
# each record before splitting so that we can reassemble the data in the
# original order after truncating the fields.
pre_truncation <- sales$all_data
split <- sales %>%
  mutate(
    group = substr(all_data, 1, 1),
    row = row_number()
  ) %>%
  split(.$group)

# Separate and truncate the fields for the S records only, then reassemble the
# data into a single pipe-delimited field. The truncation is done using the
# col_maps vector created above, which contains the maximum length for each
# field.
split$S <- split$S %>%
  separate_wider_delim(
    cols = "all_data", delim = "|", names_sep = "_"
  ) %>%
  mutate(across(
    names(col_maps),
    ~ substr(.x, 1, col_maps[cur_column()])
  )) %>%
  unite(
    col = "all_data",
    starts_with("all_data_"),
    sep = "|"
  )

# Reassemble the data in the original order and output to a text file
output <- split %>%
  bind_rows() %>%
  arrange(row) %>%
  select(all_data)

writeLines(
  output$all_data,
  file.path("output", glue("cleaned_sales_{Sys.Date()}.txt"))
)

# Compare the raw input to the cleaned output, printing a deduplication summary
# to the console and writing an Excel report to `output/` that we can share
# with stakeholders.
raw <- list.files(path = "input", full.names = TRUE, pattern = ".txt") %>%
  map(readLines) %>%
  unlist()
raw_sa <- raw[substr(raw, 1, 1) %in% c("S", "A")]
uniq_sa <- unique(raw_sa)
# Quick helper function to count the number of records in a file for a specific
# line type, e.g. S (sale) or A (additional PIN)
type_n <- function(lines, line_type) sum(substr(lines, 1, 1) == line_type)

summary_rows <- tibble(
  metric = c(
    "Total input lines",
    "- Non-S/A lines dropped",
    "= S/A records in input",
    "- Duplicates removed",
    "- Records already in iasWorld",
    "= Total unique output rows",
    "",
    "Total input S records",
    "- Duplicate S records",
    "- S records already in iasWorld",
    "= Total unique S records",
    "",
    "Total input A records",
    "- Duplicate A records",
    "- A records already in iasWorld",
    "= Total unique A records",
    ""
  ),
  value = c(
    length(raw),
    length(raw) - length(raw_sa),
    length(raw_sa),
    length(raw_sa) - length(uniq_sa),
    n_ias_excluded[["total"]],
    nrow(output),
    "",
    type_n(raw_sa, "S"),
    type_n(raw_sa, "S") - type_n(uniq_sa, "S"),
    n_ias_excluded[["S"]],
    type_n(output$all_data, "S"),
    "",
    type_n(raw_sa, "A"),
    type_n(raw_sa, "A") - type_n(uniq_sa, "A"),
    n_ias_excluded[["A"]],
    type_n(output$all_data, "A"),
    ""
  ) %>%
    as.character()
)
cat(sprintf("%-36s %s\n", summary_rows$metric, summary_rows$value), sep = "")

a_unchanged <- identical(
  pre_truncation[substr(pre_truncation, 1, 1) == "A"],
  output$all_data[substr(output$all_data, 1, 1) == "A"]
)
cat(
  "Check: All A records are unchanged -",
  ifelse(a_unchanged, "TRUE", "FALSE")
)
cat("\n\n")

# Count per field of S records whose value changed during truncation
# `before` must hold the same records as `after` (post-exclusion,
# pre-truncation) so that the two lists align element by element
before <- strsplit(
  pre_truncation[substr(pre_truncation, 1, 1) == "S"], "|",
  fixed = TRUE
)
after <- strsplit(
  output$all_data[substr(output$all_data, 1, 1) == "S"], "|",
  fixed = TRUE
)
count_changed <- function(field_num) {
  mapply(
    function(x, y) {
      !is.na(x[field_num]) &&
        !identical(x[field_num], y[field_num])
    },
    before,
    after
  ) %>%
    sum()
}

truncation_report <- idor_map %>%
  inner_join(
    read_csv(CV_LENGTH_FILE, col_types = "ccci"),
    by = c("ias_table", "ias_col")
  ) %>%
  filter(data_type == "VARCHAR2") %>%
  select(idor_field_num, ias_table, ias_col, max_length = data_length) %>%
  mutate(
    idor_field_num = as.integer(str_remove(idor_field_num, "all_data_")),
    records_truncated = map_int(idor_field_num, count_changed)
  ) %>%
  filter(records_truncated > 0) %>%
  arrange(desc(records_truncated))

n_records <- sum(mapply(function(x, y) any(x != y), before, after))
n_fields <- truncation_report %>%
  distinct(idor_field_num, records_truncated) %>%
  pull(records_truncated) %>%
  sum()

summary_rows <- bind_rows(
  summary_rows,
  tibble(
    metric = c(
      "S records with at least one truncated field",
      "Total fields truncated (each IDOR field counted once)"
    ),
    value = as.character(c(n_records, n_fields))
  )
)
cat(
  sprintf(
    "%-55s %s\n",
    tail(summary_rows$metric, 2),
    tail(summary_rows$value, 2)
  ),
  sep = ""
)
cat("\n")
print(as.data.frame(truncation_report), row.names = FALSE)

# Write the summary and truncation counts (with caveats beside them) to sheets
report_file <- file.path(
  "output",
  glue("cleaned_sales_{Sys.Date()}_report.xlsx")
)
notes <- tibble(
  note = c(
    paste(
      "Field 11 (CVLEG ZIP1) is ZIP+4 being cut to 5 digits",
      "(e.g. 606170000 -> 60617), so it affects every S record and is expected."
    ),
    paste(
      "Fields 115 and 120 are mostly long names and 'name - company' strings",
      "cut at 40 characters."
    ),
    if (a_unchanged) "Only S records are truncated; A records are unchanged."
  )
)
# Values are stored as text for console printing, so convert them to integers
# (blank spacer rows become empty cells) for the workbook
sheets <- list(
  summary = mutate(summary_rows, value = as.integer(value)),
  truncation = truncation_report
)
comma_col <- c(summary = "value", truncation = "records_truncated")
header_style <- createStyle(textDecoration = "bold")
comma_style <- createStyle(numFmt = "#,##0")

wb <- createWorkbook()
iwalk(sheets, \(df, sheet) {
  addWorksheet(wb, sheet)
  writeData(wb, sheet, df, headerStyle = header_style)
  if (sheet %in% names(comma_col)) {
    addStyle(
      wb, sheet, comma_style,
      rows = seq_len(nrow(df)) + 1,
      cols = match(comma_col[[sheet]], names(df)),
      gridExpand = TRUE, stack = TRUE
    )
  }
  setColWidths(wb, sheet, cols = seq_along(df), widths = "auto")
})

# Notes sit three columns right of the truncation table to keep them separate
writeData(
  wb, "truncation", notes,
  startCol = ncol(truncation_report) + 3, headerStyle = header_style
)

# Metric value column needs to be a touch wider to show integers properly
setColWidths(wb, "summary", cols = 2, widths = 7)

saveWorkbook(wb, report_file, overwrite = TRUE)
cat("\nWrote", report_file, "\n")
