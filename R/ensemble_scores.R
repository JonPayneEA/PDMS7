# ============================================================ #
# Tool:         ensemble_scores
# Description:  Scores of ensemble and probability forecasts: CRPS (and its fair form), the
#               Brier score with its reliability, resolution and uncertainty, reliability
#               tables, rank histograms and the spread-skill ratio, by lead time
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       An ensemble (forecasts x members), the observed values, lead times, thresholds
# Outputs:      A pdm_ensemble_scores result with plot methods
# Dependencies: stats
# ============================================================ #

#' Continuous ranked probability score of an ensemble
#'
#' For each forecast, `mean |X - y| - mean |X - X'| / 2` over the members X and X' and the
#' observed value y: the ensemble's whole distribution against what happened, in the units of
#' the flow, 0 for a perfect forecast and the absolute error for a single member. The fair form
#' (Ferro, 2014) averages the second term over distinct pairs of members only, so that a small
#' ensemble is not penalised for its size.
#'
#' @param ensemble A matrix, one row per forecast and one column per member (or a vector, one
#'   forecast).
#' @param observed The observed value of each forecast.
#' @param fair Use the fair form.
#' @return The score of each forecast.
#' @examples
#' crps_ensemble(matrix(c(0, 1), nrow = 1), 0)                # 0.25
#' crps_ensemble(matrix(c(0, 1), nrow = 1), 0, fair = TRUE)   # 0
#' @seealso [ensemble_scores()]
#' @export
crps_ensemble <- function(ensemble, observed, fair = FALSE) {
  ens <- if (is.null(dim(ensemble))) matrix(ensemble, nrow = 1L) else as.matrix(ensemble)
  .check(nrow(ens) == length(observed), "One observed value for each row of the ensemble")
  m <- ncol(ens)
  .check(!fair || m >= 2L, "The fair CRPS needs at least two members")
  vapply(seq_len(nrow(ens)), function(i) {
    x <- sort(ens[i, ])
    if (!is.finite(observed[i]) || any(!is.finite(x))) return(NA_real_)
    first <- mean(abs(x - observed[i]))
    # Mean |X - X'| over all ordered pairs, from the sorted members: 2 / m^2 sum (2 i - m - 1) x_i
    pairs <- 2 / m^2 * sum((2 * seq_len(m) - m - 1) * x)
    if (fair) pairs <- pairs * m / (m - 1)
    first - pairs / 2
  }, numeric(1))
}

#' Brier score and its decomposition
#'
#' The mean squared difference between the forecast probability of an event (a threshold
#' crossed) and whether it happened (1 or 0). Murphy's decomposition splits it, over the bins of
#' forecast probability, into reliability (how far each bin's forecast probability lies from how
#' often the event happened when it was forecast; lower is better), resolution (how far those
#' frequencies differ from the overall frequency; higher is better) and uncertainty (the
#' overall frequency's variance, which no forecast can change): BS = reliability - resolution +
#' uncertainty, exactly when each bin holds one probability.
#'
#' @param probability Forecast probabilities.
#' @param outcome What happened: 1 (or TRUE) for the event, 0 for none.
#' @param bins Bin edges for the decomposition and the reliability table; by default each
#'   distinct probability is its own bin.
#' @return A list: `brier`, `reliability`, `resolution`, `uncertainty`, and `table`, the
#'   reliability table (bin, forecasts, mean probability, observed frequency).
#' @examples
#' brier_score(c(0.9, 0.9, 0.1, 0.1), c(1, 0, 0, 0))
#' @seealso [ensemble_scores()]
#' @export
brier_score <- function(probability, outcome, bins = NULL) {
  ok <- is.finite(probability) & !is.na(outcome)
  p <- probability[ok]
  o <- as.numeric(outcome[ok])
  .check(length(p) > 0 && all(p >= 0 & p <= 1) && all(o %in% c(0, 1)),
         "Probabilities must lie in [0, 1] and outcomes be 0 or 1")
  bin <- if (is.null(bins)) factor(p) else cut(p, bins, include.lowest = TRUE)
  table <- data.frame(
    bin = levels(droplevels(bin)),
    forecasts = as.vector(tapply(p, bin, length)[levels(droplevels(bin))]),
    probability = as.vector(tapply(p, bin, mean)[levels(droplevels(bin))]),
    observed = as.vector(tapply(o, bin, mean)[levels(droplevels(bin))])
  )
  base <- mean(o)
  w <- table$forecasts / length(p)
  list(brier = mean((p - o)^2),
       reliability = sum(w * (table$probability - table$observed)^2),
       resolution = sum(w * (table$observed - base)^2),
       uncertainty = base * (1 - base), table = table)
}

