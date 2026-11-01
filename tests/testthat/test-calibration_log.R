# ============================================================ #
# Tool:         test-calibration_log
# Description:  Tests for the calibration log
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add calibration log tests
# Tier:         3
# Inputs:       Synthetic forcing and flow in temporary project folders
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

all_reviewed <- c(integrity = TRUE, data = TRUE, calibration_path = TRUE, validation = TRUE)

# Runs f() when env exits, like withr::defer, without the dependency.
defer_to <- function(f, env) {
  do.call(base::on.exit, list(as.call(list(f)), add = TRUE), envir = env)
}

as_person <- function(name, role, login, env = parent.frame()) {
  old <- options(pdmS7.user = name, pdmS7.role = role)
  local_mocked_bindings(.login = function() login, .env = env) # nolint: object_usage_linter.
  defer_to(function() options(old), env)
}

log_data <- function(n = 24 * 40) {
  set.seed(7)
  time <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600, length.out = n)
  forcing <- data.frame(
    time = time, rain = ifelse(stats::runif(n) < 0.06, stats::rexp(n, 0.3), 0), pet = 0.08
  )
  truth <- pdm_presets("standard")
  truth$area_km2 <- 20
  truth$recharge$kg <- 400
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s *
    exp(stats::rnorm(n, 0, 0.03))
  observed[200:210] <- NA
  list(forcing = forcing, observed = observed, truth = truth)
}

new_project <- function(env = parent.frame()) {
  folder <- tempfile("project-")
  defer_to(function() unlink(folder, recursive = TRUE), env)
  d <- log_data()
  as_person("Ann Custodian", "custodian", "ann", env)
  start_calibration_project(folder, "Test Brook", "99999", "Testing", 20, "A Director",
                            "Sam Steward")
  register_data(folder, d$forcing, d$observed, calibration = c(121, 700),
                validation = c("2021-01-31", "2021-02-09 23:00"))
  start <- d$truth
  start$fc <- 0.85
  select_structure(folder, start, "Standard structure")
  list(folder = folder, data = d)
}

test_that("numbers survive the log exactly", {
  x <- c(0.4, 1 / 3, 140, 1e-10, -2.5e30, 0, 123456789.123, .Machine$double.eps, pi)
  text <- yaml::as.yaml(.yaml_ready(list(v = x, s = 0.1 + 0.2, n = NA_real_, i = 3L)))
  back <- yaml::yaml.load(text)
  expect_identical(back$v, x)
  expect_identical(back$s, 0.1 + 0.2)
  expect_true(is.na(back$n))
  expect_identical(back$i, 3L)
  expect_identical(yaml::yaml.load(yaml::as.yaml(.yaml_ready(list(k = c(a = 2))))),
                   list(k = 2))
})

test_that("a project records the full calibration path", {
  p <- new_project()
  first <- log_trial(p$folder, 3, c(fc = 1), "better", "Volume too low")
  expect_equal(first$id, "0004")
  expect_equal(first$changes$fc$from, 0.85)
  expect_equal(first$configuration$fc, 1)
  log_trial(p$folder, "0004", c(surface.k1 = 3), "inconclusive", "Peak timing")
  log_note(p$folder, "Gauge check in January", refers_to = 2)
  trials <- project_trials(p$folder)
  expect_equal(trials$id, c("0003", "0004", "0005"))
  expect_equal(trials$parent, c(NA, "0003", "0004"))
  expect_gt(trials$nse[2], trials$nse[1])
  expect_match(trials$changes[2], "fc 0.85 -> 1")
  info <- read_project(p$folder)
  expect_equal(info$status, "open")
  expect_equal(info$entries$type, c("project_start", "data_registered", "structure_selected",
                                    "trial", "trial", "note"))
  expect_equal(unique(info$entries$login), "ann")
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
})

test_that("trials are scored on the calibration window only", {
  p <- new_project()
  preview <- preview_trial(p$folder, 3, c(fc = 1))
  expect_equal(preview$rows, 121:700)
  expected <- pdm_scorecard(preview$simulated[121:700], p$data$observed[121:700])
  expect_equal(unlist(preview$scores), expected)
  expect_length(list.files(file.path(p$folder, "entries")), 3L)
})

