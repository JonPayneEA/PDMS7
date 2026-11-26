# ============================================================ #
# Tool:         rainfall_kriging
# Description:  Catchment rainfall by block kriging (ordinary, and with an external drift such
#               as a long-term average grid), with a variogram fitted to the gauges, and the
#               fast path for the methods that weight the gauges linearly: the weights are
#               worked out once for each set of gauges reporting, not at every step
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-26
# Tier:         1
# Inputs:       Gauge locations and depths (mm per step); the catchment's cells and weights; a
#               drift field on the grid for kriging with external drift
# Outputs:      Catchment-average rain, mm per step, and for kriging its standard error
# Dependencies: stats
# ============================================================ #

#' A variogram of the gauges' rain
#'
#' How differently two gauges' rain behaves as the distance between them grows, fitted once
#' from many steps, for kriging with a handful of gauges (one storm's five gauges cannot
#' support a variogram of their own). At each wet step the gauges' rain is divided by that
#' step's mean over the gauges, so storms of every size count alike and the variogram is of
#' relative rain; then, for each pair of gauges, the semivariance (half the mean squared
#' difference) over the steps both report. An exponential model is fitted to those points by
#' weighted least squares:
#'
#' `gamma(h) = nugget + partial_sill * (1 - exp(-h / range))` for `h > 0`, and 0 at `h = 0`.
#'
#' The `nugget` is the difference between gauges right beside each other: gauge error and very
#' local rain. The `range` is how far apart gauges must be before their rain stops being
#' related (about 95% of the sill is reached at three times it). With few gauges the fit rests
#' on few points: read it as an estimate.
#'
#' @param gauges Data frame of gauges with columns `id`, `x` and `y`.
#' @param gauge_rain Matrix of gauge depths, one row per step, one column per gauge.
#' @param wet Mean depth over the gauges reporting, mm per step, above which a step is used.
#' @param max_steps Most wet steps used; a larger record is sampled, with `seed`.
#' @param seed Seed for that sample; the caller's random state is restored.
#' @return A list of class `pdm_variogram`: `model` ("exponential"), `nugget`, `partial_sill`,
#'   `range` (in the coordinates' units) and `empirical`, one row per pair of gauges (their
#'   distance, semivariance and the steps behind it).
#' @examples
#' gauges <- data.frame(id = 1:4, x = c(0, 3000, 0, 3000), y = c(0, 0, 3000, 3000))
#' set.seed(1)
#' common <- rexp(500)
#' gauge_rain <- sapply(1:4, function(k) common * exp(rnorm(500, sd = 0.2)))
#' rainfall_variogram(gauges, gauge_rain)
#' @seealso [merge_rainfall()]
#' @export
rainfall_variogram <- function(gauges, gauge_rain, wet = 0.1, max_steps = 20000L, seed = 1L) {
  .check_gauge_inputs(gauges, gauge_rain)
  .check(nrow(gauges) >= 3, "A variogram needs at least three gauges")
  .check(.whole(max_steps, 1, Inf), "max_steps must be a positive whole number")
  finite <- is.finite(gauge_rain)
  counted <- rowSums(finite)
  step_mean <- rowSums(ifelse(finite, gauge_rain, 0)) / pmax(counted, 1)
  steps <- which(counted >= 3 & step_mean > wet)
  .check(length(steps) > 0, "No wet steps with three gauges or more to fit a variogram")
  if (length(steps) > max_steps) {
    steps <- sort(.with_seed(seed, steps[sample.int(length(steps), max_steps)]))
  }
  # Each step's rain relative to its mean over the gauges reporting.
  relative <- gauge_rain[steps, , drop = FALSE] / step_mean[steps]
  pairs <- utils::combn(nrow(gauges), 2)
  empirical <- do.call(rbind, lapply(seq_len(ncol(pairs)), function(p) {
    a <- pairs[1, p]
    b <- pairs[2, p]
    both <- is.finite(relative[, a]) & is.finite(relative[, b])
    data.frame(gauge_a = gauges$id[a],
               gauge_b = gauges$id[b],
               distance = sqrt((gauges$x[a] - gauges$x[b])^2 + (gauges$y[a] - gauges$y[b])^2),
               semivariance = if (any(both)) {
                 0.5 * mean((relative[both, a] - relative[both, b])^2)
               } else {
                 NA_real_
               },
               steps = sum(both))
  }))
  used <- empirical[is.finite(empirical$semivariance) & empirical$distance > 0, ]
  .check(nrow(used) >= 2, "Too few pairs of gauges to fit a variogram")
  # Weighted least squares on the logs of the three parameters, so all stay positive.
  model_at <- function(p, h) exp(p[1]) + exp(p[2]) * (1 - exp(-h / exp(p[3])))
  misfit <- function(p) sum(used$steps * (used$semivariance - model_at(p, used$distance))^2)
  top <- max(used$semivariance)
  bottom <- min(used$semivariance)
  start <- log(c(max(bottom * 0.5, top * 1e-3),
                 max(top - bottom * 0.5, top * 1e-3),
                 stats::median(used$distance)))
  fit <- stats::optim(start, misfit, method = "Nelder-Mead",
                      control = list(maxit = 2000, reltol = 1e-12))
  structure(list(model = "exponential",
                 nugget = exp(fit$par[1]),
                 partial_sill = exp(fit$par[2]),
                 range = exp(fit$par[3]),
                 empirical = empirical),
            class = "pdm_variogram")
}

