# ============================================================ #
# Tool:         initial_flow
# Description:  Steady-state initial state from an observed flow
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-11-01
# Modified:     2026-11-01 - Initial steady-state start
# Tier:         3
# Inputs:       FlodePdmModel; observed flow in m3/s; baseflow share of natural flow
# Outputs:      A validated FlodePdmState in equilibrium with the observed flow
# Dependencies: S7
# ============================================================ #

#' Initial state in equilibrium with an observed flow
#'
#' A warm start that replaces an arbitrary soil fraction with a state consistent with the
#' flow observed at the start of the run. It assumes the catchment is in a steady state at that
#' moment, as it approximately is in a dry-weather recession:
#'
#' - natural flow is `observed_m3s` minus `qc`, converted to mm/h, and divided into baseflow
#'   (`baseflow_fraction`) and surface flow (the rest);
#' - each routing store, or both stores of a cascade, is set to deliver its share in
#'   equilibrium, using [storage_for_flow()];
#' - the soil store is set so that recharge equals baseflow. With standard recharge this is
#'   S = st + (kg * qb)^(1 / bg); with demand recharge it is the soil storage at which the
#'   demand formula gives qb. With split recharge the soil store does not drain to groundwater,
#'   so the steady state does not determine it and `soil_fraction` of capacity is used. The
#'   soil store is capped at capacity;
#' - the outlet delay queues hold the water already in transit at that flow.
#'
#' The state's instantaneous flow then equals `observed_m3s`. The first simulated interval is a
#' mean over the interval, so it departs from the observation as the stores respond to the
#' forcing; with no rain the surface store recedes.
#'
#' `baseflow_fraction` has no default: it varies widely between catchments. For UK gauged
#' catchments the baseflow index (BFI) published by the National River Flow Archive is a
#' reasonable value. An exponential store has no steady state at zero flow, so its share of
#' the flow must be positive.
#'
#' The compiled core does the same calculation (`pdm_state_from_flow()` in src/pdm_core.h).
#'
#' @param model A FlodePdmModel.
#' @param observed_m3s Observed flow at the start of the run, m3/s; finite and at least `qc`.
#' @param baseflow_fraction Share of the natural flow that is baseflow, in `[0, 1]`.
#' @param soil_fraction Soil storage as a fraction of capacity, used only with split
#'   recharge, in `[0, 1]`.
#'
#' @return A validated FlodePdmState with step 0.
#'
#' @examples
#' model <- pdm_model(area_km2 = 44)
#' state <- initial_state_from_flow(model, observed_m3s = 0.8, baseflow_fraction = 0.6)
#' run_pdm(model, data.frame(rain = c(0, 0), pet = c(0, 0)), state)$output$q_m3s
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
initial_state_from_flow <- function(model, observed_m3s, baseflow_fraction, soil_fraction = 0.5) {
  .check(S7::S7_inherits(model, FlodePdmModel), "model must be a FlodePdmModel")
  .check(.scalar(observed_m3s), "observed_m3s must be finite")
  .check(.scalar(baseflow_fraction, 0, 1), "baseflow_fraction must lie in [0,1]")
  .check(.scalar(soil_fraction, 0, 1), "soil_fraction must lie in [0,1]")
  if (.engine_supported(model)) {
    # Compiled calculation; results agree with the R code below (see R/engine.R).
    return(.engine_state_from_flow(model, observed_m3s, baseflow_fraction, soil_fraction))
  }
  q <- (observed_m3s - model@qc) * 3.6 / model@area_km2
  .check(q >= 0, "observed_m3s is below the constant flow qc")
  qb <- baseflow_fraction * q
  qs <- (1 - baseflow_fraction) * q
  groundwater <- .steady_storage(model@groundwater, qb, "groundwater")
  surface <- .steady_storage(model@surface, qs, "surface")
  smax <- capacity_mean(model@distribution)
  soil <- min(smax, max(0, .steady_soil(model, qb, groundwater, smax, soil_fraction)))
  FlodePdmState(
    soil = soil, surface = surface, groundwater = groundwater,
    delay_surface = .steady_queue(model, qs * model@dt),
    delay_groundwater = .steady_queue(model, qb * model@dt),
    delay_surface_end = .steady_queue(model, qs),
    delay_groundwater_end = .steady_queue(model, qb),
    step = 0
  )
}

# Storage giving flow q (mm/h) in equilibrium; a cascade gets both stores.
.steady_storage <- function(routing, q, route) {
  .check(
    !S7::S7_inherits(routing, FlodeExponentialRouting) || q > 0,
    paste("An exponential", route, "store cannot start at zero flow")
  )
  storage_for_flow(routing, q)
}

# Soil storage at which recharge equals baseflow qb (mm/h).
.steady_soil <- function(model, qb, groundwater, smax, soil_fraction) {
  r <- model@recharge
  if (S7::S7_inherits(r, FlodeStandardRecharge)) {
    return(r@st + (r@kg * qb)^(1 / r@bg))
  }
  if (S7::S7_inherits(r, FlodeDemandRecharge)) {
    sgmax <- storage_for_flow(model@groundwater, r@qsat)
    g <- min(1, max(0, (sgmax - groundwater) / sgmax))
    demand <- min(1, (g / r@alpha)^r@beta)
    dsat <- r@qsat * model@dt
    return(qb * model@dt * smax / (dsat + (smax - dsat) * demand))
  }
  soil_fraction * smax
}

# A delay queue in steady state with a constant input v per interval: full values for the
# whole intervals of delay, then the fractional remainder.
.steady_queue <- function(model, v) {
  ratio <- model@td / model@dt
  n <- floor(ratio)
  queue <- rep(v, n + 1)
  queue[n + 1] <- (ratio - n) * v
  queue
}
