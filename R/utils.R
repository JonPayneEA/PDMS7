# ============================================================ #
# Tool:         utils
# Description:  Configurable PDM framework: utils
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# All internal depths are mm over catchment area; time is hours.
.scalar <- function(x, lo = -Inf, hi = Inf, strict = FALSE) {
  is.numeric(x) &&
    length(x) ==
      1L && is.finite(x) &&
    (if (strict) {
      x > lo
    } else {
      x >= lo
    }) && x <= hi
}
.check <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
.nonnegative <- function(x, name) {
  .check(
    is.numeric(x) &&
      !anyNA(x) &&
      all(is.finite(x)) &&
      all(x >= 0),
    paste(name, "must contain finite nonnegative numbers")
  )
}
.capacity_x <- function(x) {
  .check(
    is.numeric(x) &&
      !anyNA(x) &&
      all(x >= 0),
    "Capacity must be nonnegative (Inf is allowed)"
  )
}
.scheck <- function(x, s) {
  .nonnegative(s, "Storage")
  .check(
    all(s <= capacity_mean(x)),
    "Soil storage exceeds capacity_mean(distribution)"
  )
}
.root <- function(f, lo, hi) {
  stats::uniroot(
    f, c(lo, hi),
    tol = 1e-10
  )$root
}
.bounded_params <- function(x, checks) {
  bad <- names(checks)[!vapply(checks, isTRUE, logical(1))]
  if (length(bad)) {
    paste("Invalid parameter(s):", paste(bad, collapse = ", "))
  } else {
    NULL
  }
}
