# ============================================================ #
# Tool:         test-initial_flow
# Description:  Configurable PDM framework: test-initial_flow
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-31 - Steady-state start from an observed flow
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

flow_models <- function() {
  list(
    default = pdm_model(area_km2 = 44),
    demand = pdm_model(recharge = FlodeDemandRecharge(0.5, 1.5, 0.5), area_km2 = 44),
    split = pdm_model(recharge = FlodeSplitRecharge(0.7), area_km2 = 44),
    cascade_gw = pdm_model(groundwater = FlodeCascadeRouting(30, 200), area_km2 = 44),
    exponential = pdm_model(
      surface = FlodeExponentialRouting(0.05, -5),
      groundwater = FlodeExponentialRouting(0.02, -8), area_km2 = 44
    ),
    delay = pdm_model(td = 2.5, area_km2 = 44, qc = 0.1)
  )
}

test_that(
  "the start is in steady state with the observed flow",
  {
    for (name in names(flow_models())) {
      model <- flow_models()[[name]]
      state <- initial_state_from_flow(model, observed_m3s = 1.5, baseflow_fraction = 0.6)
      q <- (1.5 - model@qc) * 3.6 / model@area_km2
      flow <- routing_flow(model@groundwater, state@groundwater) +
        routing_flow(model@surface, state@surface)
      expect_equal(flow, q, tolerance = 1e-12, label = name)
      expect_equal(routing_flow(model@groundwater, state@groundwater), 0.6 * q,
                   tolerance = 1e-12, label = name)
      smax <- capacity_mean(model@distribution)
      if (!S7::S7_inherits(model@recharge, FlodeSplitRecharge)) {
        recharge <- recharge_depth(model@recharge, state@soil, smax, state@groundwater,
                                   model@groundwater, model@dt) / model@dt
        expect_equal(recharge, 0.6 * q, tolerance = 1e-12, label = name)
      } else {
        expect_equal(state@soil, 0.5 * smax, label = name)
      }
      expect_identical(state@step, 0)
    }
  }
)

test_that(
  "with an outlet delay the queued water reproduces the observed flow",
  {
    model <- flow_models()$delay
    state <- initial_state_from_flow(model, 1.5, 0.6)
    out <- run_pdm(model, data.frame(rain = rep(0, 4), pet = 0), state)$output
    expect_equal(out$q_m3s[1:2], c(1.5, 1.5), tolerance = 1e-12)
    expect_lt(out$q_m3s[4], 1.5)
  }
)

test_that(
  "both engines give the same start",
  {
    for (name in names(flow_models())) {
      model <- flow_models()[[name]]
      for (fb in c(0.2, 0.9)) {
        old <- options(pdmS7.engine = "r")
        ref <- initial_state_from_flow(model, 0.8, fb)
        options(old)
        fast <- initial_state_from_flow(model, 0.8, fb)
        expect_engines_agree <- function(a, b) {
          for (p in names(S7::props(a))) {
            expect_lte(max(abs(S7::prop(a, p) - S7::prop(b, p))),
                       1e-12 * max(1, abs(S7::prop(b, p))), label = paste(name, fb, p))
          }
        }
        expect_engines_agree(fast, ref)
      }
    }
  }
)

test_that(
  "a full soil store is capped and invalid inputs are rejected",
  {
    model <- pdm_model(area_km2 = 1)
    state <- initial_state_from_flow(model, 50, 0.9)
    expect_equal(state@soil, capacity_mean(model@distribution))
    for (engine in c("auto", "r")) {
      old <- options(pdmS7.engine = engine)
      expect_error(initial_state_from_flow(pdm_model(qc = 1), 0.5, 0.5), "below the constant")
      expect_error(initial_state_from_flow(model, 1, 1.2), "baseflow_fraction")
      expect_error(initial_state_from_flow(model, NA_real_, 0.5), "finite")
      expect_error(initial_state_from_flow(flow_models()$exponential, 1, 1), "zero flow")
      options(old)
    }
  }
)
