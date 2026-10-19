#' OpenStreetMap layers for New York City
#'
#' Each function returns a duckplyr-backed lazy data frame connected to a
#' GeoParquet file bundled with this package, holding one layer of
#' OpenStreetMap (OSM) features within 500 feet of New York City, from the
#' Geofabrik extract of 18 October 2026.
#'
#' - `nyc_osm_points()`: tagged nodes: points of interest (amenities, shops,
#'   restaurants), transit stops, crossings, street furniture, trees, and so
#'   on. 701,481 rows, 35 columns.
#' - `nyc_osm_lines()`: open ways: streets, footways, cycleways, rail,
#'   waterways, barriers. 471,643 rows, 26 columns.
#' - `nyc_osm_buildings()`: closed ways and multipolygon relations with a
#'   `building` tag. 1,089,132 rows, 22 columns.
#' - `nyc_osm_areas()`: all other closed ways and multipolygon relations:
#'   land use, parks, leisure, water, natural features, and amenity areas
#'   such as parking lots and school grounds. 202,990 rows, 27 columns.
#' - `nyc_osm_routes()`: route relations: bicycle, bus, train, subway, road,
#'   hiking, ferry, and other routes. 2,426 rows, 13 columns.
#'
#' Use dplyr verbs to filter, select, and summarise, then call
#' [dplyr::collect()] to bring results into R memory, and
#' [nyc_osm_to_sf()] to convert them to an sf object. To pull other OSM
#' tags out of `tags` into columns, use [nyc_osm_add_tags()].
#'
#' @details
#' **Columns.** Every layer has these columns:
#' \describe{
#'   \item{osm_type}{OSM element type: `"node"`, `"way"`, or `"relation"`
#'     (character).}
#'   \item{osm_id}{OSM element ID (double). IDs are unique only within an
#'     element type, so the key is `osm_type` and `osm_id` together. The
#'     element is at `https://www.openstreetmap.org/<osm_type>/<osm_id>`.}
#'   \item{name, ...}{A selection of common OSM tags, one column per tag,
#'     listed below (character). Column names are tag keys with `:`
#'     replaced by `_`, e.g. `addr:street` is `addr_street`. Values are as
#'     entered in OSM: `NA` means the tag is absent. Numeric-looking tags
#'     such as `height`, `lanes`, or `building:levels` are text, because
#'     OSM values can include units or lists (e.g. `"12 m"`, `"2;3"`).}
#'   \item{tags}{All OSM tags of the element, as a DuckDB `MAP` of key to
#'     value. After collecting, a list column of data frames with columns
#'     `key` and `value`.}
#'   \item{borough}{Borough of the feature: `"Manhattan"`, `"Bronx"`,
#'     `"Brooklyn"`, `"Queens"`, or `"Staten Island"` (character). The
#'     borough containing a point on the feature's surface; for buildings
#'     and areas that cross a borough line, the borough holding the largest
#'     share of the polygon's area. Boroughs are those of
#'     `nycmaps::nyc_boros_sf`, which follow the legal boundaries, so a few
#'     features differ from their address: piers built out from the
#'     Brooklyn shore into the East River, for example, are in Manhattan.
#'     `NA` for features within the 500 ft buffer but in no borough, e.g.
#'     on Ellis Island or in New Jersey or Nassau County.}
#'   \item{osm_extract}{Date of the OSM extract, 2026-10-18 (Date).}
#'   \item{geometry}{Geometry in EPSG:2263 (NAD83 / New York Long Island,
#'     US feet), as WKB (raw vector, list column after collecting). Points
#'     for `nyc_osm_points()`; LineStrings for `nyc_osm_lines()`;
#'     MultiPolygons for buildings and areas; MultiLineStrings for routes.}
#' }
#'
#' Tag columns by layer:
#' - **points**: `name`, `amenity`, `shop`, `cuisine`, `highway`,
#'   `public_transport`, `railway`, `leisure`, `tourism`, `natural`,
#'   `barrier`, `man_made`, `office`, `craft`, `healthcare`, `emergency`,
#'   `historic`, `place`, `brand`, `operator`, `opening_hours`, `website`,
#'   `phone`, `wheelchair`, `addr_housenumber`, `addr_street`,
#'   `addr_postcode`, `ref`, `wikidata`.
#' - **lines**: `name`, `highway`, `service`, `footway`, `cycleway`,
#'   `surface`, `lanes`, `maxspeed`, `oneway`, `bridge`, `tunnel`, `layer`,
#'   `railway`, `waterway`, `barrier`, `access`, `bicycle`, `foot`, `ref`,
#'   `wikidata`.
#' - **buildings**: `name`, `building`, `building_levels`, `height` (in
#'   metres, the OSM convention), `nycdoitt_bin` (NYC Building Identification Number, from the
#'   import of city building footprints; joins to `bin` in the
#'   `nycbuildings` package), `addr_housenumber`, `addr_street`,
#'   `addr_postcode`, `amenity`, `shop`, `leisure`, `tourism`, `historic`,
#'   `man_made`, `office`, `wikidata`.
#' - **areas**: `name`, `amenity`, `shop`, `leisure`, `landuse`, `natural`,
#'   `water`, `tourism`, `historic`, `sport`, `man_made`, `office`,
#'   `boundary`, `admin_level`, `aeroway`, `military`, `place`,
#'   `addr_housenumber`, `addr_street`, `addr_postcode`, `wikidata`.
#' - **routes**: `name`, `route`, `ref`, `network`, `operator`, `colour`,
#'   `wikidata`.
#'
#' What tags mean is documented on the OSM wiki, e.g.
#' <https://wiki.openstreetmap.org/wiki/Key:amenity>.
#'
#' **Coverage.** Features are those in the bounding box -74.26, 40.49,
#' -73.69, 40.92 that are within 500 feet of a borough boundary in
#' `nycmaps::nyc_boros_sf`, so shoreline, pier, and bridge features are
#' kept. Points are nodes with at least one tag other than `source`,
#' `created_by`, and similar. Polygons are closed ways with a tag that
#' implies an area (e.g. `building`, `landuse`, `leisure`, `amenity`) and
#' multipolygon relations; a polygon with any `building` tag is in the
#' buildings layer.
#'
#' **Storage.** Buildings are stored as one file per borough (plus one for
#' features outside the boroughs); `nyc_osm_buildings()` reads them as a
#' single table, and its `borough` argument reads only the files needed.
#' Files are sorted along a Hilbert curve, so spatial filters on nearby
#' features read little data.
#'
#' **OSM and official sources.** OSM is edited by volunteers. For
#' authoritative NYC building footprints, streets, and boundaries, see the
#' `nycbuildings`, `nyclion`/`nycstreets`, and `nycmaps` packages. Most OSM
#' buildings in NYC were imported from the city's footprints, with building
#' types, levels, and names added since. OSM adds points of interest,
#' footways and cycleways, transit stops and routes, land use, and natural
#' features.
#'
#' **Licence.** Map data © OpenStreetMap contributors, available under the
#' Open Database License (ODbL) 1.0. See
#' <https://www.openstreetmap.org/copyright>. The bundled data are a
#' database derived from OSM and are also under the ODbL.
#'
#' @param borough `NULL` (the default) for all features, including those
#'   outside the boroughs, or one or more of `"Manhattan"`, `"Bronx"`,
#'   `"Brooklyn"`, `"Queens"`, and `"Staten Island"`.
#'
#' @return A duckplyr data frame backed by GeoParquet.
#'
#' @source © OpenStreetMap contributors,
#'   <https://www.openstreetmap.org/copyright>. Geofabrik extract
#'   `new-york-261018`,
#'   <https://download.geofabrik.de/north-america/us/new-york.html>.
#'
#' @examples
#' \dontrun{
#' library(dplyr)
#'
#' # Restaurants by cuisine in Manhattan
#' nyc_osm_points(borough = "Manhattan") |>
#'   filter(amenity == "restaurant", !is.na(cuisine)) |>
#'   count(cuisine) |>
#'   arrange(desc(n)) |>
#'   collect()
#'
#' # Cycleways in Brooklyn as sf lines
#' nyc_osm_lines(borough = "Brooklyn") |>
#'   filter(highway == "cycleway") |>
#'   collect() |>
#'   nyc_osm_to_sf()
#'
#' # Buildings in Staten Island by type
#' nyc_osm_buildings(borough = "Staten Island") |>
#'   count(building) |>
#'   arrange(desc(n)) |>
#'   collect()
#' }
#'
#' @name nyc_osm
#' @keywords functions
NULL

