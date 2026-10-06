# ============================================================ #
# Tool:         distributions_part2
# Description:  Configurable PDM framework: distributions_part2
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

S7::method(capacity_pdf, FlodeTriangularCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  w <- x@cmax - x@cmin
  pmax(0, 4 * pmin(c - x@cmin, x@cmax - c) / w^2)
}
S7::method(storage_from_capacity, FlodeTriangularCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  w <- x@cmax - x@cmin
  z <- pmin(x@cmax, pmax(x@cmin, c))
  out <- ifelse(
    z <= capacity_mean(x),
    z - 2 * (z - x@cmin)^3 / (3 * w^2), capacity_mean(x) -
      2 * (x@cmax - z)^3 / (3 * w^2)
  )
  ifelse(c < x@cmin, c, out)
}
S7::method(capacity_from_storage, FlodeTriangularCapacity) <- function(x, s) {
  .scheck(x, s)
  vapply(
    s, function(si) {
      if (si <= x@cmin) {
        return(si)
      }
      if (si == capacity_mean(x)) {
        return(x@cmax)
      }
      .root(
        function(c) {
          storage_from_capacity(x, c) -
            si
        }, x@cmin, x@cmax
      )
    }, numeric(1)
  )
}
S7::method(capacity_mean, FlodeLognormalCapacity) <- function(x) exp(x@meanlog + x@sdlog^2 / 2)
S7::method(capacity_cdf, FlodeLognormalCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  stats::plnorm(c, x@meanlog, x@sdlog)
}
S7::method(capacity_pdf, FlodeLognormalCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  stats::dlnorm(c, x@meanlog, x@sdlog)
}
S7::method(storage_from_capacity, FlodeLognormalCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  out <- numeric(length(c))
  i <- c > 0 & is.finite(c)
  z <- (log(c[i]) -
          x@meanlog) / x@sdlog
  out[i] <- capacity_mean(x) *
    stats::pnorm(z - x@sdlog) +
    c[i] * stats::pnorm(z, lower.tail = FALSE)
  out[is.infinite(c)] <- capacity_mean(x)
  pmin(
    capacity_mean(x),
    out
  )
}
