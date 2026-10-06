# ============================================================ #
# Tool:         test-model
# Description:  Configurable PDM framework: test-model
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
  "compatible model components conserve water",
  {
    dists <- make_distributions()
    # Every distribution x recharge x routing; closure in wet and dry extremes.
    set.seed(7)
    forcing <- data.frame(
      rain = c(
        0, 200, rep(
          c(0, 0, 1, 20),
          5
        ),
        500, rep(0, 10)
      ),
      pet = rep(2, 33)
    )
    # Correct vector length explicitly (no accidental recycling in tests).
    forcing$pet <- rep(2, nrow(forcing))
    routes <- list(
      linear_routing(), quadratic_routing(), cubic_routing(), power_routing(m = 2.5),
      ExponentialRouting(a = 0.05, gamma = -5),
      CascadeRouting(k1 = 2, k2 = 2)
    )
    recharges <- list(
      StandardRecharge(kg = 24, bg = 1, st = 0),
      DemandRecharge(alpha = 0.5, beta = 1, qsat = 1),
      SplitRecharge(alpha = 0.7)
    )
    for (d in dists) {
      for (re in recharges) {
        for (ro in routes) {
          if (S7::S7_inherits(re, DemandRecharge) &&
                S7::S7_inherits(ro, CascadeRouting)) {
            next
          }
          model <- pdm_model(distribution = d, recharge = re, groundwater = ro, td = 1.5)
          result <- run_pdm(model, forcing)
          check(
            max(abs(result$output$balance_error_mm)) <
              1e-07
          )
          check(
            all(result$output$soil_mm >= 0) &&
              all(result$output$q_natural_m3s >= -1e-09)
          )
        }
      }
    }
    for (name in pdm_presets()) {
      model <- pdm_from_config(pdm_presets(name))
      result <- run_pdm(model, forcing)
      check(result$water_balance["max_abs_step_mm"] < 1e-07)
    }
  }
)

test_that(
  "restart matches uninterrupted output and rejects invalid inputs",
  {
    forcing <- make_forcing()
    # Restart equivalence, timestamp checks, and deliberate validation failures.
    model <- pdm_model(td = 1.5, fc = 1.2, qc = -1, area_km2 = 44)
    all <- run_pdm(model, forcing)
    a <- run_pdm(model, forcing[1:10, ])
    b <- run_pdm(model, forcing[-(1:10), ], a$state)
    expect_close(b$output$q_m3s, all$output$q_m3s[-(1:10)])
    expect_close(b$state@soil, all$state@soil)
    fails(run_pdm(model, data.frame(rain = NA_real_, pet = 1)))
    fails(pdm_from_config(list(misspelled = 1)))
    fails(pdm_from_config(list(distribution = list(type = "pareto", bb = 1))))
    fails(pdm_model(recharge = DemandRecharge(alpha = 0.5, beta = 1, qsat = 101)))
  }
)

test_that(
  "fractional delay conserves and converts interval volume",
  {
    # Independent lag and area conversion check: a unit pulse into a linear store.
    lagmodel <- pdm_model(
      recharge = SplitRecharge(alpha = 1),
      surface = linear_routing(1),
      groundwater = linear_routing(100),
      area_km2 = 3.6, td = 1.5
    )
    lr <- run_pdm(
      lagmodel, data.frame(
        rain = c(1, 0, 0),
        pet = c(0, 0, 0)
      ),
      initial_state(lagmodel, soil_fraction = 1)
    )
    v1 <- exp(-1)
    v2 <- (1 - exp(-1))^2
    expect_close(lr$output$q_m3s, c(0, 0.5 * v1, 0.5 * (v1 + v2)))
  }
)

test_that(
  "fast pathways and water-limited losses conserve water",
  {
    routes <- make_routes()
    forcing <- make_forcing()
    # Every routing form also works in the fast pathway, including nonzero loss.
    for (ro in routes) {
      mod <- pdm_model(surface = ro)
      run <- run_pdm(mod, forcing)
      check(
        max(abs(run$output$balance_error_mm)) <
          1e-07
      )
    }
    stiff <- run_pdm(
      pdm_model(recharge = StandardRecharge(kg = 0.001, bg = 2, st = 0)),
      data.frame(
        rain = c(0, 0),
        pet = c(10000, 10000)
      )
    )
    check(all(stiff$output$soil_mm >= 0))
    expect_close(stiff$output$balance_error_mm, c(0, 0))
  }
)
