# OpenStreetMap layers for New York City

Each function returns a duckplyr-backed lazy data frame connected to a
GeoParquet file bundled with this package, holding one layer of
OpenStreetMap (OSM) features within 500 feet of New York City, from the
Geofabrik extract of 18 October 2026.

## Usage

``` r
nyc_osm_points(borough = NULL)

nyc_osm_lines(borough = NULL)

nyc_osm_buildings(borough = NULL)

nyc_osm_areas(borough = NULL)

nyc_osm_routes(borough = NULL)
```

## Source

© OpenStreetMap contributors, <https://www.openstreetmap.org/copyright>.
Geofabrik extract `new-york-261018`,
<https://download.geofabrik.de/north-america/us/new-york.html>.

## Arguments

- borough:

  `NULL` (the default) for all features, including those outside the
  boroughs, or one or more of `"Manhattan"`, `"Bronx"`, `"Brooklyn"`,
  `"Queens"`, and `"Staten Island"`.

## Value

A duckplyr data frame backed by GeoParquet.

## Details

- `nyc_osm_points()`: tagged nodes: points of interest (amenities,
  shops, restaurants), transit stops, crossings, street furniture,
  trees, and so on. 701,481 rows, 35 columns.

- `nyc_osm_lines()`: open ways: streets, footways, cycleways, rail,
  waterways, barriers. 471,643 rows, 26 columns.

- `nyc_osm_buildings()`: closed ways and multipolygon relations with a
  `building` tag. 1,089,132 rows, 22 columns.

- `nyc_osm_areas()`: all other closed ways and multipolygon relations:
  land use, parks, leisure, water, natural features, and amenity areas
  such as parking lots and school grounds. 202,990 rows, 27 columns.

- `nyc_osm_routes()`: route relations: bicycle, bus, train, subway,
  road, hiking, ferry, and other routes. 2,426 rows, 13 columns.

