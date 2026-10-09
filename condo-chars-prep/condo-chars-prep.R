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
AWS_ATHENA_CONN_NOCTUA <- dbConnect(noctua::athena(), rstudio_conn_tab = FALSE)

# Triad we want to deliver condos for
tri <- "City"

# Oldest year for which to include sales and permits
min_year <- "2024"

# DATA ----

# Retrieve condos and their statuses
condos <- dbGetQuery(
  conn = AWS_ATHENA_CONN_NOCTUA,
  glue(read_file("condos.sql"))
) %>%
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
  rename_with(~ str_replace_all(.x, c("Pin" = "PIN", "Sf" = "SF", "Qc" = "QC")))

# Formatting and output
output <- condos %>%
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
    operator = "between", value = c(0, 10000000)
  )

  dataValidation(
    wb, x,
    cols = 10, rows = 2:nrow(output[[x]]),
    type = "whole",
    operator = "between", value = c(0, 10000)
  )

  dataValidation(
    wb, x,
    cols = c(12, 14, 16), rows = 2:nrow(output[[x]]),
    type = "whole",
    operator = "between", value = c(0, 15)
  )

  dataValidation(
    wb, x,
    cols = 19, rows = 2:nrow(output[[x]]),
    type = "list",
    value = '"TRUE,FALSE"'
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
    c(seq(8, 16, 2), 19),
    ~ addStyle(wb, x, unlocked,
      cols = .x,
      rows = seq(2, nrow(output[[x]]) + 1, 1)
    )
  )
  addFilter(wb, x, rows = 1, cols = seq_len(ncol(output[[x]])))
  freezePane(wb, x, firstRow = TRUE)

  # Calculate widths dynamically: Max length of data vs length of headers
  header_widths <- nchar(names(output[[x]])) + 2
  data_widths <- apply(
    output[[x]], 2, function(x) max(nchar(as.character(x)), na.rm = TRUE)
  )

  # Use pmax to get the largest value per column
  calculated_widths <- pmax(header_widths, data_widths)

  setColWidths(
    wb, x,
    cols = seq_len(ncol(output[[x]])), widths = calculated_widths
  )
  setColWidths(wb, x, cols = c(1, 4, 21), widths = c(50, 50, 50))
  setColWidths(wb, x, cols = 2, widths = 13)
})

directions <- tibble(
  `QC Flag` = c(
    "For ALL flags",
    "More than 2 Half Baths",
    "More than 4 Full Baths",
    "More than 4 Bedrooms",
    "Unit SF not between 300 and 5,000",
    "Unit SF exceeds building SF",
    "Building SF not between 2,500 and 500,000",
    "Combined Unit SF for all units in PIN10 exceeds Building SF",
    "Multiple Building SF values for same PIN10",
    "Building has no livable units",
    "Year Built not between 1880 and 2026",
    "Parking space has non-null characteristics"
  ),
  Directions = c(
    # nolint start: line_length_linter
    "You ONLY need to input new data if something you see needs to be changed for a unit. If everything already looks good, there's no need to enter any new data for that unit.",
    "Check the number of half baths for the unit. If there are more than 2 half baths, please confirm that this is correct. If it is, no action is needed. If it is not, please update the number of half baths for the unit.",
    "Check the number of full baths for the unit. If there are more than 4 full baths, please confirm that this is correct. If it is, no action is needed. If it is not, please update the number of full baths for the unit.",
    "Check the number of bedrooms for the unit. If there are more than 4 bedrooms, please confirm that this is correct. If it is, no action is needed. If it is not, please update the number of bedrooms for the unit.",
    "Check the square footage for the unit. If the unit has a square footage less than 300 or greater than 5,000, please confirm that this is correct. If it is, no action is needed. If it is not, please update the square footage for the unit.",
    "Check the square footage for the unit and check the building square footage. Unit square footage should not exceed the building square footage.",
    "Check the building square footage. If the building has a square footage less than 2,500 or greater than 500,000, please confirm that this is correct. If it is, no action is needed. If it is not, please update the building square footage.",
    "Check the combined square footage for all units in each PIN10. Combined unit SF should not exceed the building square footage.",
    "Check for multiple building square footage values for the same PIN10. Buildings should only have one square footage value.",
    "Check if the building has any livable units. If not, please confirm that this is correct. If it is, no action is needed. If it is not, please update the building to have at least one livable unit.",
    "Check the year built for the building. If it's correct no action is needed. If it is not, please update the year built for the building.",
    "Check the unit's characteristics. If there are any non-null characteristics (beds, baths, unit SF), please determine if the parking space designation is correct. If it is, please update the relevant characteristics. If it is not, please update the unit's parking space designation."
    # nolint end: line_length_linter
  )
)

# Add directions as the first worksheet.
addWorksheet(wb, "Directions")
writeData(wb, "Directions", directions)
worksheetOrder(wb) <- c(
  length(wb$sheet_names), seq_len(length(wb$sheet_names) - 1)
)
setColWidths(wb, "Directions", cols = 1:2, widths = "auto")
addStyle(
  wb, "Directions", createStyle(wrapText = TRUE),
  rows = 1:(nrow(directions) + 1), cols = 1:2, gridExpand = TRUE
)
addStyle(
  wb, "Directions", createStyle(textDecoration = "bold"),
  rows = 1, cols = 1:2, stack = TRUE
)
addStyle(
  wb, "Directions", createStyle(textDecoration = "italic"),
  rows = 2, cols = 1:2, stack = TRUE
)
activeSheet(wb) <- length(sheets(wb))

# Export
saveWorkbook(
  wb,
  glue(file.path(
    path, "output/{str_to_lower(tri)}_condo_review_{year(Sys.Date())}.xlsx"
  )),
  overwrite = TRUE
)
