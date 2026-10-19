## nyc_osm_* — OpenStreetMap layers for NYC, written to GeoParquet
##
## 1. ogr2ogr converts the New York State PBF to GeoPackage within the NYC
##    bounding box, using data-raw/osmconf.ini to choose the tag columns.
##    (DuckDB's ST_Read() on the PBF loses closed-way polygons.)
## 2. DuckDB transforms each layer to EPSG:2263, keeps features within 500
##    ft of a borough, assigns the borough containing each feature's point on
##    surface, adds the complete tags from ST_ReadOSM(), sorts by Hilbert
##    index, and writes zstd GeoParquet.
##
## Polygons are split into buildings (any `building` tag) and other areas,
## and buildings are written as one file per borough, so that each file stays
## well under GitHub's 100 MB file limit.
##
## Requires GDAL's ogr2ogr and the DuckDB spatial extension at build time.

source(here::here("data-raw", "_source.R"))

# -- Configuration -----------------------------------------------------------
nyc_bbox <- c(-74.26, 40.49, -73.69, 40.92)
buffer_ft <- 500
grid_ft <- 5000
gpkg <- here("tmp", "nyc_bbox.gpkg")
out_dir <- here("inst", "extdata")
fs::dir_create(c(out_dir, here("tmp")))

# Tag columns kept in each output, as named by GDAL (":" becomes "_").
point_cols <- c(
  "name",
  "amenity",
  "shop",
  "cuisine",
  "highway",
  "public_transport",
  "railway",
  "leisure",
  "tourism",
  "natural",
  "barrier",
  "man_made",
  "office",
  "craft",
  "healthcare",
  "emergency",
  "historic",
  "place",
  "brand",
  "operator",
  "opening_hours",
  "website",
  "phone",
  "wheelchair",
  "addr_housenumber",
  "addr_street",
  "addr_postcode",
  "ref",
  "wikidata"
)

line_cols <- c(
  "name",
  "highway",
  "service",
  "footway",
  "cycleway",
  "surface",
  "lanes",
  "maxspeed",
  "oneway",
  "bridge",
  "tunnel",
  "layer",
  "railway",
  "waterway",
  "barrier",
  "access",
  "bicycle",
  "foot",
  "ref",
  "wikidata"
)

building_cols <- c(
  "name",
  "building",
  "building_levels",
  "height",
  "nycdoitt_bin",
  "addr_housenumber",
  "addr_street",
  "addr_postcode",
  "amenity",
  "shop",
  "leisure",
  "tourism",
  "historic",
  "man_made",
  "office",
  "wikidata"
)

area_cols <- c(
  "name",
  "amenity",
  "shop",
  "leisure",
  "landuse",
  "natural",
  "water",
  "tourism",
  "historic",
  "sport",
  "man_made",
  "office",
  "boundary",
  "admin_level",
  "aeroway",
  "military",
  "place",
  "addr_housenumber",
  "addr_street",
  "addr_postcode",
  "wikidata"
)

route_cols <- c(
  "name",
  "route",
  "ref",
  "network",
  "operator",
  "colour",
  "wikidata"
)

# -- 1. PBF to GeoPackage ----------------------------------------------------
if (!fs::file_exists(gpkg)) {
  status <- system2(
    "ogr2ogr",
    c(
      "-f GPKG",
      "-overwrite",
      shQuote(gpkg),
      shQuote(pbf),
      "-spat",
      nyc_bbox,
      "-oo",
      paste0("CONFIG_FILE=", shQuote(osmconf)),
      "-lco GEOMETRY_NAME=geometry",
      "-gt 65536",
      "points lines multilinestrings multipolygons"
    )
  )
  if (status != 0) {
    cli::cli_abort("{.code ogr2ogr} failed with status {status}.")
  }
}

# -- 2. DuckDB ---------------------------------------------------------------
con <- dbConnect(duckdb())
dbExecute(con, "INSTALL spatial")
dbExecute(con, "LOAD spatial")

# Borough boundaries (EPSG:2263) cut into grid cells, so that each
# point-in-polygon test is against a small polygon: `clip` is the buffered
# city outline, `boros` the unbuffered boroughs. Passed to DuckDB as WKB to
# keep full coordinate precision.
boros_sf <- nycmaps::nyc_boros_sf |>
  select(borough = boro_name)

clip_sf <- boros_sf |>
  st_buffer(buffer_ft) |>
  st_union() |>
  st_sf(geometry = _)

