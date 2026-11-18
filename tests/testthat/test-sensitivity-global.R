# ============================================================ #
# Tool:         test_sensitivity_global
# Description:  Morris and Sobol indices on functions whose indices are known in closed form,
#               and the wrapper on a model
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Analytic test functions; the synthetic record of helper-calibration.R
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Guards: Morris effects of a linear function are its coefficients, exactly
test_that("Morris effects of a linear function", {
  # f = z1 + 2 z2 + 0 z3: every elementary effect of z1 is 1, of z2 is 2, of z3 is 0
  f <- function(z) z[1] + 2 * z[2]
  out <- .with_seed(1, .morris(f, 3L, 10L, 4L, 1L))
  expect_equal(out$runs, 10L * 4L)
  m <- out$indices[[1]]
  expect_equal(m$mu_star, c(1, 2, 0))
  expect_equal(m$sigma, c(0, 0, 0))
})

# Guards: Sobol indices in closed form, additive and with an interaction
test_that("Sobol indices of known functions", {
  # f = z1 + 2 z2 on the unit square: variances 1/12 and 4/12 of a total 5/12, so first-order
  # and total indices 0.2 and 0.8.
  add <- .with_seed(2, .sobol(function(z) z[1] + 2 * z[2], 2L, 20000L, 1L))
  s <- add$indices[[1]]
  expect_equal(add$runs, 20000L * 4L)
  expect_equal(s$first, c(0.2, 0.8), tolerance = 0.03)
  expect_equal(s$total, c(0.2, 0.8), tolerance = 0.03)
  # f = z1 z2: V = E[z1^2] E[z2^2] - (E z1 E z2)^2 = 1/9 - 1/16 = 7/144. Alone, z1 explains
  # Var(z1 / 2) = 1/48, a first-order index of (1/48) / (7/144) = 3/7; with the interaction,
  # E[z2^2] Var(z1) = (1/3)(1/12) = 1/36, a total index of (1/36) / (7/144) = 4/7.
  prod <- .with_seed(3, .sobol(function(z) z[1] * z[2], 2L, 20000L, 1L))$indices[[1]]
  expect_equal(prod$first, c(3, 3) / 7, tolerance = 0.03)
  expect_equal(prod$total, c(4, 4) / 7, tolerance = 0.03)
})

# Guards: the model wrapper, its run count, negligible parameters and the plot
test_that("global sensitivity of a model", {
  d <- log_data(24 * 30)
  lower <- c(fc = 0.8, surface.k1 = 1, distribution.cmax = 100)
  upper <- c(fc = 1.2, surface.k1 = 20, distribution.cmax = 400)
  s <- pdm_sensitivity(d$truth, d$forcing, d$observed, lower, upper,
                       objectives = c("nse_loss", "abs_bias"), r = 4L, warmup = 48)
  expect_s3_class(s, "pdm_sensitivity")
  # Morris: r (k + 1) = 4 x 4 runs, one row per objective and parameter
  expect_equal(attr(s, "runs"), 16L)
  expect_equal(nrow(s), 6L)
  # The volume error is driven by fc, the rainfall factor, more than by the store's time
  v <- s[s$objective == "abs_bias", ]
  expect_gt(v$mu_star[v$parameter == "fc"], v$mu_star[v$parameter == "surface.k1"])
  # Negligible: mu* under 5% of the largest, by objective
  expect_identical(v$negligible, v$mu_star / max(v$mu_star) < 0.05)
  sob <- pdm_sensitivity(d$truth, d$forcing, d$observed, lower, upper,
                         objectives = "nse_loss", method = "sobol", n = 10L, warmup = 48)
  expect_equal(attr(sob, "runs"), 10L * 5L)
  expect_true(all(c("first", "total") %in% names(sob)))
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_invisible(plot(s))
  expect_invisible(plot(sob))
  expect_output(print(s), "Morris|morris")
})
