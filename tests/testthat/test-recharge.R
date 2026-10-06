# ============================================================ #
# Tool:         test-recharge
# Description:  Configurable PDM framework: test-recharge
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
  "demand recharge has correct saturated and dry limits",
  {
    # Demand recharge saturation and freely draining limits (Eq. 13).
    g <- linear_routing(24)
    dr <- DemandRecharge(alpha = 0.5, beta = 1, qsat = 1)
    expect_close(
      recharge_depth(dr, 100, 100, 24, g, 1),
      1
    )
    expect_close(
      recharge_depth(dr, 100, 100, 0, g, 1),
      100
    )
  }
)
