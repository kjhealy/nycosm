## Build data objects

# Remove the GeoParquet files in inst/extdata and regenerate them
fs::dir_ls(here::here("inst", "extdata"), glob = "*.parquet") |>
  fs::file_delete()

# Build the OSM layers
source(here::here("data-raw", "osm.R"))
