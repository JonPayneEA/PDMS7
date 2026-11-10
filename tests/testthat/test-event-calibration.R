# Tests for event calibration: the events objective of calibrate_pdm(), the events stage of
# pdm_stages(), thresholds in staged calibration, and calibration_checks().

# A noiseless hourly record from a known model with a time delay, so the truth scores zero.
event_data <- function(n = 24 * 120, td = 2) {
  set.seed(11)
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.06, stats::rgamma(n, 0.7, scale = 5), 0),
                        pet = 0.05)
  truth <- pdm_presets("standard")
  truth$area_km2 <- 20
  truth$surface$k1 <- 3
  truth$surface$k2 <- 5
  truth$td <- td
  model <- pdm_from_config(truth)
  observed <- run_pdm(model, forcing, initial_state_from_flow(model, 0.3, 0.7))$output$q_m3s
  list(forcing = forcing, observed = observed, truth = truth)
}

# Guards: the events objective is zero at the truth and positive away from it
test_that("the events objective scores the truth as perfect", {
  d <- event_data()
  ev <- find_events(d$forcing$rain, d$observed, dt = 1)
  obj <- .event_objective(ev, d$forcing$rain, d$observed, warmup = 48, dt = 1)
  model <- pdm_from_config(d$truth)
  truth_sim <- run_pdm(model, d$forcing, initial_state_from_flow(model, 0.3, 0.7))$output$q_m3s
  expect_lt(obj$score(truth_sim), 1e-12)
  late <- c(rep(truth_sim[1], 3), head(truth_sim, -3))
  expect_gt(obj$score(late), 0.05)
  expect_gt(obj$score(truth_sim * 0.6), obj$score(truth_sim * 0.9))
  expect_equal(obj$events, ceiling(0.5 * obj$found))
  expect_match(obj$name, paste(obj$events, "largest of", obj$found))
})

# Guards: share, weights and warm-up are checked and applied
test_that("the events objective checks its settings", {
  d <- event_data()
  ev <- find_events(d$forcing$rain, d$observed, dt = 1)
  all <- .event_objective(ev, d$forcing$rain, d$observed, 48, 1, share = 1)
  expect_equal(all$events, all$found)
  late <- .event_objective(ev, d$forcing$rain, d$observed, 24 * 100, 1, share = 1)
  expect_lt(late$found, all$found)
  expect_error(.event_objective(ev, d$forcing$rain, d$observed, 48, 1, share = 0), "event_share")
  expect_error(.event_objective(ev, d$forcing$rain, d$observed, 48, 1,
                                weights = c(nse = 1, peak = -1, timing = 0)), "event_weights")
  expect_error(.event_objective(ev, d$forcing$rain, d$observed, length(d$observed) - 2, 1),
               "No event")
  only_timing <- .event_objective(ev, d$forcing$rain, d$observed, 48, 1,
                                  weights = c(nse = 0, peak = 0, timing = 1))
  expect_equal(only_timing$score(d$observed * 2), 0)
})

# Guards: calibrate_pdm() with objective = "events" finds the time delay
test_that("calibrate_pdm fits the time delay on events", {
  d <- event_data()
  start <- d$truth
  start$td <- 0
  fit <- calibrate_pdm(start, d$forcing, d$observed, lower = c(td = 0), upper = c(td = 5),
                       warmup = 48, objective = "events", method = "dds", seed = 1,
                       control = list(maxit = 40))
  expect_equal(unname(fit$parameters["td"]), 2, tolerance = 0.1)
  expect_match(fit$objective_name, "^events:")
})

# Guards: the events stage comes last, searches td with DDS, and can be switched off
test_that("pdm_stages adds an events stage with the time delay", {
  cfg <- pdm_presets("standard")
  st <- pdm_stages(cfg, events = TRUE, event_budget = 120)
  expect_length(st, 4)
  last <- st[[4]]
  expect_equal(last$name, "events")
  expect_equal(last$objective, "events")
  expect_true(all(c("surface.k1", "surface.k2", "distribution.b", "td") %in% last$parameters))
  expect_equal(last$method, "dds")
  expect_equal(last$control$maxit, 120)
  expect_equal(last$extra_bounds$upper, 6)
  expect_false("td" %in% pdm_stages(cfg, events = TRUE, td_max = NULL)[[4]]$parameters)
  expect_false("td" %in% pdm_stages(cfg, events = TRUE, exclude = "td")[[4]]$parameters)
  expect_length(pdm_stages(cfg), 3)
  b <- .stage_bounds(last, calibration_bounds(cfg), cfg)
  expect_equal(unname(b$upper["td"]), 6)
})

# Guards: thresholds go on the last stage, which then searches with DDS
test_that("thresholds attach to the last stage", {
  cfg <- pdm_presets("standard")
  st <- pdm_stages(cfg, thresholds = c(warning = 5), event_budget = 90)
  expect_equal(st[[3]]$thresholds, c(warning = 5))
  expect_equal(st[[3]]$method, "dds")
  expect_equal(st[[3]]$control$maxit, 90)
  expect_null(st[[2]]$thresholds)
  named <- pdm_stages(cfg, thresholds = "Flood Warning")
  d <- event_data(n = 24 * 20)
  expect_error(calibrate_staged(cfg, d$forcing, d$observed, stages = named[3]),
               "named flows")
})