#' @rdname nyc_osm
#' @export
nyc_osm_points <- function(borough = NULL) {
  read_osm_layer("points", borough)
}

#' @rdname nyc_osm
#' @export
nyc_osm_lines <- function(borough = NULL) {
  read_osm_layer("lines", borough)
}

#' @rdname nyc_osm
#' @export
nyc_osm_buildings <- function(borough = NULL) {
  read_osm_layer("buildings", borough)
}

#' @rdname nyc_osm
#' @export
nyc_osm_areas <- function(borough = NULL) {
  read_osm_layer("areas", borough)
}

#' @rdname nyc_osm
#' @export
nyc_osm_routes <- function(borough = NULL) {
  read_osm_layer("routes", borough)
}


#' Get the file paths to the OSM GeoParquet files
#'
#' Returns the paths to the GeoParquet files bundled with this package, for
#' direct use with DuckDB, arrow, or GDAL. Buildings are stored as one file
#' per borough, plus one for features outside the boroughs; other layers
#' are one file each.
#'
#' @param layer One of `"points"`, `"lines"`, `"buildings"`, `"areas"`, or
#'   `"routes"`.
#' @inheritParams nyc_osm
#'
#' @return A character vector of file paths. For `"buildings"` with
#'   `borough = NULL`, six paths; otherwise one path per borough requested.
#'   For other layers, one path, whatever `borough` is (the file holds all
#'   boroughs).
#'
#' @export
#'
#' @examples
#' nyc_osm_path("points")
#' nyc_osm_path("buildings", borough = c("Bronx", "Queens"))
#'
#' @keywords functions
nyc_osm_path <- function(
  layer = c("points", "lines", "buildings", "areas", "routes"),
  borough = NULL
) {
  layer <- rlang::arg_match(layer)
  borough <- check_borough(borough)
  files <- if (layer == "buildings") {
    slugs <- if (is.null(borough)) {
      c(borough_slug(nyc_osm_boroughs), "outside")
    } else {
      borough_slug(borough)
    }
    paste0("nyc_osm_buildings_", slugs, ".parquet")
  } else {
    paste0("nyc_osm_", layer, ".parquet")
  }
  vapply(
    files,
    \(f) system.file("extdata", f, package = "nycosm", mustWork = TRUE),
    character(1),
    USE.NAMES = FALSE
  )
}


