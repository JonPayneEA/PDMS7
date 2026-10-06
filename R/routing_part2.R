# ============================================================ #
# Tool:         routing_part2
# Description:  Configurable PDM framework: routing_part2
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# Eq. 27, usable independently to reproduce endpoint transfer recursion.
#' Transfer coefficients
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param k1 Positive first linear-reservoir time constant, hours.
#' @param k2 Positive second linear-reservoir time constant, hours.
#' @param dt Positive model interval in hours. Internal paper equations use hours.
#'
#' @return Named numeric vector delta1, delta2, omega0, omega1 for endpoint recursion.
#'
#' @examples
#' transfer_coefficients(k1 = 2, k2 = 4, dt = 0.25)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
transfer_coefficients <- function(k1, k2, dt = 1) {
  x <- FlodeCascadeRouting(k1 = k1, k2 = k2)
  .check(
    .scalar(dt, 0, strict = TRUE),
    "dt must be positive"
  )
  e1 <- exp(-dt / k1)
  e2 <- exp(-dt / k2)
  w0 <- route_step(
    x, c(0, 0),
    1, dt
  )$q_end
  c(
    delta1 = -(e1 + e2), delta2 = e1 * e2, omega0 = w0, omega1 = (1 - e1) * (1 - e2) -
      w0
  )
}
.rk4 <- function(s, h, u, k, m) {
  f <- function(z) {
    u -
      k * max(0, z)^m
  }
  a <- f(s)
  b <- f(s + h * a / 2)
  c <- f(s + h * b / 2)
  d <- f(s + h * c)
  s + h * (a + 2 * b + 2 * c + d) / 6
}
