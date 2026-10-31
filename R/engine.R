# ============================================================ #
# Tool:         engine
# Description:  Dispatch between the R time loop and the compiled engine
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-31
# Modified:     2026-10-31 - Initial compiled engine dispatch
# Tier:         3
# Inputs:       FlodePdmModel, FlodePdmState, forcing depths in mm per interval
# Outputs:      run_pdm() output columns and final state, identical to the R loop
# Dependencies: cpp11 (build time); data.table
# ============================================================ #

#' @useDynLib pdmS7, .registration = TRUE
NULL

# The compiled engine covers Pareto capacity, standard recharge, cascade surface routing and
# power-law groundwater routing (cubic by default). Other models use the R loop. Exact class
# matching keeps any future subclass on the R loop until it is ported and tested.
# options(pdmS7.engine = "r") forces the R loop, which remains the reference implementation.
.engine_supported <- function(model) {
  if (identical(getOption("pdmS7.engine", "auto"), "r")) {
    return(FALSE)
  }
  first <- function(x) class(x)[1L]
  first(model@distribution) == "pdmS7::FlodeParetoCapacity" &&
    first(model@recharge) == "pdmS7::FlodeStandardRecharge" &&
    first(model@surface) == "pdmS7::FlodeCascadeRouting" &&
    first(model@groundwater) == "pdmS7::FlodePowerRouting"
}

.engine_flux_names <- c(
  "step", "rain_mm", "rain_corrected_mm", "pet_mm", "aet_mm", "aet_requested_mm",
  "recharge_mm", "recharge_requested_mm", "direct_runoff_mm", "surface_input_mm",
  "groundwater_input_mm", "surface_out_mm", "baseflow_out_mm", "q_natural_m3s", "q_m3s",
  "q_end_m3s", "qs_end_unlagged_mmh", "qb_end_unlagged_mmh", "soil_mm", "surface_mm",
  "groundwater_mm", "delay_mm", "saturated_fraction", "balance_error_mm"
)

.engine_run <- function(model, rain, pet, state, full) {
  .validate_state(model, state)
  d <- model@distribution
  r <- model@recharge
  s <- model@surface
  g <- model@groundwater
  par <- c(
    d@cmin, d@cmax, d@b, r@kg, r@bg, r@st, s@k1, s@k2, g@k, g@m, g@rtol, g@atol,
    model@be, model@fc, model@td, model@qc, model@area_km2, model@dt,
    as.numeric(g@solver == "smith")
  )
  packed <- c(
    state@soil, state@surface, state@groundwater, state@step,
    state@delay_surface, state@delay_groundwater,
    state@delay_surface_end, state@delay_groundwater_end
  )
  res <- pdm_engine_run(as.double(rain), as.double(pet), as.double(par), packed, full)
  out <- res$state
  n <- length(state@delay_surface)
  pending <- function(j) out[5L + (j - 1L) * n + seq_len(n)]
  final <- FlodePdmState(
    soil = out[1L], surface = out[2:3], groundwater = out[4L],
    delay_surface = pending(1L), delay_groundwater = pending(2L),
    delay_surface_end = pending(3L), delay_groundwater_end = pending(4L),
    step = out[5L]
  )
  if (full) {
    columns <- stats::setNames(res$columns, .engine_flux_names)
    output <- data.table::setDF(data.table::setDT(columns))
  } else {
    output <- list(q_m3s = res$q_m3s, q_end_m3s = res$q_end_m3s)
  }
  list(output = output, state = final)
}

# Simulated flow only, for calibration. Applies the same checks as run_pdm() and returns the
# same values as run_pdm(...)$output[[flow]] without building the full flux table.
.run_flow <- function(model, forcing, state, flow) {
  if (!.engine_supported(model)) {
    return(run_pdm(model, forcing, state)$output[[flow]])
  }
  .check_forcing(model, forcing)
  .engine_run(model, forcing$rain, forcing$pet, state, full = FALSE)$output[[flow]]
}
