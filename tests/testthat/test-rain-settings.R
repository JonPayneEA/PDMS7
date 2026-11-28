template <- function() system.file("examples", "rain.yml", package = "pdmS7")

# A settings file in a fresh folder, from lines of YAML.
write_settings <- function(..., folder = withr::local_tempdir(.local_envir = parent.frame())) {
  path <- file.path(folder, "rain.yml")
  writeLines(c(...), path)
  path
}

# The settings block of compare_rain.R, run on its own in env: what the script does before it
# reads any data.
run_settings_block <- function(env) {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  from <- grep("^# ---- Settings: read from rain.yml", code)
  to <- grep("^# ---- Read and line up the data", code) - 1
  eval(parse(text = code[from:to]), envir = env)
}

test_that("the template holds the defaults, key for key", {
  s <- read_rain_settings(template())
  d <- pdmS7:::.rain_defaults()
  expect_s3_class(s, "pdm_rain_settings")
  expect_identical(names(unclass(s)), names(d))
  home <- dirname(normalizePath(template()))
  for (key in names(d)) {
    expected <- d[[key]]
    if (key %in% c("data_folder", "output_folder")) expected <- file.path(home, expected)
    expect_identical(s[[key]], expected, info = key)
  }
  expect_identical(attr(s, "file"), normalizePath(template()))
})

