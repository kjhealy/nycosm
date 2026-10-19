# Shared code and objects
library(devtools)
library(tidyverse)
library(here)
library(sf)
library(janitor)
library(DBI)
library(duckdb)

osm_extract <- "2026-10-18"
pbf_name <- "new-york-261018.osm.pbf"

rawpath <- here("data-raw", "osm", "data")
pbf <- here(rawpath, pbf_name)
osmconf <- here("data-raw", "osmconf.ini")
