# ============================================================ #
# Tool:         test-synthetic
# Description:  Tests for the rainfall generators, their fitting, and synthetic catchments
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-02
# Modified:     2026-11-02 - Add synthetic rain and catchment tests
# Tier:         3
# Inputs:       Simulated rain and flow
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# One parameter set for every month, so a long simulation estimates one set of statistics.
constant <- function(p, method) {
  pdmS7:::.as_rain_parameters(cbind(month = 1:12, as.data.frame(t(replicate(12, p)))), method)
}

# Every element of a lies within tol of b.
near <- function(a, b, tol) testthat::expect_lt(max(abs(a - b)), tol)

aggregate_to <- function(x, h) colSums(matrix(x[seq_len(length(x) %/% h * h)], nrow = h))

# Guards: the exact pulse-model statistics equal those of long simulations
test_that("pulse-model statistics match simulation", {
  cases <- list(
    nsrp = c(lambda = 0.02, beta = 0.1, nu = 5, eta = 0.7, mux = 1.5),
    bartlett_lewis = c(lambda = 0.02, gamma = 0.15, beta = 0.6, eta = 0.9, mux = 1.5)
  )
  for (method in names(cases)) {
    par <- constant(cases[[method]], method)
    rain <- synthetic_rain("2000-01-01", years = 120, method = method, parameters = par,
                           pet = NULL, seed = 1)$rain
    exact <- rain_statistics(par, c(1, 24))
    exact <- exact[exact$month == 1, ]
    for (i in 1:2) {
      x <- aggregate_to(rain, exact$hours[i])
      expect_equal(mean(x), exact$mean[i], tolerance = 0.03)
      expect_equal(stats::var(x), exact$variance[i], tolerance = 0.05)
      near(stats::cor(x[-1], x[-length(x)]), exact$lag1[i], 0.02)
      near(mean(x == 0), exact$pdry[i], 0.01)
    }
  }
})

# Guards: rectangular cells are summed into steps exactly
test_that("cell depths are exact at any step", {
  depth <- pdmS7:::.pulse_depths(c(0.5, 2.25), c(3.5, 2.75), c(2, 4), seq(0, 4, by = 0.25))
  expect_equal(sum(depth), 2 * 3 + 4 * 0.5)
  expect_equal(depth[1:2], c(0, 0))
  expect_equal(depth[3], 0.5)
  expect_equal(depth[10], 0.25 * 2 + 0.25 * 4)
  expect_equal(pdmS7:::.pulse_depths(numeric(0), numeric(0), numeric(0), 0:3), rep(0, 3))
})

# Guards: the Markov chain's transitions and amounts follow its parameters
test_that("the Markov chain and gamma amounts follow their parameters", {
  par <- constant(c(p01 = 0.3, p11 = 0.65, shape = 0.8, scale = 6), "markov_gamma")
  x <- synthetic_rain("2000-01-01", years = 100, dt = 24, method = "markov_gamma",
                      parameters = par, pet = NULL, seed = 2)$rain
  wet <- x > 0
  near(mean(wet[-1][!wet[-length(wet)]]), 0.3, 0.02)
  near(mean(wet[-1][wet[-length(wet)]]), 0.65, 0.02)
  expect_equal(mean(x[wet]), 0.8 * 6, tolerance = 0.03)
  fit <- fit_rain(data.frame(time = seq(as.POSIXct("2000-01-01", tz = "UTC"), by = 86400,
                                        length.out = length(x)), rain = x),
                  "markov_gamma", wet_threshold = 0)
  near(fit$p01, 0.3, 0.06)
  expect_equal(fit$shape, rep(0.8, 12), tolerance = 0.12)
  expect_error(synthetic_rain("2000-01-01", 1, dt = 1, method = "markov_gamma"),
               "daily rain only")
})

# Guards: a Neyman-Scott fit reproduces the record's statistics
test_that("fit_rain matches a record's statistics", {
  rec <- synthetic_rain("2000-01-01", years = 25, seed = 3, pet = NULL)
  fit <- fit_rain(rec, "nsrp")
  expect_s3_class(fit, "pdm_rain_parameters")
  check <- attr(fit, "fit")
  expect_equal(check$mean_model, check$mean_record, tolerance = 1e-6)
  expect_equal(check$variance_model, check$variance_record, tolerance = 0.1)
  near(check$pdry_model, check$pdry_record, 0.03)
  # A month with too few days borrows its neighbours' parameters.
  gappy <- rec
  gappy$rain[as.POSIXlt(gappy$time)$mon == 1] <- NA
  mg <- fit_rain(gappy, "markov_gamma")
  expect_equal(mg$p01[2], mean(mg$p01[c(1, 3)]))
})

# Guards: records are read from plain data frames and from reach.io's objects alike
test_that("records are accepted as data frames or reach.io objects", {
  time <- seq(as.POSIXct("2020-01-01", tz = "UTC"), by = 900, length.out = 10)
  plain <- data.frame(dateTime = time, value = c(0, 0.2, NA, 0.4, rep(0, 6)))
  rec <- pdmS7:::.as_rain_record(plain)
  expect_equal(attr(rec, "step_h"), 0.25)
  expect_true(is.na(rec$rain[3]))
  holder <- S7::new_class("Holder", properties = list(readings = S7::class_data.frame))
  expect_equal(pdmS7:::.as_rain_record(holder(readings = plain)), rec)
  # A missing step becomes NA, so the record stays regular.
  expect_equal(nrow(pdmS7:::.as_rain_record(plain[-5, ])), 10L)
  expect_error(pdmS7:::.as_rain_record(data.frame(a = 1)), "time column")
})