#' Convert collected OSM data to an sf object
#'
#' Takes a data frame (typically from one of the [nyc_osm] functions after
#' filtering and collecting) and converts its WKB `geometry` column to an sf
#' geometry column.
#'
#' @param df A data frame with a `geometry` column of WKB.
#' @param crs Target CRS. Default is EPSG:2263 (NAD83 / New York Long
#'   Island, ftUS), the CRS the data are stored in.
#'
#' @return An sf object. Rows without a geometry are dropped, with a
#'   message.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' library(dplyr)
#'
#' nyc_osm_areas(borough = "Manhattan") |>
#'   filter(leisure == "park") |>
#'   collect() |>
#'   nyc_osm_to_sf()
#' }
#'
#' @keywords functions
nyc_osm_to_sf <- function(df, crs = 2263) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    cli::cli_abort(
      c(
        "{.pkg sf} is required for {.fn nyc_osm_to_sf}.",
        "i" = "Install it with {.code install.packages(\"sf\")}."
      )
    )
  }
  if (!"geometry" %in% names(df)) {
    cli::cli_abort(
      c(
        "{.arg df} must have a {.field geometry} column.",
        "i" = "Keep {.field geometry} when selecting columns."
      )
    )
  }
  has_geom <- !vapply(df$geometry, is.null, logical(1))
  if (any(!has_geom)) {
    cli::cli_inform("Dropped {sum(!has_geom)} row{?s} with no geometry.")
  }
  df <- df[has_geom, ]
  wkb <- structure(df$geometry, class = "WKB")
  df$geometry <- sf::st_as_sfc(wkb, crs = 2263)
  sf::st_as_sf(df, sf_column_name = "geometry") |>
    sf::st_transform(crs = crs)
}


