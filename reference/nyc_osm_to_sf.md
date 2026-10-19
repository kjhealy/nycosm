# Convert collected OSM data to an sf object

Takes a data frame (typically from one of the
[nyc_osm](https://kjhealy.github.io/nycosm/reference/nyc_osm.md)
functions after filtering and collecting) and converts its WKB
`geometry` column to an sf geometry column.

## Usage

``` r
nyc_osm_to_sf(df, crs = 2263)
```

## Arguments

- df:

  A data frame with a `geometry` column of WKB.

- crs:

  Target CRS. Default is EPSG:2263 (NAD83 / New York Long Island, ftUS),
  the CRS the data are stored in.

## Value

An sf object. Rows without a geometry are dropped, with a message.

## Examples

``` r
if (FALSE) { # \dontrun{
library(dplyr)

nyc_osm_areas(borough = "Manhattan") |>
  filter(leisure == "park") |>
  collect() |>
  nyc_osm_to_sf()
} # }
```