test_that("candidate, validation, sign-off and reopen follow the rules", {
  p <- new_project()
  log_trial(p$folder, 3, c(fc = 1), "better", "Volume too low")
  expect_error(validate_candidate(p$folder, "x"), "candidate first")
  propose_candidate(p$folder, 4, "Best so far")
  expect_error(sign_off_project(p$folder, "x", all_reviewed), "steward")
  val <- validate_candidate(p$folder, "Holds up")
  expect_equal(val$candidate, "0005")
  expect_true(file.exists(file.path(p$folder, val$series$file)))
  as_person("Ann Custodian", "steward", "ann")
  expect_error(sign_off_project(p$folder, "Self", all_reviewed), "another Steward")
  as_person("Someone Else", "steward", "ann")
  expect_error(sign_off_project(p$folder, "Same login", all_reviewed), "another Steward")
  as_person("Sam Steward", "steward", "sam")
  expect_error(sign_off_project(p$folder, "x", all_reviewed[1:3]), "Confirm")
  signed <- sign_off_project(p$folder, "Accepted", all_reviewed)
  expect_equal(signed$candidate, "0005")
  expect_equal(read_project(p$folder)$status, "signed_off")
  expect_error(log_note(p$folder, "late"), "signed off")
  reopen_project(p$folder, "New rating curve")
  expect_equal(read_project(p$folder)$status, "reopened")
  as_person("Ann Custodian", "custodian", "ann")
  expect_silent(log_note(p$folder, "Recalibrating"))
  expect_error(reopen_project(p$folder, "x"), "steward")
})

test_that("a delegated steward signs off in that capacity", {
  p <- new_project()
  propose_candidate(p$folder, 3, "Starting structure is adequate")
  validate_candidate(p$folder, "Fine")
  as_person("Dee Delegate", "delegated_steward", "dee")
  expect_equal(sign_off_project(p$folder, "Accepted", all_reviewed)$capacity,
               "delegated_steward")
  expect_equal(read_projects(p$folder)$signed_off_by, "Dee Delegate")
})

test_that("automatic calibration is logged with its start table", {
  p <- new_project()
  fit <- log_auto_calibration(p$folder, 3, lower = c(fc = 0.5), upper = c(fc = 1.5),
                              starts = 2L, seed = 3, control = list(maxit = 15),
                              reasoning = "Fit the volume")
  expect_length(fit$start_results$start, 2L)
  expect_true(abs(fit$configuration$fc - 1) < 0.1)
  trials <- project_trials(p$folder)
  expect_equal(trials$type[2], "auto_calibration")
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
})

test_that("tampering, missing data and changed outputs are detected", {
  p <- new_project()
  log_trial(p$folder, 3, c(fc = 1), "better", "Volume too low")
  log_trial(p$folder, 4, c(surface.k1 = 3), "better", "Timing")
  file <- file.path(p$folder, "entries", "0004-trial.yml")
  original <- readLines(file)
  writeLines(sub("Volume too low", "Volume far too low", original), file)
  checks <- verify_project(p$folder)
  expect_equal(checks[ok == FALSE, entry], "0005")
  writeLines(original, file)
  expect_true(all(verify_project(p$folder)$ok))
  file.remove(file)
  checks <- verify_project(p$folder)
  expect_true(any(checks[check == "numbering", !ok]))
  expect_true(any(checks[check == "chain", !ok]))
  writeLines(original, file)
  observed <- file.path(p$folder, "data", "0002", "observed.csv")
  cat("1\n", file = observed, append = TRUE)
  expect_false(all(verify_project(p$folder)[check == "data observed", ok]))
  expect_error(log_trial(p$folder, 3, c(fc = 0.9), "worse", "x"), "changed since")
})

test_that("a rerun that differs names the software change", {
  p <- new_project()
  local_mocked_bindings(.series_md5 = function(x) "different")
  checks <- verify_project(p$folder, rerun = TRUE)
  expect_false(checks[check == "rerun", ok])
  expect_match(checks[check == "rerun", detail], "Output differs")
})