#' Scores of ensemble forecasts by lead time
#'
#' Everything needed to judge a probabilistic forecast, lead time by lead time:
#'
#' - `crps` and `crps_fair` ([crps_ensemble()]), and `crpss`, the skill of the CRPS over the
#'   ensemble mean used as a single forecast (1 is perfect, 0 no better than the mean alone);
#' - `rmse` of the ensemble mean, `spread` (the mean standard deviation of the members) and
#'   `spread_skill` (spread over rmse, times sqrt((m + 1) / m)): near 1 the ensemble is as wide
#'   as its errors, below 1 it is overconfident, above 1 too cautious;
#' - for each threshold, the Brier score of the forecast probability of crossing it (the share
#'   of members above it), with its reliability and resolution.
#'
#' The `rank` attribute holds rank histograms (where the observed value falls among the sorted
#' members: flat when the ensemble is reliable, U-shaped when it is too narrow, a hump when too
#' wide), and `reliability` the reliability tables, for `plot()`.
#'
#' @param ensemble A matrix, one row per forecast and one column per member.
#' @param observed The observed value of each forecast.
#' @param lead_h Each forecast's lead time, hours; `NULL` treats them as one lead.
#' @param thresholds Named thresholds (m3/s) for the Brier scores.
#' @param seed Random seed for breaking ties in the rank histogram.
#' @return A `pdm_ensemble_scores` data frame, one row per lead time.
#' @examples
#' set.seed(1)
#' truth <- rgamma(200, 2)
#' ens <- t(vapply(truth, function(y) y * exp(rnorm(20, 0, 0.3)), numeric(20)))
#' s <- ensemble_scores(ens, truth, lead_h = rep(c(1, 6), 100), thresholds = c(high = 4))
#' s
#' plot(s, type = "rank")
#' @seealso [crps_ensemble()], [brier_score()]
#' @export
ensemble_scores <- function(ensemble, observed, lead_h = NULL, thresholds = NULL, seed = 1L) {
  ens <- as.matrix(ensemble)
  .check(nrow(ens) == length(observed) && ncol(ens) >= 2L,
         "ensemble needs one row per observed value and at least two members")
  lead_h <- lead_h %||% rep(0, length(observed))
  .check(length(lead_h) == length(observed), "One lead time for each forecast")
  .check(is.null(thresholds) || (is.numeric(thresholds) && !is.null(names(thresholds))),
         "thresholds must be named numbers")
  m <- ncol(ens)
  leads <- sort(unique(lead_h))
  ranks <- .with_seed(seed, .obs_ranks(ens, observed))
  rows <- lapply(leads, function(l) {
    i <- which(lead_h == l & is.finite(observed))
    e <- ens[i, , drop = FALSE]
    y <- observed[i]
    mu <- rowMeans(e)
    crps <- mean(crps_ensemble(e, y))
    rmse <- sqrt(mean((mu - y)^2))
    spread <- sqrt(mean(apply(e, 1, stats::var)))
    out <- data.frame(lead_h = l, n = length(i), crps = crps,
                      crps_fair = mean(crps_ensemble(e, y, fair = TRUE)),
                      crpss = 1 - crps / mean(abs(mu - y)), rmse = rmse, spread = spread,
                      spread_skill = spread / rmse * sqrt((m + 1) / m))
    for (t in names(thresholds)) {
      b <- brier_score(rowMeans(e > thresholds[[t]]), y > thresholds[[t]])
      out[[paste0("brier:", t)]] <- b$brier
      out[[paste0("reliability:", t)]] <- b$reliability
      out[[paste0("resolution:", t)]] <- b$resolution
    }
    out
  })
  rank <- lapply(leads, function(l) {
    tabulate(ranks[lead_h == l & is.finite(observed)], nbins = m + 1L)
  })
  reliability <- lapply(stats::setNames(names(thresholds), names(thresholds)), function(t) {
    brier_score(rowMeans(ens > thresholds[[t]]), observed > thresholds[[t]],
                bins = seq(0, 1, by = 0.1))$table
  })
  structure(do.call(rbind, rows), class = c("pdm_ensemble_scores", "data.frame"),
            rank = stats::setNames(rank, leads), reliability = reliability, members = m)
}

