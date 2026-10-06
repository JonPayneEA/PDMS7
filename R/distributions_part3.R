# ============================================================ #
# Tool:         distributions
# Description:  Configurable PDM framework: distributions
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #
S7::method(capacity_from_storage, FlodeParetoCapacity) <- function(x, s) {
  .scheck(x, s)
  z <- pmin(
    1, pmax(
      0, (s - x@cmin) / (capacity_mean(x) -
                           x@cmin)
    )
  )
  out <- x@cmin + (x@cmax - x@cmin) * (-expm1(
    log1p(-z) / (x@b +
                   1)
  ))
  ifelse(s < x@cmin, s, out)
}
.as_uniform <- function(x) FlodeParetoCapacity(cmin = x@cmin, cmax = x@cmax, b = 1)
S7::method(capacity_cdf, FlodeRectangularCapacity) <- function(x, c) {
  capacity_cdf(
    .as_uniform(x),
    c
  )
}
S7::method(capacity_pdf, FlodeRectangularCapacity) <- function(x, c) {
  capacity_pdf(
    .as_uniform(x),
    c
  )
}
S7::method(capacity_mean, FlodeRectangularCapacity) <- function(x) {
  (x@cmin +
     x@cmax) / 2
}
S7::method(storage_from_capacity, FlodeRectangularCapacity) <- function(x, c) {
  storage_from_capacity(
    .as_uniform(x),
    c
  )
}
S7::method(capacity_from_storage, FlodeRectangularCapacity) <- function(x, s) {
  capacity_from_storage(
    .as_uniform(x),
    s
  )
}

S7::method(capacity_cdf, FlodeExponentialCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  -expm1(-c / x@mean)
}
S7::method(capacity_pdf, FlodeExponentialCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  exp(-c / x@mean) / x@mean
}
S7::method(capacity_mean, FlodeExponentialCapacity) <- function(x) x@mean
S7::method(storage_from_capacity, FlodeExponentialCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  x@mean * (-expm1(-c / x@mean))
}
S7::method(capacity_from_storage, FlodeExponentialCapacity) <- function(x, s) {
  .scheck(x, s)
  -x@mean * log1p(-s / x@mean)
}
S7::method(capacity_mean, FlodeTriangularCapacity) <- function(x) {
  (x@cmin +
     x@cmax) / 2
}
S7::method(capacity_cdf, FlodeTriangularCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  z <- pmin(1, pmax(0, (c - x@cmin) / (x@cmax - x@cmin)))
  ifelse(z <= 0.5, 2 * z^2, 1 - 2 * (1 - z)^2)
}
