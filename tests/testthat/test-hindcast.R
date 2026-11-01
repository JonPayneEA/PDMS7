# ============================================================ #
# Tool:         test-hindcast
# Description:  Tests for response time, AR construction, hindcasts and lead-time scores
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add hindcast tests
# Tier:         3
# Inputs:       Synthetic forcing and flows
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

surface_only <- function(k, dt = 0.05) {
  pdm_model(area_km2 = 50, dt = dt, surface = FlodeCascadeRouting(k1 = k, k2 = k),
            recharge = FlodeStandardRecharge(kg = 1e7, bg = 1, st = 0))
}

test_that("response time matches the analytic two-store cascade", {
  # Two equal linear stores: response t exp(-t/k) / k^2, peak at k, centroid at 2k,
  # and 1/e of the peak is reached 2.146 k after it.
  for (k in c(2, 5)) {
    rt <- pdm_response_time(surface_only(k), flow = 2, max_hours = 40 * k)
    expect_equal(rt$time_to_peak_h, k, tolerance = 0.01)
    expect_equal(rt$centroid_lag_h, 2 * k, tolerance = 0.01)
    expect_equal(rt$recession_h, 2.146 * k, tolerance = 0.03)
  }
})

test_that("response time is consistent across time steps and flows", {
  hourly <- pdm_response_time(pdm_model(area_km2 = 50), flow = 5)
  quarter <- pdm_response_time(pdm_model(area_km2 = 50, dt = 0.25), flow = 5)
  expect_equal(hourly$time_to_peak_h, quarter$time_to_peak_h, tolerance = 0.05)
  wetter <- pdm_response_time(pdm_model(area_km2 = 50), flow = 20)
  expect_lt(wetter$time_to_peak_h, hourly$time_to_peak_h)
  expect_gt(hourly$recession_h, hourly$time_to_peak_h)
  expect_equal(nrow(hourly$response), 24 * 60)
})

test_that("the FEH comparison flags a factor of two", {
  model <- surface_only(3)
  near <- pdm_response_time(model, 2, max_hours = 100, feh_time_to_peak_h = 4)
  expect_false(near$feh$flag)
  expect_equal(near$feh$ratio, near$time_to_peak_h / 4)
  far <- pdm_response_time(model, 2, max_hours = 100, feh_time_to_peak_h = 10)
  expect_true(far$feh$flag)
  expect_error(pdm_response_time(model, 2, feh_time_to_peak_h = -1), "feh_time_to_peak_h")
  expect_error(pdm_response_time(model, 0), "flow")
})

test_that("default-family AR matches the published table", {
  # reach.postproc::standard_family_ar_table(), 15-minute steps: principal decay in hours,
  # then a_2 and a_3 (a_1 is 1.765 throughout). Checked against reach.postproc 0.12.2.
  published <- rbind(c(3, -0.7328501, -0.04098486), c(6, -0.7303273, -0.04085926),
                     c(24, -0.7262460, -0.04065607), c(192, -0.7246735, -0.04057777))
  for (i in seq_len(nrow(published))) {
    a <- ar_from_response_time(published[i, 1], dt = 0.25)
    expect_equal(as.numeric(a), c(1.765, published[i, 2:3]), tolerance = 1e-6)
  }
  expect_equal(sum(attr(a, "roots")), 1.765)
  expect_equal(unname(ar_ea_default()), c(1.765, -0.72625, -0.040656))
  # The family depends on decay in steps, so hours and step length trade off.
  expect_equal(ar_from_response_time(12, dt = 1), ar_from_response_time(3, dt = 0.25))
})

hindcast_case <- function(n = 24 * 30, seed = 4) {
  set.seed(seed)
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.06, stats::rgamma(n, 0.7, scale = 4),
                                      0), pet = 0.05)
  truth <- pdm_model(area_km2 = 40, fc = 1.1)
  observed <- run_pdm(truth, forcing, initial_state_from_flow(truth, 2, 0.7))$output$q_m3s
  list(forcing = forcing, observed = observed, model = pdm_model(area_km2 = 40))
}

test_that("hindcast methods reproduce their definitions", {
  case <- hindcast_case()
  start <- initial_state_from_flow(case$model, case$observed[1], 0.7)
  hc <- pdm_hindcast(case$model, case$forcing, case$observed, state = start, every_h = 12,
                     horizon_h = 6, ar = list(half = 0.5))
  f <- hc$forecasts
  expect_setequal(unique(f$method), c("none", "persistence", "half"))
  sim <- run_pdm(case$model, case$forcing, start)$output$q_m3s
  none <- f[f$method == "none", ]
  expect_equal(none$forecast, sim[none$origin + none$lead], tolerance = 1e-10)
  pers <- f[f$method == "persistence", ]
  expect_equal(pers$forecast, case$observed[pers$origin])
  half <- f[f$method == "half", ]
  e0 <- case$observed[half$origin] - sim[half$origin]
  expect_equal(half$forecast, pmax(sim[half$origin + half$lead] + 0.5^half$lead * e0, 0),
               tolerance = 1e-10)
  expect_equal(diff(sort(unique(f$origin))), rep(12L, length(unique(f$origin)) - 1))
  expect_equal(max(f$lead_h), 6)
  expect_true(all(f$origin + f$lead <= nrow(case$forcing)))
})

