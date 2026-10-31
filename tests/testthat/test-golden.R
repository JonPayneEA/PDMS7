# ============================================================ #
# Tool:         test-golden
# Description:  Configurable PDM framework: test-golden
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-31 - Check the PDM core against the golden files
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

golden_dir <- function() system.file("golden", package = "pdmS7")
golden_read <- function(name) {
  utils::read.csv(file.path(golden_dir(), name), stringsAsFactors = FALSE)
}

# Same rule as inst/golden/README.md: within 1e-12 of max(1, largest absolute expected value).
golden_agree <- function(got, want, label) {
  scale <- max(1, abs(want))
  testthat::expect_lte(max(abs(got - want)), 1e-12 * scale, label = label)
}

golden_model <- function(p) {
  pdm_model(
    distribution = FlodeParetoCapacity(cmin = p$cmin, cmax = p$cmax, b = p$b),
    recharge = FlodeStandardRecharge(kg = p$kg, bg = p$bg, st = p$st),
    surface = FlodeCascadeRouting(k1 = p$k1, k2 = p$k2),
    groundwater = power_routing(
      k = p$k, m = p$m, solver = if (p$smith == 1) "smith" else "adaptive",
      rtol = p$rtol, atol = p$atol
    ),
    be = p$be, fc = p$fc, td = p$td, qc = p$qc, area_km2 = p$area_km2, dt = p$dt
  )
}

golden_state <- function(v) {
  n <- (length(v) - 5L) / 4L
  queue <- function(j) v[5L + (j - 1L) * n + seq_len(n)]
  FlodePdmState(
    soil = v[1L], surface = v[2:3], groundwater = v[4L], step = v[5L],
    delay_surface = queue(1L), delay_groundwater = queue(2L),
    delay_surface_end = queue(3L), delay_groundwater_end = queue(4L)
  )
}

test_that(
  "both engines reproduce the golden files",
  {
    forcing <- golden_read("forcing.csv")
    forcing <- data.frame(rain = forcing$rain_mm, pet = forcing$pet_mm)
    cases <- golden_read("cases.csv")
    expect_gte(nrow(cases), 9L)
    for (i in seq_len(nrow(cases))) {
      p <- cases[i, ]
      name <- p$case
      model <- golden_model(p)
      state <- golden_state(golden_read(paste0(name, "_initial_state.csv"))$value)
      want <- golden_read(paste0(name, "_fluxes.csv"))
      want_state <- golden_read(paste0(name, "_final_state.csv"))$value
      for (engine in c("auto", "r")) {
        old <- options(pdmS7.engine = engine)
        result <- run_pdm(model, forcing, state)
        options(old)
        expect_identical(names(result$output), names(want))
        for (col in names(want)) {
          golden_agree(result$output[[col]], want[[col]], paste(name, engine, col))
        }
        got_state <- c(
          result$state@soil, result$state@surface, result$state@groundwater, result$state@step,
          result$state@delay_surface, result$state@delay_groundwater,
          result$state@delay_surface_end, result$state@delay_groundwater_end
        )
        golden_agree(got_state, want_state, paste(name, engine, "state"))
      }
    }
  }
)

test_that(
  "the core rejects every invalid golden parameter set",
  {
    invalid <- golden_read("invalid_cases.csv")
    params <- c("cmin", "cmax", "b", "kg", "bg", "st", "k1", "k2", "k", "m", "rtol", "atol",
                "be", "fc", "td", "qc", "area_km2", "dt", "smith")
    for (i in seq_len(nrow(invalid))) {
      par <- as.numeric(invalid[i, params])
      expect_error(
        pdmS7:::pdm_engine_run(1, 0.1, par, c(0, 0, 0, 0, 0, 0, 0, 0, 0), FALSE),
        regexp = "Invalid parameter|cannot exceed|incompatible",
        label = invalid$case[i]
      )
    }
  }
)
