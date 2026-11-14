# Tests of the modelled well level and fit_well_level(). The well level is hw - Ys D in m, with
# the deficit D in mm and Ys in m per mm (PDM for PCs wellfac); the expected values below come
# from that formula and from a known truth, not from comparing C with R.

well_model <- function(ys = 0.0204, hw = 83.76, smax_b = 1641, kb = 50) {
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 10
  cfg$dt <- 24
  cfg$groundwater <- list(type = "linear", kb = kb,
                          extension = list(smax_b = smax_b, ys = ys, hw = hw))
  pdm_from_config(cfg)
}

# Guards: the well level is in metres per mm of deficit, as UKCEH's Table 3 values need: with
# Ys 0.0204 m/mm a full store sits at the datum and an empty one 33.5 m below it, and draining
# a linear store, S0 exp(-t / kb), lowers the well by Ys times the water lost
test_that("the well level falls Ys metres for each mm of deficit", {
  t <- 1:30
  for (engine in c("auto", "r")) {
    model <- well_model()
    state <- initial_state(model)
    state@soil <- 0
    state@groundwater <- 1641
    old <- options(pdmS7.engine = engine)
    out <- run_pdm(model, data.frame(rain = rep(0, 30), pet = 0), state)$output
    options(old)
    s <- 1641 * exp(-24 * t / 50)
    expect_equal(out$groundwater_mm, s, tolerance = 1e-8, label = engine)
    expect_equal(out$well_level_m, 83.76 - 0.0204 * (1641 - s), tolerance = 1e-8,
                 label = engine)
    expect_equal(83.76 - 0.0204 * 1641, 50.2836)
    # Each mm drained lowers the well Ys m: 1641 (e^-0.48 - e^-14.4) mm over the run
    expect_equal(diff(range(out$well_level_m)), 0.0204 * (s[1] - s[30]), tolerance = 1e-8,
                 label = engine)
  }
})

# Guards: the fit recovers a known well factor and datum from sparse, noisy dips, and the
# choice of smax_b moves only the datum
test_that("fit_well_level() recovers the truth", {
  forcing <- synthetic_rain("2015-10-01", years = 4, dt = 24, seed = 4)
  # A slow store (storage varies by about 135 mm), so the well swings metres against 0.2 m of
  # dip error
  model <- well_model(ys = 0.025, hw = 70, smax_b = 900, kb = 20000)
  out <- run_pdm(model, forcing, initial_state(model, soil_fraction = 0.6))$output
  set.seed(1)
  readings <- rep(NA_real_, nrow(out))
  weekly <- seq(3, nrow(out), by = 7)
  readings[weekly] <- out$well_level_m[weekly] + stats::rnorm(length(weekly), sd = 0.2)
  fit <- fit_well_level(out, readings, time = forcing$time)
  expect_s3_class(fit, "pdm_well_fit")
  expect_equal(fit$smax_b, 900)
  expect_equal(fit$ys, 0.025, tolerance = 0.02)
  expect_equal(fit$hw, 70, tolerance = 0.002)
  expect_equal(fit$specific_yield, 1 / (1000 * fit$ys))
  expect_equal(fit$n, length(weekly))
  expect_lt(abs(fit$rmse_m - 0.2), 0.03)
  expect_gt(fit$r2, 0.95)
  expect_lt(max(abs(fit$modelled - out$well_level_m)), 0.3)
  other <- fit_well_level(data.frame(groundwater_mm = out$groundwater_mm), readings,
                          smax_b = 1200)
  expect_equal(other$ys, fit$ys)
  expect_equal(other$hw - other$ys * 1200, fit$hw - fit$ys * 900)
  expect_equal(other$modelled, fit$modelled)
  expect_output(print(fit), "specific yield")
  expect_silent(plot(fit))
  expect_silent(plot(fit, type = "scatter"))
})

# Guards: the fit refuses what it cannot do
test_that("fit_well_level() refuses bad inputs", {
  out <- data.frame(groundwater_mm = c(10, 20, 30, 40))
  expect_error(fit_well_level(out, c(1, 2, 3, 4)), "smax_b is needed")
  expect_error(fit_well_level(out, c(1, 2, 3), smax_b = 100), "one value per row")
  expect_error(fit_well_level(out, c(1, NA, NA, 4), smax_b = 100), "three well readings")
  expect_error(fit_well_level(out, c(4, 3, 2, 1), smax_b = 100), "falls as the modelled store")
  expect_error(fit_well_level(list(), 1), "groundwater_mm")
})
