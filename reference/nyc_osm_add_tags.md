# Add OSM tags as columns

Extracts the values of one or more OSM tag keys from the `tags` column
into new character columns. Works on the lazy data frames returned by
the [nyc_osm](https://kjhealy.github.io/nycosm/reference/nyc_osm.md)
functions (the extraction runs in DuckDB) and on collected data frames.

## Usage

``` r
nyc_osm_add_tags(df, keys)
```

## Arguments

- df:

  A data frame with a `tags` column, lazy or collected.

- keys:

  Character vector of OSM tag keys, e.g. `"diet:vegan"`, `"roof:shape"`.

## Value

`df` with one character column per key, named after the key with
characters other than letters, digits, and underscores replaced by `_`
(`"diet:vegan"` becomes `diet_vegan`). `NA` where the tag is absent.

## Examples

``` r
if (FALSE) { # \dontrun{
library(dplyr)

nyc_osm_points() |>
  filter(amenity == "restaurant") |>
  nyc_osm_add_tags(c("diet:vegan", "outdoor_seating")) |>
  filter(diet_vegan %in% c("yes", "only")) |>
  select(name, cuisine, diet_vegan, outdoor_seating) |>
  collect()
} # }
```
