# Tests for the multi-zone PDM: configuration, running, starts, bounds, stages and calibration.

mz_forcing <- function(n = 24 * 60, seed = 3) {
  set.seed(seed)
  data.frame(rain = ifelse(stats::runif(n) < 0.06, stats::rexp(n, 0.3), 0), pet = 0.08)
}
mz_base <- function() {
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 36.7
  cfg
}

# Guards: zone areas follow the shares, the first zone taking the rest; bad configurations are
# refused with a reason
test_that("a two-zone configuration builds as documented", {
  two <- two_zone_config(mz_base(), share = 0.15)
  model <- pdm_from_config(two)
  expect_true(S7::S7_inherits(model, FlodeMultiZoneModel))
  expect_equal(unname(vapply(model@zones, function(z) z@area_km2, 0)), 36.7 * c(0.85, 0.15))
  expect_equal(model@zones$fast@recharge@alpha, 1)
  bad <- two
  bad$zones$fast$share <- 1.2
  expect_error(pdm_from_config(bad), "share")
  bad <- two
  bad$zones$main$area_km2 <- 5
  expect_error(pdm_from_config(bad), "area from share")
  expect_error(two_zone_config(two), "single-zone")
  expect_false(identical(pdm_fingerprint(two), pdm_fingerprint(mz_base())))
})

# Guards: the rain adds up: every zone reads the same depths under one rainfall factor, so the
# rain volume over the zones is the catchment's; unlocking fc scales every zone together
test_that("the rainfall adds up across the zones", {
  f <- mz_forcing()
  two <- two_zone_config(mz_base(), share = 0.25)
  two$fc <- 1.1
  model <- pdm_from_config(two)
  expect_equal(unname(vapply(model@zones, function(z) z@fc, 0)), c(1.1, 1.1))
  out <- run_pdm(model, f)$output
  parts <- lapply(model@zones, function(z) run_pdm(z, f)$output)
  volume <- function(o, area) sum(o$rain_corrected_mm) * area
  expect_equal(volume(parts$main, model@zones$main@area_km2) +
                 volume(parts$fast, model@zones$fast@area_km2),
               volume(out, model@area_km2), tolerance = 1e-12)
  expect_equal(out$rain_corrected_mm, 1.1 * f$rain, tolerance = 1e-12)
  open <- calibration_bounds(two, overrides = list(fc = c(0.8, 1.2)))
  expect_true("fc" %in% open$path)
  expect_false(any(grepl("zones\\..*\\.fc$", open$path)))
  bad <- two
  bad$zones$fast$fc <- 1
  expect_error(pdm_from_config(bad), "rainfall factor once")
})

# Guards: the outlet flow is the sum of the zones' flows, depths are area-weighted, and the water
# balance closes
test_that("run_pdm adds the zones at the outlet", {
  f <- mz_forcing()
  model <- pdm_from_config(two_zone_config(mz_base(), share = 0.2))
  out <- run_pdm(model, f)$output
  parts <- lapply(model@zones, function(z) run_pdm(z, f)$output)
  expect_equal(out$q_m3s, parts$main$q_m3s + parts$fast$q_m3s, tolerance = 1e-12)
  expect_equal(out$soil_mm, 0.8 * parts$main$soil_mm + 0.2 * parts$fast$soil_mm,
               tolerance = 1e-12)
  expect_lt(max(abs(out$balance_error_mm)), 1e-9)
  # The fast zone sends nothing to groundwater
  expect_true(all(parts$fast$groundwater_input_mm == 0))
  # Calibration's flow-only path gives the same flow
  state <- initial_state(model)
  expect_equal(pdmS7:::.run_flow(model, f, state, "q_m3s"), out$q_m3s, tolerance = 1e-12)
})

# Guards: a start from flow puts the whole flow on the first zone in steady state
test_that("a start from flow starts the first zone in steady state", {
  model <- pdm_from_config(two_zone_config(mz_base()))
  state <- suppressWarnings(initial_state_from_flow(model, 0.8, 0.7))
  expect_true(S7::S7_inherits(state, FlodeMultiZoneState))
  first <- suppressWarnings(initial_state_from_flow(model@zones$main, 0.8, 0.7))
  expect_equal(state@states$main, first)
  expect_equal(state@states$fast@surface, 0)
  expect_error(run_pdm(model, mz_forcing(48), initial_state(model@zones$main)), "one state")
})

# Guards: bounds: the first zone's usual ones and the fast zone's four; unprefixed overrides and
# exclusions apply to the first zone; stages sort zone parameters by their own paths
test_that("bounds and stages cover both zones", {
  two <- two_zone_config(mz_base())
  b <- calibration_bounds(two)
  expect_true(all(c("zones.main.surface.k1", "zones.fast.share", "zones.fast.surface.kb",
                    "zones.fast.distribution.cmax", "zones.fast.td") %in% b$path))
  expect_false(any(grepl("zones.fast.(recharge|groundwater)", b$path)))
  capped <- calibration_bounds(two, overrides = list(surface.k1 = c(0.5, 12)),
                               exclude = "groundwater.kb")
  expect_equal(capped$upper[capped$path == "zones.main.surface.k1"], 12)
  expect_false("zones.main.groundwater.kb" %in% capped$path)
  stages <- pdm_stages(two, events = TRUE)
  expect_true("zones.fast.share" %in% stages[[2]]$parameters)
  expect_true("zones.fast.distribution.cmax" %in% stages[[1]]$parameters)
  expect_true("zones.main.td" %in% stages[[4]]$parameters)
})

# Guards: calibrate_pdm fits a fast zone's time constant from a known truth
test_that("calibrate_pdm fits a two-zone model", {
  f <- mz_forcing(24 * 90)
  two <- two_zone_config(mz_base(), share = 0.2)
  truth <- two
  truth$zones$fast$surface$kb <- 0.5
  obs <- run_pdm(pdm_from_config(truth), f)$output$q_m3s
  fit <- calibrate_pdm(two, f, obs, lower = c(zones.fast.surface.kb = 0.25),
                       upper = c(zones.fast.surface.kb = 12), start = "soil",
                       soil_fraction = 0.5, log_scale = "zones.fast.surface.kb",
                       control = list(maxit = 40))
  expect_equal(fit$parameters[["zones.fast.surface.kb"]], 0.5, tolerance = 0.02)
})

# Guards: the zones step's options and order
test_that("the zones step offers one and two zones, last", {
  cfg <- mz_base()
  opts <- pdmS7:::.component_variants(cfg, "zones")
  expect_equal(names(opts), c("one", "two"))
  expect_identical(opts$one, cfg)
  expect_true(pdmS7:::.is_multizone_config(opts$two))
  back <- pdmS7:::.component_variants(opts$two, "zones")
  expect_equal(back$one$surface, cfg$surface)
  expect_error(pdmS7:::.component_type(opts$two, "recharge"), "before its zones")
  expect_error(write_pdm_inp(opts$two, tempfile(), "x", c("2020-01-01", "2020-02-01")),
               "multi-zone")
})
