# Tests for the events workbench: event_workbench(), workbench_try(), plot_workbench() and the
# Events tab of the calibration app.

# A project whose structure is the truth but for a slower first surface store and no time delay,
# so the workbench has something to correct.
workbench_project <- function(env = parent.frame()) {
  folder <- tempfile("workbench-")
  defer_to(function() unlink(folder, recursive = TRUE), env) # nolint: object_usage_linter.
  set.seed(7)
  n <- 24 * 200
  time <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600, length.out = n)
  forcing <- data.frame(time = time,
                        rain = ifelse(stats::runif(n) < 0.06, stats::rexp(n, 0.3), 0), pet = 0.08)
  truth <- pdm_presets("standard")
  truth$area_km2 <- 20
  truth$recharge$kg <- 400
  truth$td <- 2
  model <- pdm_from_config(truth)
  observed <- run_pdm(model, forcing, initial_state_from_flow(model, 0.2, 0.7))$output$q_m3s *
    exp(stats::rnorm(n, 0, 0.03))
  as_person("Ann Custodian", "custodian", "ann", env) # nolint: object_usage_linter.
  start_calibration_project(folder, "Test Brook", "99999", "Testing", 20, "A Director",
                            "Sam Steward")
  register_data(folder, forcing, observed, calibration = c(500, 3500),
                validation = c(3501, n), wettest_years = 0)
  start <- truth
  start$td <- 0
  start$surface$k1 <- 6
  select_structure(folder, start, "Slow first store, no delay")
  list(folder = folder, truth = truth, observed = observed)
}

# Guards: the workbench keeps the n largest events of the window, largest first
test_that("event_workbench chooses the largest events of the window", {
  p <- workbench_project()
  wb <- event_workbench(p$folder, n = 5)
  expect_s3_class(wb, "pdm_workbench")
  expect_equal(wb$parent, "0003")
  expect_equal(nrow(wb$events), 5)
  expect_true(all(diff(wb$events$peak_flow) <= 0))
  expect_true(all(wb$events$peak_row >= 500 & wb$events$peak_row <= 3500))
  expect_equal(nrow(wb$scores), 5)
  later <- event_workbench(p$folder, n = 3, window = "validation")
  expect_true(all(later$events$peak_row > 3500))
  expect_output(print(wb), "5 largest events")
  expect_error(event_workbench(p$folder, n = 0), "whole number")
})

# Guards: a fast change reruns only the windows and matches a full run; a slow change reruns all
test_that("workbench_try matches a full run and improves the peaks", {
  p <- workbench_project()
  wb <- event_workbench(p$folder, n = 5)
  fixed <- workbench_try(wb, c(surface.k1 = 2, td = 2))
  expect_false(fixed$full_run)
  full <- .workbench_full_run(wb, fixed$configuration)
  for (e in seq_along(fixed$runs)) {
    rows <- seq.int(wb$saved$first[e], wb$saved$last[e])
    late <- rows >= wb$events$flow_start[e]
    expect_equal(fixed$runs[[e]][late], full[rows][late], tolerance = 1e-6)
  }
  expect_lt(stats::median(abs(fixed$scores$peak_error)), stats::median(abs(wb$scores$peak_error)))
  shape <- workbench_try(wb, c(distribution.b = 0.6))
  expect_true(shape$full_run)
  expect_error(workbench_try(wb, c(nonsense = 1)))
})

# Guards: the gallery draws with and without a trial
test_that("plot_workbench draws the events", {
  p <- workbench_project()
  wb <- event_workbench(p$folder, n = 3)
  trial <- workbench_try(wb, c(td = 1))
  file <- tempfile(fileext = ".pdf")
  grDevices::pdf(file)
  on.exit({
    grDevices::dev.off()
    unlink(file)
  }, add = TRUE)
  expect_identical(plot_workbench(wb), wb)
  expect_identical(plot_workbench(wb, trial, ncol = 1), wb)
})

# Guards: the sliders cover the fast parameters, b and td, and only moved ones count as changes
test_that("the Events tab sliders and changes", {
  cfg <- pdm_presets("standard")
  specs <- .wb_slider_specs(cfg)
  expect_setequal(specs$path, c("surface.k1", "surface.k2", "distribution.b", "td"))
  expect_true(all(specs$min <= specs$value & specs$value <= specs$max))
  values <- stats::setNames(as.list(specs$value), specs$path)
  expect_null(.wb_changes(specs, values))
  values$td <- 1.5
  expect_equal(.wb_changes(specs, values), c(td = 1.5))
  cfg$td <- 20
  expect_equal(max(.wb_slider_specs(cfg)$max[.wb_slider_specs(cfg)$path == "td"]), 20)
})

# Guards: the Events tab loads events, follows the sliders and saves a trial to the log
test_that("the Events tab loads, compares and saves a trial", {
  skip_if_not_installed("shiny")
  p <- workbench_project()
  shiny::testServer(.app_server(p$folder), {
    session$setInputs(user = "Ann Custodian", role = "custodian", wb_parent = "0003", wb_n = 4,
                      wb_window = "calibration")
    session$setInputs(wb_load = 1)
    expect_equal(nrow(rv$wb$events), 4)
    s <- .wb_slider_specs(rv$wb$configuration)
    session$setInputs(p_wb__surface__k1 = 2, p_wb__surface__k2 = s$value[s$path == "surface.k2"],
                      p_wb__distribution__b = s$value[s$path == "distribution.b"],
                      p_wb__td = 2)
    session$elapse(500)
    expect_false(is.null(rv$wb_trial))
    expect_false(rv$wb_trial$full_run)
    expect_equal(nrow(.wb_summary_table(rv$wb, rv$wb_trial)), 4)
    # This record is too wet for daily recessions; the app reports that and draws nothing.
    session$setInputs(wb_recession = 1)
    expect_null(rv$wb_recession)
    session$setInputs(wb_verdict = "better", wb_reasoning = "Faster store and a 2 h delay.")
    session$setInputs(wb_save = 1)
  })
  entries <- read_project(p$folder)$entries
  expect_equal(tail(entries$type, 1), "trial")
  last <- read_entry(p$folder, tail(entries$id, 1))
  expect_equal(last$changes$td$to, 2)
  expect_equal(last$changes$surface.k1$to, 2)
  expect_true(all(verify_project(p$folder)$ok))
})
