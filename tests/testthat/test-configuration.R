# ============================================================ #
# Tool:         test-configuration
# Description:  Tests that calibration recovers a known parameter
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# Guards: calibrate_pdm() finds a known fc from synthetic data
test_that(
  "calibration recovers known rainfall correction",
  {
    forcing <- make_forcing()
    # Synthetic calibration recovers a deliberately perturbed rainfall factor.
    cfg <- pdm_presets("split")
    cfg$fc <- 1.3
    obs <- run_pdm(
      pdm_from_config(cfg),
      forcing
    )$output$q_m3s
    cfg$fc <- 0.8
    fit <- calibrate_pdm(
      cfg, forcing, obs, c(fc = 0.5),
      c(fc = 2),
      control = list(maxit = 50)
    )
    expect_close(fit$parameters[["fc"]], 1.3, 0.001)
    check(
      nrow(parameter_catalog()) >=
        40
    )
  }
)

# Guards: calibration starts in steady state at the first observed flow unless told otherwise
test_that("calibration starts from the first observed flow by default", {
  config <- pdm_presets("standard")
  # 20 km2, so 0.3 m3/s is a flow the soil can sustain in steady state.
  config$area_km2 <- 20
  forcing <- data.frame(rain = c(0, 4, 1, 0, 0, 2, 0, 0, 0, 0), pet = 0.05)
  model <- pdm_from_config(config)
  observed <- run_pdm(model, forcing, initial_state_from_flow(model, 0.3, 0.7))$output$q_m3s
  observed[1] <- NA
  tight <- function(...) {
    calibrate_pdm(config, forcing, observed, lower = c(fc = 1 - 1e-12),
                  upper = c(fc = 1 + 1e-12), objective = "rmse", control = list(maxit = 1), ...)
  }
  rmse <- function(state) {
    sim <- run_pdm(model, forcing, state)$output$q_m3s
    sqrt(mean((sim[-1] - observed[-1])^2))
  }
  first <- observed[2]
  expect_equal(tight()$objective, rmse(initial_state_from_flow(model, first, 0.7)))
  expect_equal(tight(start = "soil")$objective, rmse(initial_state(model, 0.5)))
  expect_equal(tight(start_flow = 0.3, baseflow_fraction = 0.7)$objective, 0, tolerance = 1e-12)
  expect_error(tight(start_flow = -1), "first observed flow")
})
