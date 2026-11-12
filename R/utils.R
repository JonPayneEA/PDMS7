# ============================================================ #
# Tool:         utils
# Description:  Argument checks shared by the whole package
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         1
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# Units throughout the package: depths are mm over the catchment area, and time is in hours.
# Conversion to m3/s happens only at the model's outlet (see the area_km2 scaling in the core).

# TRUE when x is one finite number within [lo, hi], or (lo, hi] when strict is TRUE.
# The workhorse of argument checking: a single call states the range a parameter may take.
# The range test comes last, so a non-number or a vector returns FALSE before it is compared.
.scalar <- function(x, lo = -Inf, hi = Inf, strict = FALSE) {
  is.numeric(x) && length(x) == 1L && is.finite(x) && (if (strict) {
    x > lo
  } else {
    x >= lo
  }) && x <= hi
}

# Stops with a plain message, without the call, when ok is not exactly TRUE. isTRUE() means a
# check that returns NA, or a vector, fails rather than slipping through.
.check <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)

# Inputs such as rain and PET: every value finite and at least zero.
.nonnegative <- function(x, name) {
  .check(
    is.numeric(x) && !anyNA(x) && all(is.finite(x)) && all(x >= 0),
    paste(name, "must contain finite nonnegative numbers")
  )
}

# Finite numbers of either sign: PE, whose negative values are condensation.
.finite_depths <- function(x, name) {
  .check(is.numeric(x) && !anyNA(x) && all(is.finite(x)),
         paste(name, "must contain finite numbers"))
}

# Store capacities (mm) at which a distribution is evaluated. Inf is allowed, because the
# unbounded distributions (exponential, lognormal) are integrated to infinity.
.capacity_x <- function(x) {
  .check(
    is.numeric(x) && !anyNA(x) && all(x >= 0),
    "Capacity must be nonnegative (Inf is allowed)"
  )
}

# Soil storage s (mm) must lie between zero and the distribution's mean capacity, which is the
# most water the probability-distributed store can hold (Moore 2007, Eq. 5).
.scheck <- function(x, s) {
  .nonnegative(s, "Storage")
  .check(
    all(s <= capacity_mean(x)),
    "Soil storage exceeds capacity_mean(distribution)"
  )
}

# Used inside S7 validators: given a named list of logical checks, returns NULL when all pass,
# or one message naming every parameter that failed, which S7 then reports.
.bounded_params <- function(x, checks) {
  bad <- names(checks)[!vapply(checks, isTRUE, logical(1))]
  if (length(bad)) {
    paste("Invalid parameter(s):", paste(bad, collapse = ", "))
  } else {
    NULL
  }
}
