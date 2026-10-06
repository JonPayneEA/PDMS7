# ============================================================ #
# Tool:         test-updating
# Description:  Configurable PDM framework: test-updating
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
  "state correction matches observed endpoint flow",
  {
    # Proportional correction matches the observation with unity gains.
    model <- pdm_model()
    state <- initial_state(
      model,
      surface = c(2, 4),
      groundwater = 10
    )
    q <- (routing_flow(model@surface, state@surface) +
            routing_flow(model@groundwater, state@groundwater)) / 3.6
    z <- correct_state(model, state, q * 1.5)
    expect_close(z$q_corrected_m3s, q * 1.5)
    check(z$correction_mm > 0)
    fails(
      correct_state(
        pdm_model(td = 1),
        initial_state(pdm_model(td = 1)),
        1
      )
    )
  }
)

test_that(
  "ARMA and log correction match hand calculations",
  {
    # AR and MA hand calculations and log multiplicative case.
    z <- update_forecast(
      error_updater(ar = 0.5),
      c(2, 4),
      c(1, 2),
      c(10, 10)
    )
    expect_close(z$error_forecast, c(1, 0.5))
    z <- update_forecast(
      error_updater(ar = numeric(), ma = 0.5),
      c(2, 4),
      c(1, 2),
      c(10, 10)
    )
    expect_close(z$error_forecast, c(0.75, 0))
    z <- update_forecast(
      error_updater(ar = 0.5, scale = "log"),
      c(2),
      c(1),
      c(1, 1)
    )
    expect_close(
      z$forecast, c(
        sqrt(2),
        2^0.25
      )
    )
  }
)