#' Add OSM tags as columns
#'
#' Extracts the values of one or more OSM tag keys from the `tags` column
#' into new character columns. Works on the lazy data frames returned by the
#' [nyc_osm] functions (the extraction runs in DuckDB) and on collected data
#' frames.
#'
#' @param df A data frame with a `tags` column, lazy or collected.
#' @param keys Character vector of OSM tag keys, e.g. `"diet:vegan"`,
#'   `"roof:shape"`.
#'
#' @return `df` with one character column per key, named after the key with
#'   characters other than letters, digits, and underscores replaced by `_`
#'   (`"diet:vegan"` becomes `diet_vegan`). `NA` where the tag is absent.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' library(dplyr)
#'
#' nyc_osm_points() |>
#'   filter(amenity == "restaurant") |>
#'   nyc_osm_add_tags(c("diet:vegan", "outdoor_seating")) |>
#'   filter(diet_vegan %in% c("yes", "only")) |>
#'   select(name, cuisine, diet_vegan, outdoor_seating) |>
#'   collect()
#' }
#'
#' @keywords functions
nyc_osm_add_tags <- function(df, keys) {
  if (!is.character(keys) || length(keys) == 0 || anyNA(keys)) {
    cli::cli_abort("{.arg keys} must be a character vector of tag keys.")
  }
  if (!"tags" %in% names(df)) {
    cli::cli_abort("{.arg df} must have a {.field tags} column.")
  }
  cols <- tag_column_names(keys)
  if (inherits(df, "duckplyr_df")) {
    exprs <- lapply(keys, \(key) rlang::expr(dd$map_extract_value(tags, !!key)))
    names(exprs) <- cols
    return(dplyr::mutate(df, !!!exprs))
  }
  for (i in seq_along(keys)) {
    df[[cols[i]]] <- vapply(
      df$tags,
      \(tag) tag_value(tag, keys[i]),
      character(1)
    )
  }
  df
}


nyc_osm_boroughs <- c(
  "Manhattan",
  "Bronx",
  "Brooklyn",
  "Queens",
  "Staten Island"
)

read_osm_layer <- function(layer, borough) {
  borough <- check_borough(borough)
  df <- duckplyr::read_parquet_duckdb(nyc_osm_path(layer, borough))
  if (!is.null(borough) && layer != "buildings") {
    df <- dplyr::filter(df, .data$borough %in% !!borough)
  }
  df
}

check_borough <- function(borough, call = rlang::caller_env()) {
  if (is.null(borough)) {
    return(NULL)
  }
  rlang::arg_match(
    borough,
    nyc_osm_boroughs,
    multiple = TRUE,
    error_call = call
  )
}

borough_slug <- function(borough) {
  gsub(" ", "_", tolower(borough))
}

tag_column_names <- function(keys) {
  gsub("[^A-Za-z0-9_]", "_", keys)
}

tag_value <- function(tag, key) {
  if (is.null(tag)) {
    return(NA_character_)
  }
  value <- tag$value[tag$key == key]
  if (length(value) == 0) NA_character_ else value[[1]]
}

utils::globalVariables(c("dd", "tags"))
