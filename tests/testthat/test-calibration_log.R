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

# Guards: a configuration read back from the log is bit-for-bit the one written
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

# Guards: every entry type is written in order with its fields and parent links
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

# Guards: validation data never influence a trial's scores
test_that("trials are scored on the calibration window only", {
  p <- new_project()
  preview <- preview_trial(p$folder, 3, c(fc = 1))
  expect_equal(preview$rows, 121:700)
  expected <- pdm_scorecard(preview$simulated[121:700], p$data$observed[121:700])
  expect_equal(unlist(preview$scores), expected)
  expect_length(list.files(file.path(p$folder, "entries")), 3L)
})

# Guards: self-sign-off, out-of-order entries and writes to a closed project are refused
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

# Guards: read_entry() and read_projects() report what was written
test_that("single entries and validation scores can be read back", {
  p <- new_project()
  log_trial(p$folder, 3, c(fc = 1), "better", "Volume too low")
  trial <- read_entry(p$folder, 4)
  expect_equal(trial$type, "trial")
  expect_false(any(c(".file", ".md5") %in% names(trial)))
  expect_error(read_entry(p$folder, 99), "No entry")
  expect_true(is.na(read_projects(p$folder)$validation_score))
  propose_candidate(p$folder, 4, "Best")
  val <- validate_candidate(p$folder, "Fine")
  expect_equal(read_projects(p$folder)$validation_score, val$validation_scores$nse)
  propose_candidate(p$folder, 3, "Changed mind")
  expect_true(is.na(read_projects(p$folder)$validation_score))
})

# Guards: the test window cannot be scored twice or skipped when registered
test_that("the test window is scored once, last, and required for sign-off", {
  folder <- tempfile("project-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  d <- log_data()
  as_person("Ann Custodian", "custodian", "ann")
  start_calibration_project(folder, "T", "1", "Testing", 20, "O", "S")
  expect_error(register_data(folder, d$forcing, d$observed, c(121, 500), c(501, 700),
                             test = c(650, 900), wettest_years = 0),
               "test must not overlap validation")
  reg <- register_data(folder, d$forcing, d$observed, c(121, 500), c(501, 700),
                       test = c(721, 960), wettest_years = 0)
  expect_equal(reg$scorecard$test$first_row, 721L)
  select_structure(folder, d$truth, "Truth")
  expect_equal(preview_trial(folder, 3, c(fc = 0.9))$rows, 121:500)
  propose_candidate(folder, 3, "Truth")
  expect_error(test_candidate(folder, "x"), "Validate")
  validate_candidate(folder, "Fine")
  as_person("Sam Steward", "steward", "sam")
  expect_error(sign_off_project(folder, "x", all_reviewed), "test_candidate")
  as_person("Ann Custodian", "custodian", "ann")
  tested <- test_candidate(folder, "Holds on the final window")
  expect_equal(tested$candidate, "0004")
  expect_error(test_candidate(folder, "again"), "scored once")
  expect_equal(read_projects(folder)$test_score, tested$test_scores$nse)
  expect_true(all(verify_project(folder, rerun = TRUE)$ok))
  html <- paste(readLines(build_report(folder, sensitivity = FALSE, rerun = FALSE)),
                collapse = "")
  expect_match(html, "Tested once, after every choice was made")
  as_person("Sam Steward", "steward", "sam")
  expect_equal(sign_off_project(folder, "Accepted", all_reviewed)$test, tested$id)
})

# Guards: the test requirement applies only when a test window exists
test_that("projects without a test window sign off without one", {
  p <- new_project()
  propose_candidate(p$folder, 3, "Structure")
  validate_candidate(p$folder, "Fine")
  expect_error(test_candidate(p$folder, "x"), "no test window")
  as_person("Sam Steward", "steward", "sam")
  expect_null(sign_off_project(p$folder, "Accepted", all_reviewed)$test)
})

# Guards: the sign-off records a delegated steward's role
test_that("a delegated steward signs off in that capacity", {
  p <- new_project()
  propose_candidate(p$folder, 3, "Starting structure is adequate")
  validate_candidate(p$folder, "Fine")
  as_person("Dee Delegate", "delegated_steward", "dee")
  expect_equal(sign_off_project(p$folder, "Accepted", all_reviewed)$capacity,
               "delegated_steward")
  expect_equal(read_projects(p$folder)$signed_off_by, "Dee Delegate")
})

# Guards: every start of a logged automatic calibration is kept for review
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

# Guards: verify_project() catches edited entries, changed data and runs that no longer reproduce
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

# Guards: a CRLF checkout does not break the checksum chain
test_that("checksums survive a change of line endings, as on a Windows checkout", {
  p <- new_project()
  propose_candidate(p$folder, 3, "Starting structure")
  files <- list.files(p$folder, recursive = TRUE, full.names = TRUE,
                      pattern = "\\.(yml|csv)$")
  for (f in files) {
    text <- readBin(f, "raw", file.info(f)$size)
    crlf <- gsub("\n", "\r\n", rawToChar(text), fixed = TRUE)
    writeBin(charToRaw(crlf), f)
  }
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
  log_note(p$folder, "Still appends after conversion")
  expect_true(all(verify_project(p$folder)$ok))
})

# Guards: a failed rerun says which software changed since the entry was written
test_that("a rerun that differs names the software change", {
  p <- new_project()
  local_mocked_bindings(.series_md5 = function(x) "different")
  checks <- verify_project(p$folder, rerun = TRUE)
  expect_false(checks[check == "rerun", ok])
  expect_match(checks[check == "rerun", detail], "Output differs")
})

# Guards: copy = FALSE stores a path and checksum instead of a copy
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
  reg <- register_data(folder, csv, d$observed, calibration = c(100, 600), copy = FALSE,
                       wettest_years = 0)
  expect_false(reg$data$forcing$copied)
  expect_true(reg$data$observed$copied)
  expect_false(file.exists(file.path(folder, "data", "0002", "forcing.csv")))
  expect_equal(reg$scorecard$warmup_rows, 99L)
  expect_equal(reg$scorecard$calibration$start, "2021-01-05T03:00:00Z")
  cat("x", file = csv, append = TRUE)
  expect_false(all(verify_project(folder)$ok))
})