test_that("default AR sets use the response time, and fitting recovers an AR(1)", {
  case <- hindcast_case()
  n <- length(case$observed)
  start <- initial_state_from_flow(case$model, case$observed[1], 0.7)
  sim <- run_pdm(case$model, case$forcing, start)$output$q_m3s
  set.seed(9)
  err <- stats::arima.sim(list(ar = 0.8), n, sd = 0.05)
  observed <- pmax(sim + as.numeric(err), 0.01)
  expect_message(
    hc <- pdm_hindcast(case$model, case$forcing, observed, state = start,
                       window = (n / 2 + 1):n, fit_window = 1:(n / 2), horizon_h = 3),
    "15-minute"
  )
  expect_named(hc$ar, c("ea_2024", "response_time", "fitted"))
  rt <- pdm_response_time(case$model, stats::quantile(observed, 0.9, names = FALSE))
  expect_equal(hc$response_time$time_to_peak_h, rt$time_to_peak_h)
  expect_equal(hc$ar$response_time, ar_from_response_time(rt$time_to_peak_h, 1))
  expect_equal(unname(hc$ar$fitted[1]), 0.8, tolerance = 0.1)
  expect_lt(abs(hc$ar$fitted[2]) + abs(hc$ar$fitted[3]), 0.2)
  expect_true(all(hc$forecasts$origin > n / 2))
})

test_that("missing observations remove AR forecasts but not the simulation", {
  case <- hindcast_case()
  observed <- case$observed
  observed[300:310] <- NA
  hc <- pdm_hindcast(case$model, case$forcing, observed, every_h = 1, horizon_h = 2,
                     ar = list(one = 0.9), window = 290:320)
  f <- hc$forecasts
  gap <- f[f$origin %in% 300:310, ]
  expect_true(all(is.na(gap$forecast[gap$method == "one"])))
  expect_true(all(is.finite(gap$forecast[gap$method == "none"])))
})

test_that("state correction forecasts start from the corrected state", {
  case <- hindcast_case()
  start <- initial_state_from_flow(case$model, case$observed[1], 0.7)
  hc <- pdm_hindcast(case$model, case$forcing, case$observed, state = start, every_h = 24,
                     horizon_h = 4, ar = list(), state_correction = state_updater(),
                     window = 200:300)
  f <- hc$forecasts
  o <- f$origin[f$method == "state"][1]
  at_origin <- run_pdm(case$model, case$forcing[1:o, ], start)$state
  fixed <- correct_state(case$model, at_origin, case$observed[o])$state
  expect_equal(f$forecast[f$method == "state" & f$origin == o],
               run_pdm(case$model, case$forcing[o + 1:4, ], fixed)$output$q_m3s,
               tolerance = 1e-10)
})

test_that("lead-time scores match a hand calculation", {
  pairs <- data.frame(
    origin = rep(1:4, 2), lead_h = 1, method = rep(c("persistence", "model"), each = 4),
    forecast = c(1, 2, 3, 4, 1.5, 2, 3.5, 5), observed = rep(c(2, 2, 4, 5), 2)
  )
  s <- hindcast_scores(pairs, thresholds = c(high = 3.8), response_time_h = 2)
  m <- s[s$method == "model", ]
  expect_equal(m$rmse, sqrt(mean(c(0.25, 0, 0.25, 0))))
  expect_equal(m$bias, -0.25)
  expect_equal(m$skill, 1 - mean(c(0.25, 0, 0.25, 0)) / mean(c(1, 0, 1, 1)))
  expect_equal(m$nse, 1 - 0.5 / sum((c(2, 2, 4, 5) - 3.25)^2))
  expect_equal(m$lead_ratio, 0.5)
  expect_equal(c(m$`pod:high`, m$`far:high`, m$`csi:high`), c(0.5, 0, 0.5))
  expect_equal(s$skill[s$method == "persistence"], 0)
  expect_error(hindcast_scores(pairs[pairs$method == "model", ]), "persistence")
})

test_that("scores from a hindcast carry the response time and plot", {
  case <- hindcast_case()
  hc <- suppressMessages(pdm_hindcast(case$model, case$forcing, case$observed, horizon_h = 6))
  s <- hindcast_scores(hc)
  expect_equal(s$lead_ratio, s$lead_h / hc$response_time$time_to_peak_h)
  expect_equal(nrow(s), 4 * 6)
  pdf(NULL)
  on.exit(grDevices::dev.off())
  expect_invisible(plot_hindcast(s))
  expect_invisible(plot_hindcast(s, metric = "nse", ratio = TRUE))
  expect_invisible(plot_hindcast(s, ylim = c(-1, 1)))
  expect_error(plot_hindcast(s, metric = "nope"), "no column")
})
