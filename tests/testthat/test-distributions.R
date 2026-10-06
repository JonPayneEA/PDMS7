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
    for (d in dists) {
      hi <- if (S7::S7_inherits(d, ExponentialCapacity) ||
                  S7::S7_inherits(d, LognormalCapacity)) {
        Inf
      } else {
        d@cmax
      }
      lo <- if (is.finite(hi)) {
        d@cmin
      } else {
        0
      }
      expect_close(
        integrate(
          function(c) capacity_pdf(d, c),
          lo, hi,
          rel.tol = 1e-08
        )$value,
        1, 1e-06
      )
      expect_close(
        integrate(
          function(c) {
            1 -
              capacity_cdf(d, c)
          },
          0, hi,
          rel.tol = 1e-08
        )$value,
        capacity_mean(d),
        1e-05
      )
      for (c in c(0, 5, 20, 80, 120, 220)) {
        val <- integrate(
          function(z) {
            1 -
              capacity_cdf(d, z)
          },
          0, c,
          rel.tol = 1e-08
        )$value
        expect_close(
          storage_from_capacity(d, c),
          val, 1e-05
        )
      }
      ss <- capacity_mean(d) *
        c(0, 0.001, 0.2, 0.8, 0.999, 1)
      expect_close(
        storage_from_capacity(d, capacity_from_storage(d, ss)),
        ss, 1e-06
      )
      for (s in ss) {
        for (p in c(0.01, 10, 300)) {
          r <- soil_step(d, s, p)
          expect_close(s + p - r$storage - r$runoff, 0)
          check(r$runoff >= 0 && r$storage <= capacity_mean(d))
        }
      }
    }
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
