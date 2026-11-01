# ============================================================ #
# Tool:         test-thresholds
# Description:  Tests for threshold-crossing scores and thresholds in the calibration log
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add threshold tests
# Tier:         3
# Inputs:       Hand-built flow series; temporary projects
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

obs_hand <- c(1, 2, 6, 8, 5, 2, 1, 1, 3, 7, 4, 1)
sim_hand <- c(1, 1, 3, 7, 9, 4, 2, 1, 1, 2, 2, 1)

test_that("event scores match a hand count", {
  s <- pdm_threshold_scores(sim_hand, obs_hand, c(alert = 4, warning = 7.5),
                            tolerance_h = 1, gap_h = 1)
  alert <- s[threshold == "alert"]
  expect_equal(c(alert$observed_events, alert$simulated_events, alert$hits, alert$misses,
                 alert$false_alarms), c(2, 1, 1, 1, 0))
  expect_equal(c(alert$pod, alert$far, alert$csi, alert$bias), c(0.5, 0, 0.5, 0.5))
  expect_equal(alert$crossing_error_h, 1)
  expect_equal(alert$peak_timing_error_h, 1)
  expect_equal(alert$peak_error, 9 / 8 - 1)
  expect_equal(alert$duration_error_h, -1)
  expect_equal(alert$volume_error, 8 / 7 - 1)
  warning <- s[threshold == "warning"]
  expect_equal(c(warning$pod, warning$csi), c(1, 1))
  expect_equal(c(warning$pod_step, warning$far_step, warning$csi_step), c(0, 1, 0))
})

test_that("a late crossing is a hit within the tolerance and two errors outside it", {
  obs <- c(rep(1, 10), rep(5, 4), rep(1, 10))
  sim <- c(rep(1, 13), rep(5, 4), rep(1, 7))
  inside <- pdm_threshold_scores(sim, obs, c(t = 3), tolerance_h = 3)
  expect_equal(c(inside$hits, inside$misses, inside$false_alarms), c(1, 0, 0))
  expect_equal(inside$crossing_error_h, 3)
  outside <- pdm_threshold_scores(sim, obs, c(t = 3), tolerance_h = 2)
  expect_equal(c(outside$hits, outside$misses, outside$false_alarms), c(0, 1, 1))
  half_hourly <- pdm_threshold_scores(sim, obs, c(t = 3), dt_hours = 0.5, tolerance_h = 1)
  expect_equal(half_hourly$hits, 0)
  expect_equal(pdm_threshold_scores(sim, obs, c(t = 3), dt_hours = 0.5,
                                    tolerance_h = 1.5)$crossing_error_h, 1.5)
})

test_that("events merge across short gaps and short blips can be ignored", {
  flicker <- c(1, 5, 1, 5, 1, 5, rep(1, 30), 5, rep(1, 5))
  expect_equal(nrow(.find_events(flicker > 3, gap = 2, min_duration = 0)), 2L)
  expect_equal(nrow(.find_events(flicker > 3, gap = 1, min_duration = 0)), 4L)
  merged <- .find_events(flicker > 3, gap = 2, min_duration = 2)
  expect_equal(merged$start, 2L)
  expect_equal(merged$end, 6L)
  s <- pdm_threshold_scores(flicker, flicker, c(t = 3), gap_h = 2)
  expect_equal(c(s$observed_events, s$csi, s$crossing_error_h), c(2, 1, 0))
})

test_that("matching is one to one and closest first", {
  obs <- c(1, 5, 1, 1, 1, 5, 1, 1, 1, 1)
  sim <- c(1, 1, 1, 5, 1, 1, 1, 1, 1, 1)
  s <- pdm_threshold_scores(sim, obs, c(t = 3), tolerance_h = 3, gap_h = 1)
  expect_equal(c(s$hits, s$misses, s$false_alarms), c(1, 1, 0))
  expect_equal(s$crossing_error_h, 2) # a tie goes to the earlier observed event
})

test_that("empty denominators give NA and missing observations count as below", {
  quiet <- pdm_threshold_scores(rep(1, 20), rep(1, 20), c(t = 3))
  expect_true(is.na(quiet$pod) && is.na(quiet$far) && is.na(quiet$csi))
  expect_true(is.na(quiet$crossing_error_h))
  expect_equal(quiet$pofd_step, 0)
  obs <- c(1, NA, NA, 1, 5, 5, 1)
  sim <- c(1, 5, 5, 1, 5, 5, 1)
  s <- pdm_threshold_scores(sim, obs, c(t = 3), tolerance_h = 0, gap_h = 0)
  expect_equal(c(s$hits, s$false_alarms), c(1, 1))
  expect_equal(s$far_step, 0)
})

