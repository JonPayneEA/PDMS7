# ============================================================ #
# Tool:         test-run_log
# Description:  Tests for the run log, fingerprints and approval register
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add run log tests
# Tier:         3
# Inputs:       Synthetic forcing; temporary projects and log files
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

use_run_log <- function(env = parent.frame(), register = NULL) {
  path <- tempfile(fileext = ".csv")
  old <- options(pdmS7.run_log = path, pdmS7.register = register, pdmS7.run_tag = NULL)
  .run_log_state$register <- NULL
  defer_to(function() { # nolint: object_usage_linter.
    options(old)
    unlink(path)
    .run_log_state$register <- NULL
  }, env)
  path
}

small_forcing <- function() data.frame(rain = c(0, 4, 2, 0, 0, 1), pet = 0.1)

test_that("nothing is logged unless asked", {
  old <- options(pdmS7.run_log = NULL)
  on.exit(options(old))
  withr_env <- Sys.getenv("PDMS7_RUN_LOG", unset = NA)
  Sys.unsetenv("PDMS7_RUN_LOG")
  on.exit(if (!is.na(withr_env)) Sys.setenv(PDMS7_RUN_LOG = withr_env), add = TRUE)
  expect_false(.run_log_active())
  expect_silent(run_pdm(pdm_model(), small_forcing()))
})

test_that("each run writes one row describing it", {
  path <- use_run_log()
  options(pdmS7.run_tag = "forecast 06:00")
  model <- pdm_model(area_km2 = 12)
  forcing <- small_forcing()
  forcing$time <- seq(as.POSIXct("2024-03-01", tz = "UTC"), by = 3600, length.out = 6)
  result <- run_pdm(model, forcing)
  sim_pdm(forcing$rain, forcing$pet, pdm_presets("standard"), timestep_min = 60)
  log <- read_run_log(path)
  expect_equal(nrow(log), 2L)
  expect_equal(log$fingerprint[1], pdm_fingerprint(model))
  expect_equal(log$tag[1], "forecast 06:00")
  expect_equal(log$rows[1], 6L)
  expect_equal(log$start[1], as.POSIXct("2024-03-01 00:00", tz = "UTC"))
  expect_equal(log$end[1], as.POSIXct("2024-03-01 05:00", tz = "UTC"))
  expect_s3_class(log$timestamp, "POSIXct")
  expect_equal(log$area_km2[1], 12)
  expect_equal(log$status, c("ok", "ok"))
  expect_true(all(is.na(log$approval)))
  expect_equal(log$data_md5[1], .data_md5(forcing))
  direct <- .run_pdm_core(model, forcing, initial_state(model))
  expect_equal(result$output$q_m3s, direct$output$q_m3s)
})

test_that("a failed run is logged and still fails", {
  path <- use_run_log()
  bad <- data.frame(rain = c(1, -1), pet = 0)
  expect_error(run_pdm(pdm_model(), bad), "nonnegative")
  log <- read_run_log(path)
  expect_equal(log$status, "error")
  expect_match(log$message, "nonnegative")
})

test_that("calibration, spin-up and the calibration log are not logged as runs", {
  path <- use_run_log()
  forcing <- make_forcing() # nolint: object_usage_linter.
  config <- pdm_presets("standard")
  observed <- run_pdm(pdm_from_config(config), forcing)$output$q_m3s
  calibrate_pdm(config, forcing, observed, lower = c(fc = 0.8), upper = c(fc = 1.2),
                control = list(maxit = 3))
  spin_up(pdm_from_config(config), forcing, cycles = 3)
  expect_equal(nrow(read_run_log(path)), 1L)
  p <- new_project() # simulates its "observed" flow with one logged run
  before <- nrow(read_run_log(path))
  log_trial(p$folder, 3, c(fc = 1), "better", "x")
  propose_candidate(p$folder, 4, "x")
  build_report(p$folder, sensitivity = FALSE)
  expect_equal(nrow(read_run_log(path)), before)
})

test_that("a fingerprint identifies the model however it was built", {
  config <- pdm_presets("standard")
  model <- pdm_from_config(config)
  expect_identical(pdm_fingerprint(config), pdm_fingerprint(model))
  integer_area <- config
  integer_area$area_km2 <- 1L
  expect_identical(pdm_fingerprint(integer_area), pdm_fingerprint(model))
  changed <- config
  changed$surface$k1 <- 2.0000001
  expect_false(identical(pdm_fingerprint(changed), pdm_fingerprint(model)))
  expect_match(pdm_fingerprint(model), "^[0-9a-f]{32}$")
  expect_error(pdm_fingerprint(42), "configuration")
})

test_that("runs are flagged approved, superseded or unapproved", {
  p <- new_project()
  log_trial(p$folder, 3, c(fc = 1), "better", "Volume too low")
  propose_candidate(p$folder, 4, "Best")
  validate_candidate(p$folder, "Holds")
  as_person("Sam Steward", "steward", "sam")
  sign_off_project(p$folder, "Accepted", all_reviewed)
  register <- tempfile(fileext = ".yml")
  writeLines(c("projects:", paste0("  - ", basename(p$folder)), "  - no-such-project"), register)
  file.copy(register, file.path(dirname(p$folder), basename(register)))
  register <- file.path(dirname(p$folder), basename(register))
  table <- approved_configurations(register)
  expect_equal(table$status, c("current", "unreadable"))
  path <- use_run_log(register = register)
  approved <- read_project(p$folder)
  config <- .read_entries(approved$path)[[7]]$configuration
  forcing <- p$data$forcing[1:48, ]
  run_pdm(pdm_from_config(config), forcing)
  run_pdm(pdm_model(area_km2 = 20), forcing)
  reopen_project(p$folder, "New rating")
  .run_log_state$register <- NULL
  run_pdm(pdm_from_config(config), forcing)
  log <- read_run_log(path)
  expect_equal(log$approval, c("approved", "unapproved", "superseded"))
  expect_equal(log$project[c(1, 3)], rep(approved$id, 2))
  expect_equal(log$sign_off[1], "0007")
})

test_that("a logging failure warns once and never stops a run", {
  blocker <- tempfile()
  writeLines("x", blocker)
  old <- options(pdmS7.run_log = file.path(blocker, "sub", "runs.csv"))
  on.exit(options(old))
  .run_log_state$warned <- FALSE
  expect_warning(out <- run_pdm(pdm_model(), small_forcing()), "run log not written")
  expect_true(is.list(out))
  expect_silent(run_pdm(pdm_model(), small_forcing()))
  .run_log_state$warned <- FALSE
})
