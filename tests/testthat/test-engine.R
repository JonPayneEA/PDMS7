# ============================================================ #
# Tool:         test-engine
# Description:  Configurable PDM framework: test-engine
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-31 - Add compiled engine equivalence tests
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

engine_forcing <- function(n = 400) {
  set.seed(11)
  data.frame(
    rain = ifelse(stats::runif(n) < 0.4, stats::rgamma(n, 0.6, scale = 12), 0),
    pet = pmax(0, 2 + 1.5 * sin(seq_len(n) / 30))
  )
}

with_engine <- function(engine, code) {
  old <- options(pdmS7.engine = engine)
  on.exit(options(old))
  force(code)
}

# The engines agree to rounding, not bit for bit: R's own sum() and ^ changed between R
# versions (4.3 and 4.6 differ in the last place), so the C code cannot track them exactly.
# Each numeric column must agree within 1e-12 of its own magnitude (at least 1).
# Non-numeric columns, such as timestamps, must match exactly.
expect_engines_agree <- function(fast, ref, label = "") {
  testthat::expect_identical(names(fast), names(ref), label = label)
  for (col in names(ref)) {
    a <- fast[[col]]
    b <- ref[[col]]
    if (is.numeric(b)) {
      testthat::expect_identical(length(a), length(b), label = paste(label, col))
      scale <- max(1, abs(b))
      testthat::expect_lte(max(abs(a - b)), 1e-12 * scale, label = paste(label, col))
    } else {
      testthat::expect_identical(a, b, label = paste(label, col))
    }
  }
}
expect_states_agree <- function(fast, ref, label = "") {
  props <- names(S7::props(ref))
  expect_engines_agree(
    stats::setNames(lapply(props, function(p) S7::prop(fast, p)), props),
    stats::setNames(lapply(props, function(p) S7::prop(ref, p)), props),
    label = label
  )
}

engine_models <- function() {
  list(
    default = pdm_model(),
    smith = pdm_model(groundwater = cubic_routing(solver = "smith")),
    quarter_hour_delay = pdm_model(dt = 0.25, td = 1.1, area_km2 = 44, qc = 0.3),
    daily = pdm_model(dt = 24, area_km2 = 100),
    varied = pdm_model(
      distribution = FlodeParetoCapacity(cmin = 20, cmax = 300, b = 0.9),
      recharge = FlodeStandardRecharge(kg = 9000, bg = 2.5, st = 30),
      surface = FlodeCascadeRouting(k1 = 3, k2 = 3.000001),
      groundwater = power_routing(k = 1 / 500, m = 2.5), be = 2, fc = 1.2
    ),
    linear = pdm_model(groundwater = linear_routing(30)),
    quadratic = pdm_model(groundwater = quadratic_routing(300)),
    point_mass = pdm_model(distribution = FlodeParetoCapacity(cmin = 0, cmax = 140, b = 0)),
    rectangular = pdm_model(distribution = FlodeRectangularCapacity(cmin = 0.4, cmax = 170.7)),
    exponential_capacity = pdm_model(distribution = FlodeExponentialCapacity(mean = 110)),
    split = pdm_model(recharge = FlodeSplitRecharge(alpha = 0.7)),
    demand_power = pdm_model(recharge = FlodeDemandRecharge(alpha = 0.5, beta = 1.5, qsat = 0.5)),
    demand_exponential = pdm_model(
      recharge = FlodeDemandRecharge(alpha = 0.4, beta = 2, qsat = 0.3),
      groundwater = FlodeExponentialRouting(a = 0.02, gamma = -2)
    ),
    exponential_routes = pdm_model(
      surface = FlodeExponentialRouting(a = 0.05, gamma = -5),
      groundwater = FlodeExponentialRouting(a = 0.02, gamma = -8)
    ),
    power_surface = pdm_model(surface = power_routing(k = 0.01, m = 1.7)),
    smith_surface = pdm_model(surface = power_routing(k = 1e-3, m = 3, solver = "smith")),
    cascade_groundwater = pdm_model(groundwater = FlodeCascadeRouting(k1 = 30, k2 = 200)),
    triangular = pdm_model(distribution = FlodeTriangularCapacity(cmin = 10, cmax = 190)),
    lognormal = pdm_model(distribution = FlodeLognormalCapacity(meanlog = 4.1, sdlog = 1))
  )
}

test_that(
  "compiled engine reproduces the R loop to rounding",
  {
    forcing <- engine_forcing()
    for (name in names(engine_models())) {
      model <- engine_models()[[name]]
      check(pdmS7:::.engine_supported(model))
      ref <- with_engine("r", run_pdm(model, forcing))
      fast <- with_engine("auto", run_pdm(model, forcing))
      expect_engines_agree(fast$output, ref$output, label = name)
      expect_states_agree(fast$state, ref$state, label = name)
      expect_engines_agree(
        as.list(fast$water_balance), as.list(ref$water_balance),
        label = name
      )
    }
  }
)

