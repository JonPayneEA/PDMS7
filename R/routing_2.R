# ============================================================ #
# Tool:         routing_2
# Description:  Configurable PDM framework: routing_2
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# Moore & Bell (2002), Appendix A.6-A.7. S is a signed log-storage coordinate. It must
# not be clipped to zero as if it were a finite tank.
S7::method(route_step, FlodeExponentialRouting) <- function(x, storage, inflow, dt) {
  .route_check(x, storage, inflow, dt)
  logq <- x@gamma + x@a * storage
  .check(
    is.finite(exp(logq)) &&
      exp(logq) >
        0, "Exponential flow overflow/underflow"
  )
  if (inflow == 0) {
    lognext <- logq - log1p(
      x@a * exp(logq) *
        dt
    )
  } else {
    h <- x@a * inflow * dt
    # 1/q_next = exp(-h)/q + (1-exp(-h))/u, using log-sum-exp.
    terms <- c(
      -h - logq, log(-expm1(-h)) -
        log(inflow)
    )
    mx <- max(terms)
    lognext <- -(mx + log(sum(exp(terms - mx))))
  }
  new <- (lognext - x@gamma) / x@a
  .route_result(x, storage, new, inflow, dt)
}
.power_adaptive <- function(x, s, u, dt) {
  target <- (u / x@k)^(1 / x@m)
  if (s == target) {
    return(s)
  }
  time <- 0
  h <- dt
  iterations <- 0L
  while (time < dt) {
    iterations <- iterations + 1L
    .check(
      iterations < 100000L,
      "Routing integration did not converge; adjust tolerances/parameters"
    )
    h <- min(h, dt - time)
    one <- .rk4(s, h, u, x@k, x@m)
    half <- .rk4(s, h / 2, u, x@k, x@m)
    two <- .rk4(half, h / 2, u, x@k, x@m)
    err <- abs(two - one) / 15
    tol <- x@atol + x@rtol * max(abs(s), abs(two))
    inside <- is.finite(two) && two >= min(s, target) && two <= max(s, target)
    if (is.finite(err) && inside && err <= tol) {
      s <- two
      time <- time + h
      if (dt - time < 1e-14 * dt) {
        time <- dt
      }
      h <- h * if (err == 0) {
        2
      } else {
        min(2, max(0.2, 0.9 * (tol / err)^0.2))
      }
    } else {
      h <- h / 2
    }
    .check(h > .Machine$double.eps * max(dt, 1), "Routing step underflow")
  }
  s
}
S7::method(route_step, FlodePowerRouting) <- function(x, storage, inflow, dt) {
  .route_check(x, storage, inflow, dt)
  s <- storage
  u <- inflow
  k <- x@k
  m <- x@m
  if (x@solver == "smith") {
    lambda <- 3 * k * s^2
    phi <- if (lambda == 0) {
      dt
    } else {
      -expm1(-lambda * dt) / lambda
    }
    new <- s + phi * (u - k * s^3)
  } else if (m == 1) {
    new <- s * exp(-k * dt) + u * (-expm1(-k * dt)) / k
  } else if (u == 0) {
    if (s == 0) {
      new <- 0
    } else if (m < 1) {
      new <- max(0, s^(1 - m) - (1 - m) * k * dt)^(1 / (1 - m))
    } else {
      new <- (s^(1 - m) + (m - 1) * k * dt)^(1 / (1 - m))
    }
  } else if (m == 2) {
    equilibrium <- sqrt(u / k)
    t <- tanh(sqrt(u * k) * dt)
    new <- equilibrium * (s + equilibrium * t) / (equilibrium + s * t)
  } else {
    new <- .power_adaptive(x, s, u, dt)
  }
  .route_result(x, storage, new, u, dt)
}
