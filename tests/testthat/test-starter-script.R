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

test_that("the rain comparison parses, stops until the area is set, and names its plots", {
  script <- system.file("scripts", "compare_rain.R", package = "pdmS7")
  expect_true(nzchar(script))
  code <- readLines(script)
  expect_no_error(parse(text = code))
  # The area is left blank, so the script cannot run on a wrong default.
  expect_true(any(grepl("^area_km2 <- NA ", code)))
  # Every HOW TO READ note names a plot the script writes: 11, four for where the balance
  # fails (balance_years, flood_ratio_vs_rain, record_curves and candidate_band), and the
  # largest events' windows (flood_windows).
  notes <- sub("^\\s*# HOW TO READ ", "", grep("^\\s*# HOW TO READ ", code, value = TRUE))
  expect_length(notes, 16)
  written <- code[!grepl("^\\s*#", code)]
  for (name in notes) {
    expect_true(any(grepl(sprintf('"%s"', name), written, fixed = TRUE)), info = name)
  }
})

test_that("the H19 check parses and names the plots it draws", {
  script <- system.file("scripts", "check_h19.R", package = "pdmS7")
  expect_true(nzchar(script))
  code <- readLines(script)
  expect_no_error(parse(text = code))
  notes <- sub("^\\s*# HOW TO READ ", "", grep("^\\s*# HOW TO READ ", code, value = TRUE))
  expect_length(notes, 3)
  written <- code[!grepl("^\\s*#", code)]
  for (name in notes) {
    expect_true(any(grepl(sprintf('"%s"', name), written, fixed = TRUE)), info = name)
  }
})

test_that("the rain comparison finds its gauges by default, from a shapefile's centroid", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  # The default way of working: a search of the Hydrology API around the catchment, the gauges
  # chosen afterwards, the boundary a shapefile, and the radius worked out from the boundary.
  expect_true(any(grepl('^gauge_source <- "hydrology_api"', code)))
  expect_true(any(grepl("^gauge_ids <- c\\(\\)", code)))
  expect_true(any(grepl("^search_radius_km <- NULL", code)))
  expect_true(any(grepl('^catchment_boundary <- "catchment.shp"', code)))
  expect_true(any(grepl("^thiessen_weights <- c\\(\\)", code)))
})

test_that("the rain comparison has one period for everything, and both multiquadric averages", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  # One period cuts every series and sets the downloads; the old download_ names are gone.
  expect_true(any(grepl("^period_from <- ", code)))
  expect_true(any(grepl("^period_to <- ", code)))
  expect_false(any(grepl("download_from|download_to", code)))
  # The gauges-only and gauges-with-H19 multiquadric averages are both built names.
  expect_true(any(grepl('built_names <- c("thiessen", "equal", "equal_all", "idw", "multiquadric",',
                        code, fixed = TRUE)))
  expect_true(any(grepl('"multiquadric_h19"', code, fixed = TRUE)))
})

test_that("the rain comparison can scale the multiquadric by a long-term average grid", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  # Off by default; the grid's average is set against each series when given.
  expect_true(any(grepl("^lta_rain_file <- NULL", code)))
  expect_true(any(grepl('"multiquadric_lta"', code, fixed = TRUE)))
  expect_true(any(grepl("long_term_average_check.csv", code, fixed = TRUE)))
})

test_that("the gauges can be corrected to the long-term average over a long record", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  # Off by default; the correction record has its own window, and the downloads cover both.
  expect_true(any(grepl('^lta_correction <- "none"', code)))
  expect_true(any(grepl("^correction_from <- ", code)))
  expect_true(any(grepl("^correction_to <- ", code)))
  expect_true(any(grepl("gauge_downloads_record.csv", code, fixed = TRUE)))
})

test_that("the rain comparison is cut to the stretch every series covers", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  # The latest first value and the earliest last one, across every series and the flow.
  expect_true(any(grepl("keep <- seq(max(spans[1, ]), min(spans[2, ]))", code, fixed = TRUE)))
  expect_true(any(grepl("the stretch every series covers", code, fixed = TRUE)))
})

test_that("the rain comparison builds the averages chosen in rain_methods", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  # Every average is on the list by default, including the two new ones.
  start <- grep("^rain_methods <- c\\(", code)
  expect_length(start, 1)
  # The list runs to the first line ending in its closing bracket, however it is wrapped.
  end <- start - 1 + grep("\\)\\s*$", code[start:length(code)])[1]
  default <- eval(parse(text = paste(code[start:end], collapse = "\n")))
  expect_identical(default, c("thiessen", "equal", "equal_all", "idw", "multiquadric",
                              "multiquadric_lta", "kriging", "ked_lta", "h19", "h19_bias",
                              "h19_season", "multiquadric_h19", "ked_h19"))
  # A name the script cannot build is refused, and an average whose inputs are missing is
  # listed as not built, with the reason.
  expect_true(any(grepl("rain_methods names averages the script cannot build", code,
                        fixed = TRUE)))
  expect_true(any(grepl("Not built, though asked for:", code, fixed = TRUE)))
})

