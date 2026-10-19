# OpenStreetMap (OSM)

Raw data for an `nycosm` package: OpenStreetMap features for New York City,
including points of interest, streets, paths, rail, buildings, land use,
parks, and water. The full key–value tags are kept.

Extract **2026-10-18** (Geofabrik `new-york-261018`; OSM replication
timestamp 2026-10-18T20:25:06Z, sequence 4946). Staged 2026-10-18 by
`download-osm.R`. Each file is listed, with its source and size, in
`download-log.csv`. The PBF's MD5 is checked against Geofabrik's.

## Contents

```
osm/
├── README.md
├── download-osm.R                   stages everything below (already run)
├── download-log.csv
├── prototype/
│   └── prototype-osm-geoparquet.R   tested PBF -> GeoParquet pipeline (reference)
├── data/
│   ├── new-york-261018.osm.pbf      New York State, 498 MB
│   └── new-york-261018.osm.pbf.md5
└── docs/
    ├── new-york.poly                extract boundary (Osmosis polygon format)
    ├── geofabrik_state.txt          replication state at download time
    └── geofabrik_new-york.html      Geofabrik region page
```

## Source

- Geofabrik, <https://download.geofabrik.de/north-america/us/new-york.html>.
  The extract covers all of New York State, so NYC is complete. The file
  has to be clipped to the city.
- Geofabrik's public extracts leave out editor metadata (user names, user
  IDs, changesets). Object IDs, versions, and timestamps are not affected.
  Editor metadata is not needed here.
- Dated daily snapshots (`new-york-YYMMDD.osm.pbf`) are on the server only
  for a limited time. To refresh, change `extract_date` in
  `download-osm.R`.
- A previous exploratory extract (BBBike "NewYork", in
  `nyc-work/projects-to-incorporate/nyc-osm-pbf/raw-data`) covers a
  bounding box that includes parts of New Jersey, Nassau, and Westchester.
  Do not use it for the package.

## Licence

© OpenStreetMap contributors. The data are under the Open Database Licence
(ODbL) 1.0, <https://opendatacommons.org/licenses/odbl/>. The package must:

