# ============================================================ #
# Tool:         groundwater_extension
# Description:  The PDM groundwater extension: abstractions, negative storage and ephemeral
#               flow, underflow, external springs and well level
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-12
# Modified:     2026-11-12 - First version, from Moore and Bell (2002) and the PDM for PCs
#                            scientific guide (UKCEH, 2022), section 3 and Appendix B
#               2026-11-12 - Runs in the compiled engine (interface version 3)
# Tier:         1
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
#' baseflow-underflow deficit). Neither source states how underflow is integrated within a step.
#' Here the store and both its outlets are integrated together, `dS/dt = u - k max(S, 0)^m - qu`,
#' by RK4 with step doubling to the store's tolerances (`rtol`, `atol`), whatever its solver. Each
#' outlet stops at its own threshold within the step, so neither draws the store below it, and
#' the two share the water as the continuous equation does. (Before 0.26.0 the underflow was held
#' at its start-of-step rate, which over a long step could drain the store well below its
#' outlets.)
#'
#' **External springs.** A fraction `alpha_b` of the store's outflow leaves the catchment as
#' springs and the rest is baseflow at the outlet. A negative fraction brings water in: an
#' inter-catchment exchange (scientific guide, section 4). The import is then `-alpha_b` times
#' the store's release: the baseflow exceeds the release, the spring column is negative, and the
#' water balance counts it as a gain. `alpha_b` must lie below 1; there is no lower limit in the
#' model, and calibration searches -1 to 0.9 unless told otherwise.
#'
#' **Well level.** The storage deficit is `D = Sbmax - S` (Eq. 8), and the depth to the water
#' table `W = Ys D` (Eq. 11). With the datum `hw`, the height of the ground at the well (m), the
#' modelled well level is `hw - W`, in m.
#'
#' The exponential store cannot be extended: it needs positive flow at all times, so it cannot
#' run dry (scientific guide, Appendices A and B).
#'
#' **Negative input.** When abstraction exceeds recharge, the linear and quadratic stores cease
#' flowing and drain by the exact published solutions (Eqs. B.1 to B.4). The cubic store follows
#' its solver: with `solver = "smith"`, Smith's method as published (Eqs. 4, 6 and 7); with the
#' adaptive solver, the continuous equation integrated to the store's tolerances, through the
#' moment flow ceases and on into deficit by continuity. (Before 0.26.0 the adaptive cubic store
#' switched to Smith's method whenever its input was negative.) Below zero there is no outflow and
#' the store changes by continuity until it refills, then routes by its own solver for the rest
#' of the step.
#'
#' Models with the extension run in the compiled engine, like the standard model, and give the
#' same results as the step-by-step R loop. Starting from a flow ([initial_state_from_flow()])
#' and state correction use the R loop. Abstraction enters as a forcing column `abstraction`,
#' mm per step over the catchment.
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
  u <- d - a
  # The main outlet and the underflow drain the store together, each down to its own outlet.
  solved <- .extended_solve(st, s, u, dt, x@ku, x@dbu)
  new <- solved$storage
  under <- solved$underflow
  released <- solved$drained
  list(storage = new, outflow = (1 - x@alpha_b) * released,
       q_mean = (1 - x@alpha_b) * released / dt, q_end = routing_flow(x, new),
       spring = x@alpha_b * released, underflow = under, abstraction = a * dt,
       deficit = x@smax_b - new)
}

# The storage at the end of a step with net input u (mm/h), which may be negative.
# The end-of-step storage and the volumes through the main outlet and the underflow (mm). With
# underflow, or with the adaptive solver on a cubic store holding water whose input is negative,
# the step is integrated by .extended_adaptive(); otherwise the published closed forms (exact for
# the linear and quadratic stores, Smith's method for the cubic store with the Smith solver), and
# at or below zero continuity until the store refills, then a normal step.
.extended_solve <- function(st, s, u, dt, ku = Inf, dbu = 0) {
  if (is.finite(ku) || (st@m == 3 && st@solver != "smith" && s > 0 && u < 0)) {
    return(.extended_adaptive(st, s, u, dt, ku, dbu))
  }
  new <- .extended_closed_form(st, s, u, dt)
  list(storage = new, drained = max(0, s + u * dt - new), underflow = 0)
}
.extended_storage <- function(st, s, u, dt, ku = Inf, dbu = 0) {
  .extended_solve(st, s, u, dt, ku, dbu)$storage
}
.extended_closed_form <- function(st, s, u, dt) {
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
# dS/dt of the extended store: net input less the main outlet k max(S, 0)^m and, while the store
# is above the underflow outlet (S > -dbu), the underflow (S + dbu) / ku. Returns the rate, the
# main outlet's rate and the underflow rate.
.extended_rate <- function(st, ku, dbu, u, s) {
  q <- if (s > 0) st@k * s^st@m else 0
  qu <- if (is.finite(ku) && s > -dbu) (s + dbu) / ku else 0
  c(u - q - qu, q, qu)
}
# One classical RK4 step of length h for the storage and the volumes through the main outlet and
# the underflow. RK4 weights the rates linearly, so the storage change equals the input less the
# two volumes to rounding, and an outlet that never runs releases exactly nothing.
.extended_rk4 <- function(st, ku, dbu, u, s, h) {
  a <- .extended_rate(st, ku, dbu, u, s)
  b <- .extended_rate(st, ku, dbu, u, s + h * a[[1]] / 2)
  c <- .extended_rate(st, ku, dbu, u, s + h * b[[1]] / 2)
  d <- .extended_rate(st, ku, dbu, u, s + h * c[[1]])
  w <- h * (a + 2 * b + 2 * c + d) / 6
  c(storage = s + w[[1]], drained = w[[2]], underflow = w[[3]])
}
# The extended store integrated over a step with its outlets coupled, by RK4 with step doubling
# to the store's tolerances, as .power_adaptive(); steps shrink where an outlet stops.
.extended_adaptive <- function(st, s, u, dt, ku, dbu) {
  time <- 0
  h <- dt
  drained <- 0
  under <- 0
  iterations <- 0L
  while (time < dt) {
    iterations <- iterations + 1L
    .check(iterations < 100000L,
           "Groundwater integration did not converge; adjust tolerances/parameters")
    h <- min(h, dt - time)
    one <- .extended_rk4(st, ku, dbu, u, s, h)
    half <- .extended_rk4(st, ku, dbu, u, s, h / 2)
    two <- .extended_rk4(st, ku, dbu, u, half[["storage"]], h / 2)
    two_m <- half[["drained"]] + two[["drained"]]
    two_v <- half[["underflow"]] + two[["underflow"]]
    err <- max(abs(two[["storage"]] - one[["storage"]]), abs(two_m - one[["drained"]]),
               abs(two_v - one[["underflow"]])) / 15
    tol <- st@atol + st@rtol * max(abs(s), abs(two[["storage"]]), drained + two_m, under + two_v)
    if (is.finite(err) && is.finite(two[["storage"]]) && err <= tol) {
      s <- two[["storage"]]
      drained <- drained + two_m
      under <- under + two_v
      time <- time + h
      if (dt - time < 1e-14 * dt) time <- dt
      h <- h * (if (err == 0) 2 else min(2, max(0.2, 0.9 * (tol / err)^0.2)))
    } else {
      h <- h / 2
    }
    .check(h > .Machine$double.eps * max(dt, 1), "Groundwater integration step underflow")
  }
  list(storage = s, drained = drained, underflow = under)
}
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
