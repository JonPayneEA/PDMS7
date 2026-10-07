# ============================================================ #
# Tool:         calibration_metrics
# Description:  Evaluate discharge objectives and Pareto dominance
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Add multi-objective calibration metrics
# Tier:         3
# Inputs:       Aligned simulated and observed discharge in m3/s
# Outputs:      Loss values, all minimized; Pareto membership
# Dependencies: stats
# ============================================================ #

#' Evaluate hydrological calibration losses
#'
#' Missing observations are excluded; missing simulations at scored rows are errors.
#' NSE loss is 1-NSE. KGE loss is the Euclidean distance using correlation, standard
#' deviation ratio and mean ratio (original KGE). Bias is absolute relative volume
#' error. Peak loss compares global maxima, not event-specific peaks. All losses
#' are minimized. RMSE and log-RMSE have different scales: supply explicit scaling
#' in multi-objective calibration rather than combining raw metrics implicitly.
#' @param simulated,observed Numeric aligned nonnegative discharge vectors.
#' @param objectives Unique metric names: rmse, log_rmse, nse_loss, kge_loss,
#' abs_bias, peak_relative_error.
#' @param warmup Nonnegative number of initial rows excluded from scoring.
#' @param log_offset Positive discharge offset for logarithms, in m3/s.
#' @return Named numeric loss vector.
#' @export
pdm_objectives <- function(simulated, observed,
                           objectives = c("nse_loss", "log_rmse", "abs_bias"),
                           warmup = 0L, log_offset = 0.01) {
  allowed <- c("rmse", "log_rmse", "nse_loss", "kge_loss", "abs_bias", "peak_relative_error")
  .check(is.character(objectives) && length(objectives) > 0 &&
           !anyDuplicated(objectives) && all(objectives %in% allowed), "Invalid objectives")
  .check(is.numeric(observed) && is.numeric(simulated) &&
           length(observed) == length(simulated), "Flow vectors must have equal length")
  .check(
    .scalar(warmup, 0) && warmup == floor(warmup) && warmup < length(observed),
    "Invalid warmup"
  )
  .check(.scalar(log_offset, 0, strict = TRUE), "log_offset must be positive")
  keep <- is.finite(observed) & seq_along(observed) > warmup
  obs <- observed[keep]
  sim <- simulated[keep]
  .check(
    length(obs) >= 2 && all(obs >= 0) && all(is.finite(sim)) && all(sim >= 0),
    "Need two nonnegative scored observations and finite nonnegative simulations"
  )
  if (any(c("nse_loss", "kge_loss") %in% objectives)) {
    .check(stats::sd(obs) > 0, "NSE/KGE require variable observations")
  }
  if (any(c("abs_bias", "peak_relative_error", "kge_loss") %in% objectives)) {
    .check(sum(obs) > 0, "Relative metrics require positive observed volume")
  }
  vapply(objectives, function(metric) {
    switch(metric,
      rmse = sqrt(mean((sim - obs)^2)),
      log_rmse = sqrt(mean((log(sim + log_offset) - log(obs + log_offset))^2)),
      nse_loss = sum((sim - obs)^2) / sum((obs - mean(obs))^2),
      kge_loss = {
        .check(stats::sd(sim) > 0, "KGE is undefined for constant simulation")
        sqrt((stats::cor(sim, obs) - 1)^2 + (stats::sd(sim) / stats::sd(obs) - 1)^2 +
               (mean(sim) / mean(obs) - 1)^2)
      },
      abs_bias = abs(sum(sim) / sum(obs) - 1),
      peak_relative_error = abs(max(sim) / max(obs) - 1)
    )
  }, numeric(1))
}

#' Identify nondominated loss vectors
#' @param losses Finite numeric matrix, rows candidates and columns losses to minimize.
#' @return Logical vector; tied loss vectors are retained.
#' @export
pareto_front <- function(losses) {
  .check(is.matrix(losses) && is.numeric(losses) && ncol(losses) > 0 &&
           all(is.finite(losses)), "losses must be a finite numeric matrix")
  vapply(seq_len(nrow(losses)), function(i) {
    !any(vapply(setdiff(seq_len(nrow(losses)), i), function(j) {
      all(losses[j, ] <= losses[i, ]) && any(losses[j, ] < losses[i, ])
    }, logical(1)))
  }, logical(1))
}
