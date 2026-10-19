## Prototype: OSM PBF -> NYC-clipped, Hilbert-sorted GeoParquet via GDAL and
## DuckDB. A reference for the nycosm build script, not the build itself.
##
## Steps:
## 1. ogr2ogr converts the PBF to GeoPackage (NYC bbox only). GDAL's OSM
##   driver keeps closed-way polygons. DuckDB's ST_Read() on the PBF loses
##   them (see the note at the end).
## 2. DuckDB clips each layer to the borough boundary (500 ft buffer), sorts
##   by ST_Hilbert(), and writes zstd GeoParquet.
## 3. Rows come back into sf through WKB (the GDAL in sf has no Parquet
##   driver).
##
## Output goes to a temporary directory. Run from this folder:
## R --quiet -f prototype/prototype-osm-geoparquet.R

library(tidyverse)
library(here)
library(DBI)

pbf <- here("data", "new-york-261018.osm.pbf")
osmconf <- file.path(system.file("gdal", package = "sf"), "osmconf.ini")
out_dir <- file.path(tempdir(), "osm-prototype")
gpkg <- file.path(out_dir, "nyc_bbox.gpkg")
layers <- c(
  "points",
  "lines",
  "multilinestrings",
  "multipolygons",
  "other_relations"
)

dir.create(out_dir, showWarnings = FALSE)

## Helpers ----------------------------------------------------------------------

# Clip with ST_Intersects against one complex boundary polygon: 1-3 min per
# large layer. For the build, subdividing the boundary (e.g. one polygon per
# borough, which also gives the borough column) should be faster.
write_layer <- function(con, layer) {
  out <- file.path(out_dir, paste0(layer, ".parquet"))
  start <- Sys.time()
  dbExecute(
    con,
    paste0(
      "COPY (SELECT t.* EXCLUDE (fid, geom), t.geom AS geometry FROM ST_Read('",
      gpkg,
      "', layer = '",
      layer,
      "') t, nyc WHERE ST_Intersects(t.geom, nyc.g) ",
      "ORDER BY ST_Hilbert(t.geom, ST_Extent(nyc.g))) TO '",
      out,
      "' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000)"
    )
  )
  tibble(
    layer = layer,
    n = dbGetQuery(con, paste0("SELECT count(*) AS n FROM '", out, "'"))$n,
    mb = round(file.size(out) / 1e6, 1),
    secs = round(as.numeric(Sys.time() - start, units = "secs"))
  )
}

## 1. PBF -> GeoPackage ---------------------------------------------------------

# About one minute for the state file.
system2(
  "ogr2ogr",
  c(
    "-f GPKG",
    "-overwrite",
    shQuote(gpkg),
    shQuote(pbf),
    "-spat -74.26 40.49 -73.69 40.92",
    "-oo",
    paste0("CONFIG_FILE=", shQuote(osmconf)),
    "-gt 65536"
  )
)

## 2. Clip, sort, write GeoParquet ---------------------------------------------

con <- dbConnect(duckdb::duckdb(shared_home = FALSE))
dbExecute(con, "INSTALL spatial; LOAD spatial")

nyc_boundary <- nycmaps::nyc_boros_sf |>
  sf::st_union() |>
  sf::st_buffer(500) |>
  sf::st_transform(4326)

dbExecute(
  con,
  paste0(
    "CREATE TABLE nyc AS SELECT ST_GeomFromText('",
    sf::st_as_text(nyc_boundary),
    "') AS g"
  )
)

results <- layers |>
  map(\(layer) write_layer(con, layer)) |>
  list_rbind()

print(results)

# Spatial filter on the sorted file: lower Manhattan.
dbGetQuery(
  con,
  paste0(
    "SELECT count(*) AS n FROM '",
    file.path(out_dir, "multipolygons.parquet"),
    "' WHERE ST_Intersects(geometry, ST_MakeEnvelope(-74.01, 40.70, -73.97, 40.73))"
  )
)

# GeoParquet metadata written by DuckDB.
dbGetQuery(
  con,
  paste0(
    "SELECT key, left(decode(value), 200) AS value FROM parquet_kv_metadata('",
    file.path(out_dir, "points.parquet"),
    "')"
  )
)

## 3. Back into sf through WKB --------------------------------------------------

# The default osmconf.ini has no amenity column on points, so match the tag
# text in other_tags. A tags MAP column in the package removes the need.

pts <- dbGetQuery(
  con,
  paste0(
    "SELECT osm_id, name, ST_AsWKB(geometry) AS geometry FROM '",
    file.path(out_dir, "points.parquet"),
    "' WHERE other_tags LIKE '%\"amenity\"=>\"library\"%'"
  )
)
pts$geometry <- sf::st_as_sfc(
  structure(pts$geometry, class = "WKB"),
  crs = 4326
)
pts <- sf::st_as_sf(pts)
print(pts)

dbDisconnect(con)

## Note: reading the PBF directly with DuckDB -----------------------------------
##
## ST_Read('<pbf>', layer = 'multipolygons') fails with "Could not parse
## configuration file for OSM import" unless given
## open_options = ['CONFIG_FILE=<osmconf.ini>']. With that option, points,
## lines, multilinestrings, and other_relations match GDAL's counts, but
## multipolygons has only relation-based polygons (2,298 vs 1.29M in NYC
## with the BBBike extract): every closed way, including nearly all
## buildings, is lost. ST_ReadOSM('<pbf>') reads raw nodes, ways, and
## relations with full tag MAPs (kind, id, tags, refs, lat, lon, ...). Use
## it for the tags, not the geometry.
