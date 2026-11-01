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

# Rebuilds the S7 model from one row of cases.csv (the fields of pdm_params).
golden_route <- function(p, prefix) {
  f <- function(name) p[[paste0(prefix, name)]]
  switch(as.character(f("type")),
    "0" = FlodeCascadeRouting(k1 = f("k1"), k2 = f("k2")),
    "1" = power_routing(
      k = f("k"), m = f("m"), solver = if (f("smith") == 1) "smith" else "adaptive",
      rtol = f("rtol"), atol = f("atol")
    ),
    "2" = FlodeExponentialRouting(a = f("a"), gamma = f("gamma"))
  )
}

golden_model <- function(p) {
  distribution <- switch(as.character(p$distribution),
    "0" = FlodeParetoCapacity(cmin = p$cmin, cmax = p$cmax, b = p$b),
    "1" = FlodeRectangularCapacity(cmin = p$cmin, cmax = p$cmax),
    "2" = FlodeExponentialCapacity(mean = p$mean),
    "3" = FlodeTriangularCapacity(cmin = p$cmin, cmax = p$cmax),
    "4" = FlodeLognormalCapacity(meanlog = p$meanlog, sdlog = p$sdlog)
  )
  recharge <- switch(as.character(p$recharge),
    "0" = FlodeStandardRecharge(kg = p$kg, bg = p$bg, st = p$st),
    "1" = FlodeSplitRecharge(alpha = p$alpha),
    "2" = FlodeDemandRecharge(alpha = p$alpha, beta = p$beta, qsat = p$qsat)
  )
  pdm_model(
    distribution = distribution, recharge = recharge,
    surface = golden_route(p, "surface."), groundwater = golden_route(p, "groundwater."),
    be = p$be, fc = p$fc, td = p$td, qc = p$qc, area_km2 = p$area_km2, dt = p$dt
  )
}

# Rebuilds a FlodePdmState from a state array in the layout of src/pdm_core.h.
golden_state <- function(v, p) {
  stores <- function(type) if (type == 0) 2L else 1L
  n <- (length(v) - 6L) / 4L
  queue <- function(j) v[6L + (j - 1L) * n + seq_len(n)]
  FlodePdmState(
    soil = v[1L], surface = v[1L + seq_len(stores(p$surface.type))],
    groundwater = v[3L + seq_len(stores(p$groundwater.type))], step = v[6L],
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
    expect_gte(nrow(cases), 21L)
    for (i in seq_len(nrow(cases))) {
      p <- cases[i, ]
      name <- p$case
      model <- golden_model(p)
      state <- golden_state(golden_read(paste0(name, "_initial_state.csv"))$value, p)
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
        got_state <- pdmS7:::.engine_pack_state(result$state)
        golden_agree(got_state, want_state, paste(name, engine, "state"))
      }
    }
  }
)

test_that(
  "the core rejects every invalid golden parameter set",
  {
    invalid <- golden_read("invalid_cases.csv")
    params <- setdiff(names(invalid), c("case", "expected_code"))
    expect_length(params, 40L)
    for (i in seq_len(nrow(invalid))) {
      par <- as.numeric(invalid[i, params])
      expect_error(
        pdmS7:::pdm_engine_run(1, 0.1, par, rep(0, 10), FALSE),
        regexp = "Invalid parameter|cannot exceed|Demand recharge|incompatible",
        label = invalid$case[i]
      )
    }
  }
)
