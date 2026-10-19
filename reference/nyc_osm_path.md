# Get the file paths to the OSM GeoParquet files

Returns the paths to the GeoParquet files bundled with this package, for
direct use with DuckDB, arrow, or GDAL. Buildings are stored as one file
per borough, plus one for features outside the boroughs; other layers
are one file each.

## Usage

``` r
nyc_osm_path(
  layer = c("points", "lines", "buildings", "areas", "routes"),
  borough = NULL
)
```

## Arguments

- layer:

  One of `"points"`, `"lines"`, `"buildings"`, `"areas"`, or `"routes"`.

- borough:

  `NULL` (the default) for all features, including those outside the
  boroughs, or one or more of `"Manhattan"`, `"Bronx"`, `"Brooklyn"`,
  `"Queens"`, and `"Staten Island"`.

## Value

A character vector of file paths. For `"buildings"` with
`borough = NULL`, six paths; otherwise one path per borough requested.
For other layers, one path, whatever `borough` is (the file holds all
boroughs).

## Examples

``` r
nyc_osm_path("points")
#> [1] "/home/runner/work/_temp/Library/nycosm/extdata/nyc_osm_points.parquet"
nyc_osm_path("buildings", borough = c("Bronx", "Queens"))
#> [1] "/home/runner/work/_temp/Library/nycosm/extdata/nyc_osm_buildings_bronx.parquet" 
#> [2] "/home/runner/work/_temp/Library/nycosm/extdata/nyc_osm_buildings_queens.parquet"
```
