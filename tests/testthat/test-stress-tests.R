# ============================================================ #
# Tool:         test_stress_tests
# Description:  The differential split-sample test and parameter drift
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Synthetic records built in each test, with known parameters
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

stress_case <- function(years = 4) {
  rain <- synthetic_rain("2010-10-01", years = years, dt = 1, seed = 4)
  truth <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
  m <- pdm_from_config(truth)
  f <- rain[c("time", "rain", "pet")]
  list(forcing = f, truth = truth, model = m)
}

# Guards: water years run October to September and are named by the year they end
test_that("water years", {
  t <- as.POSIXct(c("2010-09-30 23:00", "2010-10-01 00:00", "2011-09-30 23:00"), tz = "UTC")
  expect_equal(.water_year_end(t), c(2010L, 2011L, 2011L))
})

# Guards: the dry and wet halves are chosen by rain, and an exact record scores 1 both ways
test_that("the differential split-sample test", {
  d <- stress_case(4)
  obs <- .run_flow(d$model, d$forcing, initial_state(d$model, 0.5), "q_m3s")
  sst <- split_sample_test(d$truth, d$forcing, obs, lower = c(fc = 0.5), upper = c(fc = 1.5),
                           start = "soil", control = list(maxit = 30))
  # Four complete water years, 2011 to 2014; the two with least rain are the dry half
  years <- .usable_years(d$forcing, obs)
  expect_equal(years$water_year, 2011:2014)
  dry <- sort(years$water_year[order(years$rain_mm)][1:2])
  expect_equal(sst$years$dry, dry)
  # Starting at the truth on its own flow, both calibrations stay there: NSE 1 everywhere
  expect_equal(sst$scores$nse, rep(1, 4), tolerance = 1e-6)
  expect_equal(unname(sst$parameters$fc), c(1, 1), tolerance = 1e-3)
  expect_equal(nrow(sst$scores), 4L)
  halves <- split_sample_test(d$truth, d$forcing, obs, c(fc = 0.5), c(fc = 1.5),
                              split = "halves", start = "soil", control = list(maxit = 5))
  expect_equal(halves$years, list(early = 2011:2012, late = 2013:2014))
  expect_output(print(sst), "climate")
})

# Guards: a change in the catchment halfway shows as drift in the parameter that changed
test_that("parameter drift finds a change halfway", {
  d <- stress_case(4)
  # The rainfall factor is 1.0 up to September 2012 and 1.3 after: two runs spliced
  late <- pdm_from_config(modifyList(d$truth, list(fc = 1.3)))
  s0 <- initial_state(d$model, 0.5)
  a <- .run_flow(d$model, d$forcing, s0, "q_m3s")
  b <- .run_flow(late, d$forcing, s0, "q_m3s")
  split_at <- which(d$forcing$time >= as.POSIXct("2012-10-01", tz = "UTC"))[1]
  obs <- c(a[seq_len(split_at - 1L)], b[seq.int(split_at, length(b))])
  start <- modifyList(d$truth, list(fc = 1.15))
  drift <- parameter_drift(start, d$forcing, obs, lower = c(fc = 0.6), upper = c(fc = 1.6),
                           periods = 2L, start = "soil", control = list(maxit = 40))
  expect_equal(drift$parameters$from, c(2011, 2013))
  expect_equal(drift$parameters$fc, c(1.0, 1.3), tolerance = 0.06)
  # The change, as a share of the range 0.6 to 1.6: about (1.3 - 1.0) / 1 = 0.3
  expect_equal(drift$change$fc[2], 0.3, tolerance = 0.1)
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_invisible(plot(drift))
  expect_error(parameter_drift(start, d$forcing, obs, c(fc = 0.6), c(fc = 1.6), periods = 9,
                               start = "soil"),
               "Fewer complete")
})