#' @export
print.pdm_variogram <- function(x, ...) {
  cat(sprintf(paste("Exponential variogram of relative rain: nugget %.3g, partial sill %.3g,",
                    "range %.4g (%d pairs of gauges)\n"),
              x$nugget, x$partial_sill, x$range, nrow(x$empirical)))
  invisible(x)
}

# The variogram at distances h: 0 at 0, the nugget and the exponential rise beyond.
.vgm <- function(h, v) {
  ifelse(h > 0, v$nugget + v$partial_sill * (1 - exp(-h / v$range)), 0)
}

# Block kriging weights for the gauges at (gx, gy) over the catchment's cells: ordinary, or
# with an external drift known at the gauges (dg) and averaged over the block (db). Returns
# the weights and the block's kriging variance, in the variogram's (relative) units.
.block_kriging <- function(gx, gy, cells, v, gamma_bb, dg = NULL, db = NULL) {
  k <- length(gx)
  if (k == 1) {
    g1 <- sum(cells$w * .vgm(sqrt((cells$x - gx)^2 + (cells$y - gy)^2), v)) / sum(cells$w)
    return(list(lambda = 1, variance = 2 * g1 - gamma_bb))
  }
  gamma_gg <- .vgm(sqrt(outer(gx, gx, "-")^2 + outer(gy, gy, "-")^2), v)
  gamma_gb <- vapply(seq_len(k), function(i) {
    sum(cells$w * .vgm(sqrt((cells$x - gx[i])^2 + (cells$y - gy[i])^2), v)) / sum(cells$w)
  }, 0)
  with_drift <- !is.null(dg) && k >= 3 && stats::var(dg) > 0
  a <- rbind(cbind(gamma_gg, 1), c(rep(1, k), 0))
  rhs <- c(gamma_gb, 1)
  if (with_drift) {
    a <- rbind(cbind(a, c(dg, 0)), c(dg, 0, 0))
    rhs <- c(rhs, db)
  }
  sol <- tryCatch(solve(a, rhs), error = function(e) NULL)
  if (is.null(sol)) return(list(lambda = rep(1 / k, k), variance = NA_real_))
  lambda <- sol[seq_len(k)]
  variance <- sum(lambda * gamma_gb) + sol[k + 1] +
    (if (with_drift) sol[k + 2] * db else 0) - gamma_bb
  list(lambda = lambda, variance = variance)
}

# The mean of the variogram between the block's cells: every pair, or a sample of cells for a
# large block (the mean changes little once the block is well covered).
.gamma_block <- function(cells, v, most = 1500L, seed = 1L) {
  idx <- seq_along(cells$x)
  if (length(idx) > most) idx <- sort(.with_seed(seed, sample(idx, most)))
  x <- cells$x[idx]
  y <- cells$y[idx]
  w <- cells$w[idx]
  g <- .vgm(sqrt(outer(x, x, "-")^2 + outer(y, y, "-")^2), v)
  sum(outer(w, w) * g) / sum(w)^2
}

