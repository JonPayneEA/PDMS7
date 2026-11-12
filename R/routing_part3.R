# ============================================================ #
# Tool:         routing
# Description:  Exact two-store cascade step and the shared routing result
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         1
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #
# Assembles the result of a routing step from the old and new storage. The volume released over
# the step is not integrated separately: continuity gives it as old storage plus inflow minus new
# storage. That keeps the water balance exact by construction. A materially negative volume can
# only come from a solver fault, so it stops the run.
.route_result <- function(x, old, new, u, dt) {
  v <- sum(old) + u * dt - sum(new)
  .check(
    is.finite(v) && v >= -1e-07 * max(1, sum(abs(old)), u * dt),
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
  # Store 1: s1' = u - s1 / k1. Store 2: s2' = s1 / k1 - s2 / k2. Both are solved exactly for a
  # constant inflow. The term 'cross' carries store 1's departure from its equilibrium u k1 into
  # store 2: k2 / (k1 - k2) (e1 - e2).
  e1 <- exp(-dt / x@k1)
  e2 <- exp(-dt / x@k2)
  # Stable divided difference, including the repeated-root case.
  z <- dt * (1 / x@k2 - 1 / x@k1)
  cross <- if (abs(z) < 1e-06) {
    e2 * dt / x@k1 * (1 + z / 2 + z^2 / 6 + z^3 / 24)
  } else {
    x@k2 / (x@k1 - x@k2) * (e1 - e2)
  }
  new <- c(
    storage[1] * e1 + inflow * x@k1 * (-expm1(-dt / x@k1)),
    storage[2] * e2 + inflow * x@k2 * (-expm1(-dt / x@k2)) + (storage[1] - inflow * x@k1) * cross
  )
  # Clamp rounding-level negatives; .route_result() still checks the volume released.
  new <- pmax(0, new)
  .route_result(x, storage, new, inflow, dt)
}
