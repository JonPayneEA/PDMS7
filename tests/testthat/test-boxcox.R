# ============================================================ #
# Tool:         test_boxcox
# Description:  The Box-Cox objective: the transform, the weighted loss, weights from rating
#               uncertainty, and a calibration with it
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Hand-built flows; the synthetic record of helper-calibration.R
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Guards: the transform in closed form
test_that("Box-Cox flow", {
  # lambda 0.5, offset 1: ((3 + 1)^0.5 - 1) / 0.5 = 2
  expect_equal(boxcox_flow(3, lambda = 0.5, offset = 1), 2)
  expect_equal(boxcox_flow(3, lambda = 0, offset = 1), log(4))
  expect_equal(boxcox_flow(3, lambda = 1, offset = 1), 3)
  expect_error(boxcox_flow(3, lambda = 2), "between 0 and 1")
})

# Guards: the loss, plain and weighted
test_that("the Box-Cox loss", {
  # Observed 0, 3 and 8 with offset 1 and lambda 0.5 transform to 0, 2 and 4: mean 2, spread
  # 4 + 0 + 4 = 8. Simulated 3, 3, 8 transform to 2, 2, 4: squared error 4, loss 4 / 8 = 0.5.
  obs <- c(0, 3, 8)
  loss <- .boxcox_scorer(obs, 1, 0.5)
  expect_equal(loss(obs), 0)
  expect_equal(loss(c(3, 3, 8)), 0.5)
  expect_equal(pdm_objectives(c(3, 3, 8), obs, "boxcox_loss", log_offset = 1,
                              lambda = 0.5)[["boxcox_loss"]], 0.5)
  # Weights 0, 1, 1: the weighted mean of 2 and 4 is 3, the spread 1 + 1 = 2. The error on the
  # first flow then counts for nothing; an error of 2 on the second counts 4, a loss of 2.
  w <- .boxcox_scorer(obs, 1, 0.5, c(0, 1, 1))
  expect_equal(w(c(3, 3, 8)), 0)
  expect_equal(w(c(0, 8, 8)), 2)
  expect_equal(loss(c(-5, 3, 8)), 1e30)
})

# Guards: weights by how well each flow is measured
test_that("flow weights from rating uncertainty and the highest gauging", {
  u <- data.frame(q = c(1, 50), relative = c(0.05, 0.2))
  # At 1 m3/s 5%, weight 1; at 50 m3/s 20%, (0.05 / 0.2)^2 = 0.0625; at 25.5 m3/s halfway,
  # 12.5%, (0.05 / 0.125)^2 = 0.16. Beyond the table the relative uncertainty is held flat.
  expect_equal(flow_weights(c(1, 50, 25.5, 100), u), c(1, 0.0625, 0.16, 0.0625))
  # Above a highest gauging of 30, a quarter as much again; a missing flow weighs nothing
  expect_equal(flow_weights(c(1, 50, NA), u, highest_gauged = 30), c(1, 0.015625, 0))
  expect_equal(flow_weights(c(10, 40), highest_gauged = 30, extrapolated = 0.5), c(1, 0.5))
})

# Guards: a calibration by the Box-Cox objective finds the volume factor of the truth
test_that("calibrating with the Box-Cox objective", {
  d <- log_data()
  start <- d$truth
  start$fc <- 0.85
  fit <- calibrate_pdm(start, d$forcing, d$observed, lower = c(fc = 0.5), upper = c(fc = 1.5),
                       warmup = 120, objective = "boxcox", control = list(maxit = 30))
  expect_lt(abs(fit$config$fc - 1), 0.05)
  expect_match(fit$objective_name, "Box-Cox flows \\(lambda 0.5\\)")
  top <- stats::quantile(d$observed, 0.99, na.rm = TRUE)
  w <- flow_weights(d$observed, highest_gauged = top)
  fit_w <- calibrate_pdm(start, d$forcing, d$observed, lower = c(fc = 0.5),
                         upper = c(fc = 1.5), warmup = 120, objective = "boxcox", weights = w,
                         control = list(maxit = 30))
  expect_match(fit_w$objective_name, "weighted")
  expect_lt(abs(fit_w$config$fc - 1), 0.05)
  expect_error(calibrate_pdm(start, d$forcing, d$observed, c(fc = 0.5), c(fc = 1.5),
                             objective = "boxcox", weights = 1:3), "one for each")
})