# Guards: invalid arguments leave the project untouched
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
  expect_error(register_data(folder, d$forcing, d$observed[-1], c(1, 10), wettest_years = 0),
               "align")
  expect_error(register_data(folder, d$forcing, d$observed, c(10, 500), c(400, 600),
                             wettest_years = 0), "overlap")
  expect_error(register_data(folder, d$forcing, d$observed, c(10, 500), headline = "x",
                             wettest_years = 0), "headline")
  register_data(folder, d$forcing, d$observed, c(10, 500), wettest_years = 0)
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

# Guards: concurrent writers wait for the lock, and a dead session's lock is cleared
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

# Guards: new projects record the flow start; projects registered earlier still reproduce
test_that("the start rule is registered and older projects keep the soil start", {
  p <- new_project()
  card <- read_project(p$folder)$scorecard
  expect_equal(card$start, "flow")
  expect_equal(card$baseflow_fraction, 0.7)
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
  # A registration written before the start rule existed has neither field; its runs must be
  # rerun from the soil start they were made with.
  entries <- pdmS7:::.read_entries(pdmS7:::.project_path(p$folder))
  registration <- pdmS7:::.registration(entries)
  legacy <- registration
  legacy$scorecard$start <- NULL
  legacy$scorecard$baseflow_fraction <- NULL
  info <- pdmS7:::.project_info(entries)
  config <- read_entry(p$folder, "0003")$configuration
  soil <- pdmS7:::.run_registered(p$folder, info, legacy, config)
  model <- pdm_from_config(config)
  data <- pdmS7:::.load_registration(p$folder, registration)
  direct <- run_pdm(model, data$forcing, initial_state(model, 0.5))$output$q_m3s
  expect_equal(soil$simulated, direct)
  flow <- pdmS7:::.run_registered(p$folder, info, registration, config)
  expect_false(isTRUE(all.equal(flow$simulated, direct)))
})

# Guards: a stale lock is cleared, but a lock that turns out to be fresh is put back, not deleted
test_that("stale-lock recovery never deletes a fresh lock", {
  folder <- tempfile("lock-")
  dir.create(folder)
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  lock <- file.path(folder, ".lock")
  dir.create(lock)
  # Judged stale at the first look, fresh once moved aside: another session replaced it.
  ages <- c(1000, 1)
  local_mocked_bindings(.lock_age = function(dir) {
    out <- ages[1]
    ages <<- ages[-1]
    out %||% 1
  })
  expect_error(.acquire_lock(lock, 0.1, 600, 0.05, "still locked"), "still locked")
  expect_true(dir.exists(lock))
  expect_length(list.files(folder, all.files = TRUE, no.. = TRUE), 1L)
  # Stale at both looks: removed and taken.
  ages <- c(1000, 1000)
  expect_true(.acquire_lock(lock, 0.1, 600, 0.05, "still locked"))
  expect_true(dir.exists(lock))
  expect_length(list.files(folder, all.files = TRUE, no.. = TRUE), 1L)
})
