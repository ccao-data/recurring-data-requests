# See https://github.com/ccao-data/enterprise-intelligence/issues/254

# Setup ----

library(arrow)
library(ccao)
library(colorspace)
library(DBI)
library(dplyr)
library(ggplot2)
library(ggspatial)
library(noctua)
library(openxlsx)
library(prettymapr)
library(readr)
library(purrr)
library(scales)
library(stringr)
library(sf)
library(tidyr)

noctua_options(unload = TRUE)

AWS_ATHENA_CONN_NOCTUA <- dbConnect(noctua::athena(), rstudio_conn_tab = FALSE)

# These files live on the O drive in CCAODATA/desk_review_ratio_curves/. Since
# that isn't accessible from the server they need to be copied locally or run
# from a local machine. They MUST be named according to the current naming
# scheme, and there must be PIN and Desk Review Value columns
data_path <- "O:/CCAODATA/recurring_data_requests/provisional_ratio_curves"
input_path <- file.path(data_path, "input_data")
output_path <- file.path(data_path, "output_data")
files_in <- list.files(input_path, full.names = TRUE)

# Flatfile ----

# Read in desk review workbooks, keep PIN and Desk Review Value columns.
dr_vals <- map(files_in, \(x) {
  read.xlsx(x, sheet = 1) %>%
    tibble(.name_repair = "unique") %>%
    select(
      pin = PIN,
      desk_review_value = Desk.Review.Value
    )
}) %>%
  bind_rows()

# This SQL query will return townships, neighborhoods, and model values for
# every PIN, as well as any associated sales used for training
model_vals <- dbGetQuery(
  conn = AWS_ATHENA_CONN_NOCTUA, read_file("provisional-ratio-curves.sql")
)

# Attach dr and model values to calculate ratios
all_ratios <- dr_vals %>%
  left_join(model_vals)

