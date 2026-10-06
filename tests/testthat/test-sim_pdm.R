# ============================================================ #
# Tool:         test-sim_pdm
# Description:  Configurable PDM framework: test-sim_pdm
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
  "new simulation API uses UTC and preserves numerical results",
  {
    config <- pdm_presets("standard")
    model <- pdm_from_config(config)
    datetime <- seq(
      as.POSIXct("2026-10-25 00:00:00", tz = "UTC"),
      by = "hour", length.out = 4
    )
    actual_dt <- sim_pdm(
      c(0, 10, 5, 0),
      rep(0.05, 4),
      config,
      timestep_min = 60L, datetime = datetime
    )
    old <- run_pdm(
      model, data.frame(
        rain = c(0, 10, 5, 0),
        pet = rep(0.05, 4)
      )
    )
    expect_s3_class(actual_dt, "data.table")
    expect_equal(actual_dt$qsim_cms, old$output$q_m3s)
    expect_identical(
      attr(actual_dt$datetime, "tzone"),
      "UTC"
    )
    expect_true(S7::S7_inherits(model, FlodePdmModel))
  }
)

test_that(
  "new simulation API rejects ambiguous and invalid inputs",
  {
    config <- pdm_presets("standard")
    expect_error(
      sim_pdm(numeric(), numeric(), config, 60L),
      "non-empty"
    )
    expect_error(
      sim_pdm(
        c(1, NA),
        c(0, 0),
        config, 60L
      ),
      "finite"
    )
    expect_error(
      sim_pdm(
        c(1, 2),
        0, config, 60L
      ),
      "length"
    )
    expect_error(
      sim_pdm(1, 0, config, 0L),
      "positive integer"
    )
    expect_error(
      sim_pdm(1, 0, config, 60L, warmup_steps = 1L),
      "warmup"
    )
  }
)
