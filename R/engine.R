# ============================================================ #
# Tool:         engine
# Description:  Bridge between the S7 objects and the compiled C core
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-31
# Modified:     2026-11-01 - All PDM components; only PACK snow stays on the R loop
#               2026-11-12 - The groundwater extension, with abstraction (interface version 3)
# Tier:         1
# Inputs:       FlodePdmModel, FlodePdmState, forcing depths in mm per interval
# Outputs:      run_pdm() output columns and final state, equal to the R loop to rounding
# Dependencies: cpp11 (build time); data.table
# ============================================================ #

#' @useDynLib pdmS7, .registration = TRUE
NULL

# The compiled engine covers every capacity distribution (Pareto, rectangular, exponential,
# triangular, lognormal); standard, split and demand recharge; and cascade, power-law and
# exponential stores for either route. Exact class matching keeps any future subclass on the
# R loop until it is ported and tested.
# options(pdmS7.engine = "r") forces the R loop, which remains the reference implementation.
.engine_classes <- list(
  distribution = c(
    "pdmS7::FlodeParetoCapacity" = 0, "pdmS7::FlodeRectangularCapacity" = 1,
    "pdmS7::FlodeExponentialCapacity" = 2, "pdmS7::FlodeTriangularCapacity" = 3,
    "pdmS7::FlodeLognormalCapacity" = 4
  ),
  recharge = c(
    "pdmS7::FlodeStandardRecharge" = 0, "pdmS7::FlodeSplitRecharge" = 1,
    "pdmS7::FlodeDemandRecharge" = 2
  ),
  route = c(
    "pdmS7::FlodeCascadeRouting" = 0, "pdmS7::FlodePowerRouting" = 1,
    "pdmS7::FlodeExponentialRouting" = 2
  )
)

# TRUE when every component of the model has a compiled implementation and the user has not
# asked for the R loop. Matching on the first class name, not inheritance, is deliberate. The
# core runs the groundwater extension (extended = TRUE, for simulation and calibration), but
# not its warm start from flow or state correction, which stay on the R loop.
.engine_supported <- function(model, extended = FALSE) {
  if (identical(getOption("pdmS7.engine", "auto"), "r")) {
    return(FALSE)
  }
  first <- function(x) class(x)[1L]
  ground <- model@groundwater
  if (S7::S7_inherits(ground, FlodeExtendedGroundwater)) {
    if (!extended) return(FALSE)
    ground <- ground@store
  }
  first(model@distribution) %in% names(.engine_classes$distribution) &&
    first(model@recharge) %in% names(.engine_classes$recharge) &&
    first(model@surface) %in% names(.engine_classes$route) &&
    first(ground) %in% names(.engine_classes$route)
}

# The extension block of pdm_params: the enabled flag and eight parameters, in struct order.
.engine_extension_params <- function(x) {
  p <- c(enabled = 0, ku = 0, dbu = 0, alpha_b = 0, ca = 0, fa = 0, smax_b = 0, ys = 0, hw = 0)
  if (S7::S7_inherits(x, FlodeExtendedGroundwater)) {
    p[] <- c(1, x@ku, x@dbu, x@alpha_b, x@ca, x@fa, x@smax_b, x@ys, x@hw)
  }
  stats::setNames(p, paste0("extension.", names(p)))
}

# Field values of pdm_params in src/pdm_core.h, in struct order. Fields not used by a
# component are 0. The golden file generator writes these names as column headers.
.engine_route_params <- function(x) {
  type <- .engine_classes$route[[class(x)[1L]]]
  p <- c(type = type, smith = 0, k1 = 0, k2 = 0, k = 0, m = 0, rtol = 0, atol = 0, a = 0,
         gamma = 0)
  if (type == 0) {
    p[c("k1", "k2")] <- c(x@k1, x@k2)
  } else if (type == 1) {
    p[c("smith", "k", "m", "rtol", "atol")] <-
      c(as.numeric(x@solver == "smith"), x@k, x@m, x@rtol, x@atol)
  } else {
    p[c("a", "gamma")] <- c(x@a, x@gamma)
  }
  p
}