grid <- st_make_grid(clip_sf, cellsize = grid_ft) |>
  st_sf(geometry = _)

register_wkb <- function(x, name) {
  df <- st_drop_geometry(x)
  df$wkb <- st_as_binary(st_geometry(x))
  duckdb_register(con, name, df)
}

register_wkb(st_intersection(clip_sf, grid), "clip_wkb")
register_wkb(st_intersection(boros_sf, grid), "boros_wkb")

dbExecute(
  con,
  "CREATE TABLE clip AS SELECT ST_GeomFromWKB(wkb) AS g FROM clip_wkb"
)
dbExecute(
  con,
  "CREATE TABLE boros AS SELECT borough, ST_GeomFromWKB(wkb) AS g FROM boros_wkb"
)
hilbert_box <- "(SELECT ST_Extent(ST_Union_Agg(g)) FROM clip)"

# Complete tags by element type and ID.
dbExecute(
  con,
  paste0(
    "
  CREATE TABLE osm_tags AS
  SELECT kind AS osm_type, id AS osm_id, tags
  FROM ST_ReadOSM('",
    pbf,
    "')
  WHERE cardinality(tags) > 0
"
  )
)

quote_cols <- function(cols, prefix = "f.") {
  paste0(prefix, "\"", cols, "\"", collapse = ", ")
}

# Read a GeoPackage layer, project it, and keep features near the city.
stage_layer <- function(layer, type_sql, id_sql, where = "TRUE") {
  dbExecute(
    con,
    paste0(
      "
    CREATE OR REPLACE TABLE staged AS
    WITH f AS (
      SELECT
        * EXCLUDE (osm_id),
        ",
      type_sql,
      " AS osm_type,
        CAST(",
      id_sql,
      " AS BIGINT) AS osm_id,
        ST_Transform(geometry, 'EPSG:4326', 'EPSG:2263', always_xy := true)
          AS g
      FROM ST_Read('",
      gpkg,
      "', layer = '",
      layer,
      "')
      WHERE ",
      where,
      "
    )
    SELECT f.*
    FROM f
    JOIN clip c ON ST_Intersects(f.g, c.g)
    QUALIFY row_number() OVER (PARTITION BY f.osm_type, f.osm_id) = 1
  "
    )
  )
}

# Borough for each staged feature: the borough containing a point on its
# surface. For polygons (`by_area = TRUE`) that touch more than one
# borough, the borough holding the largest share of the polygon's area
# instead, since a surface point can fall in a small part of a large
# polygon. Areas are summed over the grid pieces of each borough.
assign_boroughs <- function(by_area = FALSE) {
  dbExecute(
    con,
    "
    CREATE OR REPLACE TABLE feature_borough AS
    SELECT f.osm_type, f.osm_id, b.borough
    FROM staged f
    JOIN boros b ON ST_Intersects(
      COALESCE(TRY(ST_PointOnSurface(f.g)), ST_Centroid(f.g)),
      b.g
    )
    QUALIFY row_number() OVER (PARTITION BY f.osm_type, f.osm_id) = 1
  "
  )
  if (!by_area) {
    return(invisible())
  }
  dbExecute(
    con,
    "
    CREATE OR REPLACE TABLE pieces AS
    SELECT f.osm_type, f.osm_id, b.borough, f.g AS fg, b.g AS bg
    FROM staged f
    JOIN boros b ON ST_Intersects(f.g, b.g)
  "
  )
  dbExecute(
    con,
    "
    CREATE OR REPLACE TABLE overlap_borough AS
    WITH multi AS (
      SELECT osm_type, osm_id
      FROM pieces
      GROUP BY ALL
      HAVING COUNT(DISTINCT borough) > 1
    ),
    areas AS (
      SELECT
        p.osm_type,
        p.osm_id,
        p.borough,
        SUM(COALESCE(TRY(ST_Area(ST_Intersection(p.fg, p.bg))), 0)) AS area
      FROM pieces p
      SEMI JOIN multi m USING (osm_type, osm_id)
      GROUP BY ALL
    )
    SELECT osm_type, osm_id, borough
    FROM areas
    QUALIFY row_number() OVER (
      PARTITION BY osm_type, osm_id ORDER BY area DESC
    ) = 1
  "
  )
  dbExecute(
    con,
    "
    DELETE FROM feature_borough
    WHERE (osm_type, osm_id) IN (SELECT (osm_type, osm_id) FROM overlap_borough)
  "
  )
  dbExecute(
    con,
    "INSERT INTO feature_borough SELECT * FROM overlap_borough"
  )
  message(
    dbGetQuery(con, "SELECT COUNT(*) FROM overlap_borough")[[1]],
    " multi-borough polygons assigned by area"
  )
}

# Add borough, tags, and extract date; sort by Hilbert index.
finish_layer <- function(cols, by_area = FALSE) {
  assign_boroughs(by_area)
  dbExecute(
    con,
    paste0(
      "
    CREATE OR REPLACE TABLE final AS
    SELECT
      f.osm_type,
      f.osm_id,
      ",
      quote_cols(cols),
      ",
      t.tags,
      b.borough,
      DATE '",
      osm_extract,
      "' AS osm_extract,
      ST_SetCRS(f.g, 'EPSG:2263') AS geometry,
      ST_Hilbert(f.g, ",
      hilbert_box,
      ") AS hilbert
    FROM staged f
    LEFT JOIN osm_tags t USING (osm_type, osm_id)
    LEFT JOIN feature_borough b USING (osm_type, osm_id)
  "
    )
  )
}

# Write rows of `final` matching `where` to one zstd GeoParquet file.
write_parquet <- function(out, where = "TRUE") {
  dbExecute(
    con,
    paste0(
      "COPY (SELECT * EXCLUDE (hilbert) FROM final WHERE ",
      where,
      " ORDER BY hilbert) TO '",
      out,
      "' (FORMAT PARQUET, COMPRESSION ZSTD, COMPRESSION_LEVEL 19, ",
      "ROW_GROUP_SIZE 100000)"
    )
  )
  out
}

# File name part for a borough: "staten_island"; "outside" for features in
# the buffer zone but in no borough.
borough_slug <- function(borough) {
  if_else(
    is.na(borough),
    "outside",
    str_replace_all(str_to_lower(borough), " ", "_")
  )
}

# One file per layer, or for split layers one file per borough.
write_layer <- function(cols, name, split = FALSE, by_area = FALSE) {
  finish_layer(cols, by_area)
  if (split) {
    boroughs <- c(sort(unique(boros_sf$borough)), NA)
    paths <- map_chr(boroughs, \(boro) {
      where <- if (is.na(boro)) {
        "borough IS NULL"
      } else {
        paste0("borough = '", boro, "'")
      }
      write_parquet(
        fs::path(
          out_dir,
          paste0("nyc_osm_", name, "_", borough_slug(boro), ".parquet")
        ),
        where
      )
    })
  } else {
    paths <- write_parquet(fs::path(
      out_dir,
      paste0("nyc_osm_", name, ".parquet")
    ))
  }
  dbGetQuery(
    con,
    paste0(
      "SELECT '",
      name,
      "' AS layer, COUNT(*) AS n, ",
      "COUNT(*) FILTER (WHERE borough IS NULL) AS no_borough, ",
      "COUNT(*) FILTER (WHERE tags IS NULL) AS no_tags FROM read_parquet([",
      paste0("'", paths, "'", collapse = ", "),
      "])"
    )
  ) |>
    mutate(
      files = length(paths),
      mib = round(sum(fs::file_size(paths)) / 2^20, 1),
      max_file_mib = round(max(fs::file_size(paths)) / 2^20, 1)
    )
}

polygon_type <- "CASE WHEN osm_id IS NOT NULL THEN 'relation' ELSE 'way' END"
polygon_id <- "COALESCE(osm_id, osm_way_id)"

results <- list(
  {
    stage_layer("points", "'node'", "osm_id")
    write_layer(point_cols, "points")
  },
  {
    stage_layer("lines", "'way'", "osm_id")
    write_layer(line_cols, "lines")
  },
  {
    stage_layer(
      "multipolygons",
      polygon_type,
      polygon_id,
      where = "building IS NOT NULL"
    )
    write_layer(building_cols, "buildings", split = TRUE, by_area = TRUE)
  },
  {
    stage_layer(
      "multipolygons",
      polygon_type,
      polygon_id,
      where = "building IS NULL"
    )
    write_layer(area_cols, "areas", by_area = TRUE)
  },
  {
    stage_layer("multilinestrings", "'relation'", "osm_id")
    write_layer(route_cols, "routes")
  }
) |>
  list_rbind()

print(results)

dbDisconnect(con, shutdown = TRUE)
