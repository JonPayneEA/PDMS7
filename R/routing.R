# ============================================================ #
# Tool:         routing
# Description:  Configurable PDM framework: routing
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

#' Create FlodeRouting
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#'
#' @return An S7 component object.
#'
#' @details This is an abstract extension class. Construct a concrete subclass.
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeRouting <- S7::new_class("FlodeRouting", package = "pdmS7", abstract = TRUE)
#' Create FlodePowerRouting
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param k Positive power-reservoir coefficient, in mm^(1-m) per hour.
#' @param m Positive power-reservoir exponent; 1, 2, and 3 give linear, quadratic, and cubic
#' forms.
#' @param solver Character scalar: adaptive or smith. The Smith approximation requires m = 3.
#' @param rtol Positive relative integration tolerance; dimensionless.
#' @param atol Positive absolute integration tolerance in mm.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodePowerRouting(0.0001, 3, 'adaptive', 1e-8, 1e-10)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodePowerRouting <- S7::new_class(
  "FlodePowerRouting",
  parent = FlodeRouting, package = "pdmS7", properties = list(
    k = S7::class_numeric,
    m = S7::class_numeric,
    solver = S7::class_character,
    rtol = S7::class_numeric,

    atol = S7::class_numeric
  ),
  validator = function(self) {
    .bounded_params(
      self, list(
        k = .scalar(self@k, 0, strict = TRUE),
        m = .scalar(self@m, 0, strict = TRUE),
        solver = length(self@solver) ==
          1 && self@solver %in% c("adaptive", "smith"),
        smith_cubic = self@solver != "smith" || self@m == 3,
        rtol = .scalar(self@rtol,
                       0,
                       strict = TRUE),

        atol = .scalar(self@atol, 0, strict = TRUE)
      )
    )
  }
)
#' Create FlodeCascadeRouting
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param k1 Positive first linear-reservoir time constant, hours.
#' @param k2 Positive second linear-reservoir time constant, hours.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeCascadeRouting(2, 4)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeCascadeRouting <- S7::new_class(
  "FlodeCascadeRouting",
  parent = FlodeRouting,
  package = "pdmS7",
  properties = list(k1 = S7::class_numeric,
                    k2 = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        k1 = .scalar(self@k1, 0, strict = TRUE),
        k2 = .scalar(self@k2, 0, strict = TRUE)
      )
    )
  }
)
#' Create FlodeExponentialRouting
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param a Positive exponential-routing slope, per mm.
#' @param gamma Finite exponential-routing log-flow intercept, flow measured in mm/hour.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeExponentialRouting(0.05, -5)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeExponentialRouting <- S7::new_class(
  "FlodeExponentialRouting",
  parent = FlodeRouting,
  package = "pdmS7",
  properties = list(a = S7::class_numeric,
                    gamma = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        a = .scalar(self@a, 0, strict = TRUE),
        gamma = .scalar(self@gamma)
      )
    )
  }
)

#' Power routing
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param k Positive power-reservoir coefficient, in mm^(1-m) per hour.
#' @param m Positive power-reservoir exponent; 1, 2, and 3 give linear, quadratic, and cubic
#' forms.
#' @param solver Character scalar: adaptive or smith. The Smith approximation requires m = 3.
#' @param rtol Positive relative integration tolerance; dimensionless.
#' @param atol Positive absolute integration tolerance in mm.
#'
#' @return An S7 component object.
#'
#' @examples
#' power_routing(k = 0.0001, m = 2.5)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
power_routing <- function(k = 1 / 10000, m = 3, solver = "adaptive", rtol = 1e-08, atol = 1e-10) {
  FlodePowerRouting(k = k, m = m, solver = solver, rtol = rtol, atol = atol)
}
#' Linear routing
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param kb Positive reciprocal rate coefficient: hour mm^(m-1).
#'
#' @return An S7 component object.
#'
#' @examples
#' linear_routing(kb = 24)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
linear_routing <- function(kb = 24) power_routing(k = 1 / kb, m = 1)
#' Quadratic routing
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param kb Positive reciprocal rate coefficient: hour mm^(m-1).
#'
#' @return An S7 component object.
#'
#' @examples
#' quadratic_routing(kb = 1000)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
quadratic_routing <- function(kb = 1000) power_routing(k = 1 / kb, m = 2)
#' Cubic routing
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param kb Positive reciprocal rate coefficient: hour mm^(m-1).
#' @param solver Character scalar: adaptive or smith. The Smith approximation requires m = 3.
#'
#' @return An S7 component object.
#'
#' @examples
#' cubic_routing(kb = 10000)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
cubic_routing <- function(kb = 10000, solver = "adaptive") {
  power_routing(k = 1 / kb, m = 3, solver = solver)
}

#' Route step
#'
#' Call route_step(x, storage, inflow, dt): storage in mm, inflow in mm/hour, dt in hours.
#' Returns storage, outflow (mm), q_mean and q_end (mm/hour).
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' route_step(linear_routing(24), storage = 1, inflow = 0.1, dt = 1)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
route_step <- S7::new_generic("route_step", "x")
#' Routing flow
#'
#' Call routing_flow(x, storage), returning endpoint discharge in mm/hour.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' routing_flow(linear_routing(24), storage = 24)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
routing_flow <- S7::new_generic("routing_flow", "x")
#' Storage for flow
#'
#' Call storage_for_flow(x, q), q in mm/hour. Cascade inverse initializes both stores at
#' equilibrium.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' storage_for_flow(linear_routing(24), q = 1)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
storage_for_flow <- S7::new_generic("storage_for_flow", "x")
S7::method(routing_flow, FlodePowerRouting) <- function(x, storage) {
  x@k *
    storage^x@m
}
S7::method(storage_for_flow, FlodePowerRouting) <- function(x, q) {
  .nonnegative(q, "q")
  (q / x@k)^(1 / x@m)
}
S7::method(routing_flow, FlodeCascadeRouting) <- function(x, storage) storage[2] / x@k2
S7::method(storage_for_flow, FlodeCascadeRouting) <- function(x, q) {
  .check(
    .scalar(q, 0),
    "q must be nonnegative scalar"
  )
  c(q * x@k1, q * x@k2)
}
S7::method(routing_flow, FlodeExponentialRouting) <- function(x, storage) {
  exp(x@gamma + x@a * storage)
}
S7::method(storage_for_flow, FlodeExponentialRouting) <- function(x, q) {
  .check(
    all(is.finite(q)) &&
      all(q > 0),
    "Exponential routing needs positive q"
  )
  (log(q) -
     x@gamma) / x@a
}
.route_check <- function(x, storage, inflow, dt) {
  .check(
    .scalar(inflow, 0) &&
      .scalar(dt, 0, strict = TRUE),
    "inflow >= 0 and dt > 0 required"
  )
  .check(
    is.numeric(storage) &&
      all(is.finite(storage)),
    "FlodeRouting storage must be finite"
  )
  n <- if (S7::S7_inherits(x, FlodeCascadeRouting)) {
    2L
  } else {
    1L
  }
  .check(
    length(storage) ==
      n, paste("FlodeRouting state requires", n, "storage values")
  )
  if (!S7::S7_inherits(x, FlodeExponentialRouting)) {
    .nonnegative(storage, "FlodeRouting storage")
  }
}