# Guards: a staged calibration with the events stage improves the event fit of the polish
test_that("the events stage improves the largest events", {
  d <- event_data()
  start <- d$truth
  start$surface$k1 <- 20
  start$surface$k2 <- 30
  start$td <- 0
  st <- pdm_stages(start, events = TRUE, event_budget = 80)
  st <- st[c(2, 4)]
  fit <- calibrate_staged(start, d$forcing, d$observed, stages = st, warmup = 48,
                          control = list(maxit = 10), seed = 2)
  obj <- .event_objective(NULL, d$forcing$rain, d$observed, 48, 1)
  score <- function(cfg) {
    model <- pdm_from_config(cfg)
    obj$score(run_pdm(model, d$forcing, initial_state_from_flow(model, d$observed[1],
                                                                0.7))$output$q_m3s)
  }
  expect_lt(score(fit$config), score(fit$stages[[1]]$config))
  expect_gt(fit$config$td, 0)
})

# Guards: in a project, the events stage is logged with its objective and weights, and the
# checks report the bounds and the events
test_that("a logged events stage and the acceptance checks", {
  p <- new_project()
  stages <- pdm_stages(p$data$truth, exclude = c("groundwater.kb", "distribution.cmax"),
                       events = TRUE, event_budget = 20)
  stages <- stages[c(2, 4)]
  stages[[1]]$parameters <- "surface.k1"
  out <- log_staged_calibration(p$folder, parent = "0003", reasoning = "Events.",
                                stages = stages, control = list(maxit = 3), seed = 1)
  last <- read_entry(p$folder, out[[2]]$id)
  expect_equal(last$objective, "events")
  expect_equal(last$method, "dds")
  expect_equal(last$event_weights$timing, 0.5)
  expect_match(last$objective_name, "events:")
  expect_true("td" %in% names(last$bounds$lower))
  expect_true(all(verify_project(p$folder)$ok))
  checks <- calibration_checks(p$folder, entry = out[[2]]$id, top = 5)
  expect_setequal(checks$parameters$path,
                  c("surface.k1", "distribution.b", "surface.k2", "td"))
  expect_true(all(checks$parameters$lower <= checks$parameters$value &
                    checks$parameters$value <= checks$parameters$upper))
  expect_true(all(checks$summary$events <= 5))
  expect_true("calibration" %in% checks$summary$period)
  expect_named(checks$response_h, c("observed", "simulated"))
  expect_error(calibration_checks(p$folder), "No candidate")
})

# Guards: a parameter pushed to its bound is flagged, except at a natural lower bound of zero
test_that("bound flags find parameters at either end, but not at zero", {
  entries <- list(
    list(id = "0001", type = "structure", configuration = list()),
    list(id = "0002", type = "auto_calibration", parent = "0001",
         bounds = list(lower = list(a = 1, b = 0, c = 0), upper = list(a = 1000, b = 10, c = 10)),
         log_scale = list("a")),
    list(id = "0003", type = "auto_calibration", parent = "0002",
         bounds = list(lower = list(c = 2), upper = list(c = 20)),
         configuration = list(a = 999, b = 5, c = 0.05))
  )
  flags <- .bound_flags(entries, entries[[3]], 0.01)
  flags <- flags[order(flags$path), ]
  expect_equal(flags$at_bound, c("upper", NA, NA))
  expect_equal(flags$scale, c("log", "linear", "linear"))
  expect_equal(flags$upper[flags$path == "c"], 20)
  above_zero <- entries
  above_zero[[2]]$bounds$lower$c <- 0.01
  flags <- .bound_flags(above_zero, above_zero[[3]], 0.01)
  expect_equal(flags$at_bound[flags$path == "c"], "lower")
})

# Guards: a split recharge's alpha at 0 or 1 is flagged, with what it switches off, though a zero
# lower bound is otherwise left alone
test_that("a split recharge's alpha at either end is flagged", {
  entries <- function(alpha, type = "split") {
    list(
      list(id = "0001", type = "structure_selected"),
      list(id = "0002", type = "auto_calibration", parent = "0001",
           bounds = list(lower = list(recharge.alpha = 0, td = 0),
                         upper = list(recharge.alpha = 1, td = 6)),
           configuration = list(recharge = list(type = type, alpha = alpha), td = 0))
    )
  }
  flags <- function(e) {
    f <- .bound_flags(e, e[[2]], 0.01)
    f[order(f$path), ]
  }
  off <- flags(entries(0))
  expect_equal(off$at_bound, c("lower", NA))
  expect_match(off$note[1], "surface stores carry nothing")
  expect_true(is.na(off$note[2]))
  expect_equal(flags(entries(1))$at_bound[1], "upper")
  expect_match(flags(entries(1))$note[1], "no direct runoff reaches groundwater")
  expect_true(is.na(flags(entries(0.4))$at_bound[1]))
  expect_true(is.na(flags(entries(0, "demand"))$at_bound[1]))
})
