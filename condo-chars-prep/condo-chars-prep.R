# See https://github.com/ccao-data/enterprise-intelligence/issues/156
library(arrow)
library(ccao)
library(dplyr)
library(glue)
library(lubridate)
library(noctua)
library(openxlsx)
library(readr)
library(purrr)
library(scales)
library(stringr)
library(tidyr)

path <- "O:/CCAODATA/recurring-data-requests/condo-chars-prep"

# Connect to Athena
noctua_options(unload = TRUE)
AWS_ATHENA_CONN_NOCTUA <- dbConnect(
        noctua::athena(), rstudio_conn_tab = FALSE)

# Triad we want to deliver condos for
tri <- "South"

# Oldest year for which to include sales and permits
min_year <- "2022"

# DATA ----

# Gather previously identified problematic unit-level flags
condo_qc <- read.xlsx(file.path(path, "input/Flagged_Condos.xlsx"), sheet = 1) %>%
  mutate(pin = gsub("-", "", `14-Digit.PIN`)) %>%
  select(c("PIN" = "pin", "QC Flag" = "Flag.Comments"))

# Retrieve condos and their statuses
condos <- dbGetQuery(
  conn = AWS_ATHENA_CONN_NOCTUA,
  glue(read_file("condos.sql"))
) %>%
  # Only keep buildings that have a unit with a QC flag
  filter(substr(pin, 1, 10) %in% substr(condo_qc$PIN, 1, 10)) %>%
  mutate(
    address = str_replace_all(address, "[^[:alnum:]]", " "),
    # Hyperlinks for google search and nearmap
    address = paste0(
      '=HYPERLINK("https://www.google.com/search?q=',
      address,
      '", "',
      address,
      '")'
    ),
    across(where(is.character), ~ na_if(.x, "")),
    pin10 = paste0(
      '=HYPERLINK("https://maps.cookcountyil.gov/nearmapOpenlayers/?map=19.00/',
      lon, "/", lat, "/0&pin10=", pin10,
      '", "',
      pin_format_pretty(pin10),
      '")'
    )
  ) %>%
  # Aggregate sales and permits by PIN using mutate since there are too many
  # columns that would need to be preserved using summarize.
  mutate(
    across(c(sales, permits), ~ paste(na.omit(.x), collapse = ", ")),
    .by = pin
  ) %>%
  mutate(across(c(sales, permits), ~ na_if(.x, ""))) %>%
  # We use distinct here because we aggregated all sales and permits per pin
  # using mutate rather than summarize. Sales and permits are the only source of
  # duplicate pins.
  distinct(pin, .keep_all = TRUE) %>%
  rename_with(~ str_to_title(gsub("_", " ", .x))) %>%
  rename_with(~ str_replace_all(.x, c("Pin" = "PIN", "Sf" = "SF")))

# Formatting and output
output <- condos %>%
  left_join(condo_qc) %>%
  mutate(PIN = ccao::pin_format_pretty(PIN, full_length = TRUE)) %>%
  relocate("QC Flag") %>%
  relocate(c("Permits", "Sales"), .after = "Neighborhood Code") %>%
  arrange(PIN) %>%
  split(.$Township) %>%
  map(function(x) {
    class(x$PIN10) <- c(class(x$PIN10), "formula")
    class(x$Address) <- c(class(x$Address), "formula")
    x %>% select(-c(Township, Lon, Lat))
  })

# OUTPUT ----

# Create styles
hyperlink <- createStyle(
  fontColour = "#4F81BD",
  textDecoration = c("underline")
)

unlocked <- createStyle(locked = FALSE)

# Create workbook using list of townships
wb <- output %>%
  buildWorkbook()

# Apply data validation and styles to each sheet in the workbook
walk(wb$sheet_names, function(x) {
  protectWorksheet(wb, x,
    lockAutoFilter = FALSE, lockSorting = FALSE,
    lockFormattingColumns = FALSE
  )

  # Add data validation to workbook
  dataValidation(
    wb, x,
    cols = 8, rows = 2:nrow(output[[x]]),
    type = "whole",
    operator = "between", value = c(0, 10000000), allowBlank = TRUE
  )

  dataValidation(
    wb, x,
    cols = 10, rows = 2:nrow(output[[x]]),
    type = "whole",
    operator = "between", value = c(0, 10000), allowBlank = TRUE
  )

  dataValidation(
    wb, x,
    cols = c(12, 14, 16), rows = 2:nrow(output[[x]]),
    type = "whole",
    operator = "between", value = c(0, 15), allowBlank = TRUE
  )

  # Add styling to and modify protection for workbook
  walk(
    c(2, 4),
    ~ addStyle(wb, x, hyperlink,
      cols = .x,
      rows = seq(2, nrow(output[[x]]) + 1, 1)
    )
  )
  walk(
    c(seq(8, 16, 2)),
    ~ addStyle(wb, x, unlocked,
      cols = .x,
      rows = seq(2, nrow(output[[x]]) + 1, 1)
    )
  )
  addFilter(wb, x, rows = 1, cols = seq_len(ncol(output[[x]])))
  freezePane(wb, x, firstRow = TRUE)
  setColWidths(wb, x, cols = seq_len(ncol(output[[x]])), widths = "auto")
})

# Export
saveWorkbook(
  wb,
  glue(file.path(path, "output/{str_to_lower(tri)}_condo_review_{year(Sys.Date())}.xlsx")),
  overwrite = TRUE
)
