# ============================================================ #
# Tool:         test_coarse
# Description:  The coarse-step stage: collapsing a record, fitting the slow stores on it,
#               and the faster stage settings of pdm_stages()
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Hand-built records; the synthetic record of helper-calibration.R
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Guards: rain is summed, flow averaged, gaps never filled, leftover steps dropped
test_that("a record collapsed to a coarser step", {
  f <- data.frame(time = as.POSIXct("2021-01-01", tz = "UTC") + 900 * (0:9),
                  rain = 1:10, pet = rep(0.1, 10))
  obs <- c(1, 2, 3, 4, 5, NA, 7, 8, 9, 10)
  out <- .coarsen(f, obs, 4L)
  # Blocks 1-4 and 5-8; steps 9 and 10 are left over. Rain 1+2+3+4 = 10 and 5+6+7+8 = 26
  expect_equal(out$forcing$rain, c(10, 26))
  expect_equal(out$forcing$pet, c(0.4, 0.4))
  expect_equal(out$forcing$time, f$time[c(1, 5)])
  # Flow (1+2+3+4)/4 = 2.5; the second block has a gap, so it stays missing
  expect_equal(out$observed, c(2.5, NA))
  expect_error(.coarsen(cbind(f, temperature_c = 1), obs, 4L), "temperature_c")
})

# Guards: the step, warm-up and configuration move together
test_that("coarse inputs for a 15-minute model", {
  cfg <- modifyList(pdm_presets("standard"), list(dt = 0.25, area_km2 = 10))
  f <- data.frame(rain = rep(1, 40), pet = 0)
  cz <- .coarse_inputs(cfg, f, rep(1, 40), 10L, 1)
  # Four 15-minute steps an hour; a warm-up of 10 steps covers ceiling(10 / 4) = 3 hours
  expect_equal(cz$factor, 4L)
  expect_equal(cz$config$dt, 1)
  expect_equal(cz$warmup, 3L)
  expect_equal(nrow(cz$forcing), 10L)
  expect_identical(.coarse_inputs(cfg, f, rep(1, 40), 10L, 0.25)$forcing, f)
  expect_error(.coarse_inputs(cfg, f, rep(1, 40), 10L, 0.6), "whole number")
})

# Guards: pdm_stages() hands the first stages to DDS and the slow stage to the coarse step
test_that("faster stage settings", {
  st <- pdm_stages(pdm_presets("standard"), method = "dds", budget = 50L, coarse_dt = 2,
                   events = TRUE)
  expect_equal(vapply(st[1:3], function(s) s$method, character(1)), rep("dds", 3))
  expect_equal(st[[1]]$control$maxit, 50L)
  expect_equal(st[[1]]$coarse_dt, 2)
  expect_null(st[[2]]$coarse_dt)
  # The events stage keeps its own budget
  expect_equal(st[[4]]$control$maxit, 300L)
  expect_error(pdm_stages(pdm_presets("standard"), method = "dds", budget = 0), "budget")
})

# Guards: the coarse stage is exactly a fit on the collapsed record, put back on the fine step
test_that("a staged calibration with its slow stage on a coarse step", {
  d <- log_data(24 * 30)
  cfg <- d$truth
  cfg$fc <- 0.85
  st <- pdm_stages(cfg, polish = FALSE, method = "dds", budget = 20L, coarse_dt = 2)
  fit <- calibrate_staged(cfg, d$forcing, d$observed, stages = st, warmup = 48, seed = 3,
                          bounds = calibration_bounds(cfg))
  first <- fit$stages[[1]]
  expect_equal(first$coarse_dt, 2)
  expect_equal(fit$config$dt, cfg$dt %||% 1)
  # The same search by hand on the record in two-hour blocks gives the same parameters
  b <- .stage_bounds(st[[1]], calibration_bounds(cfg), cfg)
  cz <- .coarse_inputs(cfg, d$forcing, d$observed, 48, 2)
  by_hand <- calibrate_pdm(cz$config, cz$forcing, cz$observed, b$lower, b$upper,
                           warmup = cz$warmup, objective = st[[1]]$objective, method = "dds",
                           control = list(maxit = 20L), seed = 3,
                           volume_weight = st[[1]]$volume_weight, log_scale = b$log_scale)
  expect_equal(first$parameters, by_hand$parameters)
  # In a project, the stage records its coarse step and still verifies on the full record
  p <- new_project()
  stages <- pdm_stages(p$data$truth, polish = FALSE, method = "dds", budget = 10L,
                       coarse_dt = 2)
  written <- log_staged_calibration(p$folder, 3, "Faster stages", stages = stages, seed = 1)
  expect_equal(written[[1]]$coarse_dt, 2)
  expect_null(written[[2]]$coarse_dt)
  expect_equal(written[[1]]$configuration$dt, p$data$truth$dt)
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
})
