# ============================================================ #
# Tool:         initial_flow
# Description:  Steady-state starting states from an observed flow
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
#'   soil store is capped at capacity, with a warning: the run then starts out of balance;
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
  .warn_soil_cap(model, observed_m3s, baseflow_fraction, soil_fraction)
  if (.engine_supported(model)) {
    # Compiled calculation; results agree with the R code below (see R/engine.R).
    return(.engine_state_from_flow(model, observed_m3s, baseflow_fraction, soil_fraction))
  }
  # Steady state at the observed flow: convert m3/s to mm/h over the catchment, after removing the
  # constant flow qc, and split it between the slow and fast pathways.
  q <- (observed_m3s - model@qc) * 3.6 / model@area_km2
  .check(q >= 0, "observed_m3s is below the constant flow qc")
  qb <- baseflow_fraction * q
  qs <- (1 - baseflow_fraction) * q
  groundwater <- .steady_storage(model@groundwater, qb, "groundwater")
  surface <- .steady_storage(model@surface, qs, "surface")
  # Soil storage is set so that recharge supplies the baseflow. If that needs more than Smax it is
  # capped, and the run then starts slightly out of balance.
  smax <- capacity_mean(model@distribution)
  soil <- min(smax, max(0, .steady_soil(model, qb, groundwater, smax, soil_fraction)))
  # Delay queues are pre-filled as if the same flows had been passing for the whole delay: volumes
  # (mm per step) for the main queues, rates (mm/h) for the endpoint queues.
  FlodePdmState(
    soil = soil, surface = surface, groundwater = groundwater,
    delay_surface = .steady_queue(model, qs * model@dt),
    delay_groundwater = .steady_queue(model, qb * model@dt),
    delay_surface_end = .steady_queue(model, qs),
    delay_groundwater_end = .steady_queue(model, qb),
    step = 0
  )
}

# Warns when the baseflow asked for needs more soil storage than the store holds. The soil is then
# capped at capacity and supplies less recharge than the groundwater store releases, so the run
# starts out of balance: baseflow falls at first, whatever the rain.
.warn_soil_cap <- function(model, observed_m3s, baseflow_fraction, soil_fraction) {
  if (S7::S7_inherits(model@recharge, FlodeSplitRecharge)) return(invisible())
  q <- (observed_m3s - model@qc) * 3.6 / model@area_km2
  if (!is.finite(q) || q < 0) return(invisible())
  qb <- baseflow_fraction * q
  smax <- capacity_mean(model@distribution)
  need <- tryCatch({
    groundwater <- .steady_storage(model@groundwater, qb, "groundwater")
    .steady_soil(model, qb, groundwater, smax, soil_fraction)
  }, error = function(e) NA_real_)
  if (is.finite(need) && need > smax * (1 + 1e-9)) {
    warning(sprintf(paste(
      "A steady start at %.4g m3/s with baseflow_fraction %.2f needs %.4g mm of soil storage,",
      "more than the store's capacity of %.4g mm; the soil is capped and the run starts out of",
      "balance. Start at a lower flow or a smaller baseflow_fraction, or use start = \"soil\"."
    ), observed_m3s, baseflow_fraction, need, smax), call. = FALSE)
  }
  invisible()
}

# The starting state of a calibration or logged run. "flow": steady state at a given flow.
# "soil": the soil store a fraction full and the routing stores empty.
.start_state <- function(model, start, flow, baseflow_fraction, soil_fraction) {
  if (identical(start, "soil")) return(initial_state(model, soil_fraction))
  .check(.scalar(flow, 0), "start = \"flow\" needs a finite, nonnegative first observed flow")
  initial_state_from_flow(model, flow, baseflow_fraction, soil_fraction)
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
  # Standard recharge: invert (S - st)^bg / kg = qb.
  if (S7::S7_inherits(r, FlodeStandardRecharge)) {
    return(r@st + (r@kg * qb)^(1 / r@bg))
  }
  # Demand recharge: invert Eq. 13 for the soil storage, given the groundwater storage.
  if (S7::S7_inherits(r, FlodeDemandRecharge)) {
    sgmax <- storage_for_flow(model@groundwater, r@qsat)
    g <- min(1, max(0, (sgmax - groundwater) / sgmax))
    demand <- min(1, (g / r@alpha)^r@beta)
    dsat <- r@qsat * model@dt
    return(qb * model@dt * smax / (dsat + (smax - dsat) * demand))
  }
  # Split recharge takes groundwater input from runoff, not soil drainage, so the soil level is
  # not determined by the flow; use the fraction given.
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