# The field at the cells as a fixed weighting of the gauges at (gx, gy): a matrix of cells by
# gauges, so that the field at a step is the matrix times that step's gauge depths.
.field_weights <- function(method, gx, gy, cells, c, smooth, power) {
  k <- length(gx)
  if (method == "thiessen") {
    nearest <- .nearest(cells$x, cells$y, gx, gy)
    return(outer(nearest, seq_len(k), "==") + 0)
  }
  if (method == "idw") {
    d <- sqrt(outer(cells$x, gx, "-")^2 + outer(cells$y, gy, "-")^2)
    on_gauge <- d == 0
    w <- 1 / d^power
    w[on_gauge] <- 0
    w <- w / rowSums(w)
    hit <- which(rowSums(on_gauge) > 0)
    for (r in hit) w[r, ] <- as.numeric(seq_len(k) == which(on_gauge[r, ])[1])
    return(w)
  }
  # Multiquadric with a constant term: the field is [Phi, 1] times the first k columns of the
  # inverse of the system matrix, applied to the gauges' depths.
  if (k == 1) return(matrix(1, length(cells$x), 1))
  phi <- function(ax, ay, bx, by) sqrt(outer(ax, bx, "-")^2 + outer(ay, by, "-")^2 + c^2)
  a <- rbind(cbind(phi(gx, gy, gx, gy) + diag(smooth, k), 1), c(rep(1, k), 0))
  inverse <- tryCatch(solve(a), error = function(e) NULL)
  if (is.null(inverse)) return(matrix(1 / k, length(cells$x), k))
  cbind(phi(cells$x, cells$y, gx, gy), 1) %*% inverse[, seq_len(k), drop = FALSE]
}

# The catchment average at every step for a method that weights the gauges linearly. Steps are
# grouped by which gauges report; each group's weights are worked out once. For the field
# methods the field is then made at every cell, set to zero where it dips below, and averaged,
# a block of steps at a time; for kriging the block weights give the average directly, with
# its standard error.
.merge_linear <- function(gauges, gauge_rain, cells, method, c, smooth, power, variogram,
                          drift_cells, drift_gauges) {
  n <- ncol(gauge_rain)
  steps <- nrow(gauge_rain)
  rain <- rep(NA_real_, steps)
  kriged <- method %in% c("kriging", "ked")
  se <- if (kriged) rep(NA_real_, steps)
  reporting <- is.finite(gauge_rain)
  code <- as.vector(reporting %*% 2^(seq_len(n) - 1))
  wsum <- sum(cells$w)
  gamma_bb <- if (kriged) .gamma_block(cells, variogram)
  db <- if (!is.null(drift_cells)) sum(cells$w * drift_cells) / wsum
  block <- max(1L, floor(5e6 / max(1, length(cells$x))))
  for (pattern in unique(code[code > 0])) {
    rows <- which(code == pattern)
    ok <- reporting[rows[1], ]
    z <- gauge_rain[rows, ok, drop = FALSE]
    gx <- gauges$x[ok]
    gy <- gauges$y[ok]
    if (kriged) {
      kw <- .block_kriging(gx, gy, cells, variogram, gamma_bb,
                           if (method == "ked") drift_gauges[ok], db)
      estimate <- drop(z %*% kw$lambda)
      rain[rows] <- pmax(estimate, 0)
      # The variance is of relative rain: back to mm with each step's mean over the gauges.
      se[rows] <- sqrt(max(kw$variance, 0)) * rowMeans(z)
    } else {
      m <- .field_weights(method, gx, gy, cells, c, smooth, power)
      for (start in seq(1, length(rows), by = block)) {
        r <- rows[start:min(length(rows), start + block - 1)]
        field <- gauge_rain[r, ok, drop = FALSE] %*% t(m)
        field[field < 0] <- 0
        rain[r] <- drop(field %*% cells$w) / wsum
      }
    }
  }
  list(rain = rain, se = se)
}
