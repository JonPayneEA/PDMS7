# ============================================================ #
# Tool:         scorecard
# Description:  Diagnostic scores for manual and automatic calibration
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add scorecard for the calibration log
# Tier:         3
# Inputs:       Aligned simulated and observed discharge in m3/s
# Outputs:      Named numeric vector of scores
# Dependencies: stats
# ============================================================ #

#' Score a simulation against observed flow
#'
#' Computes every score used by the calibration log. Unlike [pdm_objectives()], which returns
#' losses to minimise, these are diagnostics in their natural form, signed where the sign
#' tells the calibrator which way to move.
#'
#' | Score | Meaning | Best |
#' |---|---|---|
#' | `nse` | Nash-Sutcliffe efficiency | 1 |
#' | `log_nse` | NSE of log(flow + log_offset), weighting low flows | 1 |
#' | `kge` | Kling-Gupta efficiency (Gupta et al. 2009) | 1 |
#' | `kge_r` | Correlation | 1 |
#' | `kge_alpha` | Ratio of standard deviations, simulated over observed | 1 |
#' | `kge_beta` | Ratio of means, simulated over observed | 1 |
#' | `rmse` | Root mean square error, m3/s | 0 |
#' | `log_rmse` | RMSE of log(flow + log_offset) | 0 |
#' | `volume_error` | Signed volume error as a fraction: positive is too wet | 0 |
#' | `abs_volume_error` | Absolute volume error as a fraction | 0 |
#' | `peak_error` | Signed error in the highest flow as a fraction | 0 |
#' | `fdc_high` | Volume bias of the flow-duration curve above 2 per cent exceedance | 0 |
#' | `fdc_mid` | Bias in the slope of the curve between 20 and 70 per cent exceedance | 0 |
#' | `fdc_low` | Bias in the low-flow segment above 70 per cent exceedance | 0 |
#'
#' The three flow-duration-curve signatures follow Yilmaz et al. (2008), as fractions
#' rather than percentages; logarithms use `log_offset` so zero flows are allowed. A score
#' that is undefined for the data, such as KGE for a constant simulation, is `NA`.
#'
#' @param simulated,observed Numeric aligned nonnegative discharge vectors, m3/s. Missing
#'   observations are excluded; simulations at scored rows must be finite.
#' @param log_offset Positive offset added before logarithms, m3/s.
#' @return Named numeric vector, in the order of the table above.
#' @references Gupta et al. (2009), doi:10.1016/j.jhydrol.2009.08.003; Yilmaz et al.
#'   (2008), doi:10.1029/2007WR006716.
#' @examples
#' obs <- c(1, 3, 8, 5, 3, 2, 1.5, 1.2, 1, 0.9)
#' pdm_scorecard(obs * 1.1, obs)
#' @export
pdm_scorecard <- function(simulated, observed, log_offset = 0.01) {
  .check(is.numeric(observed) && is.numeric(simulated) &&
           length(observed) == length(simulated), "Flow vectors must have equal length")
  .check(.scalar(log_offset, 0, strict = TRUE), "log_offset must be positive")
  keep <- is.finite(observed)
  obs <- observed[keep]
  sim <- simulated[keep]
  .check(length(obs) >= 2 && all(obs >= 0) && all(is.finite(sim)) && all(sim >= 0),
         "Need two nonnegative scored observations and finite nonnegative simulations")
  log_obs <- log(obs + log_offset)
  log_sim <- log(sim + log_offset)
  kge <- .kge_parts(sim, obs)
  c(
    nse = .nse(sim, obs),
    log_nse = .nse(log_sim, log_obs),
    kge = kge[["kge"]],
    kge_r = kge[["r"]],
    kge_alpha = kge[["alpha"]],
    kge_beta = kge[["beta"]],
    rmse = sqrt(mean((sim - obs)^2)),
    log_rmse = sqrt(mean((log_sim - log_obs)^2)),
    volume_error = .ratio_error(sum(sim), sum(obs)),
    abs_volume_error = abs(.ratio_error(sum(sim), sum(obs))),
    peak_error = .ratio_error(max(sim), max(obs)),
    .fdc_signatures(sim, obs, log_offset)
  )
}

.nse <- function(sim, obs) {
  denominator <- sum((obs - mean(obs))^2)
  if (denominator > 0) 1 - sum((sim - obs)^2) / denominator else NA_real_
}

.ratio_error <- function(sim, obs) if (obs > 0) sim / obs - 1 else NA_real_

.kge_parts <- function(sim, obs) {
  sd_obs <- stats::sd(obs)
  sd_sim <- stats::sd(sim)
  r <- if (sd_obs > 0 && sd_sim > 0) stats::cor(sim, obs) else NA_real_
  alpha <- if (sd_obs > 0) sd_sim / sd_obs else NA_real_
  beta <- if (mean(obs) > 0) mean(sim) / mean(obs) else NA_real_
  kge <- 1 - sqrt((r - 1)^2 + (alpha - 1)^2 + (beta - 1)^2)
  c(kge = kge, r = r, alpha = alpha, beta = beta)
}

# Yilmaz et al. (2008), Eq. 4-6, as fractions. Exceedance probability i / (n + 1).
.fdc_signatures <- function(sim, obs, log_offset) {
  n <- length(obs)
  s <- sort(sim, decreasing = TRUE)
  o <- sort(obs, decreasing = TRUE)
  p <- seq_len(n) / (n + 1)
  high <- p <= 0.02
  fdc_high <- NA_real_
  if (any(high) && sum(o[high]) > 0) fdc_high <- sum(s[high] - o[high]) / sum(o[high])
  at <- function(x, exceedance) {
    log(stats::quantile(x, 1 - exceedance, names = FALSE, type = 7) + log_offset)
  }
  obs_slope <- at(obs, 0.2) - at(obs, 0.7)
  fdc_mid <- NA_real_
  if (obs_slope > 0) fdc_mid <- (at(sim, 0.2) - at(sim, 0.7) - obs_slope) / obs_slope
  low <- p >= 0.7
  fdc_low <- NA_real_
  if (sum(low) >= 2) {
    ls <- log(s[low] + log_offset)
    lo <- log(o[low] + log_offset)
    obs_low <- sum(lo - min(lo))
    if (obs_low > 0) fdc_low <- -(sum(ls - min(ls)) - obs_low) / obs_low
  }
  c(fdc_high = fdc_high, fdc_mid = fdc_mid, fdc_low = fdc_low)
}

# Which scores may be the headline, and which way is better.
.headline_scores <- function() {
  c(nse = "higher", log_nse = "higher", kge = "higher", rmse = "lower",
    log_rmse = "lower", abs_volume_error = "lower")
}
