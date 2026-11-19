# ============================================================ #
# Tool:         test_ensemble_scores
# Description:  CRPS, the Brier score and its decomposition, ranks and the spread-skill ratio,
#               in closed form and on ensembles of known reliability
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Hand-built ensembles; ensembles drawn from known distributions
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Guards: the CRPS in closed form
test_that("CRPS of small ensembles", {
  # One member: the absolute error
  expect_equal(crps_ensemble(matrix(3, 1, 1), 1), 2)
  # Members 0 and 1, observed 0: mean |X - y| = 0.5; over all four ordered pairs mean
  # |X - X'| = 0.5, so CRPS = 0.5 - 0.25 = 0.25. Over the two distinct pairs it is 1, so the
  # fair CRPS is 0.5 - 0.5 = 0.
  e <- matrix(c(0, 1), 1)
  expect_equal(crps_ensemble(e, 0), 0.25)
  expect_equal(crps_ensemble(e, 0, fair = TRUE), 0)
  # Members 1, 2, 3, observed 2: mean |X - y| = 2/3; ordered pairs mean |X - X'| = 8/9
  expect_equal(crps_ensemble(matrix(1:3, 1), 2), 2 / 3 - 4 / 9)
  expect_equal(crps_ensemble(rbind(c(0, 1), c(1, 2, NA)[1:2]), c(0, NA)), c(0.25, NA))
})

# Guards: the Brier score and Murphy's decomposition, worked by hand
test_that("Brier score and its decomposition", {
  # Forecasts 0.9, 0.9, 0.1, 0.1 for outcomes 1, 0, 0, 0:
  # BS = (0.01 + 0.81 + 0.01 + 0.01) / 4 = 0.21. Bins: 0.9 (observed 1/2) and 0.1 (observed 0),
  # each half the forecasts. Reliability = 0.5 x 0.4^2 + 0.5 x 0.1^2 = 0.085; base rate 0.25,
  # resolution = 0.5 x 0.25^2 + 0.5 x 0.25^2 = 0.0625; uncertainty = 0.25 x 0.75 = 0.1875.
  b <- brier_score(c(0.9, 0.9, 0.1, 0.1), c(1, 0, 0, 0))
  expect_equal(b$brier, 0.21)
  expect_equal(b$reliability, 0.085)
  expect_equal(b$resolution, 0.0625)
  expect_equal(b$uncertainty, 0.1875)
  expect_equal(b$brier, b$reliability - b$resolution + b$uncertainty)
  expect_equal(b$table$observed, c(0, 0.5))
  expect_error(brier_score(1.2, 1), "lie in")
})

# Guards: a reliable ensemble has a flat rank histogram and a spread-skill ratio near 1; one
# half as wide is U-shaped and overconfident
test_that("ranks and spread of reliable and narrow ensembles", {
  set.seed(3)
  n <- 4000
  m <- 9
  centre <- stats::rnorm(n)
  truth <- centre + stats::rnorm(n)
  good <- centre + matrix(stats::rnorm(n * m), n, m)
  narrow <- centre + 0.5 * matrix(stats::rnorm(n * m), n, m)
  sg <- ensemble_scores(good, truth, thresholds = c(high = 1))
  sn <- ensemble_scores(narrow, truth)
  # Truth and members come from the same spread around the centre: every rank equally likely
  rg <- attr(sg, "rank")[[1]] / n
  expect_equal(rg, rep(1 / (m + 1), m + 1), tolerance = 0.25)
  expect_equal(sg$spread_skill, 1, tolerance = 0.05)
  rn <- attr(sn, "rank")[[1]] / n
  expect_gt(rn[1] + rn[m + 1], 2.5 / (m + 1))
  expect_lt(sn$spread_skill, 0.7)
  expect_lt(sg$crps, sn$crps)
  expect_true(all(c("brier:high", "reliability:high", "resolution:high") %in% names(sg)))
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (type in c("crps", "rank", "reliability")) expect_invisible(plot(sg, type = type))
  expect_error(plot(sn, type = "reliability"), "needs thresholds")
})

# Guards: lead times are scored apart
test_that("scores by lead time", {
  e <- rbind(c(0, 1), c(0, 1), c(1, 3), c(1, 3))
  s <- ensemble_scores(e, c(0, 0, 2, 2), lead_h = c(1, 1, 6, 6))
  expect_equal(s$lead_h, c(1, 6))
  # Lead 1: CRPS 0.25 each (above). Lead 6: members 1 and 3, observed 2: 1 - 0.5 = 0.5
  expect_equal(s$crps, c(0.25, 0.5))
  expect_equal(s$n, c(2L, 2L))
})
