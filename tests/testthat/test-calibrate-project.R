# Tests for calibrate_project(), candidate_model(), the calibration_checks() readout and
# event_run().

# One quick end-to-end calibration of the helper record, shared by the tests below.
calibrated <- function(env = parent.frame()) {
  folder <- file.path(tempfile("whole-"), "brook")
  # nolint start: object_usage_linter. Test helpers from helper-calibration.R.
  defer_to(function() unlink(dirname(folder), recursive = TRUE), env)
  d <- log_data()
  as_person("Ann Custodian", "custodian", "ann", env)
  # nolint end
  start <- d$truth
  start$fc <- 0.9
  summary <- suppressWarnings(calibrate_project(
    folder, d$forcing, d$observed, area_km2 = 20, calibration = c(121, 700),
    validation = c("2021-01-31", "2021-02-09 23:00"), structure = start, starts = 1L,
    control = list(maxit = 5L), wettest_years = 0, reasoning = "Synthetic record."
  ))
  list(folder = folder, data = d, summary = summary)
}

# Guards: one call logs every step from the start to the validated candidate, in order
test_that("calibrate_project runs the whole logged calibration", {
  p <- calibrated()
  types <- read_project(p$folder)$entries$type
  expect_equal(types[1:3], c("project_start", "data_registered", "structure_selected"))
  expect_equal(utils::tail(types, 2), c("candidate", "validation"))
  expect_equal(sum(types == "auto_calibration"), 3)
  expect_false(is.na(p$summary$candidate))
  expect_equal(read_project(p$folder)$project$owner, "Ann Custodian")
})

# Guards: a finished project is left alone; an unfinished one is moved aside, log kept
test_that("calibrate_project leaves finished projects and moves unfinished ones", {
  p <- calibrated()
  before <- nrow(read_project(p$folder)$entries)
  expect_message(again <- calibrate_project(p$folder, p$data$forcing, p$data$observed, 20,
                                            c(121, 700)), "already has a candidate")
  expect_equal(nrow(read_project(p$folder)$entries), before)
  expect_equal(again$candidate, p$summary$candidate)
  half <- file.path(dirname(p$folder), "half")
  start_calibration_project(half, "Half Brook", "2", "Testing", 20, "Owner", "Steward")
  expect_warning(
    suppressMessages(calibrate_project(half, p$data$forcing, p$data$observed, 20, c(121, 700),
                                       structure = p$data$truth, starts = 1L,
                                       control = list(maxit = 2L), wettest_years = 0)),
    "Moved the unfinished project"
  )
  expect_length(list.files(dirname(half), pattern = "^half_unfinished_"), 1)
})

# Guards: candidate_model rebuilds the candidate's configuration; checks print a readout
test_that("candidate_model and the checks readout", {
  p <- calibrated()
  model <- candidate_model(p$folder)
  entry <- read_entry(p$folder, p$summary$candidate)
  expect_equal(pdm_fingerprint(model), pdm_fingerprint(pdm_from_config(
    read_entry(p$folder, entry$entry)$configuration
  )))
  checks <- calibration_checks(p$folder, top = 3)
  expect_s3_class(checks, "pdm_calibration_checks")
  expect_output(print(checks), "Largest events in each window")
  expect_error(candidate_model(p$folder, "0001"), "holds no model")
})

# Guards: an event inside the record starts warm from the record's own run; one outside starts
# steady from its first flow; missing pet comes from the record
test_that("event_run starts warm inside the record and steady outside it", {
  p <- calibrated()
  d <- p$data
  rows <- 400:520
  event <- data.frame(time = d$forcing$time[rows], rain = d$forcing$rain[rows])
  inside <- event_run(p$folder, event, d$observed[rows])
  expect_s3_class(inside, "pdm_event_run")
  expect_equal(inside$start, "warm")
  expect_equal(inside$series$pet, d$forcing$pet[rows])
  # The same rows of a run over the whole record, from the project's start rule.
  model <- candidate_model(p$folder)
  card <- .registration(.read_entries(p$folder))$scorecard
  start <- .workbench_start(model, card, d$observed)
  full <- run_pdm(model, d$forcing[c("rain", "pet")], start)$output$q_m3s
  expect_equal(inside$series$simulated, full[rows], tolerance = 1e-8)
  expect_true(is.finite(inside$scores$nse))
  later <- d$forcing$time[rows] + 365 * 86400
  outside <- event_run(p$folder, data.frame(time = later, rain = d$forcing$rain[rows],
                                            pet = 0.05), d$observed[rows])
  expect_equal(outside$start, "steady")
  expect_output(print(outside), "steady start")
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_identical(plot(outside), outside)
  expect_error(event_run(p$folder, data.frame(time = later, rain = 0)), "needs observed flow")
})

# Guards: the calibration path lists the stages in order with their scores and starts, and the
# candidate's windows; the checks and the path draw in both engines
test_that("calibration_path and the checks plots", {
  p <- calibrated()
  path <- calibration_path(p$folder)
  expect_s3_class(path, "pdm_calibration_path")
  expect_equal(nrow(path$stages), 3)
  expect_equal(path$stages$step, 1:3)
  expect_true(all(path$starts$best))
  expect_setequal(unique(path$windows$window), c("calibration", "validation"))
  expect_output(print(path), "Candidate NSE by window")
  checks <- calibration_checks(p$folder, top = 3)
  bounds <- .bounds_spec(checks)
  expect_equal(length(bounds$yticks$at), nrow(checks$parameters))
  inside <- bounds$series[bounds$series$geom == "point", ]
  expect_true(all(inside$x >= 0 & inside$x <= 1))
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (type in c("stages", "starts", "windows")) expect_identical(plot(path, type = type), path)
  for (type in c("bounds", "peaks", "timing", "balance")) {
    expect_identical(plot(checks, type = type), checks)
  }
  skip_if_not_installed("ggplot2")
  for (type in c("stages", "starts", "windows")) {
    expect_silent(ggplot2::ggplot_build(ggplot2::autoplot(path, type = type)))
  }
  for (type in c("bounds", "peaks", "timing", "balance")) {
    expect_silent(ggplot2::ggplot_build(ggplot2::autoplot(checks, type = type)))
  }
})