test_that(
  "compiled engine honours initial state, restart and time columns",
  {
    forcing <- engine_forcing(200)
    model <- pdm_model(td = 2.5)
    state <- initial_state(model, 0.9, surface = c(3, 4), groundwater = 20)
    ref <- with_engine("r", run_pdm(model, forcing, state))
    fast <- run_pdm(model, forcing, state)
    expect_engines_agree(fast$output, ref$output)
    # Restarting from a final state matches one continuous run.
    first <- run_pdm(model, forcing[1:120, ], state)
    second <- run_pdm(model, forcing[121:200, ], first$state)
    expect_identical(second$output$q_m3s, fast$output$q_m3s[121:200])
    expect_identical(second$state, fast$state)
    timed <- forcing
    timed$time <- as.POSIXct("2026-01-01", tz = "UTC") + 3600 * seq_len(nrow(forcing))
    expect_engines_agree(
      run_pdm(model, timed)$output,
      with_engine("r", run_pdm(model, timed))$output
    )
  }
)

test_that(
  "compiled engine accepts a state held as integers",
  {
    model <- pdm_model()
    # Every value an integer, as read.csv() returns for whole numbers.
    state <- FlodePdmState(
      soil = 50L, surface = c(3L, 4L), groundwater = 20L, step = 0L,
      delay_surface = 0L, delay_groundwater = 0L,
      delay_surface_end = 0L, delay_groundwater_end = 0L
    )
    forcing <- engine_forcing(50)
    expect_engines_agree(
      run_pdm(model, forcing, state)$output,
      with_engine("r", run_pdm(model, forcing, state))$output
    )
  }
)

test_that(
  "the r option uses the R loop",
  {
    check(!with_engine("r", pdmS7:::.engine_supported(pdm_model())))
  }
)

test_that(
  "a rectangular store filled exactly to capacity runs on both engines",
  {
    # (cmin + cmax) / 2 and cmin + (cmax - cmin) / 2 differ in the last place for these
    # bounds; a full store used to fail with "Soil storage exceeds capacity_mean".
    distribution <- FlodeRectangularCapacity(cmin = 0.2, cmax = 1.0)
    model <- pdm_model(distribution = distribution)
    state <- initial_state(model, 1)
    forcing <- data.frame(rain = c(0, 5, 0), pet = 0.1)
    expect_engines_agree(
      run_pdm(model, forcing, state)$output,
      with_engine("r", run_pdm(model, forcing, state))$output
    )
    expect_equal(capacity_from_storage(distribution, capacity_mean(distribution)), 1.0)
  }
)

test_that(
  "lean flow path matches run_pdm and calibration is engine independent",
  {
    forcing <- engine_forcing(150)
    model <- pdm_model()
    state <- initial_state(model, 0.3)
    full <- run_pdm(model, forcing, state)$output
    for (flow in c("q_m3s", "q_end_m3s")) {
      expect_identical(pdmS7:::.run_flow(model, forcing, state, flow), full[[flow]])
    }
    cfg <- pdm_presets("standard")
    observed <- full$q_m3s
    args <- list(
      cfg, forcing, observed, c(fc = 0.6, recharge.kg = 10), c(fc = 1.5, recharge.kg = 40),
      control = list(maxit = 3)
    )
    fast <- do.call(calibrate_pdm, args)
    ref <- with_engine("r", do.call(calibrate_pdm, args))
    # The optimiser can amplify last-place differences, so allow a looser tolerance here.
    expect_equal(fast$parameters, ref$parameters, tolerance = 1e-8)
    expect_equal(fast$objective, ref$objective, tolerance = 1e-8)
  }
)

test_that(
  "compiled engine rejects invalid inputs as the R loop does",
  {
    model <- pdm_model()
    forcing <- engine_forcing(20)
    bad <- forcing
    bad$rain[5] <- -1
    expect_error(run_pdm(model, bad))
    bad$rain[5] <- NA
    expect_error(run_pdm(model, bad))
    expect_error(run_pdm(model, forcing, initial_state(pdm_model(td = 3))))
    expect_error(pdmS7:::.run_flow(model, bad, initial_state(model), "q_m3s"))
  }
)

test_that(
  "Smith with a step above one hour warns once per session",
  {
    flags <- pdmS7:::.engine_flags
    flags$smith_warned <- NULL
    on.exit(flags$smith_warned <- NULL)
    expect_silent(pdm_model(groundwater = cubic_routing(solver = "smith"), dt = 1))
    expect_silent(pdm_model(dt = 24))
    expect_warning(
      pdm_model(groundwater = cubic_routing(solver = "smith"), dt = 24),
      "Smith solver is inaccurate"
    )
    expect_silent(pdm_model(groundwater = cubic_routing(solver = "smith"), dt = 24))
    flags$smith_warned <- NULL
    cfg <- pdm_presets("paper_cubic")
    cfg$dt <- 3
    expect_warning(pdm_from_config(cfg), "Smith solver is inaccurate")
  }
)
