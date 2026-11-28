# The hand-off from compare_rain.R to calibrate_site.R: calibration_inputs.yml, written by
# write_calibration_inputs() and read by read_calibration_inputs() and read_site_settings().

# A comparison's output folder with the series' files in catchment_rain/, and its hand-off.
comparison <- function(rain = c(thiessen = "catchment_rain/thiessen.csv",
                                multiquadric = "catchment_rain/multiquadric.csv"),
                       step_hours = 0.25, rain_error = 0.12,
                       warnings = "Gauge A's clock: logged in local time.",
                       period = c("2010-10-01", "2018-10-01")) {
  folder <- tempfile("rain_comparison")
  dir.create(file.path(folder, "catchment_rain"), recursive = TRUE)
  for (f in rain) file.create(file.path(folder, f))
  write_calibration_inputs(file.path(folder, "calibration_inputs.yml"), rain, period = period,
                           step_hours = step_hours, rain_error = rain_error,
                           warnings = warnings, made_by = "test")
  folder
}

# A site whose settings take their rain from a comparison: no data: rain.
site_with <- function(folder, extra = character(0), step_hours = 0.25) {
  home <- tempfile("site")
  dir.create(file.path(home, "data"), recursive = TRUE)
  for (f in c("flow.csv", "pet.csv")) file.create(file.path(home, "data", f))
  writeLines(c("site: {name: Test Brook, area_km2: 12.5}",
               sprintf("data: {folder: data, step_hours: %s, flow: flow.csv, pet: pet.csv}",
                       step_hours),
               "calibration: ['2010-10-01', '2015-09-30 23:45']",
               "validation: ['2015-10-01', '2018-09-30 23:45']",
               sprintf("rain_comparison: %s", folder),
               extra),
             file.path(home, "site.yml"))
  file.path(home, "site.yml")
}

test_that("the hand-off reads back as written, its paths from its own folder", {
  folder <- comparison()
  ci <- read_calibration_inputs(folder)
  expect_s3_class(ci, "pdm_calibration_inputs")
  home <- normalizePath(folder)
  # The order is kept: the first calibrates.
  expect_identical(names(ci$rain), c("thiessen", "multiquadric"))
  expect_identical(ci$rain$thiessen, file.path(home, "catchment_rain", "thiessen.csv"))
  expect_identical(ci$rain_error, 0.12)
  expect_identical(ci$step_hours, 0.25)
  expect_identical(ci$period, c("2010-10-01", "2018-10-01"))
  expect_identical(ci$warnings, "Gauge A's clock: logged in local time.")
  # The file itself, or its folder, both serve.
  expect_identical(read_calibration_inputs(file.path(folder, "calibration_inputs.yml"))$rain,
                   ci$rain)
  expect_output(print(ci), "thiessen.csv \\(calibrates\\)")
})

test_that("no rain error and no warnings read as NA and none", {
  ci <- read_calibration_inputs(comparison(rain_error = NA, warnings = character(0)))
  expect_identical(ci$rain_error, NA_real_)
  expect_identical(ci$warnings, character(0))
  expect_output(print(ci), "No warnings")
})

test_that("a missing hand-off or a missing series is refused with what to do", {
  expect_error(read_calibration_inputs(tempdir()), "run compare_rain.R")
  folder <- comparison()
  unlink(file.path(folder, "catchment_rain", "multiquadric.csv"))
  expect_error(read_calibration_inputs(folder), "missing for multiquadric")
  expect_error(write_calibration_inputs(tempfile(), c("a.csv"), c("2010-10-01", "2011-10-01"),
                                        0.25), "named character vector")
  expect_error(write_calibration_inputs(tempfile(), c(a = "a.csv"), "2010-10-01", 0.25),
               "two dates")
})

