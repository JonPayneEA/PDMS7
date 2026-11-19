# ============================================================ #
# Tool:         test-unrestricted-split
# Description:  The unrestricted split (PDM for PCs runoff model 2): alpha of the direct
#               runoff to the surface store and beta to groundwater, not tied to 1 - alpha
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-19
# Modified:     2026-11-19 - First version
# Tier:         1
# Inputs:       Synthetic forcing; the standard example input file, edited
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

split_forcing <- function(n = 24 * 20) {
  # Rain in a block every fourth day, enough to fill a 120 mm store and make runoff
  data.frame(rain = ifelse((seq_len(n) - 1) %% 96 < 12, 6, 0), pet = 0.05)
}

split_model <- function(recharge) {
  pdm_model(distribution = FlodeParetoCapacity(cmin = 0, cmax = 120, b = 0.5),
            recharge = recharge, area_km2 = 20)
}

test_that("each store gets its share of the direct runoff, on both engines", {
  forcing <- split_forcing()
  model <- split_model(FlodeUnrestrictedSplitRecharge(alpha = 0.6, beta = 0.6))
  for (engine in c("r", "auto")) {
    out <- withr::with_options(list(pdmS7.engine = engine), run_pdm(model, forcing))$output
    expect_gt(sum(out$direct_runoff_mm), 0)
    # By definition: 0.6 of the runoff to each store, none from soil drainage
    expect_equal(out$surface_input_mm, 0.6 * out$direct_runoff_mm, tolerance = 1e-12)
    expect_equal(out$groundwater_input_mm, 0.6 * out$direct_runoff_mm, tolerance = 1e-12)
    expect_true(all(out$recharge_mm == 0))
    # alpha + beta = 1.2: the stores receive a fifth more than the soil gives up, which the
    # balance counts as an input, so its residual stays a rounding error
    expect_equal(sum(out$surface_input_mm + out$groundwater_input_mm),
                 1.2 * sum(out$direct_runoff_mm), tolerance = 1e-12)
    expect_lt(max(abs(out$balance_error_mm)), 1e-9)
  }
})

test_that("with beta = 1 - alpha it is the restricted split", {
  forcing <- split_forcing()
  free <- run_pdm(split_model(FlodeUnrestrictedSplitRecharge(alpha = 0.7, beta = 0.3)),
                  forcing)$output
  tied <- run_pdm(split_model(FlodeSplitRecharge(alpha = 0.7)), forcing)$output
  expect_equal(free$q_m3s, tied$q_m3s, tolerance = 1e-12)
})

test_that("the compiled core matches the R loop", {
  model <- split_model(FlodeUnrestrictedSplitRecharge(alpha = 0.4, beta = 0.2))
  expect_true(pdmS7:::.engine_supported(model))
  forcing <- split_forcing()
  r <- withr::with_options(list(pdmS7.engine = "r"), run_pdm(model, forcing))$output
  c <- withr::with_options(list(pdmS7.engine = "auto"), run_pdm(model, forcing))$output
  expect_equal(c$q_m3s, r$q_m3s, tolerance = 1e-10)
  expect_equal(c$balance_error_mm, r$balance_error_mm, tolerance = 1e-9)
})

test_that("the configuration, bounds and checks know the unrestricted split", {
  cfg <- pdm_presets("standard")
  cfg$recharge <- list(type = "split_unrestricted", alpha = 0.6, beta = 0.5)
  model <- pdm_from_config(cfg)
  expect_true(S7::S7_inherits(model@recharge, FlodeUnrestrictedSplitRecharge))
  expect_equal(model@recharge@beta, 0.5)
  b <- calibration_bounds(cfg)
  expect_true(all(c("recharge.alpha", "recharge.beta") %in% b$path))
  expect_equal(b$lower[b$path == "recharge.beta"], 0.05)
  expect_error(FlodeUnrestrictedSplitRecharge(alpha = 0.5, beta = -0.1), "beta must be")
  expect_error(FlodeUnrestrictedSplitRecharge(alpha = 1.5, beta = 0.1), "alpha must lie")
})

test_that("a runoff model 2 input file is read, and not yet written", {
  text <- readLines(system.file("examples", "standard.inp", package = "pdmS7"))
  at <- grep("'tdly'", text, fixed = TRUE)
  text <- append(text, c("  0     0.7        0.1      .1       'theta'",
                         "  1     0.55       0.1      .1       'alpha'",
                         "  1     0.25       0.1      .1       'beta'"), after = at - 1)
  text <- sub("   1        0     22     3     -13 /", "   1        2     22     3     -16 /",
              text, fixed = TRUE)
  path <- tempfile(fileext = ".inp")
  writeLines(text, path)
  cfg <- read_pdm_inp(path)
  expect_equal(cfg$recharge, list(type = "split_unrestricted", alpha = 0.55, beta = 0.25))
  expect_equal(cfg$td, 0.17)   # tdly, now 16th in the list
  expect_error(write_pdm_inp(cfg, tempfile(), "x", c("2010-10-01", "2011-10-01")),
               "unrestricted split .* cannot be written")
  # Without beta, runoff model 2 is refused rather than guessed
  writeLines(sub("-16 /", "-15 /", text[!grepl("'beta'", text)], fixed = TRUE), path)
  expect_error(read_pdm_inp(path), "beta")
})