test_that("step scores follow the contingency definitions", {
  obs <- c(5, 5, 1, 1, 5, 1, 1, 1)
  sim <- c(5, 1, 5, 1, 5, 1, 1, 1)
  s <- pdm_threshold_scores(sim, obs, c(t = 3))
  a <- 2
  b <- 1
  c <- 1
  d <- 4
  n <- 8
  random <- (a + b) * (a + c) / n
  expect_equal(s$pod_step, a / (a + c))
  expect_equal(s$far_step, b / (a + b))
  expect_equal(s$pofd_step, b / (b + d))
  expect_equal(s$ets_step, (a - random) / (a + b + c - random))
  expect_equal(s$pss_step, a / (a + c) - b / (b + d))
})

test_that("arguments are checked", {
  expect_error(pdm_threshold_scores(1:3, 1:2, c(t = 1)), "equal length")
  expect_error(pdm_threshold_scores(1:3, 1:3, 2), "named")
  expect_error(pdm_threshold_scores(1:3, 1:3, c(t = -1)), "positive")
  expect_error(pdm_threshold_scores(1:3, 1:3, c(t = 1), dt_hours = 0), "dt_hours")
  expect_error(pdm_threshold_scores(1:3, 1:3, c(t = 1), gap_h = -1), "nonnegative")
  expect_error(pdm_threshold_scores(c(1, NA, 3), 1:3, c(t = 1)), "finite")
})

test_that("level thresholds convert through the rating and never extrapolate", {
  rating <- .as_rating(data.frame(stage_m = c(1, 0.5, 2), q_m3s = c(4, 1, 16)))
  expect_equal(.level_to_flow(c(0.5, 1, 2), rating), c(1, 4, 16))
  expect_equal(.level_to_flow(1.5, rating), 8)
  expect_error(.level_to_flow(2.1, rating), "outside the rating")
  expect_error(.as_rating(data.frame(stage_m = c(1, 2), q_m3s = c(5, 4))), "rise")
  t <- .resolve_thresholds(data.frame(name = c("A", "W"), value = c(3, 1.5),
                                      unit = c("flow", "level")), rating)
  expect_equal(vapply(t, function(x) x$flow_m3s, numeric(1)), c(3, 8))
  expect_error(.resolve_thresholds(data.frame(name = "W", value = 1, unit = "level"), NULL),
               "rating")
  expect_error(.resolve_thresholds(data.frame(name = "a:b", value = 1, unit = "flow"), NULL),
               "colon")
  expect_error(.resolve_thresholds(data.frame(name = "a", value = 1, unit = "m"), NULL),
               "flow")
})

test_that("projects score thresholds on every run and can rank by them", {
  folder <- tempfile("project-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  d <- log_data() # nolint: object_usage_linter.
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  start_calibration_project(folder, "T", "1", "Warnings", 20, "O", "S")
  high <- stats::quantile(d$observed, 0.97, na.rm = TRUE)
  rating <- data.frame(stage_m = c(0, 1, 2), q_m3s = c(0.1, high, high * 3))
  thresholds <- data.frame(name = c("Flood Alert", "Flood Warning"),
                           value = c(stats::quantile(d$observed, 0.9, na.rm = TRUE), 1),
                           unit = c("flow", "level"))
  reg <- register_data(folder, d$forcing, d$observed, c(121, 700), c(721, 960),
                       headline = "csi:Flood Alert", thresholds = thresholds, rating = rating,
                       event_tolerance_h = 4, event_gap_h = 12)
  expect_equal(reg$scorecard$thresholds[[2]]$flow_m3s, unname(high))
  expect_equal(reg$scorecard$events$tolerance_h, 4)
  expect_true(file.exists(file.path(folder, reg$data$rating$stored)))
  select_structure(folder, d$truth, "Truth")
  run <- preview_trial(folder, 3, c(fc = 0.8))
  direct <- pdm_threshold_scores(run$simulated[121:700], d$observed[121:700],
                                 c(`Flood Alert` = thresholds$value[1], `Flood Warning` = high),
                                 tolerance_h = 4, gap_h = 12)
  expect_equal(run$scores[["csi:Flood Alert"]], direct$csi[1])
  expect_equal(run$scores[["pod:Flood Warning"]], direct$pod[2])
  trials <- project_trials(folder)
  expect_true("csi:Flood Alert" %in% names(trials))
  expect_true(all(verify_project(folder, rerun = TRUE)$ok))
  expect_error(register_data(folder, d$forcing, d$observed, c(121, 700),
                             headline = "csi:Nope", thresholds = thresholds, rating = rating),
               "headline")
  expect_error(register_data(folder, d$forcing, d$observed, c(121, 700),
                             headline = "bias:Flood Alert", thresholds = thresholds,
                             rating = rating), "headline")
  file <- build_report(folder, sensitivity = FALSE, rerun = FALSE)
  expect_true(file.exists(file))
})

calibration_case <- function() {
  set.seed(42)
  n <- 24 * 60
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.07, stats::rgamma(n, 0.7, scale = 3), 0),
                        pet = 0.06)
  start <- pdm_presets("standard")
  start$recharge$kg <- 60
  truth <- start
  truth$fc <- 1.15
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s *
    exp(stats::rnorm(n, 0, 0.03))
  list(forcing = forcing, observed = observed, start = start,
       thresholds = c(alert = unname(stats::quantile(observed, 0.95))))
}

