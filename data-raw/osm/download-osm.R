## Stage raw data for an OpenStreetMap (OSM) package.
##
## - Downloads a dated Geofabrik extract of New York State (PBF) and its MD5
##   checksum, and verifies the checksum.
## - Downloads the extract's boundary polygon and replication state file.
##
## Geofabrik keeps dated daily snapshots for a limited time. To refresh, set
## `extract_date` to a date listed on the region page.
##
## Records every file in download-log.csv.
## Run from this folder: R --quiet -f download-osm.R

library(tidyverse)
library(here)

root <- here::here()
user_agent <- "Mozilla/5.0 (nycosm data download)"
extract_date <- "261018"
geofabrik <- "https://download.geofabrik.de/north-america/us"
pbf_name <- paste0("new-york-", extract_date, ".osm.pbf")

dir.create(file.path(root, "data"), showWarnings = FALSE)
dir.create(file.path(root, "docs"), showWarnings = FALSE)

## Download helper ------------------------------------------------------------

fetch <- function(source, url, dest) {
  status <- tryCatch(
    {
      download.file(
        url,
        dest,
        mode = "wb",
        quiet = TRUE,
        method = "libcurl",
        headers = c("User-Agent" = user_agent)
      )
      "ok"
    },
    error = \(e) conditionMessage(e)
  )
  tibble(
    source = source,
    url = url,
    file = str_remove(dest, paste0("^", root, "/")),
    status = status,
    bytes = if (file.exists(dest)) file.size(dest) else NA_real_,
    downloaded = Sys.time()
  )
}

## Downloads ------------------------------------------------------------------

downloads <- tribble(
  ~url                                               , ~dest                          ,
  file.path(geofabrik, pbf_name)                     , file.path("data", pbf_name)    ,
  file.path(geofabrik, paste0(pbf_name, ".md5"))     ,
  file.path("data", paste0(pbf_name, ".md5"))        ,
  file.path(geofabrik, "new-york.poly")              , "docs/new-york.poly"           ,
  file.path(geofabrik, "new-york-updates/state.txt") ,
  "docs/geofabrik_state.txt"                         ,
  file.path(geofabrik, "new-york.html")              , "docs/geofabrik_new-york.html"
) |>
  mutate(source = "Geofabrik", dest = file.path(root, dest))

options(timeout = 3600)

download_log <- downloads |>
  pmap(fetch) |>
  bind_rows()

md5_expected <- read_lines(file.path(root, "data", paste0(pbf_name, ".md5"))) |>
  str_extract("^[0-9a-f]{32}")
md5_actual <- unname(tools::md5sum(file.path(root, "data", pbf_name)))

if (!identical(md5_expected, md5_actual)) {
  cli::cli_abort(
    "MD5 mismatch for {.file {pbf_name}}: expected {md5_expected}, got {md5_actual}."
  )
}

download_log <- download_log |>
  mutate(md5 = if_else(file == file.path("data", pbf_name), md5_actual, NA))

write_csv(download_log, file.path(root, "download-log.csv"))
print(select(download_log, file, status, bytes), n = Inf)
