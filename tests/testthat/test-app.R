# ============================================================ #
# Tool:         test-app
# Description:  Tests for the calibration app's server logic
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add calibration app tests
# Tier:         3
# Inputs:       Temporary projects driven through shiny::testServer
# Outputs:      testthat expectations
# Dependencies: testthat; shiny (suggested)
# ============================================================ #

app_files <- function(env = parent.frame()) {
  d <- log_data() # nolint: object_usage_linter.
  folder <- tempfile("app-")
  dir.create(folder)
  defer_to(function() unlink(folder, recursive = TRUE), env) # nolint: object_usage_linter.
  forcing <- d$forcing
  forcing$time <- format(forcing$time, "%Y-%m-%dT%H:%M:%SZ")
  data.table::fwrite(forcing, file.path(folder, "forcing.csv"))
  data.table::fwrite(data.frame(q_m3s = d$observed), file.path(folder, "flow.csv"))
  list(folder = folder, project = file.path(folder, "project"), data = d)
}

entry_types <- function(project) read_project(project)$entries$type

test_that("the app runs a calibration from setup to sign-off", {
  skip_if_not_installed("shiny")
  f <- app_files()
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  shiny::testServer(.app_server(NULL), {
    session$setInputs(user = "Ann Custodian", role = "custodian", new_path = f$project,
                      catchment = "App Brook", gauge = "12345", purpose = "Testing",
                      area = 20, owner = "Owner", steward = "Sam Steward", description = "")
    session$setInputs(start = 1)
    expect_equal(rv$project, f$project)
    session$setInputs(forcing_path = file.path(f$folder, "forcing.csv"),
                      observed_path = file.path(f$folder, "flow.csv"),
                      cal_start = "121", cal_end = "700", val_start = "2021-01-31",
                      val_end = "2021-02-09 23:00", headline = "kge", log_offset = 0.01,
                      soil_fraction = 0.5, copy = TRUE, register_reasoning = "")
    session$setInputs(register = 1)
    session$setInputs(config_path = "", preset = "standard",
                      structure_reasoning = "Standard structure")
    session$setInputs(structure = 1)
    expect_equal(entry_types(f$project),
                 c("project_start", "data_registered", "structure_selected"))
    expect_equal(state$headline(), "kge")

    session$setInputs(parent = "0003", p_fc = 0.9)
    session$setInputs(preview = 1)
    expect_equal(rv$preview$changes$fc$to, 0.9)
    expect_length(entry_types(f$project), 3L)
    expect_match(output$scores, "fdc_high")
    expect_match(output$scores, "0.9")
    session$setInputs(verdict = "worse", trial_reasoning = "Too dry")
    session$setInputs(save_trial = 1)
    expect_equal(entry_types(f$project)[4], "trial")
    expect_null(rv$preview)

    session$setInputs(note = "Checked the rating")
    session$setInputs(save_note = 1)
    session$setInputs(candidate_entry = "0003", candidate_reasoning = "Structure is adequate")
    session$setInputs(propose = 1)
    session$setInputs(validation_reasoning = "Fine")
    session$setInputs(validate = 1)
    expect_equal(entry_types(f$project)[5:7], c("note", "candidate", "validation"))
    expect_equal(rv$validation$score[1], "nse")
    expect_match(output$validation_scores, "validation")

    needed <- c("integrity", "data", "calibration_path", "validation")
    session$setInputs(checklist = needed, statement = "Self approval")
    session$setInputs(sign = 1)
    expect_length(entry_types(f$project), 7L)
  })
  as_person("Sam Steward", "steward", "sam") # nolint: object_usage_linter.
  shiny::testServer(.app_server(f$project), {
    session$setInputs(user = "Sam Steward", role = "steward",
                      checklist = c("integrity", "data", "calibration_path"),
                      statement = "Accepted")
    session$setInputs(sign = 1)
    expect_length(entry_types(f$project), 7L)
    session$setInputs(checklist = c("integrity", "data", "calibration_path", "validation"))
    session$setInputs(sign = 2)
    expect_equal(entry_types(f$project)[8], "sign_off")
    session$setInputs(report_rerun = FALSE, report_sensitivity = FALSE)
    session$setInputs(build = 1)
    expect_true(file.exists(rv$report))
    session$setInputs(reopen_reason = "New rating curve")
    session$setInputs(reopen = 1)
    expect_equal(read_project(f$project)$status, "reopened")
  })
})

test_that("the app refuses empty changes and bad input without writing", {
  skip_if_not_installed("shiny")
  p <- new_project() # nolint: object_usage_linter.
  shiny::testServer(.app_server(p$folder), {
    session$setInputs(user = "Ann Custodian", role = "custodian", parent = "0003")
    session$setInputs(preview = 1)
    expect_null(rv$preview)
    session$setInputs(p_fc = 1, verdict = "better", trial_reasoning = "")
    session$setInputs(save_trial = 1)
    session$setInputs(calib_params = character(0), calib_range = 0.5, calib_starts = 1,
                      calib_seed = 1, calib_maxit = 5, calib_reasoning = "x")
    session$setInputs(run_calib = 1)
    session$setInputs(project_path = tempdir())
    session$setInputs(open = 1)
    expect_equal(rv$project, p$folder)
  })
  expect_length(entry_types(p$folder), 3L)
})

test_that("the app opens a project and the launcher builds an app", {
  skip_if_not_installed("shiny")
  p <- new_project() # nolint: object_usage_linter.
  shiny::testServer(.app_server(NULL), {
    session$setInputs(user = "Ann", role = "custodian", project_path = p$folder)
    session$setInputs(open = 1)
    expect_equal(rv$project, p$folder)
    expect_length(state$nodes(), 1L)
  })
  expect_s3_class(calibration_app(p$folder), "shiny.appobj")
  expect_equal(.window_input("1", "20"), c(1, 20))
  expect_equal(.window_input("2020-01-01", "2020-02-01"), c("2020-01-01", "2020-02-01"))
  expect_null(.window_input("", "5"))
  expect_true("qc" %in% .editable_paths(pdm_presets("standard")))
  expect_false("area_km2" %in% .editable_paths(pdm_presets("standard")))
})
