# ============================================================ #
# Tool:         sim_pdm
# Description:  Configurable PDM framework: sim_pdm
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

#' Sim pdm
#'
#' All intervals are retained. Warm-up is flagged rather than removed. The attributes
#' final_state, model, and water_balance support restart and diagnostics. With no datetime,
#' timestamps remain UTC NA values. The numerical engine retains the paper's hour-based
#' coefficients.
#'
#' @param rainfall_mm Non-empty finite nonnegative numeric rainfall depths in mm per interval.
#' @param pet_mm Finite nonnegative numeric PET depths in mm per interval, equal length to
#' rainfall_mm.
#' @param params A named configuration list or FlodePdmModel. For a list, timestep_min sets dt.
#' @param timestep_min Positive integer-valued interval in minutes; must match a supplied model.
#' @param warmup_steps Nonnegative integer number of rows flagged is_warmup, less than the
#' forcing length.
#' @param datetime Optional aligned POSIXct interval-end timestamps. Converted to UTC without
#' changing instants.
#' @param state A compatible FlodePdmState; NULL in sim_pdm initializes the model.
#'
#' @return A data.table containing datetime (UTC), qsim_cms, qsim_end_cms, soil_moisture_mm,
#' groundwater_mm, is_warmup, and detailed fluxes. See Details for attributes.
#'
#' @examples
#' sim_pdm(c(0, 10, 5), rep(0.05, 3), pdm_presets('standard'), 60L)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
sim_pdm <- function(
  rainfall_mm, pet_mm, params, timestep_min, warmup_steps = 0L, datetime = NULL, state = NULL
) {
  .check(
    length(rainfall_mm) >
      0L, "rainfall_mm must be non-empty"
  )
  .check(
    length(rainfall_mm) ==
      length(pet_mm),
    "rainfall_mm and pet_mm must have equal length"
  )
  .nonnegative(rainfall_mm, "rainfall_mm")
  .nonnegative(pet_mm, "pet_mm")
  .check(
    .scalar(timestep_min, 0, .Machine$integer.max, strict = TRUE) &&
      timestep_min == floor(timestep_min),
    "timestep_min must be a positive integer number of minutes"
  )
  .check(
    .scalar(warmup_steps, 0) &&
      warmup_steps == floor(warmup_steps) &&
      warmup_steps < length(rainfall_mm),
    "warmup_steps must be an integer less than input length"
  )
  timestep_min <- as.integer(timestep_min)
  if (S7::S7_inherits(params, FlodePdmModel)) {
    model <- params
    .check(
      abs(model@dt * 60 - timestep_min) <
        1e-08, "timestep_min must match the model; rebuild the model to change time step"
    )
  } else {
    .check(
      is.list(params),
      "params must be a model or a named configuration list"
    )
    params$dt <- as.double(timestep_min) / 60
    model <- pdm_from_config(params)
  }
  forcing_dt <- data.table::data.table(rain = rainfall_mm, pet = pet_mm)
  if (!is.null(datetime)) {
    .check(
      inherits(datetime, "POSIXct") &&
        length(datetime) ==
          length(rainfall_mm) &&
        all(is.finite(as.numeric(datetime))),
      "datetime must be complete POSIXct with input length"
    )
    datetime <- as.POSIXct(
      as.numeric(datetime),
      origin = "1970-01-01", tz = "UTC"
    )
    data.table::set(forcing_dt, j = "time", value = datetime)
  }
  if (is.null(state)) {
    state <- initial_state(model)
  }
  result <- run_pdm(model, forcing_dt, state)
  output_dt <- data.table::as.data.table(result$output)
  data.table::setnames(
    output_dt, c("q_m3s", "q_end_m3s", "soil_mm"),
    c("qsim_cms", "qsim_end_cms", "soil_moisture_mm")
  )
  if ("time" %in% names(output_dt)) {
    data.table::setnames(output_dt, "time", "datetime")
  } else {
    # No artificial epoch is attached to undated hydrological forcing.
    data.table::set(
      output_dt,
      j = "datetime", value = as.POSIXct(
        rep(NA_real_, nrow(output_dt)),
        origin = "1970-01-01", tz = "UTC"
      )
    )
  }
  data.table::set(
    output_dt,
    j = "is_warmup", value = seq_len(nrow(output_dt)) <=
      warmup_steps
  )
  data.table::setattr(output_dt, "final_state", result$state)
  data.table::setattr(output_dt, "model", model)
  data.table::setattr(output_dt, "water_balance", result$water_balance)
  logger::log_debug("Simulated {nrow(output_dt)} intervals at {timestep_min} minutes")
  output_dt
}
