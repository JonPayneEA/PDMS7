# ============================================================ #
# Tool:         model_2
# Description:  Configurable PDM framework: model_2
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

#' Run a forcing sequence
#' @inheritParams pdm_step
#' @param forcing Data frame with rain and pet interval depths in mm and optional POSIXct time.
#' @return A list containing output, final state, initial state, model and water balance.
#' @export
run_pdm <- function(model, forcing, state = initial_state(model)) {
  .check(is.data.frame(forcing) && all(c("rain", "pet") %in% names(forcing)),
         "forcing must be a data.frame with rain and pet columns (mm per interval)")
  .check(nrow(forcing) > 0L, "forcing must have at least one row")
  .nonnegative(forcing$rain, "rain")
  .nonnegative(forcing$pet, "pet")
  if ("time" %in% names(forcing)) {
    .check(inherits(forcing$time, "POSIXt") && all(is.finite(as.numeric(forcing$time))),
           "time must be complete finite POSIXct/POSIXlt")
    if (nrow(forcing) > 1) {
      .check(all(abs(as.numeric(diff(forcing$time), units = "hours") - model@dt) < 1e-8),
             "time spacing must equal model@dt hours")
    }
  }
  initial <- state
  rows <- vector("list", nrow(forcing))
  for (i in seq_len(nrow(forcing))) {
    step <- pdm_step(model, state, forcing$rain[i], forcing$pet[i])
    state <- step$state
    rows[[i]] <- step$flux
  }
  output <- data.table::setDF(data.table::rbindlist(rows))
  if ("time" %in% names(forcing)) {
    datetime <- as.POSIXct(as.numeric(forcing$time), origin = "1970-01-01", tz = "UTC")
    output <- cbind(time = datetime, output)
  }
  list(output = output, state = state, initial_state = initial, model = model,
       water_balance = c(residual_mm = sum(output$balance_error_mm),
                         max_abs_step_mm = max(abs(output$balance_error_mm))))
}

# Spin-up uses complete forcing cycles; caller selects duration/convergence.
#' Spin up
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param model A FlodePdmModel compatible with the supplied state.
#' @param forcing Data frame or data.table with rain and pet depths in mm per interval; optional
#' POSIXct time.
#' @param cycles Positive integer number of complete spin-up forcing cycles.
#' @param state A compatible FlodePdmState; NULL in sim_pdm initializes the model.
#'
#' @return A FlodePdmState after the requested cycles.
#'
#' @examples
#' spin_up(pdm_model(), data.frame(rain = c(0, 10), pet = c(0.05, 0.05)), cycles = 2)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
spin_up <- function(model, forcing, cycles = 5, state = initial_state(model)) {
  .check(
    .scalar(cycles, 1) &&
      cycles == floor(cycles),
    "cycles must be a positive integer"
  )
  for (i in seq_len(cycles)) state <- run_pdm(model, forcing, state)$state
  state@step <- 0
  state
}
