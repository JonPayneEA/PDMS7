# ============================================================ #
# Tool:         model
# Description:  Configurable PDM framework: model
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #
#' Pdm step
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param model A FlodePdmModel compatible with the supplied state.
#' @param state A compatible FlodePdmState; NULL in sim_pdm initializes the model.
#' @param rain Nonnegative interval rainfall depth in mm.
#' @param pet Nonnegative interval potential evaporation depth in mm.
#'
#' @return A list with state and a one-row flux data.frame.
#'
#' @examples
#' model <- pdm_model()
#' pdm_step(model, initial_state(model), rain = 10, pet = 0.05)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
pdm_step <- function(model, state, rain, pet) {
  .validate_state(model, state)
  .check(
    .scalar(rain, 0) &&
      .scalar(pet, 0),
    "rain and pet must be finite nonnegative depths"
  )
  dt <- model@dt
  old <- .total_storage(state)
  smax <- capacity_mean(model@distribution)
  p <- rain * model@fc
  # Eq. 8 and 10-14 are evaluated at the start of the interval.
  et_requested <- pet * (-expm1(model@be * log1p(-state@soil / smax)))
  dr_requested <- recharge_depth(model@recharge,
                                 state@soil,
                                 smax,
                                 state@groundwater,
                                 model@groundwater,
                                 dt)
  # Explicit water-limited boundary policy: evaporation first, then recharge.  This only
  # changes requests that would otherwise overdraw the soil store.
  et <- min(et_requested, state@soil + p)
  dr <- min(dr_requested, max(0, state@soil + p - et))
  soil <- soil_step(model@distribution, state@soil, p - et - dr)
  fast <- soil$runoff
  slow <- dr
  if (S7::S7_inherits(model@recharge, FlodeSplitRecharge)) {
    fast <- soil$runoff * model@recharge@alpha
    slow <- soil$runoff * (1 - model@recharge@alpha)
  }
  surf <- route_step(model@surface, state@surface, fast / dt, dt)
  ground <- route_step(model@groundwater, state@groundwater, slow / dt, dt)
  d1 <- .delay(state@delay_surface, surf$outflow, model@td / dt)
  d2 <- .delay(state@delay_groundwater, ground$outflow, model@td / dt)
  e1 <- .delay(state@delay_surface_end, surf$q_end, model@td / dt)
  e2 <- .delay(state@delay_groundwater_end, ground$q_end, model@td / dt)
  next_state <- FlodePdmState(
    soil = soil$storage,
    surface = surf$storage,
    groundwater = ground$storage,
    delay_surface = d1$pending,

    delay_groundwater = d2$pending,
    delay_surface_end = e1$pending,
    delay_groundwater_end = e2$pending,

    step = state@step + 1
  )
  # 1 mm/hour over 1 km2 = 1/3.6 m3/s.
  factor <- model@area_km2 / 3.6
  natural <- d1$out + d2$out
  residual <- old + p - et - natural - .total_storage(next_state)
  flux_dt <- data.table::data.table(
    step = next_state@step, rain_mm = rain, rain_corrected_mm = p, pet_mm = pet, aet_mm = et,
    aet_requested_mm = et_requested, recharge_mm = dr, recharge_requested_mm = dr_requested,
    direct_runoff_mm = soil$runoff, surface_input_mm = fast, groundwater_input_mm = slow,
    surface_out_mm = d1$out, baseflow_out_mm = d2$out, q_natural_m3s = natural / dt * factor,
    q_m3s = natural / dt * factor + model@qc, q_end_m3s = (e1$out + e2$out) * factor + model@qc,
    qs_end_unlagged_mmh = surf$q_end, qb_end_unlagged_mmh = ground$q_end, soil_mm = next_state@soil,
    surface_mm = sum(next_state@surface),
    groundwater_mm = sum(next_state@groundwater),
    delay_mm = sum(next_state@delay_surface, next_state@delay_groundwater),
    saturated_fraction = capacity_cdf(model@distribution,
                                      capacity_from_storage(model@distribution,
                                                            next_state@soil)),

    balance_error_mm = residual
  )
  list(state = next_state, flux = data.table::setDF(flux_dt))
}
