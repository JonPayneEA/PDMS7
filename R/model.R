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

#' Create FlodePdmModel
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param distribution An S7 capacity distribution object.
#' @param recharge An S7 recharge component.
#' @param surface An S7 fast routing component, or initial routing storage vector in mm for state
#' functions.
#' @param groundwater An S7 slow routing component, or initial storage vector in mm for state
#' functions.
#' @param be Positive exponent in the actual evaporation function.
#' @param fc Nonnegative dimensionless rainfall correction factor.
#' @param td Nonnegative common outlet delay in hours.
#' @param qc Finite signed external constant flow in cubic metres per second.
#' @param area_km2 Positive catchment area in square kilometres.
#' @param dt Positive model interval in hours. Internal paper equations use hours.
#'
#' @return An S7 component object.
#'
#' @examples
#' pdm_model()
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodePdmModel <- S7::new_class(
  "FlodePdmModel",
  package = "pdmS7", properties = list(
    distribution = FlodeCapacityDistribution, recharge = FlodeRecharge, surface = FlodeRouting,
    groundwater = FlodeRouting,
    be = S7::class_numeric,
    fc = S7::class_numeric,
    td = S7::class_numeric,

    qc = S7::class_numeric, area_km2 = S7::class_numeric, dt = S7::class_numeric
  ),
  validator = function(self) {
    errors <- .bounded_params(
      self, list(
        be = .scalar(self@be, 0, strict = TRUE),
        fc = .scalar(self@fc, 0),
        td = .scalar(self@td, 0),
        qc = .scalar(self@qc),
        area_km2 = .scalar(self@area_km2, 0, strict = TRUE),
        dt = .scalar(self@dt, 0, strict = TRUE)
      )
    )
    if (!is.null(errors)) {
      return(errors)
    }
    if (S7::S7_inherits(self@recharge, FlodeStandardRecharge) &&
          self@recharge@st > capacity_mean(self@distribution)) {
      return("st cannot exceed Smax")
    }
    if (S7::S7_inherits(self@recharge, FlodeDemandRecharge)) {
      if (S7::S7_inherits(self@groundwater, FlodeCascadeRouting)) {
        return("Demand recharge requires a single groundwater store")
      }
      if (storage_for_flow(self@groundwater, self@recharge@qsat) <=
            0) {
        return("Demand recharge requires Sgmax > 0")
      }
      if (self@recharge@qsat * self@dt > capacity_mean(self@distribution)) {
        return("Demand recharge requires qsat*dt <= Smax")
      }
    }
    NULL
  }
)
#' Create FlodePdmState
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param soil Scalar nonnegative basin soil storage in mm.
#' @param surface An S7 fast routing component, or initial routing storage vector in mm for state
#' functions.
#' @param groundwater An S7 slow routing component, or initial storage vector in mm for state
#' functions.
#' @param delay_surface Nonnegative pending fast-path outlet volumes in mm.
#' @param delay_groundwater Nonnegative pending slow-path outlet volumes in mm.
#' @param delay_surface_end Nonnegative pending fast-path endpoint rates in mm/hour.
#' @param delay_groundwater_end Nonnegative pending slow-path endpoint rates in mm/hour.
#' @param step Nonnegative integer-valued completed interval count.
#'
#' @return An S7 component object.
#'
#' @examples
#' initial_state(pdm_model())
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodePdmState <- S7::new_class(
  "FlodePdmState",
  package = "pdmS7", properties = list(
    soil = S7::class_numeric, surface = S7::class_numeric, groundwater = S7::class_numeric,
    delay_surface = S7::class_numeric,
    delay_groundwater = S7::class_numeric,
    delay_surface_end = S7::class_numeric,

    delay_groundwater_end = S7::class_numeric, step = S7::class_numeric
  ),
  validator = function(self) {
    finite <- function(x) {
      is.numeric(x) &&
        length(x) >
          0 && all(is.finite(x))
    }
    errors <- .bounded_params(
      self, list(
        soil = .scalar(self@soil, 0),
        surface = finite(self@surface) &&
          length(self@surface) %in%
            1:2, groundwater = finite(self@groundwater) &&
          length(self@groundwater) %in%
            1:2, step = .scalar(self@step, 0) &&
          self@step == floor(self@step)
      )
    )
    if (!is.null(errors)) {
      return(errors)
    }
    for (name in c("delay_surface",
                   "delay_groundwater",
                   "delay_surface_end",
                   "delay_groundwater_end")) {
      value <- S7::prop(self, name)
      if (!finite(value) ||
            any(value < 0)) {
        return(paste(name, "must be finite and nonnegative"))
      }
    }
    NULL
  }
)

