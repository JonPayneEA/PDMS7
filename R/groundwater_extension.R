# ============================================================ #
# Tool:         groundwater_extension
# Description:  The PDM groundwater extension: abstractions, negative storage and ephemeral
#               flow, underflow, external springs and well level
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-12
# Modified:     2026-11-12 - First version, from Moore and Bell (2002) and the PDM for PCs
#                            scientific guide (UKCEH, 2022), section 3 and Appendix B
# Tier:         3
# Inputs:       A linear, quadratic or cubic groundwater store; recharge and recorded
#               abstraction per step (mm)
# Outputs:      Storage, which may fall below zero; baseflow, spring flow, underflow,
#               abstraction, storage deficit and well level
# Dependencies: S7
# ============================================================ #

#' The PDM groundwater extension
#'
#' Extends a linear, quadratic or cubic groundwater store as in the extended PDM of Moore and
#' Bell (2002) and the PDM for PCs scientific guide (UKCEH, 2022, section 3 and Appendix B), for
#' catchments with pumped abstractions, ephemeral streams and losses below or beyond the gauge.
#'
#' **Abstraction and negative storage.** The input to the store is recharge less abstraction,
#' `u = d - A`, with `A = cA + fA Ar` where `Ar` is the recorded abstraction (Eq. 9). A negative
#' input drains the store, and when it empties flow at the outlet stops: the time to cessation
#' within the step, `T'`, is exact for each store (Eqs. B.1, B.3 and B.5), and the storage at the
#' end of that step is `u (dt - T')` (Eqs. B.2, B.4 and B.6). Below zero the storage changes by
#' continuity alone, with no outflow, until recharge refills it and flow starts again for the
#' rest of that step.
#'
#' **Underflow** leaves through a lower outlet below the gauge, linearly in the water above it:
#' `qu = (S + Dbu) / ku` while `S > -Dbu` (Eq. 10, with `Dbu = Du - Sbmax`, the
#' baseflow-underflow deficit). It is worked out from the storage at the start of the step and
#' taken from the step's input, as the PDM does for evaporation and recharge; it never draws
#' the store below the underflow outlet within the step. Neither source states how underflow is
#' integrated within a step: this follows the model's convention for its other losses.
#'
#' **External springs.** A fraction `alpha_b` of the store's outflow leaves the catchment as
#' springs and the rest is baseflow at the outlet. A negative fraction brings water in: an
#' inter-catchment exchange (scientific guide, section 4).
#'
#' **Well level.** The storage deficit is `D = Sbmax - S` (Eq. 8), and the depth to the water
#' table `W = Ys D` (Eq. 11). With the datum `hw`, the height of the ground at the well (m), the
#' modelled well level is `hw - W`, in m.
#'
#' The exponential store cannot be extended: it needs positive flow at all times, so it cannot
#' run dry (scientific guide, Appendices A and B). With a negative input the cubic store is
#' stepped by Smith's method, Eqs. 4, 6 and 7, as published, whichever solver it uses for
#' positive input.
#'
#' Models with the extension run in R, not the compiled engine. Abstraction enters as a forcing
#' column `abstraction`, mm per step over the catchment.
#'
#' @param store A linear, quadratic or cubic groundwater store, from [linear_routing()],
#'   [quadratic_routing()], [cubic_routing()] or [power_routing()] with `m` 1, 2 or 3.
#' @param ku Underflow time constant, h; `Inf` (the default) for no underflow.
#' @param dbu Baseflow-underflow deficit, mm: how far below the baseflow outlet the underflow
#'   outlet lies.
#' @param alpha_b Fraction of the store's outflow lost to springs outside the catchment; negative
#'   for an import. At most 1.
#' @param ca Constant abstraction, mm/h.
#' @param fa Factor on the recorded abstraction.
#' @param smax_b Maximum groundwater storage, mm, for the deficit and well level.
#' @param ys Specific yield of the aquifer; 0 (the default) for no well level.
#' @param hw Well level datum: the height of the ground at the well, m.
#' @return A `FlodeExtendedGroundwater` store.
#' @references Moore, R.J. and Bell, V.A. (2002). Incorporation of groundwater losses and well
#'   level data in rainfall-runoff models illustrated using the PDM. Hydrology and Earth System
#'   Sciences, 6(1), 25-38. UKCEH (2022). A Guide to the PDM Rainfall-Runoff Model, in PDM for
#'   PCs, version 3.0.3.
#' @examples
#' store <- groundwater_extension(cubic_routing(5000), ku = 12000, dbu = 400, ca = 0.002,
#'                                smax_b = 1600, ys = 0.02, hw = 84)
#' cfg <- pdm_presets("standard")
#' cfg$groundwater$extension <- list(ku = 12000, dbu = 400, ca = 0.002)
#' model <- pdm_from_config(cfg)
#' @export
groundwater_extension <- function(store, ku = Inf, dbu = 0, alpha_b = 0, ca = 0, fa = 1,
                                  smax_b = 0, ys = 0, hw = 0) {
  FlodeExtendedGroundwater(store = store, ku = ku, dbu = dbu, alpha_b = alpha_b, ca = ca,
                           fa = fa, smax_b = smax_b, ys = ys, hw = hw)
}

