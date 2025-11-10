# See https://github.com/ccao-data/enterprise-intelligence/issues/153
library(dplyr)
library(glue)
library(noctua)
library(openxlsx)
library(purrr)
library(stringr)

# Connect to Athena
AWS_ATHENA_CONN_NOCTUA <- dbConnect(noctua::athena(), rstudio_conn_tab = FALSE)

# Declare year for CCAO mailed values we'd like to compare to prior year BOR
# certified values
mail_year <- 2025

# All output files will be named the same as their corresponding input file, but
# placed in the output folder. The script only assumes there will be an input
# column named "Permanent Index Number".

input <- "O:/CCAODATA/recurring-data-requests/ahsap-avs/input"

# Loop through all input files provided by valuations
map(list.files(input, full.names = TRUE), \(x) {
  # Ingest provided PINs
  ahsap_parcels <- read.xlsx(x, sheet = 1) %>%
    mutate(pin = gsub("-", "", str_trim(Permanent.Index.Number)))

  # Retrieve values for PINs from Athena
  changes <- dbGetQuery(
    conn = AWS_ATHENA_CONN_NOCTUA,
    glue_sql(
      "
      SELECT
        hist.pin,
        hist.class AS Class,
        hist.twoyr_pri_certified_tot AS \"{mail_year - 2}.BoR.Certified.AV\",
        hist.oneyr_pri_certified_tot AS \"{mail_year - 1}.BoR.Certified.AV\",
        hist.mailed_tot AS \"{mail_year}.Mailed.AV\",
        CAST((hist.mailed_tot - hist.oneyr_pri_certified_tot) AS double) /
          CAST(hist.oneyr_pri_certified_tot AS double) AS \"Percent.Change\",
        -- Construct large increase indicator
        hist.mailed_tot > hist.oneyr_pri_certified_tot * 1.2
          AS \"Large.Increase\"
      FROM default.vw_pin_history AS hist
      WHERE hist.pin IN ({vals*})
        AND hist.year = '{mail_year}'
      ",
      vals = ahsap_parcels$pin,
      .con = AWS_ATHENA_CONN_NOCTUA
    )
  )

  # Join input and AVs, write output
  left_join(ahsap_parcels, changes, by = "pin") %>%
    select(-pin) %>%
    rename_with(~ gsub("\\.", " ", .x), .cols = everything()) %>%
    write.xlsx(gsub("input", "output", x))
})
