# ============================================================ #
# Tool:         test-distributions
# Description:  Configurable PDM framework: test-distributions
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
  "capacity laws integrate and invert consistently",
  {
    # Independent quadrature, derivatives, inverses, and probability normalisation.
    dists <- list(
      ParetoCapacity(cmin = 10, cmax = 140, b = 0.4),
      RectangularCapacity(cmin = 10, cmax = 190),
      TriangularCapacity(cmin = 10, cmax = 190),
      ExponentialCapacity(mean = 100),
      LognormalCapacity(
        meanlog = log(100) -
          0.5, sdlog = 1
      )
    )
    for (d in dists) check_capacity_law(d)
    p <- ParetoCapacity(cmin = 0, cmax = 140, b = 0.4)
    expect_close(
      capacity_mean(p),
      100
    )
    expect_close(
      soil_step(p, 0, 140)$runoff,
      40
    )
    expect_close(
      soil_step(p, 100, 42)$runoff,
      42
    )
    p0 <- ParetoCapacity(cmin = 10, cmax = 140, b = 0)
    expect_close(
      soil_step(p0, 0, 150)$runoff,
      10
    )
    expect_close(
      capacity_cdf(p0, c(139, 140)),
      c(0, 1)
    )
    fails(capacity_pdf(p0, 10))
    fails(ParetoCapacity(cmin = 10, cmax = 5, b = 1))
    expect_close(
      soil_step(
        RectangularCapacity(cmin = 10, cmax = 190),
        0, 5
      )$storage,
      5
    )
  }
)
