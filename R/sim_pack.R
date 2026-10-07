# ============================================================ #
# Tool:         sim_pack
# Description:  Simulate snow alone or coupled to PDM
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Add snow simulation and restart
# Tier:         3
# Inputs:       Interval precipitation mm, temperature Celsius and PET mm
# Outputs:      data.table fluxes and restart attributes
# Dependencies: S7; data.table
# ============================================================ #

#' Simulate PACK snow
#' @param precipitation_mm,temperature_c Aligned, nonempty numeric forcing vectors.
#' @param params FlodePackModel or named PACK parameter list.
#' @param timestep_min Positive integer interval minutes.
#' @param state NULL for an empty pack, or a complete FlodePackState.
#' @return data.table with snow fluxes, final_state and water_balance attributes.
#' @export
sim_pack <- function(precipitation_mm, temperature_c, params = pack_presets(),
                     timestep_min = 60L, state = NULL) {
  .nonnegative(precipitation_mm, "precipitation_mm")
  .check(
    length(precipitation_mm) > 0 && is.numeric(temperature_c) &&
      length(temperature_c) == length(precipitation_mm) && all(is.finite(temperature_c)),
    "Snow forcing must be finite, aligned and nonempty"
  )
  .check(
    .scalar(timestep_min, 0, strict = TRUE) && timestep_min == floor(timestep_min),
    "timestep_min must be a positive integer"
  )
  model <- if (S7::S7_inherits(params, FlodePackModel)) params else pack_from_config(params)
  if (is.null(state)) state <- FlodePackState()
  rows <- vector("list", length(precipitation_mm))
  for (i in seq_along(precipitation_mm)) {
    result <- pack_step(model, state, precipitation_mm[i], temperature_c[i], timestep_min / 60)
    state <- result$state
    rows[[i]] <- as.list(result$flux)
  }
  output <- data.table::rbindlist(rows)
  data.table::setattr(output, "final_state", state)
  data.table::setattr(output, "water_balance", sum(output$snow_balance_error_mm))
  output
}

#' Simulate coupled PACK and PDM
#'
#' PACK precipitation_factor is applied before snow partitioning; PDM fc subsequently
#' multiplies effective rain. Set fc=1 to avoid a second correction. Combined balance
#' explicitly includes this second correction as an external input adjustment.
#' @inheritParams sim_pack
#' @param pet_mm Nonnegative aligned PET depths.
#' @param params Named list with exactly pdm and snow configurations.
#' @param state NULL or the complete final_state list from a previous coupled run.
#' @param datetime Optional POSIXct interval-end timestamps, validated by sim_pdm.
#' @param warmup_steps Number of initial rows flagged for exclusion from scoring.
#' @return data.table with PDM and snow fluxes, a combined balance residual, and
#' final_state list containing pdm and snow states. Rain-only sim_pdm is unchanged.
#' @export
sim_snow_pdm <- function(precipitation_mm, temperature_c, pet_mm,
                         params = list(pdm = pdm_presets("standard"), snow = pack_presets()),
                         timestep_min = 60L, state = NULL, datetime = NULL, warmup_steps = 0L) {
  .check(is.list(params) && length(params) == 2 &&
           setequal(names(params), c("pdm", "snow")), "params must contain only pdm and snow")
  if (is.null(state)) state <- list(pdm = NULL, snow = NULL)
  .check(
    is.list(state) && length(state) == 2 && setequal(names(state), c("pdm", "snow")),
    "state must contain pdm and snow"
  )
  snow <- sim_pack(precipitation_mm, temperature_c, params$snow, timestep_min, state$snow)
  output <- sim_pdm(snow$effective_rain_mm, pet_mm, params$pdm, timestep_min,
    warmup_steps = warmup_steps, datetime = datetime, state = state$pdm
  )
  checkpoint <- list(pdm = attr(output, "final_state"), snow = attr(snow, "final_state"))
  for (name in names(snow)) data.table::set(output, j = name, value = snow[[name]])
  adjustment <- output$rain_corrected_mm - output$effective_rain_mm
  data.table::set(output, j = "pdm_correction_mm", value = adjustment)
  data.table::set(output,
    j = "combined_balance_error_mm",
    value = output$balance_error_mm + output$snow_balance_error_mm
  )
  data.table::setattr(output, "final_state", checkpoint)
  data.table::setattr(output, "water_balance", c(
    residual_mm = sum(output$combined_balance_error_mm),
    max_abs_step_mm = max(abs(output$combined_balance_error_mm))
  ))
  output
}
