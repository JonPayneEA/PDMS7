# ============================================================ #
# Tool:         test_pack
# Description:  Verify PACK accounting and coupled restart
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Add snow tests
# Tier:         3
# Inputs:       Embedded synthetic forcing
# Outputs:      testthat expectations
# Dependencies: testthat; S7
# ============================================================ #

test_that("image values and report values remain distinct", {
  a <- pack_presets()
  expect_equal(a$lower_rate_h, 0.00677)
  expect_equal(a$upper_rate_h, 0.27095)
  expect_equal(a$melt_threshold_c, 1)
  expect_equal(a$snow_threshold_c, 0)
  b <- pack_presets("report_daily")
  expect_equal(b$lower_rate_h * 24, 0.15)
  expect_equal(b$upper_rate_h * 24, 0.85)
  expect_equal(b$melt_factor_mmh_c * 24, 4)
  expect_error(pack_from_config(list(typo = 1)))
  expect_error(FlodePackModel(retention_fraction = 1))
  expect_error(FlodePackModel(adc_alpha = 0))
  expect_error(FlodePackModel(max_step_min = NA_real_))
  expect_error(FlodePackState(wet_mm = -1))
})

test_that("dry accumulation, melt and two-outlet drainage follow hand calculations", {
  m <- FlodePackModel(
    melt_factor_mmh_c = 1, lower_rate_h = 0.1,
    upper_rate_h = 0.2, retention_fraction = 0.04, areal_depletion = FALSE
  )
  cold <- pack_step(m, FlodePackState(), 10, -2)
  expect_equal(cold$state@dry_mm, 10)
  expect_equal(cold$flux[["effective_rain_mm"]], 0)
  warm <- pack_step(m, cold$state, 2, 3)
  # Dry 10-2=8, provisional wet 2+2=4, threshold=.04*12=.48.
  expect_equal(warm$flux[["melt_mm"]], 2)
  expect_equal(warm$flux[["drainage_mm"]], 0.1 * 4 + 0.2 * (4 - 0.48))
  expect_equal(warm$flux[["snow_balance_error_mm"]], 0, tolerance = 1e-12)
  frozen <- pack_step(m, FlodePackState(wet_mm = 10), 0, -1)
  expect_equal(frozen$state@wet_mm, 10)
  rain <- pack_step(m, FlodePackState(), 5, 0)
  expect_equal(rain$flux[["rainfall_mm"]], 5)
  expect_equal(rain$flux[["bypass_mm"]], 5)
})

test_that("cover depletion and fresh snow memory have the documented shape", {
  m <- FlodePackModel()
  s <- FlodePackState(dry_mm = 20)
  expect_equal(pdmS7:::.pack_cover(m, s), log1p(20) / log1p(100))
  snow <- pack_step(m, s, 10, -2)$state
  expect_equal(pdmS7:::.pack_cover(m, snow), 1)
  snow@dry_mm <- 21.25
  expected <- log1p(20) / log1p(100) + (1 - log1p(20) / log1p(100)) * 0.5
  expect_equal(pdmS7:::.pack_cover(m, snow), expected)
  snow@dry_mm <- 20
  expect_equal(pdmS7:::.pack_cover(m, snow), log1p(20) / log1p(100))
  expect_equal(pdmS7:::.pack_cover(m, FlodePackState(dry_mm = 200)), 1)
})

test_that("snow mass is conserved and restart includes cover history", {
  p <- c(20, 10, 0, 0, 5, rep(0, 30))
  t <- c(-3, -1, 2, 5, -2, rep(8, 30))
  full <- sim_pack(p, t)
  first <- sim_pack(p[1:8], t[1:8])
  last <- sim_pack(p[-(1:8)], t[-(1:8)], state = attr(first, "final_state"))
  expect_equal(last$effective_rain_mm, full$effective_rain_mm[-(1:8)])
  expect_equal(attr(last, "final_state"), attr(full, "final_state"))
  expect_lt(max(abs(full$snow_balance_error_mm)), 1e-10)
  expect_true(all(full$dry_snow_mm >= 0 & full$wet_snow_mm >= 0))
  fast <- sim_pack(20, 10, FlodePackModel(lower_rate_h = 10, upper_rate_h = 10),
    timestep_min = 1440, state = FlodePackState(dry_mm = 1)
  )
  expect_lt(abs(attr(fast, "water_balance")), 1e-10)
  expect_error(sim_pack(numeric(), numeric()))
  expect_error(sim_pack(1, NA_real_))
  expect_error(sim_pack(-1, 0))
  expect_error(sim_pack(1, 0, timestep_min = 0))
  expect_error(pack_step(FlodePackModel(), FlodePackState(), 1, 0, dt = Inf))
})

test_that("coupling conserves corrected water and reproduces rain-only runs", {
  cfg <- list(pdm = pdm_presets("standard"), snow = pack_presets())
  rain <- c(1, 10, 0, 4)
  plain <- sim_pdm(rain, rep(0.1, 4), cfg$pdm, 60)
  out <- sim_snow_pdm(rain, rep(5, 4), rep(0.1, 4), cfg)
  expect_equal(out$qsim_cms, plain$qsim_cms)
  cold <- sim_snow_pdm(rain, c(-2, -2, 5, 8), rep(0.1, 4), cfg)
  first <- sim_snow_pdm(rain[1:2], c(-2, -2), rep(0.1, 2), cfg)
  last <- sim_snow_pdm(rain[3:4], c(5, 8), rep(0.1, 2), cfg,
    state = attr(first, "final_state")
  )
  expect_equal(last$qsim_cms, cold$qsim_cms[3:4])
  expect_equal(attr(last, "final_state"), attr(cold, "final_state"))
  expect_lt(max(abs(cold$combined_balance_error_mm)), 1e-9)
  expect_error(sim_snow_pdm(1, 1, 0, list(snow = cfg$snow)))
  expect_error(sim_snow_pdm(1, 1, 0, cfg, state = list()))
})