# Flattens a model into the numeric parameter vector the C core reads: component type codes, then
# every distribution and recharge field (zero where unused), then both routes, then the catchment
# settings, then the groundwater extension. Order matters and must match pdm_params in
# src/pdm_core.h. An extended groundwater store passes its inner store as the route.
.engine_params <- function(model) {
  d <- model@distribution
  r <- model@recharge
  dtype <- .engine_classes$distribution[[class(d)[1L]]]
  rtype <- .engine_classes$recharge[[class(r)[1L]]]
  p <- c(distribution = dtype, recharge = rtype, cmin = 0, cmax = 0, b = 0, mean = 0,
         meanlog = 0, sdlog = 0, kg = 0, bg = 0, st = 0, alpha = 0, beta = 0, qsat = 0)
  if (dtype == 0) {
    p[c("cmin", "cmax", "b")] <- c(d@cmin, d@cmax, d@b)
  } else if (dtype %in% c(1, 3)) {
    p[c("cmin", "cmax")] <- c(d@cmin, d@cmax)
  } else if (dtype == 2) {
    p[["mean"]] <- d@mean
  } else {
    p[c("meanlog", "sdlog")] <- c(d@meanlog, d@sdlog)
  }
  if (rtype == 0) {
    p[c("kg", "bg", "st")] <- c(r@kg, r@bg, r@st)
  } else if (rtype == 1) {
    p[["alpha"]] <- r@alpha
  } else {
    p[c("alpha", "beta", "qsat")] <- c(r@alpha, r@beta, r@qsat)
  }
  surface <- .engine_route_params(model@surface)
  ground <- model@groundwater
  extended <- S7::S7_inherits(ground, FlodeExtendedGroundwater)
  groundwater <- .engine_route_params(if (extended) ground@store else ground)
  names(surface) <- paste0("surface.", names(surface))
  names(groundwater) <- paste0("groundwater.", names(groundwater))
  c(p, surface, groundwater,
    be = model@be, fc = model@fc, td = model@td, qc = model@qc, area_km2 = model@area_km2,
    dt = model@dt, .engine_extension_params(ground))
}

# State array of src/pdm_core.h: soil, two surface slots, two groundwater slots, step, then the
# four delay queues. The second slot of a single-store route is 0.
.engine_pack_state <- function(state) {
  two <- function(x) if (length(x) == 1L) c(x, 0) else x
  as.double(c(
    state@soil, two(state@surface), two(state@groundwater), state@step,
    state@delay_surface, state@delay_groundwater,
    state@delay_surface_end, state@delay_groundwater_end
  ))
}

# Rebuilds an S7 state from the core's flat state vector. The template supplies the shapes the
# vector does not carry: whether each route has one store or two, and the delay queue length.
.engine_unpack_state <- function(v, template) {
  n <- length(template@delay_surface)
  queue <- function(j) v[6L + (j - 1L) * n + seq_len(n)]
  FlodePdmState(
    soil = v[1L], surface = v[1L + seq_along(template@surface)],
    groundwater = v[3L + seq_along(template@groundwater)],
    delay_surface = queue(1L), delay_groundwater = queue(2L),
    delay_surface_end = queue(3L), delay_groundwater_end = queue(4L),
    step = v[6L]
  )
}

# Column names of the full output table, in the order the core writes them; identical to the
# columns pdm_step() returns, so either path gives the same table.
.engine_flux_names <- c(
  "step", "rain_mm", "rain_corrected_mm", "pet_mm", "aet_mm", "aet_requested_mm",
  "recharge_mm", "recharge_requested_mm", "direct_runoff_mm", "surface_input_mm",
  "groundwater_input_mm", "surface_out_mm", "baseflow_out_mm", "q_natural_m3s", "q_m3s",
  "q_end_m3s", "qs_end_unlagged_mmh", "qb_end_unlagged_mmh", "soil_mm", "surface_mm",
  "groundwater_mm", "delay_mm", "saturated_fraction", "balance_error_mm"
)