# The rank of each observed value among its forecast's members, 1 to m + 1, ties broken at
# random so a tie does not always count as below.
.obs_ranks <- function(ens, observed) {
  vapply(seq_len(nrow(ens)), function(i) {
    below <- sum(ens[i, ] < observed[i])
    ties <- sum(ens[i, ] == observed[i])
    as.integer(below + 1L + if (ties > 0) sample.int(ties + 1L, 1L) - 1L else 0L)
  }, integer(1))
}

#' @rdname ensemble_scores
#' @param x,object A `pdm_ensemble_scores` result.
#' @param type `"crps"` (CRPS and spread-skill against lead time), `"rank"` (rank
#'   histograms) or `"reliability"` (reliability diagram of the first threshold).
#' @param ... Not used.
#' @export
plot.pdm_ensemble_scores <- function(x, type = c("crps", "rank", "reliability"), ...) {
  .draw_base(.ensemble_spec(x, match.arg(type)))
  invisible(x)
}

#' @rdname ensemble_scores
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_ensemble_scores <- function(object, type = c("crps", "rank", "reliability"), ...) {
  .draw_gg(.ensemble_spec(object, match.arg(type)))
}

.ensemble_spec <- function(x, type) {
  switch(type,
    crps = .spec_crps(x),
    rank = .spec_rank(x),
    reliability = .spec_reliability(x)
  )
}

# CRPS, the ensemble mean's RMSE and the spread against lead time.
.spec_crps <- function(x) {
  crps <- .layer(x$lead_h, x$crps, "CRPS", .pdm_roles[["simulated"]], lwd = 1.8)
  rmse <- .layer(x$lead_h, x$rmse, "RMSE of the ensemble mean", .pdm_roles[["alternative"]],
                 lwd = 1.2, lty = 2)
  spread <- .layer(x$lead_h, x$spread, "Spread", .pdm_roles[["reference"]], lwd = 1.2)
  list(series = rbind(crps, rmse, spread), xlab = "Lead time (h)", ylab = "m3/s",
       title = "Ensemble scores by lead time",
       subtitle = sprintf("Spread over RMSE, adjusted for %d members: %s", attr(x, "members"),
                          paste(sprintf("%.2f", x$spread_skill), collapse = ", ")))
}

# One panel per lead: the share of forecasts at each rank, against the flat line of a reliable
# ensemble.
.spec_rank <- function(x) {
  ranks <- attr(x, "rank")
  m <- attr(x, "members")
  series <- do.call(rbind, lapply(seq_along(ranks), function(p) {
    share <- ranks[[p]] / sum(ranks[[p]])
    k <- seq_along(share)
    bars <- .layer(as.vector(rbind(k, k, NA)), as.vector(rbind(0, share, NA)),
                   "Share of forecasts", .pdm_roles[["simulated"]], lwd = 6, panel = p)
    flat <- .layer(c(0.5, m + 1.5), rep(1 / (m + 1), 2), "Reliable",
                   .pdm_roles[["reference"]], lty = 2, lwd = 1, panel = p)
    rbind(bars, flat)
  }))
  list(series = series, zero = TRUE, ncol = min(3L, length(ranks)),
       panels = data.frame(panel = seq_along(ranks),
                           title = paste("Lead", names(ranks), "h")),
       xlab = "Rank of the observed value among the members", ylab = "Share",
       title = "Rank histograms",
       subtitle = "Flat: reliable; U-shaped: too narrow; humped: too wide")
}

.spec_reliability <- function(x) {
  rel <- attr(x, "reliability")
  .check(length(rel) > 0, "A reliability diagram needs thresholds")
  t <- rel[[1]]
  perfect <- .layer(c(0, 1), c(0, 1), "Perfect reliability", .pdm_roles[["reference"]],
                    lty = 2, lwd = 1)
  line <- .layer(t$probability, t$observed, "Forecasts", .pdm_roles[["simulated"]], lwd = 1.6)
  dots <- .layer(t$probability, t$observed, ".points", .pdm_roles[["simulated"]],
                 geom = "point", lwd = 2.4)
  list(series = rbind(perfect, line, dots), xlim = c(0, 1), ylim = c(0, 1),
       xlab = "Forecast probability", ylab = "Observed frequency",
       title = paste("Reliability:", names(rel)[1]),
       subtitle = sprintf("%d forecasts, all lead times", sum(t$forecasts)))
}
