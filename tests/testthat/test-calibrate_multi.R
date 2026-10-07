# ============================================================ #
# Tool:         test_calibrate_multi
# Description:  Verify objective definitions and bounded trade-off search
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Add multi-objective tests
# Tier:         3
# Inputs:       Embedded synthetic flows
# Outputs:      testthat expectations
# Dependencies: testthat; data.table
# ============================================================ #

test_that("objectives match independent analytical values", {
  obs <- c(1, 2, 3)
  names <- c("rmse", "log_rmse", "nse_loss", "kge_loss", "abs_bias", "peak_relative_error")
  expect_equal(unname(pdm_objectives(obs, obs, names)), rep(0, 6), tolerance = 1e-14)
  loss <- pdm_objectives(2 * obs, obs, names)
  expect_equal(loss[["rmse"]], sqrt(14 / 3))
  expect_equal(loss[["nse_loss"]], 7)
  expect_equal(loss[["kge_loss"]], sqrt(2))
  expect_equal(loss[["abs_bias"]], 1)
  expect_equal(loss[["peak_relative_error"]], 1)
  expect_equal(unname(pdm_objectives(c(NA, 2, 3), c(NA, 2, 3), "rmse")), 0)
  expect_error(pdm_objectives(numeric(), numeric()))
  expect_error(pdm_objectives(c(NA, 2), c(1, 2)))
  expect_error(pdm_objectives(c(1, 1), c(1, 1)))
  expect_error(pdm_objectives(c(1, 1), c(1, 2), "kge_loss"))
  expect_error(pdm_objectives(c(1, 1), c(0, 0), "abs_bias"))
  expect_error(pdm_objectives(c(1, 2), c(1, 2), "typo"))
})

test_that("Pareto filtering retains trade-offs and ties", {
  x <- rbind(c(1, 3), c(2, 2), c(3, 1), c(3, 3), c(1, 3))
  expect_identical(pareto_front(x), c(TRUE, TRUE, TRUE, FALSE, TRUE))
  expect_length(pareto_front(matrix(numeric(), 0, 2)), 0)
  expect_error(pareto_front(matrix(NA_real_, 2, 2)))
})

test_that("weighted search is reproducible, bounded and restores random state", {
  cfg <- pdm_presets("standard")
  forcing <- data.frame(rain = c(0, 30, 5, 0, 10, 0), pet = rep(0.1, 6))
  observed <- sim_pdm(forcing$rain, forcing$pet, cfg, 60)$qsim_cms
  cfg$fc <- 1.1
  set.seed(90)
  seed_before <- .Random.seed
  fit <- calibrate_pdm_multi(cfg, forcing, observed, c(fc = 0.8), c(fc = 1.2),
    objectives = c("rmse", "abs_bias"), weights = c(rmse = 1, abs_bias = 1),
    n_samples = 2, starts = 1, control = list(maxit = 3)
  )
  expect_identical(.Random.seed, seed_before)
  expect_true(nrow(fit$pareto) >= 1)
  expect_true(all(fit$archive$fc >= 0.8 & fit$archive$fc <= 1.2))
  expect_true(all(fit$pareto$pareto))
  expect_lt(min(fit$archive$loss_rmse), fit$archive$loss_rmse[1])
  repeat_fit <- calibrate_pdm_multi(cfg, forcing, observed, c(fc = 0.8), c(fc = 1.2),
    objectives = c("rmse", "abs_bias"), weights = c(rmse = 1, abs_bias = 1),
    n_samples = 2, starts = 1, control = list(maxit = 3)
  )
  expect_equal(fit$archive, repeat_fit$archive)
  expect_error(calibrate_pdm_multi(cfg, forcing, observed, c(fc = 2), c(fc = 3)))
  expect_error(calibrate_pdm_multi(cfg, forcing, observed, c(fc = 0), c(fc = 2),
    scales = c(wrong = 1)
  ))
})

test_that("snow parameters can be calibrated jointly with PDM", {
  cfg <- list(pdm = pdm_presets("standard"), snow = pack_presets())
  forcing <- data.frame(
    rain = c(20, 0, 0, 0), pet = rep(0, 4),
    temperature_c = c(-2, 5, 8, 10)
  )
  observed <- sim_snow_pdm(forcing$rain, forcing$temperature_c, forcing$pet, cfg)$qsim_cms
  fit <- calibrate_pdm_multi(cfg, forcing, observed,
    c(snow.melt_factor_mmh_c = 0.1), c(snow.melt_factor_mmh_c = 0.3),
    objectives = "rmse", n_samples = 0, starts = 1, control = list(maxit = 1)
  )
  expect_equal(min(fit$archive$loss_rmse), 0, tolerance = 1e-12)
  expect_true(is.list(fit$configs[[1]]$snow))
})