#' @rdname groundwater_extension
#' @export
FlodeExtendedGroundwater <- S7::new_class(
  "FlodeExtendedGroundwater",
  parent = FlodeRouting,
  package = "pdmS7",
  properties = list(
    store = FlodePowerRouting, ku = S7::class_numeric, dbu = S7::class_numeric,
    alpha_b = S7::class_numeric, ca = S7::class_numeric, fa = S7::class_numeric,
    smax_b = S7::class_numeric, ys = S7::class_numeric, hw = S7::class_numeric
  ),
  validator = function(self) .extension_problems(self)
)

# What is wrong with an extended store's parameters, or NULL.
.extension_problems <- function(x) {
  if (!x@store@m %in% c(1, 2, 3)) {
    return("The groundwater extension needs a linear, quadratic or cubic store (m = 1, 2 or 3)")
  }
  if (!(identical(x@ku, Inf) || .scalar(x@ku, 0, strict = TRUE))) {
    return("ku must be a positive number of hours, or Inf")
  }
  ok <- c(dbu = .scalar(x@dbu, 0), alpha_b = .scalar(x@alpha_b) && x@alpha_b < 1,
          ca = .scalar(x@ca), fa = .scalar(x@fa, 0), smax_b = .scalar(x@smax_b, 0),
          ys = .scalar(x@ys, 0), hw = .scalar(x@hw))
  if (all(ok)) return(NULL)
  paste("Invalid groundwater extension parameter:", paste(names(ok)[!ok], collapse = ", "),
        "(dbu, fa, smax_b and ys nonnegative; alpha_b below 1)")
}

# The outflow at the catchment outlet: the share of the store's outflow that is not lost to
# springs. Nothing flows while the storage is at or below zero.
S7::method(routing_flow, FlodeExtendedGroundwater) <- function(x, storage) {
  if (storage <= 0) return(0)
  (1 - x@alpha_b) * routing_flow(x@store, storage)
}

# The storage giving a baseflow q at the outlet.
S7::method(storage_for_flow, FlodeExtendedGroundwater) <- function(x, q) {
  storage_for_flow(x@store, q / (1 - x@alpha_b))
}

# One step with no abstraction, for callers that know only the recharge.
S7::method(route_step, FlodeExtendedGroundwater) <- function(x, storage, inflow, dt) {
  .route_check(x, storage, inflow, dt)
  .extended_step(x, storage, inflow, 0, dt)
}

# One step of the extended store. d is the recharge rate (mm/h) and abstraction the recorded
# abstraction over the step (mm). Returns the fields of a routing step, with outflow and q_end
# the baseflow at the outlet, and the losses: springs, underflow and abstraction (mm).
.extended_step <- function(x, storage, d, abstraction, dt) {
  st <- x@store
  s <- storage
  a <- x@ca + x@fa * abstraction / dt
  # Underflow from the start-of-step storage, never below the underflow outlet within the step.
  above <- max(0, s + x@dbu)
  qu <- if (is.finite(x@ku)) min(above / x@ku, above / dt) else 0
  u <- d - a - qu
  new <- .extended_storage(st, s, u, dt)
  released <- max(0, s + u * dt - new)
  list(storage = new, outflow = (1 - x@alpha_b) * released,
       q_mean = (1 - x@alpha_b) * released / dt, q_end = routing_flow(x, new),
       spring = x@alpha_b * released, underflow = qu * dt, abstraction = a * dt,
       deficit = x@smax_b - new)
}

# The storage at the end of a step with net input u (mm/h), which may be negative.
.extended_storage <- function(st, s, u, dt) {
  if (s > 0 && u >= 0) return(route_step(st, s, u, dt)$storage)
  if (s > 0) {
    k <- st@k
    m <- st@m
    q <- k * s^m
    cease <- .time_to_cessation(m, k, s, q, u)
    if (cease < dt) return(u * (dt - cease))
    return(.negative_input_storage(m, k, s, q, u, dt))
  }
  # At or below zero: continuity until the store refills, then a normal step for the rest.
  if (u <= 0) return(s + u * dt)
  refill <- -s / u
  if (refill >= dt) return(s + u * dt)
  route_step(st, 0, u, dt - refill)$storage
}

# Time to flow cessation with a negative input u, from storage s and outflow q (Appendix B):
# Eq. B.1 (linear), B.3 (quadratic) and B.5 (cubic, Smith's method). Inf when Smith's step
# never reaches zero.
.time_to_cessation <- function(m, k, s, q, u) {
  if (m == 1) return(-log(u / (u - q)) / k)
  if (m == 2) return(sqrt(1 / (-k * u)) * atan(sqrt(q / (-u))))
  inside <- 1 + 3 * q / (u - q)
  if (inside <= 0) return(Inf)
  -log(inside) / (3 * k * s^2)
}

# The storage after a whole step of negative input in which flow does not cease: the exact
# linear solution, Eq. A.5 for the quadratic store, and Smith's Eq. A.8 for the cubic.
.negative_input_storage <- function(m, k, s, q, u, dt) {
  if (m == 1) return(s * exp(-k * dt) + u * (-expm1(-k * dt)) / k)
  if (m == 2) {
    q_next <- -u * tan(atan(sqrt(q / (-u))) - sqrt(-u * k) * dt)^2
    return(sqrt(q_next / k))
  }
  lambda <- 3 * k * s^2
  s + (-expm1(-lambda * dt) / lambda) * (u - k * s^3)
}
