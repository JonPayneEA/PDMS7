# ============================================================ #
# Tool:         test-structures
# Description:  Tests for bounds, structure sets, log-scale search and comparisons
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add structure comparison tests
# Tier:         3
# Inputs:       Synthetic data; temporary projects
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

test_that("every structure in the set is valid and starts inside its bounds", {
  set <- structure_set()
  expect_named(set, c("standard", "rectangular", "triangular", "exponential", "lognormal",
                      "split", "demand", "exponential_groundwater"))
  for (n in names(set)) {
    b <- calibration_bounds(set[[n]])
    start <- vapply(b$path, function(p) .path_get(set[[n]], p), numeric(1))
    expect_true(all(start >= b$lower & start <= b$upper), info = n)
    expect_true(all(b$lower[b$scale == "log"] > 0), info = n)
  }
  expect_equal(set$lognormal$distribution$type, "lognormal")
  expect_equal(set$split$distribution$type, "pareto")
})

test_that("structure names mean the same structure whatever the base", {
  base <- structure_set("lognormal")$lognormal
  base$area_km2 <- 33
  base$td <- 2
  set <- structure_set(c("standard", "split"), base = base)
  expect_equal(set$standard$distribution$type, "pareto")
  expect_equal(set$split$recharge$type, "split")
  expect_equal(c(set$standard$area_km2, set$standard$td), c(33, 2))
  expect_error(structure_set("nope"), "among")
})

test_that("bounds can be overridden, extended and excluded", {
  overrides <- list(fc = c(0.8, 1.2), td = c(0, 3))
  b <- calibration_bounds(pdm_presets("standard"), overrides = overrides,
                          exclude = "distribution.b")
  expect_equal(unlist(b[b$path == "fc", c("lower", "upper")]), c(lower = 0.8, upper = 1.2))
  expect_true("td" %in% b$path)
  expect_false("distribution.b" %in% b$path)
  expect_equal(b$scale[b$path == "recharge.kg"], "log")
  expect_error(calibration_bounds(pdm_presets("standard"), overrides = list(fc = 1)), "pairs")
  expect_error(calibration_bounds(pdm_presets("standard"), overrides = list(x = c(0, 1))),
               "Unknown parameter")
})

test_that("log-scale search finds wide-ranging parameters in fewer runs", {
  set.seed(1)
  forcing <- data.frame(rain = ifelse(stats::runif(1500) < 0.07,
                                      stats::rgamma(1500, 0.7, scale = 3), 0), pet = 0.06)
  truth <- pdm_presets("standard")
  truth$recharge$kg <- 40
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s
  start <- pdm_presets("standard")
  start$recharge$kg <- 1000
  args <- list(start, forcing, observed, c(recharge.kg = 1), c(recharge.kg = 5000),
               warmup = 200, objective = "nse", control = list(maxit = 50))
  linear <- do.call(calibrate_pdm, args)
  logged <- do.call(calibrate_pdm, c(args, list(log_scale = "recharge.kg")))
  expect_lt(abs(logged$parameters[["recharge.kg"]] - 40), 0.01)
  expect_lt(sum(logged$start_results$evaluations), sum(linear$start_results$evaluations))
  expect_error(do.call(calibrate_pdm, c(args, list(log_scale = "fc"))), "log_scale")
  mixed <- pdm_presets("standard")
  mixed$groundwater <- list(type = "exponential", a = 0.05, gamma = -5)
  b <- calibration_bounds(mixed)
  expect_no_warning(calibrate_pdm(
    mixed, forcing, observed, stats::setNames(b$lower, b$path), stats::setNames(b$upper, b$path),
    warmup = 200, objective = "nse", control = list(maxit = 2),
    log_scale = b$path[b$scale == "log"]
  ))
})

comparison_project <- function(env = parent.frame()) {
  folder <- tempfile("compare-")
  defer_to(function() unlink(folder, recursive = TRUE), env) # nolint: object_usage_linter.
  set.seed(5)
  n <- 24 * 60
  time <- seq(as.POSIXct("2023-10-01", tz = "UTC"), by = 3600, length.out = n)
  forcing <- data.frame(time = time, pet = 0.06,
                        rain = ifelse(stats::runif(n) < 0.07, stats::rgamma(n, 0.7, scale = 3), 0))
  truth <- structure_set("lognormal")$lognormal
  truth$area_km2 <- 40
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s *
    exp(stats::rnorm(n, 0, 0.03))
  as_person("Ann Custodian", "custodian", "ann", env) # nolint: object_usage_linter.
  start_calibration_project(folder, "Brook", "1", "Structures", 40, "O", "S")
  register_data(folder, forcing, observed, c(169, 1000), c(1001, 1300), test = c(1301, n))
  folder
}

test_that("structures are calibrated alike, logged and ranked on validation", {
  folder <- comparison_project()
  ranking <- compare_structures(folder, structure_set(c("standard", "lognormal", "split")),
                                starts = 1, control = list(maxit = 15),
                                reasoning = "Which store?")
  expect_equal(sort(ranking$structure), c("lognormal", "split", "standard"))
  expect_equal(ranking$rank, 1:3)
  expect_true(all(diff(ranking$validation) <= 0))
  expect_equal(ranking$change, ranking$validation - ranking$calibration)
  types <- read_project(folder)$entries$type
  expect_equal(sum(types == "auto_calibration"), 3L)
  fit <- read_entry(folder, ranking$calibration_entry[1])
  expect_equal(fit$structure_name, ranking$structure[1])
  expect_equal(fit$parent, ranking$structure_entry[1])
  expect_true("recharge.kg" %in% unlist(fit$log_scale) || ranking$structure[1] == "split")
  expect_equal(structure_comparison(folder), ranking, ignore_attr = TRUE)
  expect_true(all(verify_project(folder, rerun = TRUE)$ok))
  html <- paste(readLines(build_report(folder, sensitivity = FALSE, rerun = FALSE)),
                collapse = "")
  expect_match(html, "Structure comparison")
})

test_that("cross-validation ranks on the mean of two held-out scores", {
  folder <- comparison_project()
  ranking <- compare_structures(folder, structure_set(c("standard", "rectangular")),
                                starts = 1, control = list(maxit = 10), cross_validate = TRUE,
                                reasoning = "Short record")
  expect_true("cross_validated" %in% names(ranking))
  expect_true(all(diff(ranking$cross_validated) <= 0))
  fit <- read_entry(folder, ranking$calibration_entry[1])
  expect_equal(ranking$cross_validated[1],
               (fit$comparison_validation_scores$nse + fit$cross_validation_scores$nse) / 2)
})

test_that("a comparison needs a validation window and a named list", {
  folder <- tempfile("compare-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  d <- log_data() # nolint: object_usage_linter.
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  start_calibration_project(folder, "T", "1", "P", 20, "O", "S")
  register_data(folder, d$forcing, d$observed, c(121, 700))
  expect_error(compare_structures(folder, reasoning = "x"), "validation window")
  expect_error(structure_comparison(folder), "no structure comparison")
})

test_that("parallel comparison gives the same ranking as serial", {
  skip_on_cran()
  folder <- comparison_project()
  set <- structure_set(c("standard", "rectangular"))
  serial <- compare_structures(folder, set, starts = 1, control = list(maxit = 8),
                               reasoning = "Serial")
  parallel_run <- compare_structures(folder, set, starts = 1, control = list(maxit = 8),
                                     cores = 2, reasoning = "Parallel")
  expect_equal(parallel_run$structure, serial$structure)
  expect_equal(parallel_run$validation, serial$validation)
})