- give attribution ("© OpenStreetMap contributors", with a link to
  <https://www.openstreetmap.org/copyright>) in DESCRIPTION, README,
  `inst/CITATION`, and the dataset docs;
- state that the bundled database is under the ODbL. A database derived from
  the data (a clipped, restructured extract) must be shared under the ODbL
  too. The package code can have a different licence, e.g. MIT, if the data
  licence is stated separately.

## File contents

The GDAL OSM driver (`ogr2ogr`, `sf`, `osmextract`) reads the PBF as five
layers. Features with a geometry in the NYC bounding box
(−74.26, 40.49, −73.69, 40.92) with GDAL's default `osmconf.ini`:

| Layer | Features | OSM source |
|---|---|---|
| `points` | 755,404 | tagged nodes |
| `lines` | 500,113 | open ways (highways, rail, waterways, barriers) |
| `multilinestrings` | 2,499 | route relations (bus, subway, bike) |
| `multipolygons` | 1,399,549 | closed ways and multipolygon relations (buildings, land use, parks, water) |
| `other_relations` | 14,056 | other relations |

The bounding box includes some of New Jersey and Nassau, so clipping to the
borough boundary leaves fewer features. Clipped to the boroughs with a
500 ft buffer by `prototype/prototype-osm-geoparquet.R` (default
`osmconf.ini`, zstd GeoParquet):

| Layer | Features | Size |
|---|---|---|
| `points` | 701,480 | 18.2 MB |
| `lines` | 471,642 | 28.1 MB |
| `multilinestrings` | 2,426 | 4.6 MB |
| `multipolygons` | 1,292,123 | 118 MB |
| `other_relations` | 13,322 | 1.8 MB |

## Prototype pipeline

`prototype/prototype-osm-geoparquet.R` is a tested reference for the
package build script, run on this extract on 2026-10-18. It:

1. converts the PBF to GeoPackage with `ogr2ogr` (NYC bbox; under a
   minute);
2. clips each layer in DuckDB to `nycmaps::nyc_boros_sf` with a 500 ft
   buffer, sorts by `ST_Hilbert()`, and writes zstd GeoParquet;
3. reads the results back into sf through WKB.

It writes to `tempdir()` only. Things to fix in the build:

- `ogr2ogr` names the GeoPackage geometry column `geom` (osmextract uses
  `geometry`). The prototype renames it to `geometry`.
- Clipping against one complex boundary polygon takes 1–3 min per large
  layer. One polygon per borough would probably be faster and also gives
  the `borough` column.
- With the default `osmconf.ini`, `points` has no `amenity` or `shop`
  columns. These are only in `other_tags`.
- The buffer keeps some features just outside the city (e.g. on Ellis
  Island). Decide whether `borough` assignment drops them.
- The script also records what goes wrong when DuckDB reads the PBF
  directly (see below).

- **Tags.** The layers have a fixed set of tag columns, set by
  `osmconf.ini`. All other tags go into `other_tags` in hstore text format
  (`"key"=>"value","key2"=>"value2"`). Put the tags in a DuckDB
  `MAP(VARCHAR, VARCHAR)` column so that queries like `tags['cuisine']`
  work.
- **IDs.** `osm_id` is the node, way, or relation ID. In `multipolygons`,
  `osm_id` is set for relations and `osm_way_id` for closed ways. The ID
  spaces of the three types overlap, so the key is the pair (type, id).
- **CRS.** WGS84 (EPSG:4326).

## Notes for packaging

- **Reading the PBF.**
  - DuckDB spatial (1.5.6) `ST_Read()` fails on the PBF unless
    `open_options = ['CONFIG_FILE=<path to osmconf.ini>']` is given.
  - Even then it returns only relation-based multipolygons and loses closed
    ways (about 99.8% of polygons, including nearly all buildings).
  - Convert with `ogr2ogr` (GDAL 3.13.3 is available) to GeoPackage first,
    then read that with DuckDB. A state-to-NYC-bbox conversion takes about
    one minute.
  - `ST_ReadOSM()` reads the raw nodes, ways, and relations with full tag
    `MAP`s and is fast. Use it to get the complete tags by (type, id).
- **Custom `osmconf.ini`.** Put a project config in the package's
  `data-raw/` with the columns we want (e.g. `highway`, `railway`,
  `cycleway`, `amenity`, `shop`, `cuisine`, `public_transport`, `addr:*`,
  `height`, `building:levels`, `wikidata`).
- **Clipping.** Clip to `nycmaps::nyc_boros_sf` with a small buffer so
  shoreline and bridge features stay in. Add a `borough` column.
- **Output.** DuckDB writes `GEOMETRY('EPSG:4326')` columns to Parquet with
  GeoParquet 1.0 metadata. Sorting with `ST_Hilbert()` before writing makes
  spatial filters fast (0.17 s for a lower Manhattan bbox on 1.29M
  polygons). Estimated size of all layers after clipping: about 180 MB.
- **sf.** The GDAL inside `sf` has no Parquet driver. Collect WKB with
  DuckDB and convert with `sf::st_as_sfc()`, as `nyc_pluto_to_sf()` does.
- **Overlap with other packages.** OSM is crowd-sourced. The reference
  sources for NYC are:
  - buildings: DoITT building footprints (`nycbuildings`). OSM buildings
    were largely imported from DoITT, and OSM adds building type, levels,
    and names;
  - streets: LION (`nyclion`, `nycstreets`);
  - boundaries: `nycmaps`.

  State this in the package docs. What OSM adds: points of interest
  (amenities, shops, cuisine), footways and cycleways, transit stops and
  routes, land use, leisure, and natural features, and names in many
  languages.
- **Versions.** Put the extract date in a column on every table (e.g.
  `osm_extract = "2026-10-18"`).
