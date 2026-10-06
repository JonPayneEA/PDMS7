# ============================================================ #
# Tool:         test-edge_cases
# Description:  Configurable PDM framework: test-edge_cases
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
  "capacity constructors reject nonphysical parameters",
  {
    expect_error(FlodeRectangularCapacity(10, 5))
    expect_error(FlodeTriangularCapacity(0, NA_real_))
    expect_error(FlodeExponentialCapacity(0))
    expect_error(FlodeLognormalCapacity(0, -1))
    expect_error(FlodeParetoCapacity(0, 100, -1))
    for (distribution in make_distributions()) {
      expect_error(capacity_cdf(distribution, -1))
      expect_error(capacity_pdf(distribution, NA_real_))
      expect_error(
        capacity_from_storage(
          distribution, capacity_mean(distribution) +
            1
        )
      )
      expect_equal(
        capacity_cdf(distribution, numeric()),
        numeric()
      )
      expect_equal(
        storage_from_capacity(distribution, numeric()),
        numeric()
      )
    }
  }
)

test_that(
  "model states reject invalid content at construction",
  {
    state <- initial_state(pdm_model())
    expect_error(state@soil <- -1)
    expect_error(state@step <- 0.5)
    expect_error(state@delay_surface <- -1)
    expect_error(state@surface <- c(1, NA_real_))
  }
)

test_that(
  "routing rejects malformed states and rates",
  {
    for (routing in make_routes()) {
      storage <- if (S7::S7_inherits(routing, FlodeCascadeRouting)) {
        c(0, 0)
      } else {
        0
      }
      expect_error(route_step(routing, storage, -1, 1))
      expect_error(route_step(routing, storage, 0, 0))
      expect_error(route_step(routing, numeric(), 0, 1))
      expect_error(route_step(routing, NA_real_, 0, 1))
    }
    expect_error(power_routing(k = 0))
    expect_error(power_routing(m = 2, solver = "smith"))
    expect_error(FlodeCascadeRouting(0, 1))
    expect_error(
      storage_for_flow(
        FlodeExponentialRouting(0.1, -5),
        0
      )
    )
  }
)

test_that(
  "forcing refuses gaps and preserves caller timestamps",
  {
    model <- pdm_model()
    expect_error(run_pdm(model, data.frame(rain = numeric(), pet = numeric())))
    expect_error(run_pdm(model, data.frame(rain = "1", pet = 0)))
    time <- as.POSIXct(
      c("2026-07-01 01:00", "2026-07-01 03:00"),
      tz = "Europe/London"
    )
    expect_error(
      run_pdm(
        model, data.frame(
          time = time, rain = c(1, 1),
          pet = c(0, 0)
        )
      )
    )
    time <- seq(time[1], by = "hour", length.out = 2)
    forcing_dt <- data.table::data.table(
      time = time, rain = c(1, 1),
      pet = c(0, 0)
    )
    copy_dt <- data.table::copy(forcing_dt)
    result <- run_pdm(model, forcing_dt)
    expect_identical(forcing_dt, copy_dt)
    expect_identical(
      attr(result$output$time, "tzone"),
      "UTC"
    )
    expect_equal(
      as.numeric(result$output$time),
      as.numeric(time)
    )
  }
)

test_that(
  "updating schemes expose external adjustments and invalid histories",
  {
    model <- pdm_model()
    state <- initial_state(
      model,
      surface = c(2, 4),
      groundwater = 10
    )
    for (scheme in c("super_proportional", "non_proportional")) {
      update <- correct_state(model, state, 0.5, state_updater(scheme, gg = 1))
      expect_true(is.finite(update$correction_mm))
    }
    expect_error(state_updater(gb = -1))
    expect_error(error_updater(ar = NA_real_))
    expect_error(update_forecast(error_updater(), numeric(), numeric(), 1))
    expect_error(update_forecast(error_updater(), 1, 1, NA_real_))
    expect_error(
      update_forecast(
        error_updater(scale = "log"),
        0, 1, 1
      )
    )
    expect_error(fit_error_updater(1:4, 1:4, order = c(-1, 0)))
    fitted <- fit_error_updater(
      c(1, 2, 1, 3, 2, 1, 2, 4),
      rep(1, 8),
      order = c(0, 0)
    )
    expect_true(S7::S7_inherits(fitted$updater, FlodeErrorUpdater))
  }
)

test_that(
  "calibration validates bounds, observations, and warmup",
  {
    config <- pdm_presets("standard")
    forcing <- make_forcing()
    observed <- run_pdm(
      pdm_from_config(config),
      forcing
    )$output$q_m3s
    expect_error(
      calibrate_pdm(
        config, forcing, observed, c(fc = 2),
        c(fc = 1)
      )
    )
    expect_error(
      calibrate_pdm(
        config, forcing, observed, c(fc = 0),
        c(fc = 2),
        warmup = 33
      )
    )
    expect_error(
      calibrate_pdm(
        config, forcing, rep(1, 33),
        c(fc = 0),
        c(fc = 2),
        objective = "nse"
      )
    )
    for (objective in c("nse", "log_rmse")) {
      fit <- calibrate_pdm(
        config, forcing, observed, c(fc = 0.9),
        c(fc = 1.1),
        objective = objective, control = list(maxit = 2)
      )
      expect_lt(fit$objective, 1e-07)
    }
  }
)

test_that(
  "spin-up and canonical API retain restart memory",
  {
    config <- pdm_presets("standard")
    model <- pdm_from_config(config)
    state <- spin_up(model, make_forcing(), cycles = 2)
    expect_equal(state@step, 0)
    expect_error(spin_up(model, make_forcing(), cycles = 0))
    output_dt <- sim_pdm(
      c(1, 0),
      c(0, 0),
      model, 60L,
      warmup_steps = 1L, state = state
    )
    expect_equal(output_dt$is_warmup, c(TRUE, FALSE))
    expect_true(all(is.na(output_dt$datetime)))
    expect_true(
      S7::S7_inherits(
        attr(output_dt, "final_state"),
        FlodePdmState
      )
    )
    expect_error(sim_pdm(1, 0, model, 15L))
  }
)
