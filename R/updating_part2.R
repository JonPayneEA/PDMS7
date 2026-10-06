# ============================================================ #
# Tool:         updating
# Description:  Configurable PDM framework: updating
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #
#' Update forecast
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param updater A compatible FlodeStateUpdater or FlodeErrorUpdater object.
#' @param observed_history Complete numeric observed flow history in chronological order, cubic
#' metres per second.
#' @param simulated_history Complete aligned simulated history, cubic metres per second.
#' @param forecast Finite numeric base forecast, cubic metres per second, in increasing lead
#' order.
#'
#' @return A list containing updated forecast, error_forecast, and historical innovations.
#'
#' @examples
#' update_forecast(error_updater(ar = 0.7), c(2, 3), c(1, 2), c(2, 2))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
update_forecast <- function(updater, observed_history, simulated_history, forecast) {
  .check(
    is.numeric(forecast) &&
      length(forecast) >
        0 && all(is.finite(forecast)),
    "forecast must be finite"
  )
  eta <- .errors(observed_history, simulated_history, updater@scale, updater@offset)
  n <- length(eta)
  errors <- c(eta, rep(0, length(forecast)))
  innovations <- numeric(length(errors))
  predicted <- numeric(length(errors))
  # R convention eta[t] = sum(ar*eta[t-i]) + sum(ma*a[t-j]) + a[t].  Moore's phi
  # coefficients have the opposite sign: ar = -phi.
  for (t in seq_along(errors)) {
    for (i in seq_along(updater@ar)) {
      if (t >
            i) {
        predicted[t] <- predicted[t] + updater@ar[i] * errors[t - i]
      }
    }
    for (j in seq_along(updater@ma)) {
      if (t >
            j) {
        predicted[t] <- predicted[t] + updater@ma[j] * innovations[t - j]
      }
    }
    if (t <= n) {
      innovations[t] <- errors[t] - predicted[t]
    } else {
      errors[t] <- predicted[t]
    }
  }
  correction <- errors[n + seq_along(forecast)]
  updated <- if (updater@scale == "additive") {
    forecast + correction
  } else {
    .check(
      all(forecast + updater@offset > 0),
      "Log forecast must be positive plus offset"
    )
    (forecast + updater@offset) * exp(correction) -
      updater@offset
  }
  list(forecast = updated, error_forecast = correction, innovations = innovations[seq_len(n)])
}
#' Fit error updater
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param observed Observed discharges in cubic metres per second, aligned to forcing or
#' simulation.
#' @param simulated Complete simulated discharges aligned with observed, cubic metres per second.
#' @param order Integer vector c(p,q) of nonnegative AR and MA orders.
#' @param scale Error scale: additive or log.
#' @param offset Nonnegative offset in cubic metres per second for log error updating.
#'
#' @return A list with an S7 updater and fitted stats::arima object.
#'
#' @examples
#' fit_error_updater(c(1, 2, 1, 3, 2, 1, 2, 4), rep(1, 8), order = c(0, 0))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
fit_error_updater <- function(
  observed, simulated, order = c(3, 0),
  scale = "additive", offset = 0
) {
  .check(
    length(order) ==
      2 && all(is.finite(order)) &&
      all(order >= 0) &&
      all(order == floor(order)),
    "order must be c(p,q) of nonnegative integers"
  )
  .check(
    scale %in% c("additive", "log") &&
      .scalar(offset, 0),
    "Invalid error scale/offset"
  )
  eta <- .errors(observed, simulated, scale, offset)
  fit <- stats::arima(
    eta,
    order = c(order[1], 0, order[2]),
    include.mean = FALSE, method = "ML"
  )
  ar <- unname(fit$coef[grepl("^ar", names(fit$coef))])
  ma <- unname(fit$coef[grepl("^ma", names(fit$coef))])
  list(
    updater = error_updater(ar, ma, scale, offset),
    fit = fit
  )
}