test_that("Nelder-Mead stays in bounds and recovers a parameter", {
  k <- calibration_case()
  fit <- calibrate_pdm(k$start, k$forcing, k$observed, c(fc = 0.8), c(fc = 1.5), warmup = 200,
                       objective = "nse", method = "nelder_mead", control = list(maxit = 80))
  expect_equal(fit$method, "nelder_mead")
  expect_lt(abs(fit$parameters[["fc"]] - 1.15), 0.01)
  low_start <- k$start
  low_start$fc <- 0.7
  edge <- calibrate_pdm(low_start, k$forcing, k$observed, c(fc = 0.6), c(fc = 0.9), warmup = 200,
                        objective = "nse", method = "nelder_mead", control = list(maxit = 80))
  expect_true(edge$parameters[["fc"]] <= 0.9 && edge$parameters[["fc"]] > 0.85)
  default <- calibrate_pdm(k$start, k$forcing, k$observed, c(fc = 0.8), c(fc = 1.5),
                           warmup = 200, objective = "nse")
  expect_equal(default$method, "lbfgsb")
  expect_equal(default$objective_name, "1-NSE")
})

test_that("the threshold objective is 1 - NSE plus the threshold loss at the optimum", {
  k <- calibration_case()
  fit <- calibrate_pdm(k$start, k$forcing, k$observed, c(fc = 0.8), c(fc = 1.5), warmup = 200,
                       objective = "nse", method = "nelder_mead", thresholds = k$thresholds,
                       threshold_weight = 0.5, control = list(maxit = 60))
  sim <- run_pdm(fit$model, k$forcing, initial_state(fit$model, 0.5))$output$q_m3s
  rows <- 201:length(sim)
  nse <- pdm_scorecard(sim[rows], k$observed[rows])[["nse"]]
  csi <- pdm_threshold_scores(sim[rows], k$observed[rows], k$thresholds)$csi
  expect_equal(fit$objective, (1 - nse) + 0.5 * (1 - csi))
  expect_match(fit$objective_name, "1-NSE \\+ 0.5 x mean threshold loss \\(csi at alert\\)")
  only <- calibrate_pdm(k$start, k$forcing, k$observed, c(fc = 0.8), c(fc = 1.5),
                        warmup = 200, objective = "threshold", method = "nelder_mead",
                        thresholds = k$thresholds, threshold_score = "far",
                        control = list(maxit = 30))
  expect_true(only$objective >= 0 && only$objective <= 1)
})

test_that("threshold objectives are refused where they cannot work", {
  k <- calibration_case()
  args <- list(k$start, k$forcing, k$observed, c(fc = 0.8), c(fc = 1.5), objective = "nse")
  expect_error(do.call(calibrate_pdm, c(args, list(thresholds = k$thresholds))), "nelder_mead")
  expect_error(calibrate_pdm(k$start, k$forcing, k$observed, c(fc = 0.8), c(fc = 1.5),
                             objective = "threshold", method = "nelder_mead"), "needs thresholds")
  expect_error(do.call(calibrate_pdm, c(args, list(method = "nelder_mead",
                                                   thresholds = c(huge = 1e6)))), "never exceeds")
  expect_error(do.call(calibrate_pdm, c(args, list(method = "nelder_mead",
                                                   thresholds = k$thresholds,
                                                   threshold_score = "bias"))), "threshold_score")
  expect_error(do.call(calibrate_pdm, c(args, list(method = "nelder_mead",
                                                   thresholds = k$thresholds,
                                                   threshold_weight = -1))), "weight")
})

test_that("a logged threshold calibration records what the optimiser was rewarded for", {
  folder <- tempfile("project-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  d <- log_data() # nolint: object_usage_linter.
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  start_calibration_project(folder, "T", "1", "Warnings", 20, "O", "S")
  alert <- unname(stats::quantile(d$observed, 0.95, na.rm = TRUE))
  register_data(folder, d$forcing, d$observed, c(121, 700), c(721, 960),
                thresholds = data.frame(name = "Flood Alert", value = alert, unit = "flow"))
  start <- d$truth
  start$fc <- 0.9
  select_structure(folder, start, "Start")
  expect_error(log_auto_calibration(folder, 3, c(fc = 0.7), c(fc = 1.3), reasoning = "x",
                                    method = "nelder_mead", threshold_objective = "Nope"),
               "Unknown threshold")
  entry <- log_auto_calibration(folder, 3, c(fc = 0.7), c(fc = 1.3), reasoning = "Warnings",
                                method = "nelder_mead", threshold_objective = "Flood Alert",
                                threshold_weight = 2, control = list(maxit = 25))
  expect_equal(entry$method, "nelder_mead")
  expect_equal(entry$threshold_weight, 2)
  expect_equal(entry$threshold_score, "csi")
  expect_match(entry$objective_name, "csi at Flood Alert")
  expect_equal(entry$evaluations, sum(entry$start_results$evaluations))
  expect_true(all(verify_project(folder, rerun = TRUE)$ok))
})