# Guards: resampling copies whole days of the record from near the same date
test_that("resampled rain is real rain from the same season", {
  rec <- synthetic_rain("2000-10-01", years = 6, seed = 4, pet = NULL)
  out <- synthetic_rain("2030-10-01", years = 2, method = "resample", record = rec,
                        block_days = 5, window_days = 10, seed = 5)
  days <- matrix(out$rain, nrow = 24)
  pool <- matrix(rec$rain, nrow = 24)
  key <- function(m) apply(m, 2, paste, collapse = ",")
  expect_true(all(key(days) %in% key(pool)))
  # A January output day comes from a record day within ten days of the same date.
  jan <- which(as.POSIXlt(out$time[seq(1, nrow(out), 24)])$yday == 15)[1]
  src <- match(key(days)[jan], key(pool))
  gap <- abs(as.POSIXlt(rec$time[(src - 1) * 24 + 1])$yday - 15)
  expect_lte(min(gap, 365 - gap), 10 + 5)
  daily <- synthetic_rain("2030-10-01", 1, dt = 24, method = "resample", record = rec, seed = 5)
  expect_equal(nrow(daily), 365L)
  expect_error(synthetic_rain("2030-10-01", 1, method = "resample"), "needs a record")
})

# Guards: a seed reproduces the series and leaves the caller's random stream alone
test_that("seeds reproduce and do not disturb the caller", {
  set.seed(10)
  before <- stats::runif(1)
  set.seed(10)
  a <- synthetic_rain("2020-01-01", 1, seed = 6)
  after <- stats::runif(1)
  expect_equal(before, after)
  expect_identical(a, synthetic_rain("2020-01-01", 1, seed = 6))
  expect_gte(min(a$pet), 0)
  expect_equal(sum(a$pet[a$time < as.POSIXct("2020-01-02", tz = "UTC")]),
               1.5 + 1.3 * cos(2 * pi * (1.5 - 182) / 365.25), tolerance = 0.01)
})

# Guards: storms, the rating bend and the gauge error do exactly what they say
test_that("a synthetic catchment adds storms, bends the rating and adds persistent error", {
  base <- synthetic_rain("2010-10-01", years = 3, dt = 24, seed = 7)
  storm <- data.frame(time = "2011-12-01", depth_mm = 120, duration_h = 48)
  exact <- synthetic_catchment(base, storms = storm, error = list(sd = 0, memory_h = 24),
                               highest_gauged_m3s = 10, rating_bias = 0.2)
  expect_equal(sum(exact$forcing$rain) - sum(base$rain), 120)
  q <- exact$true_flow
  ratio <- exact$observed / q
  expect_equal(ratio[q <= 10], rep(1, sum(q <= 10)))
  expect_equal(pdmS7:::.rating_bend(20, 10, 0.2), 16)
  expect_true(all(ratio[q > 10] < 1))
  expect_equal(exact$truth$distribution$cmax, 300)
  # Spun up: the first year looks like the second, not like an emptying store.
  expect_equal(mean(q[1:365]), mean(q[366:730]), tolerance = 0.5)
  noisy <- synthetic_catchment(synthetic_rain("2000-10-01", years = 30, dt = 24, seed = 8),
                               error = list(sd = 0.1, memory_h = 48), seed = 9)
  e <- log(noisy$observed / noisy$true_flow)
  expect_equal(stats::sd(e), 0.1, tolerance = 0.1)
  near(stats::cor(e[-1], e[-length(e)]), exp(-24 / 48), 0.05)
  expect_output(print(exact), "Rating: exact to 10")
  wrong <- exact$truth
  wrong$dt <- 1
  expect_error(synthetic_catchment(base, truth = wrong), "forcing's step")
  expect_error(synthetic_catchment(base, storms = data.frame(time = "2030-01-01", depth_mm = 1,
                                                             duration_h = 1)), "within")
})

# Guards: a synthetic sample is written as batch-ready basins, reproducibly, inside the bounds
test_that("synthetic_basins writes a reproducible sample the batch can calibrate", {
  root <- tempfile("sample-")
  output <- tempfile("batch-")
  on.exit(unlink(c(root, output), recursive = TRUE), add = TRUE)
  s <- synthetic_basins(root, n = 2, years = 3, seed = 4)
  expect_equal(s$basin, c("S001", "S002"))
  expect_true(all(file.exists(file.path(root, "S001", c("forcing.csv", "flow.csv",
                                                         "basin.yml", "truth.yml")))))
  truth <- read_pdm_config(file.path(root, "S002", "truth.yml"))
  expect_equal(truth$distribution$cmax, s$cmax[2])
  bounds <- calibration_bounds(truth)
  values <- vapply(bounds$path, function(p) pdmS7:::.path_get(truth, p), numeric(1))
  expect_true(all(values >= bounds$lower & values <= bounds$upper))
  meta <- yaml::read_yaml(file.path(root, "S001", "basin.yml"))
  expect_equal(meta$wettest_years, 0)
  expect_equal(meta$highest_gauged_m3s, s$highest_gauged_m3s[1])
  again <- tempfile("sample-")
  on.exit(unlink(again, recursive = TRUE), add = TRUE)
  expect_equal(synthetic_basins(again, n = 2, years = 3, seed = 4), s)
  expect_error(synthetic_basins(root, n = 2, years = 3), "already exist")
  expect_error(synthetic_basins(tempfile(), n = 1, ranges = list(cmax = c(5, 1))), "range")
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  status <- calibrate_batch(root, output, starts = 1, control = list(maxit = 3))
  expect_equal(status$state, c("done", "done"))
})