test_that("every setting is a variable the script uses", {
  code <- readLines(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  used <- code[!grepl("^\\s*#", code)]
  for (key in names(pdmS7:::.rain_defaults())) {
    expect_true(any(grepl(sprintf("\\b%s\\b", key), used)), info = key)
  }
})

test_that("groups are for reading: a key may sit in any group or at the top level", {
  a <- read_rain_settings(write_settings("catchment:", "  area_km2: 52.3"))
  b <- read_rain_settings(write_settings("area_km2: 52.3"))
  c <- read_rain_settings(write_settings("events:", "  area_km2: 52.3"))
  expect_identical(a$area_km2, 52.3)
  expect_identical(b$area_km2, 52.3)
  expect_identical(c$area_km2, 52.3)
  # Everything left out takes its default.
  expect_identical(a$step_hours, 0.25)
  expect_identical(a$candidate_rating, "auto")
})

test_that("a misspelt or repeated key is refused, never ignored", {
  expect_error(read_rain_settings(write_settings("catchment:", "  area_km: 52.3")),
               "does not know: catchment: area_km")
  expect_error(read_rain_settings(write_settings("aera_km2: 52.3")), "does not know: aera_km2")
  expect_error(read_rain_settings(write_settings("area_km2: 50", "catchment:",
                                                 "  area_km2: 52.3")),
               "given twice: area_km2")
})

test_that("YAML's lists become the vectors and data frames the script works with", {
  s <- read_rain_settings(write_settings(
    "rain_gauges:",
    "  gauge_ids: [254336TP, 100000, \"SS92F014\"]",
    "  thiessen_weights: {\"254336TP\": 0.264, SS92F014: 0.736}",
    "  gauges:",
    "    - {name: A, file: a.csv, x: 412000, y: 291000}",
    "    - {name: n, file: n.csv, x: 413500.5, y: null}",
    "other_rain_files: {radar: rain_h19.csv}"))
  # 100000 written without quotes reads as a number: kept as its digits, never "1e+05".
  expect_identical(s$gauge_ids, c("254336TP", "100000", "SS92F014"))
  expect_identical(s$thiessen_weights, c("254336TP" = 0.264, SS92F014 = 0.736))
  expect_identical(s$other_rain_files, c(radar = "rain_h19.csv"))
  # YAML 1.1 reads a bare y or n as true or false. The key y and a gauge named n stay text.
  expect_identical(s$gauges, data.frame(name = c("A", "n"), file = c("a.csv", "n.csv"),
                                        x = c(412000, 413500.5), y = c(291000, NA)))
  # true and false still read as TRUE and FALSE.
  f <- read_rain_settings(write_settings("radar_scan_only: true", "event_independent: false"))
  expect_true(f$radar_scan_only)
  expect_false(f$event_independent)
})

test_that("folders are taken from the settings file's folder; file names are left to data_folder", {
  folder <- withr::local_tempdir()
  path <- write_settings("data_folder: inputs", "output_folder: /tmp/out",
                         "flow_file: flow_39001.csv", folder = folder)
  s <- read_rain_settings(path)
  expect_identical(s$data_folder, file.path(normalizePath(folder), "inputs"))
  expect_identical(s$output_folder, "/tmp/out")
  expect_identical(s$flow_file, "flow_39001.csv")
  expect_null(s$radar_folder)
})

test_that("every problem is reported at once, each with its advice", {
  err <- tryCatch(read_rain_settings(write_settings(
    "area_km2: -3", "step_hours: 0", "period_from: \"2024-10-01\"", "period_to: \"2015-10-01\"",
    "year_start_month: 13", "gauge_source: wiski", "rain_methods: [thiessen, krigin]",
    "lta_correction: some", "candidate_rating: sometimes", "candidate_boot: 50",
    "gauging_uncertainty: 0.7", "missed_share: 1.5")), error = conditionMessage)
  for (part in c("area_km2 must be the catchment area", "step_hours must be",
                 "period_from must come before period_to", "year_start_month must be",
                 "gauge_source must be hydrology_api or files", "rain_methods holds krigin",
                 "lta_correction must be none, relative or absolute",
                 "candidate_rating must be auto, always or never", "candidate_boot must be",
                 "gauging_uncertainty must be", "missed_share must be")) {
    expect_match(err, part, fixed = TRUE)
  }
  expect_error(read_rain_settings(write_settings("period_from: 1st October")),
               "period_from must be a date")
})

test_that("settings changed in R are checked again, and may hold data frames", {
  s <- read_rain_settings(template())
  s$gaugings_file <- data.frame(stage_m = 1, discharge_cms = 2)
  s$gauge_ids <- c("254336TP", "SS92F014")
  again <- read_rain_settings(s)
  expect_identical(again$gaugings_file, s$gaugings_file)
  expect_identical(again$gauge_ids, s$gauge_ids)
  s$candidate_rating <- "sometimes"
  expect_error(read_rain_settings(s), "candidate_rating must be auto, always or never")
})

test_that("the print shows where the settings came from and what will run", {
  s <- read_rain_settings(template())
  expect_output(print(s), "Rain settings from .*rain.yml")
  expect_output(print(s), "3 gauges: gauge_A, gauge_B, gauge_C")
  expect_output(print(s), "gauge_ids +\\(none\\)")
})

test_that("the script reads rain.yml, or settings_file, and makes each setting a variable", {
  folder <- withr::local_tempdir()
  withr::local_dir(folder)
  env <- new.env(parent = globalenv())
  expect_error(run_settings_block(env), "No settings file .*Copy the template")
  writeLines(c("area_km2: 52.3", "gauge_ids: [254336TP]"), "rain.yml")
  expect_output(run_settings_block(env), "Settings from .*rain.yml")
  expect_identical(env$area_km2, 52.3)
  expect_identical(env$gauge_ids, "254336TP")
  expect_identical(env$candidate_boot, 500)
  # settings_file names another file.
  env2 <- new.env(parent = globalenv())
  writeLines("area_km2: 10", "other.yml")
  env2$settings_file <- "other.yml"
  expect_output(run_settings_block(env2), "other.yml")
  expect_identical(env2$area_km2, 10)
})

test_that("the script keeps settings changed in R, unless the file changed since", {
  folder <- withr::local_tempdir()
  withr::local_dir(folder)
  writeLines("area_km2: 52.3", "rain.yml")
  env <- new.env(parent = globalenv())
  env$rain_settings <- read_rain_settings("rain.yml")
  env$rain_settings$step_hours <- 1
  expect_output(run_settings_block(env), "Settings from")
  expect_identical(env$step_hours, 1)
  # The file edited after it was read: read again, with a message, and the change in R dropped.
  writeLines("area_km2: 60", "rain.yml")
  Sys.setFileTime("rain.yml", attr(env$rain_settings, "mtime") + 10)
  expect_message(expect_output(run_settings_block(env)), "has changed since")
  expect_identical(env$area_km2, 60)
  expect_identical(env$step_hours, 0.25)
})

test_that("a setting that must be given says what to give", {
  expect_error(read_rain_settings(write_settings("step_hours: null")),
               "step_hours must be given: the time step in hours", fixed = TRUE)
})
