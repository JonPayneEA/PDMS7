# ============================================================ #
# Tool:         test-starter-script
# Description:  The single-site starter script parses; read_site_settings() reads the example
#               settings, resolves paths from the file's folder, fills defaults, reports every
#               problem at once, and checks settings changed in R
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-24
# Modified:     2026-11-24 - read_site_settings()
# Tier:         1
# Inputs:       inst/scripts/calibrate_site.R, inst/examples/site.yml; settings files written
#               to a temporary folder
# Outputs:      None
# Dependencies: testthat, yaml
# ============================================================ #

# A settings folder with empty data files, so the file checks pass.
site_folder <- function(lines, files = c("flow.csv", "pet.csv", "rain.csv")) {
  home <- tempfile("site")
  dir.create(file.path(home, "data"), recursive = TRUE)
  for (f in files) file.create(file.path(home, "data", f))
  writeLines(lines, file.path(home, "site.yml"))
  file.path(home, "site.yml")
}
minimal <- c(
  "site: {name: Test Brook, area_km2: 12.5}",
  "data: {folder: data, flow: flow.csv, pet: pet.csv, rain: rain.csv}",
  "calibration: ['2010-10-01', '2015-09-30 23:45']",
  "validation: ['2015-10-01', '2018-09-30 23:45']")

test_that("the starter script parses", {
  script <- system.file("scripts", "calibrate_site.R", package = "pdmS7")
  expect_true(nzchar(script))
  expect_no_error(parse(script))
})

test_that("the example settings hold every required setting, with sound defaults", {
  settings <- yaml::read_yaml(system.file("examples", "site.yml", package = "pdmS7"))
  expect_true(is.numeric(settings$site$area_km2))
  expect_true(all(c("flow", "pet", "rain") %in% names(settings$data)))
  expect_lt(as.POSIXct(settings$calibration[2], tz = "UTC"),
            as.POSIXct(settings$validation[1], tz = "UTC"))
  # A newcomer's first run checks the data and stops before calibrating.
  expect_true(settings$stop_after_checks)
})

test_that("read_site_settings() resolves paths and fills the defaults", {
  file <- site_folder(minimal)
  home <- dirname(normalizePath(file))
  s <- read_site_settings(file)
  expect_s3_class(s, "pdm_site_settings")
  expect_identical(s$area_km2, 12.5)
  # Data files sit in data/ under the settings file's folder; output beside the file.
  expect_identical(s$flow, file.path(home, "data", "flow.csv"))
  expect_identical(s$rain, list(rain = file.path(home, "data", "rain.csv")))
  expect_identical(s$output, file.path(home, "output"))
  # Defaults: 15-minute data, standard effort, stop after the checks, rain factor fixed.
  expect_identical(s$step_hours, 0.25)
  expect_identical(s$effort, "standard")
  expect_true(s$stop_after_checks)
  expect_null(s$rainfall_factor)
  expect_false(s$snow)
  # A storm's rain typically 15% out; no single gauges, no regional comparison.
  expect_identical(s$rain_error, 0.15)
  expect_null(s$rain_gauges)
  expect_null(s$regional_results)
  expect_identical(s$bayes_generations, 2000L)
  expect_output(print(s), "Test Brook")
})

test_that("several named rain files keep their names and order; a range frees the factor", {
  file <- site_folder(
    c(minimal[-2],
      "data: {folder: data, flow: flow.csv, pet: pet.csv, rain: {thiessen: a.csv, gauge: b.csv}}",
      "rainfall_factor: [0.9, 1.3]",
      "thresholds: [{name: Alert, value: 12}]"),
    files = c("flow.csv", "pet.csv", "a.csv", "b.csv"))
  s <- read_site_settings(file)
  expect_identical(names(s$rain), c("thiessen", "gauge"))
  expect_identical(basename(unlist(s$rain)), c("a.csv", "b.csv"))
  expect_identical(s$rainfall_factor, c(0.9, 1.3))
  expect_identical(s$thresholds, data.frame(name = "Alert", value = 12, unit = "flow"))
})