test_that("the rain comparison counts its years from the month set, calendar years by default", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  expect_true(any(grepl("^year_start_month <- 1$", code)))
  expect_true(any(grepl("water_year_start = year_start_month", code, fixed = TRUE)))
})

test_that("the rain comparison needs the pdmS7 it was written for", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  need <- sub('.*< "([0-9.]+)".*', "\\1", grep('packageVersion\\("pdmS7"\\) <', code, value = TRUE))
  expect_length(need, 1)
  # The version it asks for is never newer than the package it ships in.
  expect_true(utils::packageVersion("pdmS7") >= need)
})

test_that("the rain comparison says how sure its order is and what to calibrate on", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  # The floods drawn again 200 times, the places taken in 90% of the draws.
  expect_true(any(grepl("^draws <- 200$", code)))
  expect_true(any(grepl("place_low", code, fixed = TRUE)))
  # A list for calibration, written out, with near-copies left off.
  expect_true(any(grepl("recommended_for_calibration.csv", code, fixed = TRUE)))
  expect_true(any(grepl("near_copy <- function(a, b)", code, fixed = TRUE)))
  # The conditional merge is kept with a key of the gauges it came from.
  expect_true(any(grepl("radar_merge_key.txt", code, fixed = TRUE)))
  # Kriging with the radar as the drift is kept the same way, with the variogram in its key.
  expect_true(any(grepl("radar_ked_key.txt", code, fixed = TRUE)))
  # Where the balance fails: the diagnosis on the series recommended first, and the flow
  # record checked with reach.rate only when stage is given.
  expect_true(any(grepl("^stage_file <- NULL", code)))
  expect_true(any(grepl("balance_diagnosis(grid$time,", code, fixed = TRUE)))
  expect_true(any(grepl("reach.rate::check_flow_record(record,", code, fixed = TRUE)))
  # The WISKI ID alone is enough for the stage, and the gaugings and ratings may be data frames.
  expect_true(any(grepl('stage_file <- paste0("stage_", flow_station_wiski, ".csv")', code,
                        fixed = TRUE)))
  expect_true(any(grepl("read_or_take(gaugings_file,", code, fixed = TRUE)))
  expect_true(any(grepl("read_or_take(ratings_file,", code, fixed = TRUE)))
  expect_false(any(grepl("here(gaugings_file)", code, fixed = TRUE)))
  # Whether the rating needs more work, at the head of the section.
  expect_true(any(grepl("follow_up <- rating_follow_up(diagnosis,", code, fixed = TRUE)))
  expect_true(any(grepl("rating_follow_up.csv", code, fixed = TRUE)))
  # The candidate rating: fitted in the script when the gaugings call for it, at the in-force
  # breakpoints, written up for review, and the balance worked out on its flow.
  expect_true(any(grepl('^candidate_rating <- "auto"', code)))
  expect_true(any(grepl('breakpoint_origin = "existing_rating"', code, fixed = TRUE)))
  expect_true(any(grepl("reach.rate::rating_report(candidate,", code, fixed = TRUE)))
  expect_true(any(grepl("balance_with_candidate.csv", code, fixed = TRUE)))
  # Its bootstrap band: the flow bound in the diagnosis, and the refit test in the follow-up.
  expect_true(any(grepl("^candidate_boot <- 500", code)))
  expect_true(any(grepl("rating_band = rating_band_share)", code, fixed = TRUE)))
  expect_true(any(grepl("band = band)", code, fixed = TRUE)))
  # The band from reach.rate's rating_uncertainty(): combined where the shared gauging error is
  # given, sampling where not, never assumed; the bootstrap where reach.rate is older.
  expect_true(any(grepl("^gauging_uncertainty <- NULL", code)))
  expect_true(any(grepl("reach.rate::rating_uncertainty(candidate,", code, fixed = TRUE)))
  # Radar by season: why the raw radar sits apart from the gauges.
  expect_true(any(grepl("radar_season <- radar_by_season(season_pairs,", code, fixed = TRUE)))
  expect_true(any(grepl("radar_by_season.csv", code, fixed = TRUE)))
  # h19_season: the radar scaled by fixed monthly factors, written for a forecasting system.
  expect_true(any(grepl("season_factors <- radar_season_factors(factor_pairs)", code,
                        fixed = TRUE)))
  expect_true(any(grepl("radar_season_factors.csv", code, fixed = TRUE)))
  expect_true(any(grepl('exists("rating_uncertainty", envir = asNamespace("reach.rate")', code,
                        fixed = TRUE)))
})