test_that("a site naming the comparison takes its rain, rain error and warnings", {
  folder <- comparison()
  s <- read_site_settings(site_with(folder))
  home <- normalizePath(folder)
  expect_identical(names(s$rain), c("thiessen", "multiquadric"))
  expect_identical(s$rain$thiessen, file.path(home, "catchment_rain", "thiessen.csv"))
  expect_true(s$rain_from_comparison)
  # rain_error not given: the comparison's, 0.12.
  expect_identical(s$rain_error, 0.12)
  expect_true(s$rain_error_from_comparison)
  expect_identical(s$calibration_inputs$warnings, "Gauge A's clock: logged in local time.")
  expect_output(print(s), "Rain from:    the rain comparison")
  expect_output(print(s), "logged in local time")
  # Read again in R, as the script does: the same rain, and no second copy of a warning.
  again <- read_site_settings(s)
  expect_identical(again$rain, s$rain)
  expect_identical(again$calibration_inputs$warnings, s$calibration_inputs$warnings)
})

test_that("a rain error given in the settings wins over the comparison's", {
  s <- read_site_settings(site_with(comparison(), "rain_error: 0.2"))
  expect_identical(s$rain_error, 0.2)
  expect_false(s$rain_error_from_comparison)
})

test_that("rain given both ways, or at another step, is refused", {
  folder <- comparison()
  file <- site_with(folder)
  lines <- readLines(file)
  lines[2] <- "data: {folder: data, step_hours: 0.25, flow: flow.csv, pet: pet.csv, rain: r.csv}"
  writeLines(lines, file)
  file.create(file.path(dirname(file), "data", "r.csv"))
  expect_error(read_site_settings(file), "not both")
  # Hourly site data against 15-minute comparison rain.
  expect_error(read_site_settings(site_with(folder, step_hours = 1)),
               "0.25-hour steps, the site's data at 1")
})

test_that("calibration beyond the period the rain was judged over is warned of", {
  # The comparison judged 2012-10-01 to 2018-10-01; calibration starts 2010-10-01.
  s <- read_site_settings(site_with(comparison(period = c("2012-10-01", "2018-10-01"))))
  expect_length(s$calibration_inputs$warnings, 2)
  expect_match(s$calibration_inputs$warnings[2], "part of them uses rain it did not judge")
})

test_that("forecast_use is stage by default, and only the three uses are taken", {
  s <- read_site_settings(site_with(comparison()))
  expect_identical(s$forecast_use, "stage")
  # Without a band (comparison() writes none), hydrodynamic_own needs peak_tolerance: 0.
  s2 <- read_site_settings(site_with(comparison(),
                                     c("forecast_use: hydrodynamic_own", "peak_tolerance: 0")))
  expect_identical(s2$forecast_use, "hydrodynamic_own")
  expect_error(read_site_settings(site_with(comparison(), "forecast_use: flood_map")),
               "forecast_use must be stage, hydrodynamic_rated or hydrodynamic_own")
})

test_that("the example site.yml leaves the comparison out and forecasts stage", {
  ex <- yaml::read_yaml(system.file("examples", "site.yml", package = "pdmS7"))
  expect_true("rain_comparison" %in% names(ex))
  expect_null(ex$rain_comparison)
  expect_identical(ex$forecast_use, "stage")
  # rain_error left null: 0.15 without a comparison.
  expect_null(ex$rain_error)
})

test_that("both scripts know the hand-off", {
  cr <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  call <- 'write_calibration_inputs(file.path(output_folder, "calibration_inputs.yml"),'
  expect_true(any(grepl(call, cr, fixed = TRUE)))
  cs <- readLines(system.file("scripts", "calibrate_site.R", package = "pdmS7"))
  expect_true(any(grepl("ci <- s$calibration_inputs", cs, fixed = TRUE)))
})

test_that("a site with rain gauges but no data: rain reads its rain from the comparison", {
  # Regression: the settings were read with `$`, which partial-matches, so a data: block with
  # rain_gauges and no rain read rain_gauges as the rain, and then refused it as rain given
  # both ways.
  folder <- comparison()
  file <- site_with(folder)
  lines <- readLines(file)
  lines[2] <- paste("data: {folder: data, step_hours: 0.25, flow: flow.csv, pet: pet.csv,",
                    "rain_gauges: {Gauge A: a.csv}}")
  writeLines(lines, file)
  file.create(file.path(dirname(file), "data", "a.csv"))
  s <- read_site_settings(file)
  expect_identical(names(s$rain), c("thiessen", "multiquadric"))
  expect_identical(names(s$rain_gauges), "Gauge A")
})

