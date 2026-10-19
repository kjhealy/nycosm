test_that("nyc_osm_path returns existing files", {
  for (layer in c("points", "lines", "areas", "routes")) {
    path <- nyc_osm_path(layer)
    expect_length(path, 1)
    expect_true(file.exists(path))
  }
  expect_length(nyc_osm_path("buildings"), 6)
  expect_length(nyc_osm_path("buildings", borough = c("Bronx", "Queens")), 2)
  expect_match(
    nyc_osm_path("buildings", borough = "Staten Island"),
    "staten_island"
  )
})

test_that("nyc_osm_path rejects unknown layers and boroughs", {
  expect_error(nyc_osm_path("roads"))
  expect_error(nyc_osm_path("points", borough = "Hoboken"), "borough")
})

test_that("layers have the shared columns and expected widths", {
  shared <- c(
    "osm_type",
    "osm_id",
    "tags",
    "borough",
    "osm_extract",
    "geometry"
  )
  widths <- c(points = 35, lines = 26, buildings = 22, areas = 27, routes = 13)
  layers <- list(
    points = nyc_osm_points(),
    lines = nyc_osm_lines(),
    buildings = nyc_osm_buildings(),
    areas = nyc_osm_areas(),
    routes = nyc_osm_routes()
  )
  for (layer in names(layers)) {
    expect_true(all(shared %in% names(layers[[layer]])), label = layer)
    expect_length(names(layers[[layer]]), widths[[layer]])
  }
})

test_that("borough argument restricts rows", {
  boroughs <- nyc_osm_points(borough = c("Bronx", "Queens")) |>
    dplyr::distinct(borough) |>
    dplyr::collect()
  expect_setequal(boroughs$borough, c("Bronx", "Queens"))

  buildings <- nyc_osm_buildings(borough = "Manhattan") |>
    dplyr::distinct(borough) |>
    dplyr::collect()
  expect_equal(buildings$borough, "Manhattan")
})

test_that("all buildings files read as one table", {
  boroughs <- nyc_osm_buildings() |>
    dplyr::count(borough) |>
    dplyr::collect()
  expect_equal(nrow(boroughs), 6)
  expect_true(anyNA(boroughs$borough))
})

test_that("osm_type and osm_id identify rows", {
  checks <- nyc_osm_routes() |>
    dplyr::summarise(
      n = dplyr::n(),
      n_id = dplyr::n_distinct(osm_type, osm_id)
    ) |>
    dplyr::collect()
  expect_equal(checks$n, checks$n_id)
})

test_that("nyc_osm_add_tags works on lazy and collected data", {
  lazy <- nyc_osm_routes() |>
    dplyr::filter(route == "subway") |>
    nyc_osm_add_tags(c("route", "public_transport:version"))
  expect_true(all(c("route", "public_transport_version") %in% names(lazy)))

  collected <- nyc_osm_routes() |>
    dplyr::filter(route == "subway") |>
    utils::head(5) |>
    dplyr::collect()
  added <- nyc_osm_add_tags(collected, c("type", "no:such:key"))
  expect_equal(unique(added$type), "route")
  expect_true(all(is.na(added$no_such_key)))
})

test_that("nyc_osm_add_tags checks its inputs", {
  expect_error(nyc_osm_add_tags(nyc_osm_routes(), 1), "character")
  expect_error(nyc_osm_add_tags(data.frame(x = 1), "name"), "tags")
})

test_that("nyc_osm_to_sf returns geometries in EPSG:2263", {
  skip_if_not_installed("sf")
  pts <- nyc_osm_points(borough = "Manhattan") |>
    dplyr::filter(amenity == "library") |>
    dplyr::collect() |>
    nyc_osm_to_sf()
  expect_s3_class(pts, "sf")
  expect_true(all(sf::st_geometry_type(pts) == "POINT"))
  expect_equal(sf::st_crs(pts)$epsg, 2263)

  parks <- nyc_osm_areas(borough = "Manhattan") |>
    dplyr::filter(leisure == "park") |>
    utils::head(10) |>
    dplyr::collect() |>
    nyc_osm_to_sf(crs = 4326)
  expect_equal(sf::st_crs(parks)$epsg, 4326)
})

test_that("nyc_osm_to_sf errors without geometry", {
  skip_if_not_installed("sf")
  expect_error(nyc_osm_to_sf(data.frame(x = 1)), "geometry")
})