test_that("every problem in the file is reported at once", {
  file <- site_folder(c(
    "site: {name: Bad, area_km2: lots}",
    "data: {folder: data, flow: missing.csv, pet: pet.csv, rain: rain.csv}",
    "calibration: ['2010-10-01', '2015-09-30']",
    "validation: ['2014-10-01', '2018-09-30']",
    "effort: maximal"))
  err <- tryCatch(read_site_settings(file), error = conditionMessage)
  # Four problems: the area, the missing flow file, overlapping windows, the effort.
  expect_match(err, "area_km2")
  expect_match(err, "missing.csv")
  expect_match(err, "validation must start after calibration ends")
  expect_match(err, "effort must be quick, standard or thorough")
})

test_that("settings changed in R are checked again", {
  s <- read_site_settings(site_folder(minimal))
  s$effort <- "quick"
  expect_identical(read_site_settings(s)$effort, "quick")
  s$area_km2 <- -1
  expect_error(read_site_settings(s), "area_km2")
})

test_that("every HOW TO READ note names a plot the script writes", {
  # The reading guide matches notes to plots by file name, so a note whose name drifts from
  # the file the script writes would silently drop out of the guide.
  code <- readLines(system.file("scripts", "calibrate_site.R", package = "pdmS7"))
  notes <- sub("^\\s*# HOW TO READ ", "", grep("^\\s*# HOW TO READ ", code, value = TRUE))
  expect_length(notes, 33)
  written <- code[!grepl("^\\s*#", code)]
  for (name in notes) {
    expect_true(any(grepl(sprintf('"%s"', name), written, fixed = TRUE)), info = name)
  }
})

test_that("rain gauges, the rain error and the regional results are read and checked", {
  file <- site_folder(
    c(minimal[-2],
      "data: {folder: data, flow: flow.csv, pet: pet.csv, rain: rain.csv,",
      "       rain_gauges: {Gauge A: a.csv, Gauge B: b.csv}}",
      "rain_error: 0.2",
      "regional_results: results.csv"),
    files = c("flow.csv", "pet.csv", "rain.csv", "a.csv", "b.csv"))
  home <- dirname(normalizePath(file))
  file.create(file.path(home, "results.csv"))
  s <- read_site_settings(file)
  expect_identical(names(s$rain_gauges), c("Gauge A", "Gauge B"))
  expect_identical(s$rain_gauges[["Gauge B"]], file.path(home, "data", "b.csv"))
  expect_identical(s$rain_error, 0.2)
  # The results file sits beside the settings file, not in the data folder.
  expect_identical(s$regional_results, file.path(home, "results.csv"))
  s$rain_error <- 1.5
  expect_error(read_site_settings(s), "rain_error")
  s$rain_error <- 0.2
  s$regional_results <- file.path(home, "missing.csv")
  expect_error(read_site_settings(s), "regional_results")
})

test_that("new_site() sets up an empty site that explains itself when read too soon", {
  folder <- file.path(tempfile("new"), "Mine")
  file <- suppressMessages(new_site(folder))
  expect_identical(file, file.path(folder, "site.yml"))
  expect_true(file.exists(file.path(folder, "data", "README.txt")))
  # The untouched example names data files that are not there yet: the error says so, and
  # says what to do.
  err <- tryCatch(read_site_settings(file), error = conditionMessage)
  expect_match(err, "Cannot find a flow file")
  expect_match(err, "still the example settings")
  expect_match(err, "practice = TRUE", fixed = TRUE)
})

test_that("new_site(practice = TRUE) is ready to run and never overwrites", {
  folder <- file.path(tempfile("practice"), "Practice")
  file <- suppressMessages(new_site(folder, practice = TRUE))
  s <- read_site_settings(file)
  expect_identical(s$area_km2, 60)
  expect_identical(s$step_hours, 1)
  expect_identical(names(s$rain_gauges), c("Gauge A", "Gauge B"))
  expect_identical(s$highest_gauged_m3s, 25L)
  # Six 365-day years of hourly steps: 6 x 365 x 24 = 52560 rows, plus the header.
  expect_length(readLines(s$flow), 52561)
  # The truth: the standard preset with 12-hour surface stores, as synthetic_catchment()
  # documents.
  truth <- utils::read.csv(file.path(folder, "data", "truth.csv"))
  expect_identical(truth$value[truth$parameter == "surface.k1"], 12)
  # A second call keeps what is there.
  writeLines("edited", file.path(folder, "data", "rain.csv"))
  expect_message(new_site(folder, practice = TRUE), "never overwrites")
  expect_identical(readLines(file.path(folder, "data", "rain.csv")), "edited")
})