#' Pdm model
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param distribution An S7 capacity distribution object.
#' @param recharge An S7 recharge component.
#' @param surface An S7 fast routing component, or initial routing storage vector in mm for state
#' functions.
#' @param groundwater An S7 slow routing component, or initial storage vector in mm for state
#' functions.
#' @param be Positive exponent in the actual evaporation function.
#' @param fc Nonnegative dimensionless rainfall correction factor.
#' @param td Nonnegative common outlet delay in hours.
#' @param qc Finite signed external constant flow in cubic metres per second.
#' @param area_km2 Positive catchment area in square kilometres.
#' @param dt Positive model interval in hours. Internal paper equations use hours.
#'
#' @return A validated FlodePdmModel.
#'
#' @examples
#' pdm_model(area_km2 = 44, dt = 0.25)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
pdm_model <- function(
  distribution = FlodeParetoCapacity(cmin = 0, cmax = 140, b = 0.4),
  recharge = FlodeStandardRecharge(kg = 24, bg = 1, st = 0),
  surface = FlodeCascadeRouting(k1 = 2, k2 = 4),
  groundwater = cubic_routing(), be = 1, fc = 1, td = 0, qc = 0, area_km2 = 1, dt = 1
) {
  FlodePdmModel(
    distribution = distribution, recharge = recharge, surface = surface, groundwater = groundwater,
    be = be, fc = fc, td = td, qc = qc, area_km2 = area_km2, dt = dt
  )
}
#' Initial state
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param model A FlodePdmModel compatible with the supplied state.
#' @param soil_fraction Initial fraction of basin capacity between zero and one.
#' @param surface An S7 fast routing component, or initial routing storage vector in mm for state
#' functions.
#' @param groundwater An S7 slow routing component, or initial storage vector in mm for state
#' functions.
#'
#' @return A validated FlodePdmState.
#'
#' @examples
#' initial_state(pdm_model(), soil_fraction = 0.5)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
initial_state <- function(model, soil_fraction = 0.5, surface = NULL, groundwater = NULL) {
  .check(
    .scalar(soil_fraction, 0, 1),
    "soil_fraction must lie in [0,1]"
  )
  if (is.null(surface)) {
    surface <- if (S7::S7_inherits(model@surface, FlodeCascadeRouting)) {
      c(0, 0)
    } else {
      0
    }
  }
  if (is.null(groundwater)) {
    groundwater <- if (S7::S7_inherits(model@groundwater, FlodeCascadeRouting)) {
      c(0, 0)
    } else {
      0
    }
  }
  .route_check(model@surface, surface, 0, model@dt)
  .route_check(model@groundwater, groundwater, 0, model@dt)
  pending <- rep(
    0, floor(model@td / model@dt) +
      1L
  )
  FlodePdmState(
    soil = soil_fraction * capacity_mean(model@distribution),
    surface = surface,
    groundwater = groundwater,
    delay_surface = pending,
    delay_groundwater = pending,

    delay_surface_end = pending, delay_groundwater_end = pending, step = 0
  )
}
.validate_state <- function(model, state) {
  .check(
    S7::S7_inherits(state, FlodePdmState),
    "state must be a FlodePdmState"
  )
  .scheck(model@distribution, state@soil)
  .check(
    length(state@soil) ==
      1L && .scalar(state@step, 0) &&
      state@step == floor(state@step),
    "Invalid state dimensions"
  )
  .route_check(model@surface, state@surface, 0, model@dt)
  .route_check(model@groundwater, state@groundwater, 0, model@dt)
  n <- floor(model@td / model@dt) +
    1L
  for (name in c("delay_surface",
                 "delay_groundwater",
                 "delay_surface_end",
                 "delay_groundwater_end")) {
    v <- S7::prop(state, name)
    .nonnegative(v, name)
    .check(
      length(v) ==
        n, "Delay state incompatible with td/dt; reinitialise after changing time step"
    )
  }
  invisible(TRUE)
}
.total_storage <- function(state) {
  sum(
    state@soil, state@surface, state@groundwater, state@delay_surface, state@delay_groundwater
  )
}
.delay <- function(pending, value, ratio) {
  n <- floor(ratio)
  fraction <- ratio - n
  work <- c(pending, 0)
  work[n + 1L] <- work[n + 1L] + (1 - fraction) * value
  work[n + 2L] <- work[n + 2L] + fraction * value
  list(out = work[1L], pending = work[-1L])
}
