# ============================================================ #
# Tool:         helper-fixtures
# Description:  Configurable PDM framework: helper-fixtures
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

check <- function(x) testthat::expect_true(isTRUE(x))
expect_close <- function(a, b, tol = 1e-07) {
  testthat::expect_lt(
    max(abs(a - b)),
    tol
  )
}
fails <- function(expr) testthat::expect_error(force(expr))
make_distributions <- function() {
  list(
    ParetoCapacity(cmin = 10, cmax = 140, b = 0.4),
    RectangularCapacity(cmin = 10, cmax = 190),
    TriangularCapacity(cmin = 10, cmax = 190),
    ExponentialCapacity(mean = 100),
    LognormalCapacity(
      meanlog = log(100) -
        0.5, sdlog = 1
    )
  )
}
make_forcing <- function() {
  data.frame(
    rain = c(
      0, 200, rep(
        c(0, 0, 1, 20),
        5
      ),
      500, rep(0, 10)
    ),
    pet = rep(2, 33)
  )
}
make_routes <- function() {
  list(
    linear_routing(), quadratic_routing(), cubic_routing(), power_routing(m = 2.5),
    ExponentialRouting(a = 0.05, gamma = -5),
    CascadeRouting(k1 = 2, k2 = 2)
  )
}
