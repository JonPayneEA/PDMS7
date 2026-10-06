# ============================================================ #
# Tool:         test-routing
# Description:  Configurable PDM framework: test-routing
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
  "cascade routing matches transfer recursion",
  {
    # Exact transfer-function recurrence vs independent state-space route solution.
    for (ks in list(
      c(2, 4),
      c(2, 2),
      c(2, 2 + 1e-09)
    )) {
      r <- CascadeRouting(k1 = ks[1], k2 = ks[2])
      cf <- transfer_coefficients(ks[1], ks[2], 0.25)
      u <- c(1, 2, 0, 0, 0, 5, rep(0, 100))
      pastq <- c(0, 0)
      pastu <- 0
      s <- c(0, 0)
      for (v in u) {
        expected <- -cf[1] * pastq[1] - cf[2] * pastq[2] + cf[3] * v + cf[4] * pastu
        z <- route_step(r, s, v, 0.25)
        expect_close(z$q_end, expected, 2e-08)
        expect_close(
          sum(s) +
            v * 0.25 - sum(z$storage) -
            z$outflow, 0
        )
        s <- z$storage
        pastq <- c(z$q_end, pastq[1])
        pastu <- v
      }
    }
  }
)

test_that(
  "reservoirs match analytical solutions and step refinement",
  {
    # Exact steady states and closed-form recession checks.
    equal_cascade <- route_step(
      CascadeRouting(k1 = 2, k2 = 2),
      c(0, 0),
      1, 3
    )
    expect_close(equal_cascade$q_end, 1 - (1 + 3 / 2) * exp(-3 / 2))
    expect_close(
      equal_cascade$storage, c(
        2 * (1 - exp(-3 / 2)),
        2 * (1 - (1 + 3 / 2) * exp(-3 / 2))
      )
    )
    for (m in c(0.5, 1, 2, 2.5, 3, 5)) {
      r <- power_routing(k = 0.01, m = m)
      ss <- storage_for_flow(r, 2)
      z <- route_step(r, ss, 2, 5)
      expect_close(z$storage, ss)
      expect_close(z$outflow, 10)
      s0 <- 4
      dt <- 3
      exact <- if (m == 1) {
        s0 * exp(-0.01 * dt)
      } else {
        max(0, s0^(1 - m) + (m - 1) * 0.01 * dt)^(1 / (1 -
                                                         m))
      }
      expect_close(
        route_step(r, s0, 0, dt)$storage,
        exact
      )
      # Step-halving agreement with changing initial flow and nonzero input.
      full <- route_step(r, 1, 0.4, 2)
      half <- route_step(r, 1, 0.4, 1)
      two <- route_step(r, half$storage, 0.4, 1)
      expect_close(full$storage, two$storage, 2e-06)
    }
    r <- cubic_routing(kb = 10000, solver = "smith")
    s <- 20
    u <- 2
    dt <- 0.25
    expected <- s - expm1(-3 / 10000 * s^2 * dt) / (3 / 10000 *
                                                      s^2) * (u - s^3 / 10000)
    expect_close(
      route_step(r, s, u, dt)$storage,
      expected
    )
    expect_close(
      route_step(r, 0, u, dt)$storage,
      u * dt
    )
    e <- ExponentialRouting(a = 0.05, gamma = -5)
    s <- 20
    q <- routing_flow(e, s)
    expect_close(
      route_step(e, s, 0, 3)$q_end,
      q / (1 + 0.05 * q * 3)
    )
    for (u in c(0, 0.01, 2)) {
      one <- route_step(e, 20, u, 4)
      half <- route_step(e, 20, u, 2)
      two <- route_step(e, half$storage, u, 2)
      expect_close(one$storage, two$storage)
    }
  }
)
