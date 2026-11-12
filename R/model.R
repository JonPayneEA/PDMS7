# ============================================================ #
# Tool:         model
# Description:  Model and state classes, constructors, state checks and the outlet delay
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
# The complete model: a soil store (distribution), a recharge rule, a fast surface store, a slow
# groundwater store, and catchment-wide settings:
#   be       exponent of the evaporation function (Eq. 8);
#   fc       rainfall factor applied before anything else;
#   td       outlet time delay, hours, applied to both pathways;
#   qc       constant flow added at the outlet, m3/s (an effluent or a compensation flow);
#   area_km2 catchment area, which converts mm per hour to m3/s;
#   dt       model time step, hours.
# The validator rejects combinations the equations cannot support.
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
      return(.demand_problems(self))
    }
    NULL
  }
)

# What stops a model using demand recharge, or NULL: it needs a single groundwater store, not
# the extension, with room for the saturation recharge within a step.
.demand_problems <- function(self) {
  if (S7::S7_inherits(self@groundwater, FlodeExtendedGroundwater)) {
    return("Demand recharge cannot be used with the groundwater extension")
  }
  if (S7::S7_inherits(self@groundwater, FlodeCascadeRouting)) {
    return("Demand recharge requires a single groundwater store")
  }
  if (storage_for_flow(self@groundwater, self@recharge@qsat) <= 0) {
    return("Demand recharge requires Sgmax > 0")
  }
  if (self@recharge@qsat * self@dt > capacity_mean(self@distribution)) {
    return("Demand recharge requires qsat*dt <= Smax")
  }
  NULL
}
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
# The model's state between steps: soil, surface and groundwater storages (mm), and four queues
# that implement the outlet delay. delay_surface and delay_groundwater hold volumes (mm) still to
# leave; the *_end queues hold endpoint flows (mm/h) for the q_end_m3s output. step counts steps.
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
    errors <- .bounded_params(self, list(
      soil = .scalar(self@soil, 0),
      surface = .store_vector(self@surface),
      groundwater = .store_vector(self@groundwater),
      step = .whole(self@step, 0, Inf)
    ))
    if (!is.null(errors)) {
      return(errors)
    }
    for (name in c("delay_surface", "delay_groundwater", "delay_surface_end",
                   "delay_groundwater_end")) {
      value <- S7::prop(self, name)
      if (!.finite_vector(value) || any(value < 0)) {
        return(paste(name, "must be finite and nonnegative"))
      }
    }
    NULL
  }
)

# A non-empty numeric vector with no missing or infinite values.
.finite_vector <- function(x) is.numeric(x) && length(x) > 0 && all(is.finite(x))

# One store, or the two stores of a cascade.
.store_vector <- function(x) .finite_vector(x) && length(x) %in% 1:2

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
#' @details The Smith closed-form cubic solver loses accuracy as the time step grows: its
#' error scales with the square of dt. pdm_model() warns, once per R session, when a Smith
#' solver is combined with dt above 1 hour, where errors can exceed 1 per cent of peak flow.
#' Use solver = "adaptive" (the default) for longer steps.
#'
#' @examples
#' pdm_model(area_km2 = 44, dt = 0.25)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
pdm_model <- function(
  distribution = FlodeParetoCapacity(cmin = 0, cmax = 300, b = 0.4),
  recharge = FlodeStandardRecharge(kg = 4000, bg = 1, st = 0),
  surface = FlodeCascadeRouting(k1 = 2, k2 = 4),
  groundwater = cubic_routing(), be = 1, fc = 1, td = 0, qc = 0, area_km2 = 1, dt = 1
) {
  model <- FlodePdmModel(
    distribution = distribution, recharge = recharge, surface = surface, groundwater = groundwater,
    be = be, fc = fc, td = td, qc = qc, area_km2 = area_km2, dt = dt
  )
  # The Smith cubic solver loses accuracy at long steps; warn once per session when dt > 1 h.
  .warn_smith_step(model)
  model
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
# A simple starting state: the soil store a given fraction full, routing stores empty unless given,
# and empty delay queues. Each queue has floor(td / dt) + 1 slots, enough to hold water for the
# whole delay. For a starting state matched to an observed flow, see initial_state_from_flow().
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
    0, floor(model@td / model@dt) + 1L
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
# Checks that a state fits a model before a step: soil within capacity, routing storages of the
# right length, and delay queues of the length the model's td and dt imply. A state saved under a
# different time step cannot be reused, because its queues would mean different delays.
.validate_state <- function(model, state) {
  .check(
    S7::S7_inherits(state, FlodePdmState),
    "state must be a FlodePdmState"
  )
  .scheck(model@distribution, state@soil)
  .check(
    length(state@soil) == 1L && .scalar(state@step, 0) && state@step == floor(state@step),
    "Invalid state dimensions"
  )
  .route_check(model@surface, state@surface, 0, model@dt)
  .route_check(model@groundwater, state@groundwater, 0, model@dt)
  n <- floor(model@td / model@dt) + 1L
  for (name in c("delay_surface",
                 "delay_groundwater",
                 "delay_surface_end",
                 "delay_groundwater_end")) {
    v <- S7::prop(state, name)
    .nonnegative(v, name)
    .check(
      length(v) == n, "Delay state incompatible with td/dt; reinitialise after changing time step"
    )
  }
  invisible(TRUE)
}
# All water held in the model (mm): stores plus volumes waiting in the delay queues. The endpoint
# queues hold rates, not volumes, so they are left out. Used for the per-step water balance.
.total_storage <- function(state) {
  sum(
    state@soil, state@surface, state@groundwater, state@delay_surface, state@delay_groundwater
  )
}
# Pushes one step's output volume into a delay queue and pops the volume due now. A delay of
# ratio = td / dt steps is split between the two neighbouring whole steps in proportion, so a
# 1.5-step delay releases half the water after one step and half after two. Volume is conserved.
.delay <- function(pending, value, ratio) {
  n <- floor(ratio)
  fraction <- ratio - n
  work <- c(pending, 0)
  work[n + 1L] <- work[n + 1L] + (1 - fraction) * value
  work[n + 2L] <- work[n + 2L] + fraction * value
  list(out = work[1L], pending = work[-1L])
}
