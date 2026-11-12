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

# Guards: recommend = TRUE chooses the structure first, logs each choice, and runs the stages
# from the recommended calibration, with stages built for the chosen structure
test_that("calibrate_project can choose the structure first", {
  folder <- file.path(tempfile("recommend-"), "brook")
  on.exit(unlink(dirname(folder), recursive = TRUE), add = TRUE)
  d <- log_data() # nolint: object_usage_linter. Helper from helper-calibration.R.
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  built_for <- NULL
  stages <- function(config) {
    built_for <<- config
    pdm_stages(config, polish = FALSE)
  }
  suppressWarnings(calibrate_project(
    folder, d$forcing, d$observed, area_km2 = 20, calibration = c(121, 700),
    validation = c("2021-01-31", "2021-02-09 23:00"), structure = d$truth, recommend = TRUE,
    stages = stages, overrides = list(surface.k1 = c(0.5, 12)), starts = 1L,
    control = list(maxit = 2L), wettest_years = 0, reasoning = "Synthetic record."
  ))
  entries <- read_project(folder)$entries
  notes <- vapply(Filter(function(e) e$type == "note", .read_entries(.project_path(folder))),
                  function(e) e$text, character(1))
  expect_length(grep("^Structure recommendation", notes), 3)
  # The latest comparison is the last step, the groundwater store
  comparisons <- structure_comparison(folder)
  expect_setequal(comparisons$structure, c("cubic", "quadratic", "linear", "exponential"))
  stage_fits <- entries[entries$type == "auto_calibration", ]
  first_stage <- read_entry(folder, utils::tail(stage_fits$id, 2)[1])
  expect_true(first_stage$parent %in% comparisons$calibration_entry)
  expect_false(is.null(built_for))
  expect_equal(utils::tail(entries$type, 2), c("candidate", "validation"))
  expect_error(calibrate_project(file.path(dirname(folder), "nov"), d$forcing, d$observed, 20,
                                 c(121, 700), recommend = TRUE), "validation window")
})

# Guards: test years without a validation window are refused before the search, not after it
test_that("calibrate_project refuses test years without validation before searching", {
  folder <- file.path(tempfile("novalid-"), "brook")
  on.exit(unlink(dirname(folder), recursive = TRUE), add = TRUE)
  d <- log_data() # nolint: object_usage_linter. Helper from helper-calibration.R.
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  expect_error(
    calibrate_project(folder, d$forcing, d$observed, area_km2 = 20, calibration = c(121, 700),
                      test = c(701, 960), structure = d$truth, starts = 1L,
                      control = list(maxit = 2L), wettest_years = 0),
    "no validation window"
  )
  expect_false("auto_calibration" %in% read_project(folder)$entries$type)
})

# Guards: a run interrupted after the candidate is finished by a rerun, report included
test_that("calibrate_project finishes the missing steps of an interrupted run", {
  folder <- file.path(tempfile("resume-"), "brook")
  on.exit(unlink(dirname(folder), recursive = TRUE), add = TRUE)
  d <- log_data() # nolint: object_usage_linter. Helper from helper-calibration.R.
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  run <- function() {
    suppressWarnings(calibrate_project(
      folder, d$forcing, d$observed, area_km2 = 20, calibration = c(121, 700),
      validation = c("2021-01-31", "2021-02-09 23:00"), structure = d$truth, starts = 1L,
      control = list(maxit = 2L), wettest_years = 0, report = TRUE
    ))
  }
  local({
    local_mocked_bindings(validate_candidate = function(...) stop("interrupted"))
    expect_error(run(), "interrupted")
  })
  types <- read_project(folder)$entries$type
  expect_equal(utils::tail(types, 1), "candidate")
  expect_message(summary <- run(), "finishing any missing steps")
  types <- read_project(folder)$entries$type
  expect_equal(sum(types == "candidate"), 1)
  expect_equal(utils::tail(types, 1), "validation")
  expect_true(file.exists(file.path(folder, "report", "report.html")))
  expect_false(is.na(summary$validation_score))
  # Nothing left to do: a third run adds no entries
  before <- length(types)
  expect_message(run(), "finishing any missing steps")
  expect_length(read_project(folder)$entries$type, before)
})

# Guards: the candidate is the last stage unless an earlier fit beats it on the calibration
# headline by more than the tie tolerance; then the better fit is proposed, and the reason says so
test_that("the best fit in hand is proposed, not a worse final stage", {
  p <- new_project()
  structure <- "0003"
  good <- log_trial(p$folder, structure, c(fc = 1), "better", "Volume right")$id
  close <- log_trial(p$folder, good, c(fc = 0.995), "inconclusive", "Nearly the same")$id
  pick <- pdmS7:::.best_candidate(p$folder, c(good, structure))
  expect_identical(pick$id, good)
  expect_match(pick$reason, "not proposed")
  expect_identical(pdmS7:::.best_candidate(p$folder, c(structure, good))$id, good)
  kept <- pdmS7:::.best_candidate(p$folder, c(good, close))
  expect_identical(kept$id, close)
  expect_identical(kept$reason, "Final stage of the staged calibration.")
})

# Guards: a split recharge's default bounds keep both flow paths open
test_that("split recharge is searched off 0 and 1", {
  b <- calibration_bounds(structure_set("split")$split)
  expect_equal(unlist(b[b$path == "recharge.alpha", c("lower", "upper")]),
               c(lower = 0.05, upper = 0.95))
  open <- calibration_bounds(structure_set("split")$split,
                             overrides = list(recharge.alpha = c(0, 1)))
  expect_equal(unlist(open[open$path == "recharge.alpha", c("lower", "upper")]),
               c(lower = 0, upper = 1))
})