# The extension's columns, which pdm_step() adds after the others for an extended model.
.engine_ext_flux_names <- c("abstraction_mm", "underflow_mm", "spring_mm",
                            "groundwater_deficit_mm", "well_level_m")

# Runs the compiled PDM. full = TRUE returns every flux column; full = FALSE returns only the two
# flow series, which is all calibration needs and avoids building a large table thousands of times.
# abstraction is NULL for none, or one recorded depth per step (mm), for an extended model.
.engine_run <- function(model, rain, pet, state, full, abstraction = NULL) {
  .validate_state(model, state)
  res <- pdm_engine_run(
    as.double(rain), as.double(pet), as.double(abstraction %||% numeric(0)),
    as.double(.engine_params(model)), .engine_pack_state(state), full
  )
  final <- .engine_unpack_state(res$state, state)
  if (full) {
    columns <- stats::setNames(res$columns, .engine_flux_names)
    ground <- model@groundwater
    if (S7::S7_inherits(ground, FlodeExtendedGroundwater)) {
      extra <- stats::setNames(res$ext_columns, .engine_ext_flux_names)
      # The core writes NaN without a well; the R loop's column is NA.
      if (ground@ys <= 0) extra$well_level_m <- rep(NA_real_, length(rain))
      columns <- c(columns, extra)
    }
    output <- data.table::setDF(data.table::setDT(columns))
  } else {
    output <- list(q_m3s = res$q_m3s, q_end_m3s = res$q_end_m3s)
  }
  list(output = output, state = final)
}

# Simulated flow only, for calibration. Applies the same checks as run_pdm() and returns the
# same values as run_pdm(...)$output[[flow]] without building the full flux table.
.run_flow <- function(model, forcing, state, flow) {
  if (.is_multizone(model)) return(.multizone_flow(model, forcing, state, flow))
  if (!.engine_supported(model, extended = TRUE)) {
    return(run_pdm(model, forcing, state)$output[[flow]])
  }
  .check_forcing(model, forcing)
  .engine_run(model, forcing$rain, forcing$pet, state, full = FALSE,
              abstraction = forcing$abstraction)$output[[flow]]
}

# The Smith cubic solver's error grows with the square of dt. Measured against a tight
# adaptive reference (docs/benchmarks/solver-timing.md), it stays within about 1 per cent of
# peak flow up to a 1-hour step for kb of 1,000 or more, and reaches 60 to 100 per cent at a
# daily step. Warn once per session so calibration loops do not repeat the message.
.smith_max_dt <- 1
.engine_flags <- new.env(parent = emptyenv())
.warn_smith_step <- function(model) {
  uses_smith <- function(route) {
    if (S7::S7_inherits(route, FlodeExtendedGroundwater)) route <- route@store
    class(route)[1L] == "pdmS7::FlodePowerRouting" && route@solver == "smith"
  }
  if (model@dt > .smith_max_dt && (uses_smith(model@surface) || uses_smith(model@groundwater)) &&
        !isTRUE(.engine_flags$smith_warned)) {
    .engine_flags$smith_warned <- TRUE
    warning(
      sprintf(
        paste0(
          "The Smith solver is inaccurate above a %g-hour step (dt = %g hours here); ",
          "errors can exceed 1 per cent of peak flow and reach 100 per cent at a daily step. ",
          "Use solver = \"adaptive\". This warning is shown once per session."
        ),
        .smith_max_dt, model@dt
      ),
      call. = FALSE
    )
  }
  invisible(NULL)
}

# ---- PACK snowpack ---------------------------------------------------------------------------

