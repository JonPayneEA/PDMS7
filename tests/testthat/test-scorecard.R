# ============================================================ #
# Tool:         test-scorecard
# Description:  Tests for pdm_scorecard
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add scorecard tests
# Tier:         3
# Inputs:       Synthetic flows, m3/s
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

score_flows <- function(n = 400) {
  set.seed(4)
  0.5 + cumsum(stats::rnorm(n))^2 / 50
}

test_that("a perfect simulation scores perfectly", {
  obs <- score_flows()
  s <- pdm_scorecard(obs, obs)
  expect_named(s, c("nse", "log_nse", "kge", "kge_r", "kge_alpha", "kge_beta", "rmse",
                    "log_rmse", "volume_error", "abs_volume_error", "peak_error",
                    "fdc_high", "fdc_mid", "fdc_low"))
  expect_equal(unname(s[c("nse", "log_nse", "kge", "kge_r", "kge_alpha", "kge_beta")]),
               rep(1, 6))
  expect_equal(unname(s[c("rmse", "log_rmse", "volume_error", "abs_volume_error",
                          "peak_error", "fdc_high", "fdc_mid", "fdc_low")]), rep(0, 8))
})

test_that("a uniformly wet simulation shows its sign and size", {
  obs <- score_flows()
  s <- pdm_scorecard(obs * 1.1, obs)
  expect_equal(s[["volume_error"]], 0.1)
  expect_equal(s[["abs_volume_error"]], 0.1)
  expect_equal(s[["peak_error"]], 0.1)
  expect_equal(s[["kge_beta"]], 1.1)
  expect_equal(s[["kge_alpha"]], 1.1)
  expect_equal(s[["kge_r"]], 1)
  expect_equal(s[["fdc_high"]], 0.1)
  dry <- pdm_scorecard(obs * 0.9, obs)
  expect_equal(dry[["volume_error"]], -0.1)
})

test_that("scores agree with pdm_objectives losses", {
  obs <- score_flows()
  sim <- obs * 0.95 + 0.1 * sin(seq_along(obs))
  s <- pdm_scorecard(sim, obs, log_offset = 0.05)
  loss <- pdm_objectives(sim, obs, c("nse_loss", "kge_loss", "rmse", "log_rmse", "abs_bias",
                                     "peak_relative_error"), log_offset = 0.05)
  expect_equal(s[["nse"]], 1 - loss[["nse_loss"]])
  expect_equal(s[["kge"]], 1 - loss[["kge_loss"]])
  expect_equal(s[["rmse"]], loss[["rmse"]])
  expect_equal(s[["log_rmse"]], loss[["log_rmse"]])
  expect_equal(s[["abs_volume_error"]], loss[["abs_bias"]])
  expect_equal(abs(s[["peak_error"]]), loss[["peak_relative_error"]])
})

test_that("flow-duration signatures follow Yilmaz et al. (2008)", {
  obs <- score_flows()
  sim <- rev(obs) # same flow-duration curve, different timing
  s <- pdm_scorecard(sim, obs)
  expect_equal(unname(s[c("fdc_high", "fdc_mid", "fdc_low")]), c(0, 0, 0))
  expect_lt(s[["nse"]], 1)
  steep <- pdm_scorecard(obs^1.2, obs)
  expect_gt(steep[["fdc_mid"]], 0)
})

test_that("missing observations are skipped and undefined scores are NA", {
  obs <- score_flows(100)
  obs[c(5, 50)] <- NA
  s <- pdm_scorecard(score_flows(100), obs)
  expect_equal(s[["nse"]], 1)
  flat <- pdm_scorecard(rep(2, 100), score_flows(100))
  expect_true(is.na(flat[["kge_r"]]))
  expect_true(is.na(flat[["kge"]]))
  expect_error(pdm_scorecard(c(1, NA, 3), c(1, 2, 3)), "finite")
  expect_error(pdm_scorecard(1:3, 1:2), "equal length")
  expect_error(pdm_scorecard(1:3, 1:3, log_offset = 0), "positive")
})