test_that("data can be referenced rather than copied", {
  folder <- tempfile("project-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  d <- log_data()
  csv <- tempfile(fileext = ".csv")
  forcing <- d$forcing
  forcing$time <- format(forcing$time, "%Y-%m-%dT%H:%M:%SZ")
  data.table::fwrite(forcing, csv)
  as_person("Ann Custodian", "custodian", "ann")
  start_calibration_project(folder, "Test", "1", "Testing", 20, "Owner", "Steward")
  reg <- register_data(folder, csv, d$observed, calibration = c(100, 600), copy = FALSE)
  expect_false(reg$data$forcing$copied)
  expect_true(reg$data$observed$copied)
  expect_false(file.exists(file.path(folder, "data", "0002", "forcing.csv")))
  expect_equal(reg$scorecard$warmup_rows, 99L)
  expect_equal(reg$scorecard$calibration$start, "2021-01-05T03:00:00Z")
  cat("x", file = csv, append = TRUE)
  expect_false(all(verify_project(folder)$ok))
})

test_that("bad input is refused before anything is written", {
  folder <- tempfile("project-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  d <- log_data()
  old <- options(pdmS7.user = NULL, pdmS7.role = NULL)
  env_old <- Sys.getenv(c("PDMS7_USER", "PDMS7_ROLE"), unset = NA)
  Sys.unsetenv(c("PDMS7_USER", "PDMS7_ROLE"))
  on.exit({
    options(old)
    for (v in names(env_old)) if (!is.na(env_old[[v]])) do.call(Sys.setenv, as.list(env_old[v]))
  }, add = TRUE)
  expect_error(start_calibration_project(folder, "T", "1", "P", 20, "O", "S"), "Declare")
  as_person("Ann", "hydrologist", "ann")
  expect_error(start_calibration_project(folder, "T", "1", "P", 20, "O", "S"), "Role")
  as_person("Ann", "custodian", "ann")
  start_calibration_project(folder, "T", "1", "P", 20, "O", "S")
  expect_error(start_calibration_project(folder, "T", "1", "P", 20, "O", "S"), "not empty")
  expect_error(select_structure(folder, d$truth, "x"), "Register data first")
  expect_error(register_data(folder, d$forcing, d$observed[-1], c(1, 10)), "align")
  expect_error(register_data(folder, d$forcing, d$observed, c(10, 500), c(400, 600)),
               "overlap")
  expect_error(register_data(folder, d$forcing, d$observed, c(10, 500), headline = "x"),
               "headline")
  register_data(folder, d$forcing, d$observed, c(10, 500))
  wrong_area <- d$truth
  wrong_area$area_km2 <- 5
  expect_error(select_structure(folder, wrong_area, "x"), "differs")
  expect_error(select_structure(folder, d$truth, ""), "explanation")
  select_structure(folder, d$truth, "ok")
  expect_error(log_trial(folder, 2, c(fc = 1), "better", "x"), "data_registered")
  expect_error(log_trial(folder, 3, c(nope = 1), "better", "x"), "Unknown parameter")
  expect_error(log_trial(folder, 3, c(fc = 1), "great", "x"), "should be one of")
  expect_error(validate_candidate(folder, "x"), "candidate first")
  propose_candidate(folder, 3, "ok")
  expect_error(validate_candidate(folder, "x"), "no validation window")
  expect_equal(nrow(read_project(folder)$entries), 4L)
})

test_that("the lock serialises writers and clears when stale", {
  folder <- tempfile("project-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  dir.create(file.path(folder, "entries"), recursive = TRUE)
  lock <- file.path(folder, "entries", ".lock")
  dir.create(lock)
  expect_error(.with_lock(folder, function() 1, wait = 0.3), "Another session")
  Sys.setFileTime(lock, Sys.time() - 3600)
  expect_equal(.with_lock(folder, function() 1), 1)
  expect_false(dir.exists(lock))
})