.pack_flux_names <- c(
  "snowfall_mm", "rainfall_mm", "melt_mm", "drainage_mm", "bypass_mm", "effective_rain_mm",
  "precipitation_corrected_mm", "dry_snow_mm", "wet_snow_mm", "snow_cover_fraction",
  "snow_balance_error_mm"
)

# Field values of pdm_pack_params in src/pdm_core.h, in struct order.
.pack_engine_params <- function(model) {
  c(
    precipitation_factor = model@precipitation_factor, lower_rate_h = model@lower_rate_h,
    upper_rate_h = model@upper_rate_h, retention_fraction = model@retention_fraction,
    melt_factor_mmh_c = model@melt_factor_mmh_c, adc_alpha = model@adc_alpha,
    adc_depth_mm = model@adc_depth_mm, melt_threshold_c = model@melt_threshold_c,
    snow_threshold_c = model@snow_threshold_c, drain_threshold_c = model@drain_threshold_c,
    max_step_min = model@max_step_min, areal_depletion = as.numeric(model@areal_depletion)
  )
}

# PACK state as the flat vector the core reads: dry, wet, anchor depth, anchor cover, fresh depth.
.pack_pack_state <- function(state) {
  as.double(c(state@dry_mm, state@wet_mm, state@anchor_mm, state@anchor_fraction,
              state@fresh_mm))
}

# Runs PACK through the compiled core; returns the same output as the R loop in sim_pack().
.pack_engine_run <- function(model, precipitation, temperature, state, dt) {
  res <- pack_engine_run(
    as.double(precipitation), as.double(temperature), as.double(.pack_engine_params(model)),
    .pack_pack_state(state), as.double(dt)
  )
  v <- res$state
  final <- FlodePackState(dry_mm = v[1L], wet_mm = v[2L], anchor_mm = v[3L],
                          anchor_fraction = v[4L], fresh_mm = v[5L])
  output <- data.table::setDT(stats::setNames(res$columns, .pack_flux_names))
  list(output = output, state = final)
}

# ---- Forecast updating ------------------------------------------------------------------------

# Fields of pdm_state_updater in src/pdm_core.h, in struct order.
.engine_updater_params <- function(updater) {
  scheme <- match(updater@scheme, c("proportional", "super_proportional", "non_proportional")) - 1
  c(scheme = scheme, soil_proportional = as.numeric(updater@soil_proportional),
    gb = updater@gb, gs = updater@gs, gg = updater@gg, beta1 = updater@beta1,
    beta2 = updater@beta2)
}

# State correction (Moore 2007, Eq. 28-30) in the core: returns the corrected state and the
# diagnostics correct_state() reports.
.engine_correct <- function(model, state, observed_m3s, updater) {
  res <- correct_engine_run(
    as.double(.engine_params(model)), .engine_pack_state(state), as.double(observed_m3s),
    as.double(.engine_updater_params(updater))
  )
  list(
    state = .engine_unpack_state(res$state, state), correction_mm = res$correction_mm,
    q_corrected_m3s = res$q_corrected_m3s, innovation_mmh = res$innovation_mmh,
    alpha = res$alpha
  )
}

# ARMA error prediction (Eq. 31-42) in the core; returns the list update_forecast() documents.
.engine_update_forecast <- function(updater, observed_history, simulated_history, forecast) {
  forecast_engine_run(
    as.double(updater@ar), as.double(updater@ma), as.integer(updater@scale == "log"),
    as.double(updater@offset), as.double(observed_history), as.double(simulated_history),
    as.double(forecast)
  )
}

# Steady-state start from an observed flow, computed in the core; mirrors the R code in
# initial_state_from_flow().
.engine_state_from_flow <- function(model, observed_m3s, baseflow_fraction, soil_fraction) {
  v <- from_flow_engine_run(
    as.double(.engine_params(model)), as.double(observed_m3s), as.double(baseflow_fraction),
    as.double(soil_fraction)
  )
  .engine_unpack_state(v, initial_state(model))
}