test_that("the hand-off carries the mask periods and the rating band", {
  folder <- tempfile("rain_comparison")
  dir.create(file.path(folder, "catchment_rain"), recursive = TRUE)
  file.create(file.path(folder, "catchment_rain", "thiessen.csv"))
  write_calibration_inputs(
    file.path(folder, "calibration_inputs.yml"), c(thiessen = "catchment_rain/thiessen.csv"),
    period = c("2010-10-01", "2018-10-01"), step_hours = 0.25,
    mask = data.frame(from = as.POSIXct("2015-12-05 06:00", tz = "UTC"),
                      to = as.POSIXct("2015-12-07 18:00", tz = "UTC"),
                      reason = "an event thiessen missed"),
    rating_band = data.frame(q = c(1, 50), lower = c(-0.05, -0.2), upper = c(0.05, 0.3)),
    rating_band_source = "the candidate's band")
  ci <- read_calibration_inputs(folder)
  expect_identical(ci$mask, data.frame(from = "2015-12-05 06:00", to = "2015-12-07 18:00",
                                       reason = "an event thiessen missed"))
  expect_identical(ci$rating_band, data.frame(q = c(1, 50), lower = c(-0.05, -0.2),
                                              upper = c(0.05, 0.3)))
  expect_identical(ci$rating_band_source, "the candidate's band")
  expect_output(print(ci), "Mask: 1 periods")
})

# A comparison with a band and a mask, for the peak tolerance tests.
banded <- function() {
  folder <- tempfile("rain_comparison")
  dir.create(file.path(folder, "catchment_rain"), recursive = TRUE)
  file.create(file.path(folder, "catchment_rain", "thiessen.csv"))
  write_calibration_inputs(
    file.path(folder, "calibration_inputs.yml"), c(thiessen = "catchment_rain/thiessen.csv"),
    period = c("2010-10-01", "2018-10-01"), step_hours = 0.25,
    mask = data.frame(from = "2012-01-01 00:00", to = "2012-01-02 00:00", reason = "missed"),
    rating_band = data.frame(q = c(1, 50), lower = c(-0.05, -0.2), upper = c(0.05, 0.3)),
    rating_band_source = "a test band")
  folder
}

test_that("peak_tolerance auto: none for stage and rated, half the band for hydrodynamic_own", {
  folder <- banded()
  st <- read_site_settings(site_with(folder))
  expect_identical(st$peak_tolerance_factor, 0)
  expect_match(st$peak_tolerance_reason, "auto, for forecast_use stage: none")
  rated <- read_site_settings(site_with(folder, "forecast_use: hydrodynamic_rated"))
  expect_identical(rated$peak_tolerance_factor, 0)
  own <- read_site_settings(site_with(folder, "forecast_use: hydrodynamic_own"))
  expect_identical(own$peak_tolerance_factor, 0.5)
  expect_match(own$peak_tolerance_reason, "about one standard error")
  expect_identical(own$rating_band_source, "a test band")
  expect_identical(nrow(own$calibration_inputs$mask), 1L)
  # A factor given wins, and says so.
  two <- read_site_settings(site_with(folder, c("forecast_use: stage", "peak_tolerance: 2")))
  expect_identical(two$peak_tolerance_factor, 2)
  expect_match(two$peak_tolerance_reason, "given in the settings: 2 times")
  expect_output(print(own), "errors within 0.5 of the rating's band forgiven")
})

test_that("a tolerance with no band to hand is refused, never assumed", {
  # comparison() writes no band.
  expect_error(read_site_settings(site_with(comparison(), "forecast_use: hydrodynamic_own")),
               "peak_tolerance needs the rating's band")
  expect_error(read_site_settings(site_with(banded(), "peak_tolerance: lots")),
               "peak_tolerance must be auto, 0")
  expect_error(read_site_settings(site_with(banded(), "mask_periods: [{from: x, to: y}]")),
               "each from and to must be a date-time")
})
