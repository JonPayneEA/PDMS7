# ============================================================ #
# Tool:         test-batch
# Description:  Tests for batch calibration
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add batch calibration tests
# Tier:         3
# Inputs:       Temporary basin folders
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

make_basins <- function(n_basins = 3, env = parent.frame()) {
  root <- tempfile("basins-")
  output <- tempfile("batch-")
  defer_to(function() unlink(c(root, output), recursive = TRUE), env) # nolint: object_usage_linter.
  set.seed(3)
  n <- 24 * 40
  time <- seq(as.POSIXct("2023-10-01", tz = "UTC"), by = 3600, length.out = n)
  for (i in seq_len(n_basins)) {
    folder <- file.path(root, sprintf("B%02d", i))
    dir.create(folder, recursive = TRUE)
    forcing <- data.frame(time = format(time, "%Y-%m-%dT%H:%M:%SZ"), pet = 0.05,
                          rain = ifelse(stats::runif(n) < 0.07, stats::rgamma(n, 0.7, scale = 3),
                                        0))
    truth <- pdm_presets("standard")
    truth$area_km2 <- 20 * i
    q <- run_pdm(pdm_from_config(truth), forcing[, c("rain", "pet")])$output$q_m3s
    data.table::fwrite(forcing, file.path(folder, "forcing.csv"))
    data.table::fwrite(data.frame(q_m3s = q), file.path(folder, "flow.csv"))
    writeLines(c(paste("area_km2:", 20 * i), "calibration: [2023-10-08, 2023-10-28]",
                 "validation: [2023-10-29, 2023-11-03]", "test: [2023-11-04, 2023-11-09]"),
               file.path(folder, "basin.yml"))
  }
  list(root = root, output = output)
}

quick <- list(starts = 1, control = list(maxit = 5),
              exclude = c("groundwater.kb", "distribution.b", "recharge.kg"))

test_that("a batch calibrates every basin, records failures and resumes", {
  b <- make_basins()
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  bad <- file.path(b$root, "B02", "forcing.csv")
  good <- readLines(bad)
  broken <- good
  broken[50] <- sub(",0.05,", ",-1,", broken[50], fixed = TRUE)
  writeLines(broken, bad)
  status <- do.call(calibrate_batch, c(list(b$root, b$output), quick))
  expect_equal(status$state, c("done", "failed", "done"))
  expect_equal(status$step[2], "register")
  expect_match(status$message[2], "pet")
  expect_equal(as.integer(attr(status, "counts")[c("done", "failed")]), c(2L, 1L))
  expect_equal(read_project(file.path(b$output, "B01"))$entries$type,
               c("project_start", "data_registered", "structure_selected", "auto_calibration",
                 "candidate", "validation"))
  writeLines(good, bad)
  status <- do.call(calibrate_batch, c(list(b$root, b$output, only = "B02"), quick))
  expect_equal(status$state, rep("done", 3))
  expect_equal(sum(read_project(file.path(b$output, "B02"))$entries$type == "project_start"), 1L)
  results <- batch_results(b$output)
  expect_equal(results$project, c("B01", "B02", "B03"))
  expect_true(all(!is.na(results$validation_score)))
})

test_that("finished steps are never repeated and new steps are added", {
  b <- make_basins(2)
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  do.call(calibrate_batch, c(list(b$root, b$output), quick))
  before <- read_project(file.path(b$output, "B01"))$entries
  do.call(calibrate_batch, c(list(b$root, b$output, test = TRUE), quick))
  after <- read_project(file.path(b$output, "B01"))$entries
  expect_equal(after$type, c(before$type, "test"))
  expect_true(all(verify_project(file.path(b$output, "B01"))$ok))
})

test_that("an interrupted basin carries on from its last step", {
  b <- make_basins(1)
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  project <- file.path(b$output, "B01")
  start_calibration_project(project, "B01", "B01", "Batch calibration", 20, "O", "S", id = "B01")
  register_data(project, file.path(b$root, "B01", "forcing.csv"),
                file.path(b$root, "B01", "flow.csv"), c("2023-10-08", "2023-10-28"),
                c("2023-10-29", "2023-11-03"))
  do.call(calibrate_batch, c(list(b$root, b$output), quick))
  types <- read_project(project)$entries$type
  expect_equal(sum(types == "data_registered"), 1L)
  expect_equal(types[3:6], c("structure_selected", "auto_calibration", "candidate",
                             "validation"))
})

test_that("seeds depend on the basin and inputs are checked", {
  expect_identical(.basin_seed("B07", 1), .basin_seed("B07", 1))
  expect_false(identical(.basin_seed("B07", 1), .basin_seed("B08", 1)))
  b <- make_basins(1)
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  expect_error(calibrate_batch(b$root, b$output, only = "Nope"), "Unknown basins")
  expect_error(calibrate_batch(tempfile(), b$output), "folder")
  empty <- tempfile()
  dir.create(empty)
  on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  expect_error(calibrate_batch(empty, b$output), "No basin folders")
  expect_error(batch_status(empty), "No batch status")
})

test_that("a parallel batch gives the same results as a serial one", {
  skip_on_cran()
  b <- make_basins(2)
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  serial <- file.path(b$output, "serial")
  parallel_run <- file.path(b$output, "parallel")
  do.call(calibrate_batch, c(list(b$root, serial), quick))
  do.call(calibrate_batch, c(list(b$root, parallel_run, cores = 2), quick))
  expect_equal(batch_results(parallel_run)$candidate_score,
               batch_results(serial)$candidate_score)
})

test_that("a snow basin is calibrated on PACK rain and melt at fixed parameters", {
  b <- make_basins(1)
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  folder <- file.path(b$root, "B01")
  forcing <- data.table::fread(file.path(folder, "forcing.csv"))
  n <- nrow(forcing)
  forcing$temperature <- 2 + 6 * sin(2 * pi * seq_len(n) / (24 * 10))
  data.table::fwrite(forcing, file.path(folder, "forcing.csv"))
  cat("snow: true\n", file = file.path(folder, "basin.yml"), append = TRUE)
  status <- do.call(calibrate_batch, c(list(b$root, b$output), quick))
  expect_equal(status$state, "done")
  project <- file.path(b$output, "B01")
  entries <- read_project(project)$entries
  expect_equal(entries$type[1:3], c("project_start", "note", "data_registered"))
  note <- read_entry(project, entries$id[2])
  expect_match(note$text, "^Snow: .*not calibrated")
  expect_match(note$text, pdmS7:::.md5_file(file.path(folder, "forcing.csv")), fixed = TRUE)
  stored <- data.table::fread(list.files(file.path(project, "data"), "forcing",
                                         recursive = TRUE, full.names = TRUE)[1])
  melt <- sim_pack(forcing$rain, forcing$temperature, pack_presets())$effective_rain_mm
  expect_equal(stored$rain, melt, tolerance = 1e-6)
  expect_false(isTRUE(all.equal(stored$rain, forcing$rain)))
  # A rerun neither repeats the note nor the registration.
  do.call(calibrate_batch, c(list(b$root, b$output), quick))
  expect_equal(nrow(read_project(project)$entries), nrow(entries))
  writeLines(c(readLines(file.path(folder, "basin.yml"))[1:4], "snow: [1, 2]"),
             file.path(folder, "basin.yml"))
  expect_error(pdmS7:::.basin_pack(list(snow = c(1, 2), folder = folder)), "snow in basin.yml")
})
