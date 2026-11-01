# ============================================================ #
# Tool:         distributions_2
# Description:  Configurable PDM framework: distributions_2
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# Positive net depth fills the common water level; negative net depth directly reduces
# basin storage, as required by Eq. 15.
#' Soil step
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param distribution An S7 capacity distribution object.
#' @param storage Basin soil storage in mm for soil_step.
#' @param net_depth Signed net interval depth in mm, after evaporation and recharge.
#'
#' @return A list with storage and runoff, both in mm.
#'
#' @examples
#' soil_step(FlodeParetoCapacity(0, 140, 0.4), storage = 50, net_depth = 10)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
soil_step <- function(distribution, storage, net_depth) {
  .scheck(distribution, storage)
  .check(
    length(storage) ==
      1L && .scalar(net_depth),
    "soil_step needs scalar inputs"
  )
  if (net_depth <= 0) {
    return(
      list(
        storage = max(0, storage + net_depth),
        runoff = 0
      )
    )
  }
  c <- capacity_from_storage(distribution, storage)
  next_s <- storage_from_capacity(distribution, c + net_depth)
  next_s <- min(storage + net_depth, max(storage, next_s))
  list(storage = next_s, runoff = max(0, net_depth - (next_s - storage)))
}
S7::method(capacity_from_storage, FlodeLognormalCapacity) <- function(x, s) {
  .scheck(x, s)
  vapply(s, function(si) .lognormal_inverse(x, si), numeric(1))
}

# Inverse of the lognormal storage function by safeguarded Newton iteration. dS/dC is the
# survival probability 1 - F(C), known exactly. S is increasing and concave, so Newton steps
# from below never overshoot; a bracket and bisection guard against slow progress in the tail.
# Converges to machine precision. Mirrored in src/pdm_core.c.
.lognormal_inverse <- function(x, si) {
  if (si == 0) {
    return(0)
  }
  if (si >= capacity_mean(x)) {
    return(Inf)
  }
  lo <- 0
  hi <- .lognormal_bracket(x, si)
  c <- min(si, hi)
  for (i in seq_len(200L)) {
    f <- storage_from_capacity(x, c) - si
    if (f == 0) {
      return(c)
    }
    if (f < 0) lo <- c else hi <- c
    nxt <- .lognormal_newton(x, c, f, lo, hi)
    if (abs(nxt - c) <= 4 * .Machine$double.eps * nxt) {
      return(nxt)
    }
    c <- nxt
  }
  c
}

# Upper end of a bracket for the lognormal inverse: doubles from max(1, Smax) until it holds.
.lognormal_bracket <- function(x, si) {
  hi <- max(1, capacity_mean(x))
  while (storage_from_capacity(x, hi) < si) {
    hi <- hi * 2
    .check(is.finite(hi), "Could not bracket lognormal inverse")
  }
  hi
}

# One Newton step with slope 1 - F(C), replaced by bisection if it leaves the bracket.
.lognormal_newton <- function(x, c, f, lo, hi) {
  slope <- stats::pnorm((log(c) - x@meanlog) / x@sdlog, lower.tail = FALSE)
  nxt <- c - f / slope
  if (!(is.finite(nxt) && nxt > lo && nxt < hi)) {
    nxt <- (lo + hi) / 2
  }
  nxt
}
