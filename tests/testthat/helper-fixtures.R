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

# Quadrature, inverses and water balance for one capacity law.
check_capacity_law <- function(d) {
  hi <- if (S7::S7_inherits(d, ExponentialCapacity) ||
              S7::S7_inherits(d, LognormalCapacity)) {
    Inf
  } else {
    d@cmax
  }
  lo <- if (is.finite(hi)) {
    d@cmin
  } else {
    0
  }
  expect_close(
    integrate(
      function(c) capacity_pdf(d, c),
      lo, hi,
      rel.tol = 1e-08
    )$value,
    1, 1e-06
  )
  expect_close(
    integrate(
      function(c) {
        1 -
          capacity_cdf(d, c)
      },
      0, hi,
      rel.tol = 1e-08
    )$value,
    capacity_mean(d),
    1e-05
  )
  for (c in c(0, 5, 20, 80, 120, 220)) {
    val <- integrate(
      function(z) {
        1 -
          capacity_cdf(d, z)
      },
      0, c,
      rel.tol = 1e-08
    )$value
    expect_close(
      storage_from_capacity(d, c),
      val, 1e-05
    )
  }
  ss <- capacity_mean(d) *
    c(0, 0.001, 0.2, 0.8, 0.999, 1)
  expect_close(
    storage_from_capacity(d, capacity_from_storage(d, ss)),
    ss, 1e-06
  )
  for (s in ss) {
    for (p in c(0.01, 10, 300)) {
      r <- soil_step(d, s, p)
      expect_close(s + p - r$storage - r$runoff, 0)
      check(r$runoff >= 0 && r$storage <= capacity_mean(d))
    }
  }
}

# Water balance and nonnegative stores for one combination of components.
check_conserves <- function(d, re, ro, forcing) {
  if (S7::S7_inherits(re, DemandRecharge) && S7::S7_inherits(ro, CascadeRouting)) {
    return(invisible())
  }
  model <- pdm_model(distribution = d, recharge = re, groundwater = ro, td = 1.5)
  result <- run_pdm(model, forcing)
  check(max(abs(result$output$balance_error_mm)) < 1e-07)
  check(all(result$output$soil_mm >= 0) && all(result$output$q_natural_m3s >= -1e-09))
}
