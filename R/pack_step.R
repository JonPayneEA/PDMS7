# ============================================================ #
# Tool:         pack_step
# Description:  pack_step(): one time step of the PACK snow model in R
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Implement PACK accounting
# Tier:         3
# Inputs:       Precipitation depth mm; temperature Celsius; interval hours
# Outputs:      Updated S7 snow state and conservative water fluxes
# Dependencies: S7 (typed model components)
# ============================================================ #

#' Advance a PACK snow state
#'
#' Implements report equations 2.1-2.8 with explicit conservative accounting.
#' Forcing is constant within an interval. Internal steps are bounded by max_step_min
#' and the sum of drainage rates. Melt is limited by dry storage, drainage by wet
#' storage. Melt over partial cover is scaled by its current area fraction.
#' Fresh-snow reversion uses total pack depletion, following the Figure 2.2 axis;
#' see docs/snow-model.md for this interpretation and other numerical conventions.
#' @param model A FlodePackModel.
#' @param state A complete FlodePackState.
#' @param precipitation_mm Nonnegative interval precipitation depth, mm.
#' @param temperature_c Finite interval mean temperature, Celsius.
#' @param dt Positive interval length in hours.
#' @return List with state and named numeric flux vector; depths in mm.
#' @export
# One step of PACK over dt hours, in sub-steps short enough for the explicit drainage scheme to be
# stable (at most max_step_min long, and short enough that the drainage rates times the sub-step
# stay below one). Precipitation and temperature are constant across the step.
pack_step <- function(model, state, precipitation_mm, temperature_c, dt = 1) {
  .check(S7::S7_inherits(model, FlodePackModel), "Expected FlodePackModel")
  .check(S7::S7_inherits(state, FlodePackState), "Expected FlodePackState")
  .check(.scalar(precipitation_mm, 0), "precipitation_mm must be finite and nonnegative")
  .check(.scalar(temperature_c), "temperature_c must be finite")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be positive and finite")
  rate <- model@lower_rate_h + model@upper_rate_h
  steps <- ceiling(max(dt * 60 / model@max_step_min, dt * rate, 1))
  .check(is.finite(steps) && steps <= 100000, "Too many snow substeps; inspect dt and rates")
  h <- dt / steps
  corrected <- precipitation_mm * model@precipitation_factor
  .check(is.finite(corrected), "Corrected precipitation overflow")
  p <- corrected / steps
  old <- state@dry_mm + state@wet_mm
  totals <- c(
    snowfall_mm = 0, rainfall_mm = 0, melt_mm = 0,
    drainage_mm = 0, bypass_mm = 0, effective_rain_mm = 0
  )
  for (i in seq_len(steps)) {
    # Partition: all precipitation is snow below the snow threshold, all rain above it.
    theta <- state@dry_mm + state@wet_mm
    cover <- .pack_cover(model, state)
    snow <- if (temperature_c < model@snow_threshold_c) p else 0
    rain <- p - snow
    if (snow > 0) {
      # Consecutive snowfall grows one excursion; a depleted excursion starts anew.
      if (state@fresh_mm == 0 || theta < state@anchor_mm + state@fresh_mm - 1e-10) {
        state@anchor_mm <- theta
        state@anchor_fraction <- cover
        state@fresh_mm <- snow
      } else {
        state@fresh_mm <- state@fresh_mm + snow
      }
      cover <- 1
    }
    # Melt: degree-hour melt over the covered area, never more than the dry store holds. Melt and
    # rain on the covered area join the wet store; rain on bare ground bypasses the pack.
    dry <- state@dry_mm + snow
    melt <- min(dry, model@melt_factor_mmh_c *
                  max(0, temperature_c - model@melt_threshold_c) * h * cover)
    dry <- dry - melt
    wet <- state@wet_mm + rain * cover + melt
    # Drainage: a slow rate on all liquid water, plus a fast rate on liquid above what the pack can
    # retain. None when frozen.
    threshold <- model@retention_fraction * (wet + dry)
    drainage <- if (temperature_c < model@drain_threshold_c) {
      0
    } else {
      min(wet, h * (model@lower_rate_h * wet + model@upper_rate_h * max(0, wet - threshold)))
    }
    bypass <- rain * (1 - cover)
    state@dry_mm <- dry
    state@wet_mm <- wet - drainage
    if (dry + state@wet_mm <= state@anchor_mm) state@fresh_mm <- 0
    totals <- totals + c(snow, rain, melt, drainage, bypass, drainage + bypass)
  }
  # Water balance: pack before, plus corrected precipitation, minus pack after, minus water released
  # to the ground (drainage plus bypass). Zero to rounding.
  residual <- old + corrected - sum(state@dry_mm, state@wet_mm) - totals[["effective_rain_mm"]]
  list(state = state, flux = c(totals,
    precipitation_corrected_mm = corrected,
    dry_snow_mm = state@dry_mm, wet_snow_mm = state@wet_mm,
    snow_cover_fraction = .pack_cover(model, state), snow_balance_error_mm = residual
  ))
}