Use dplyr verbs to filter, select, and summarise, then call
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
to bring results into R memory, and
[`nyc_osm_to_sf()`](https://kjhealy.github.io/nycosm/reference/nyc_osm_to_sf.md)
to convert them to an sf object. To pull other OSM tags out of `tags`
into columns, use
[`nyc_osm_add_tags()`](https://kjhealy.github.io/nycosm/reference/nyc_osm_add_tags.md).

**Columns.** Every layer has these columns:

- osm_type:

  OSM element type: `"node"`, `"way"`, or `"relation"` (character).

- osm_id:

  OSM element ID (double). IDs are unique only within an element type,
  so the key is `osm_type` and `osm_id` together. The element is at
  `https://www.openstreetmap.org/<osm_type>/<osm_id>`.

- name, ...:

  A selection of common OSM tags, one column per tag, listed below
  (character). Column names are tag keys with `:` replaced by `_`, e.g.
  `addr:street` is `addr_street`. Values are as entered in OSM: `NA`
  means the tag is absent. Numeric-looking tags such as `height`,
  `lanes`, or `building:levels` are text, because OSM values can include
  units or lists (e.g. `"12 m"`, `"2;3"`).

- tags:

  All OSM tags of the element, as a DuckDB `MAP` of key to value. After
  collecting, a list column of data frames with columns `key` and
  `value`.

- borough:

  Borough of the feature: `"Manhattan"`, `"Bronx"`, `"Brooklyn"`,
  `"Queens"`, or `"Staten Island"` (character). The borough containing a
  point on the feature's surface; for buildings and areas that cross a
  borough line, the borough holding the largest share of the polygon's
  area. Boroughs are those of `nycmaps::nyc_boros_sf`, which follow the
  legal boundaries, so a few features differ from their address: piers
  built out from the Brooklyn shore into the East River, for example,
  are in Manhattan. `NA` for features within the 500 ft buffer but in no
  borough, e.g. on Ellis Island or in New Jersey or Nassau County.

- osm_extract:

  Date of the OSM extract, 2026-10-18 (Date).

- geometry:

  Geometry in EPSG:2263 (NAD83 / New York Long Island, US feet), as WKB
  (raw vector, list column after collecting). Points for
  `nyc_osm_points()`; LineStrings for `nyc_osm_lines()`; MultiPolygons
  for buildings and areas; MultiLineStrings for routes.

Tag columns by layer:

- **points**: `name`, `amenity`, `shop`, `cuisine`, `highway`,
  `public_transport`, `railway`, `leisure`, `tourism`, `natural`,
  `barrier`, `man_made`, `office`, `craft`, `healthcare`, `emergency`,
  `historic`, `place`, `brand`, `operator`, `opening_hours`, `website`,
  `phone`, `wheelchair`, `addr_housenumber`, `addr_street`,
  `addr_postcode`, `ref`, `wikidata`.

- **lines**: `name`, `highway`, `service`, `footway`, `cycleway`,
  `surface`, `lanes`, `maxspeed`, `oneway`, `bridge`, `tunnel`, `layer`,
  `railway`, `waterway`, `barrier`, `access`, `bicycle`, `foot`, `ref`,
  `wikidata`.

- **buildings**: `name`, `building`, `building_levels`, `height` (in
  metres, the OSM convention), `nycdoitt_bin` (NYC Building
  Identification Number, from the import of city building footprints;
  joins to `bin` in the `nycbuildings` package), `addr_housenumber`,
  `addr_street`, `addr_postcode`, `amenity`, `shop`, `leisure`,
  `tourism`, `historic`, `man_made`, `office`, `wikidata`.

- **areas**: `name`, `amenity`, `shop`, `leisure`, `landuse`, `natural`,
  `water`, `tourism`, `historic`, `sport`, `man_made`, `office`,
  `boundary`, `admin_level`, `aeroway`, `military`, `place`,
  `addr_housenumber`, `addr_street`, `addr_postcode`, `wikidata`.

- **routes**: `name`, `route`, `ref`, `network`, `operator`, `colour`,
  `wikidata`.

What tags mean is documented on the OSM wiki, e.g.
<https://wiki.openstreetmap.org/wiki/Key:amenity>.

**Coverage.** Features are those in the bounding box -74.26, 40.49,
-73.69, 40.92 that are within 500 feet of a borough boundary in
`nycmaps::nyc_boros_sf`, so shoreline, pier, and bridge features are
kept. Points are nodes with at least one tag other than `source`,
`created_by`, and similar. Polygons are closed ways with a tag that
implies an area (e.g. `building`, `landuse`, `leisure`, `amenity`) and
multipolygon relations; a polygon with any `building` tag is in the
buildings layer.

**Storage.** Buildings are stored as one file per borough (plus one for
features outside the boroughs); `nyc_osm_buildings()` reads them as a
single table, and its `borough` argument reads only the files needed.
Files are sorted along a Hilbert curve, so spatial filters on nearby
features read little data.

**OSM and official sources.** OSM is edited by volunteers. For
authoritative NYC building footprints, streets, and boundaries, see the
`nycbuildings`, `nyclion`/`nycstreets`, and `nycmaps` packages. Most OSM
buildings in NYC were imported from the city's footprints, with building
types, levels, and names added since. OSM adds points of interest,
footways and cycleways, transit stops and routes, land use, and natural
features.

**Licence.** Map data © OpenStreetMap contributors, available under the
Open Database License (ODbL) 1.0. See
<https://www.openstreetmap.org/copyright>. The bundled data are a
database derived from OSM and are also under the ODbL.

## Examples

``` r
if (FALSE) { # \dontrun{
library(dplyr)

# Restaurants by cuisine in Manhattan
nyc_osm_points(borough = "Manhattan") |>
  filter(amenity == "restaurant", !is.na(cuisine)) |>
  count(cuisine) |>
  arrange(desc(n)) |>
  collect()

# Cycleways in Brooklyn as sf lines
nyc_osm_lines(borough = "Brooklyn") |>
  filter(highway == "cycleway") |>
  collect() |>
  nyc_osm_to_sf()

# Buildings in Staten Island by type
nyc_osm_buildings(borough = "Staten Island") |>
  count(building) |>
  arrange(desc(n)) |>
  collect()
} # }
```
