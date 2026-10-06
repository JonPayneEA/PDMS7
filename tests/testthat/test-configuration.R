# ============================================================ #
# Tool:         test-configuration
# Description:  Configurable PDM framework: test-configuration
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

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
