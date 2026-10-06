# ============================================================ #
# Tool:         routing
# Description:  Configurable PDM framework: routing
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #
.route_result <- function(x, old, new, u, dt) {
  v <- sum(old) +
    u * dt - sum(new)
  .check(
    is.finite(v) &&
      v >= -1e-07 * max(
        1, sum(abs(old)),
        u * dt
      ),
    "FlodeRouting solver produced invalid volume"
  )
  # Tiny cancellation errors must not become negative pending delay water.
  v <- max(0, v)
  list(storage = new, outflow = v, q_mean = v / dt, q_end = routing_flow(x, new))
}

# Exact state-space solution of the same two-reservoir system as Eq. 26-27.  Unlike
# treating endpoint samples as interval totals, this also accounts for the exact
# discharged volume via continuity.
S7::method(route_step, FlodeCascadeRouting) <- function(x, storage, inflow, dt) {
  .route_check(x, storage, inflow, dt)
  e1 <- exp(-dt / x@k1)
  e2 <- exp(-dt / x@k2)
  # Stable divided difference, including the repeated-root case.
  z <- dt * (1 / x@k2 - 1 / x@k1)
  cross <- if (abs(z) <
                 1e-06) {
    e2 * dt / x@k1 * (1 + z / 2 + z^2 / 6 + z^3 / 24)
  } else {
    x@k2 / (x@k1 - x@k2) * (e1 - e2)
  }
  new <- c(
    storage[1] * e1 + inflow * x@k1 * (-expm1(-dt / x@k1)),
    storage[2] * e2 + inflow * x@k2 * (-expm1(-dt / x@k2)) +
      (storage[1] - inflow * x@k1) * cross
  )
  new <- pmax(0, new)
  .route_result(x, storage, new, inflow, dt)
}