walk(unique(all_ratios$township_name), \(x) {
  # Construct list for outputting multisheet .xlsx
  output <- list()
  output$`All Parcels` <- all_ratios %>%
    filter(township_name == x) %>%
    select(-township_name) %>%
    mutate(
      price_decile = ntile(sale_price, 10),
      model_sale_ratio = model_value / sale_price,
      desk_review_sale_ratio = desk_review_value / sale_price
    )

  # Summarize ratios and price ranges by decile for .xlsx output
  output$`Ratio Deciles` <- output$`All Parcels` %>%
    filter(!is.na(sale_price)) %>%
    summarize(
      model_ratio = median(model_sale_ratio),
      model_cod = assessr::cod(model_sale_ratio),
      desk_review_ratio = median(desk_review_sale_ratio),
      desk_review_cod = assessr::cod(desk_review_sale_ratio),
      price_range = paste(
        scales::dollar(min(sale_price)),
        scales::dollar(max(sale_price)),
        sep = "-"
      ),
      number_of_sales = n(),
      .by = price_decile
    ) %>%
    arrange(price_decile) %>%
    mutate(across(model_ratio:desk_review_cod, ~ round(.x, digits = 6))) %>%
    rename_with(~ str_to_title(gsub("_", " ", .x)))

  # Calculate vertical equity metrics for .xlsx output
  output$`Town-Level Stats` <- output$`All Parcels` %>%
    filter(!is.na(sale_price)) %>%
    summarize(
      model_ratio = median(model_sale_ratio),
      model_cod = assessr::cod(model_sale_ratio),
      model_prd = assessr::prd(model_value, sale_price),
      model_prb = assessr::prb(model_value, sale_price),
      model_mki = assessr::mki(model_value, sale_price),
      desk_review_ratio = median(desk_review_sale_ratio),
      desk_review_cod = assessr::cod(desk_review_sale_ratio),
      desk_review_prd = assessr::prd(desk_review_value, sale_price),
      desk_review_prb = assessr::prb(desk_review_value, sale_price),
      desk_review_mki = assessr::mki(desk_review_value, sale_price),
      price_range = paste(
        scales::dollar(min(sale_price)),
        scales::dollar(max(sale_price)),
        sep = "-"
      ),
      number_of_sales = n()
    ) %>%
    mutate(across(model_ratio:desk_review_mki, ~ round(.x, digits = 6))) %>%
    rename_with(~ str_to_title(gsub("_", " ", .x)))

  output$`All Parcels` <- output$`All Parcels` %>%
    rename_with(~ str_to_title(gsub("_", " ", .x)))

  output %>%
    write.xlsx(file.path(output_path, paste0(gsub(" ", "_", x), ".xlsx")))

  # Pivot decile data for graph
  decile_ratios <- output$`Ratio Deciles` %>%
    select(`Price Decile`, `Model Ratio`, `Desk Review Ratio`) %>%
    pivot_longer(
      cols = c("Model Ratio", "Desk Review Ratio"),
      names_to = "Stage",
      values_to = "Sale Ratio"
    )

  # Graph ----

  # Create ratio curves for both stages
  # Compute dynamic y-axis range
  y_min <- min(decile_ratios$`Sale Ratio`, 0.7, na.rm = TRUE)
  y_max <- max(decile_ratios$`Sale Ratio`, 1.3, na.rm = TRUE)

  ggplot(decile_ratios, aes(
    x = `Price Decile`,
    y = `Sale Ratio`,
    group = Stage,
    color = Stage,
    label = round(`Sale Ratio`, 2)
  )) +
    # IAAO dotted range
    geom_hline(yintercept = 1, color = "darkgreen", linewidth = 1) +
    geom_hline(yintercept = 0.9, linetype = "dotted", color = "black", linewidth = 0.8) +
    geom_hline(yintercept = 1.1, linetype = "dotted", color = "black", linewidth = 0.8) +
    annotate(
      "text",
      x = 1, y = 1.11,
      label = "IAAO Range (0.9 - 1.1)",
      hjust = 0,
      vjust = -0.5,
      size = 4
    ) +
    geom_line(linewidth = 1) +
    geom_label(show.legend = FALSE) +
    theme_minimal() +
    coord_cartesian(ylim = c(y_min, y_max)) +
    scale_y_continuous(breaks = seq(floor(y_min * 10) / 10, ceiling(y_max * 10) / 10, by = 0.1)) +
    scale_x_continuous(breaks = seq(1, 10, by = 1)) +
    ggtitle(
      label = paste0("Sale Ratios for ", x, " Township"),
      subtitle = "Model and Desk Review Values"
    )

  ggsave(
    file.path(output_path, paste0(gsub(" ", "_", x), "_ratio_curve.png")),
    bg = "white"
  )

  # Maps ----

  # Gather neighborhood polygons
  neighborhoods <- ccao::nbhd_shp %>%
    filter(township_name == x) %>%
    select(town_nbhd, geometry)

  map_data <- output$`All Parcels` %>%
    select(
      `Neighborhood Number`,
      `Model Sale Ratio`,
      `Desk Review Sale Ratio`
    ) %>%
    summarize(
      `Model` = median(`Model Sale Ratio`, na.rm = TRUE),
      `Desk Review` = median(`Desk Review Sale Ratio`, na.rm = TRUE),
      .by = `Neighborhood Number`
    ) %>%
    pivot_longer(
      cols = c("Desk Review", "Model"),
      names_to = "Stage",
      values_to = "Median Sale Ratio"
    ) %>%
    mutate(
      Stage = factor(Stage, levels = c("Model", "Desk Review")),
      `Neighborhood Number` = gsub("-", "", `Neighborhood Number`)
    ) %>%
    left_join(neighborhoods, c("Neighborhood Number" = "town_nbhd")) %>%
    st_as_sf(crs = 4326)

  ggplot() +
    annotation_map_tile(type = "cartolight", zoomin = 0) +
    geom_sf(
      data = map_data,
      aes(fill = `Median Sale Ratio`),
      alpha = 0.8,
      linewidth = 0.1
    ) +
    scale_fill_continuous_diverging(
      palette = "Purple-Green", mid = 1, rev = TRUE, alpha = 0.8
    ) +
    theme_void() +
    labs(fill = "Median Ratio") +
    facet_grid(cols = vars(Stage)) +
    theme(strip.text.x = element_text(size = 14))

  ggsave(
    file.path(output_path, paste0(gsub(" ", "_", x), "_map.png")),
    bg = "white"
  )
})
