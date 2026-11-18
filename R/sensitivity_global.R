# ============================================================ #
# Tool:         sensitivity_global
# Description:  Global sensitivity of a model's scores to its parameters across their bounds:
#               Morris elementary effects for screening, Sobol first-order and total indices
#               for apportioning, and the parameters the scores barely respond to
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       A configuration, forcing, observed flow and parameter bounds
# Outputs:      A pdm_sensitivity table with plot methods
# Dependencies: stats
# ============================================================ #

#' Global sensitivity of the scores to the parameters
#'
#' How much each parameter matters to the fit, across the whole of its range and with every
#' other parameter varying too: not one at a time from a single calibrated point, where a
#' parameter can look unimportant only because of where the others happen to sit.
#'
#' **Morris** (`method = "morris"`) screens. It walks r random paths (argument r) through the
#' parameter space, changing one parameter at a time by a fixed step, and records each change
#' in the score (an elementary effect). `mu_star`, the mean absolute effect, says how much a
#' parameter matters; `sigma`, their spread, says how much its effect depends on the others
#' (interaction or a curved response). It costs r x (parameters + 1) model runs: with 10
#' parameters and r of 20, 220 runs.
#'
#' **Sobol** (`method = "sobol"`) apportions the variance of the score. `first` is the share
#' a parameter explains alone; `total` the share it explains with all its interactions (Saltelli
#' et al., 2010, estimators: Saltelli for the first order, Jansen for the total). A parameter
#' with a small total index can be fixed anywhere in its range without changing the score: it
#' is a parameter the data cannot determine. It costs `n` x (parameters + 2) runs; `n` of 500
#' to 1,000 is usual, so several thousand runs, cheap on the compiled core.
#'
#' `negligible` marks parameters to consider fixing at a regional or default value: a total
#' index (Sobol) or a `mu_star` relative to the largest (Morris) below `fix_below`. Fixing them
#' leaves the calibration to the parameters the record can pin down, which makes repeated
#' calibrations agree.
#'
#' Each run starts as [calibrate_pdm()] would start it (`start`, `baseflow_fraction`,
#' `soil_fraction`). Parameters in `log_scale` are sampled uniformly in log(value).
#'
#' @param config,forcing,observed,lower,upper As in [calibrate_pdm()].
#' @param objectives Losses of [pdm_objectives()] to analyse, such as `"nse_loss"` and
#'   `"boxcox_loss"`; each gets its own indices from the same runs.
#' @param method `"morris"` or `"sobol"`.
#' @param r Morris paths.
#' @param levels Morris grid levels; the step is `levels / (2 (levels - 1))` of the range.
#' @param n Sobol base sample size.
#' @param fix_below Threshold for `negligible`.
#' @param warmup,log_offset,log_scale,start,baseflow_fraction,soil_fraction As in
#'   [calibrate_pdm()].
#' @param seed Random seed; the caller's random state is restored.
#' @param cores Cores for the model runs.
#' @return A `pdm_sensitivity` data frame: `objective`, `parameter`, the indices (`mu_star`,
#'   `sigma` for Morris; `first`, `total` for Sobol) and `negligible`, with the number of model
#'   runs in the `runs` attribute.
#' @examples
#' rain <- synthetic_rain("2021-01-01", years = 1, dt = 1, seed = 2)
#' cfg <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(cfg), rain[c("rain", "pet")])$output$q_m3s
#' s <- pdm_sensitivity(cfg, rain[c("time", "rain", "pet")], flow,
#'                      lower = c(distribution.cmax = 100, surface.k1 = 1, fc = 0.8),
#'                      upper = c(distribution.cmax = 400, surface.k1 = 20, fc = 1.2),
#'                      r = 6, warmup = 24 * 30)
#' s
#' plot(s)
#' @seealso [calibrate_pdm()], [calibration_bounds()]
#' @export
pdm_sensitivity <- function(config, forcing, observed, lower, upper,
                            objectives = c("nse_loss", "boxcox_loss"),
                            method = c("morris", "sobol"), r = 20L, levels = 4L, n = 500L,
                            fix_below = 0.05, warmup = 0L, log_offset = 0.01,
                            log_scale = character(0), start = c("flow", "soil"),
                            baseflow_fraction = 0.7, soil_fraction = 0.5, seed = 1L,
                            cores = getOption("pdmS7.cores", 1L)) {
  method <- match.arg(method)
  start <- match.arg(start)
  .check(.named_bounds(lower, upper), "Supply finite, uniquely named ordered bounds")
  .check(.whole(r, 2, 1e5) && .whole(levels, 2, 100) && .whole(n, 10, 1e6),
         "r, levels and n must be whole numbers (r >= 2, levels >= 2, n >= 10)")
  .check(.scalar(fix_below, 0, 1), "fix_below must be between 0 and 1")
  pdm_objectives(observed, observed, objectives, warmup, log_offset)
  box <- .search_box(lower, upper, log_scale)
  settings <- list(start = start, start_flow = observed[is.finite(observed)][1L],
                   baseflow_fraction = baseflow_fraction, soil_fraction = soil_fraction,
                   flow = "q_m3s")
  simulate <- .multi_simulator(config, forcing, settings)
  score <- function(z) {
    cfg <- config
    v <- box$to_value(z)
    for (p in names(v)) cfg <- .path_set(cfg, p, unname(v[[p]]))
    tryCatch(pdm_objectives(simulate(cfg), observed, objectives, warmup, log_offset),
             error = function(e) rep(NA_real_, length(objectives)))
  }
  k <- length(lower)
  m <- length(objectives)
  out <- .with_seed(seed, if (method == "morris") {
    .morris(score, k, r, levels, cores, m)
  } else {
    .sobol(score, k, n, cores, m)
  })
  table <- do.call(rbind, lapply(seq_along(objectives), function(j) {
    cbind(data.frame(objective = objectives[j], parameter = names(lower)),
          out$indices[[j]])
  }))
  key <- if (method == "morris") "mu_star" else "total"
  table$negligible <- FALSE
  for (o in objectives) {
    rows <- table$objective == o
    v <- table[[key]][rows]
    if (method == "morris") v <- v / max(v, na.rm = TRUE)
    table$negligible[rows] <- v < fix_below
  }
  structure(table, class = c("pdm_sensitivity", "data.frame"), method = method,
            runs = out$runs, fix_below = fix_below)
}

# Scores of every row of a matrix of unit-box points, on several cores if asked; a matrix with
# one row per point and one column per objective.
.score_points <- function(score, z, cores, m) {
  rows <- split(seq_len(nrow(z)), ceiling(seq_len(nrow(z)) / max(1, ceiling(nrow(z) / cores))))
  parts <- .run_jobs(rows, function(i) {
    matrix(vapply(i, function(j) score(z[j, ]), numeric(m)), ncol = m, byrow = TRUE)
  }, min(as.integer(cores), length(rows)))
  do.call(rbind, parts)
}

# Morris elementary effects on [0, 1]^k (Morris, 1991; mu* after Campolongo et al., 2007). Each
# of r paths starts at a random grid point from which a step of delta stays inside, and moves
# each coordinate once, in random order, by +delta or -delta. An effect is the change in score
# over delta, in unit-box terms, so effects of different parameters compare directly.
.morris <- function(score, k, r, levels, cores, m = 1L) {
  delta <- levels / (2 * (levels - 1))
  grid <- (0:(levels - 1)) / (levels - 1)
  paths <- lapply(seq_len(r), function(i) {
    x <- sample(grid[grid <= 1 - delta + 1e-12], k, replace = TRUE)
    sign <- ifelse(stats::runif(k) < 0.5, -1, 1)
    # A step down needs room below: start such coordinates a step up
    x[sign < 0] <- x[sign < 0] + delta
    order <- sample.int(k)
    pts <- matrix(x, k + 1L, k, byrow = TRUE)
    for (s in seq_len(k)) {
      pts[(s + 1L):(k + 1L), order[s]] <- pts[s, order[s]] + sign[order[s]] * delta
    }
    list(points = pts, order = order, sign = sign)
  })
  z <- do.call(rbind, lapply(paths, `[[`, "points"))
  f <- .score_points(score, z, cores, m)
  effects <- array(NA_real_, c(r, k, m))
  for (i in seq_len(r)) {
    rows <- (i - 1L) * (k + 1L) + seq_len(k + 1L)
    p <- paths[[i]]
    for (s in seq_len(k)) {
      effects[i, p$order[s], ] <- (f[rows[s + 1L], ] - f[rows[s], ]) /
        (p$sign[p$order[s]] * delta)
    }
  }
  list(runs = nrow(z), indices = lapply(seq_len(m), function(j) {
    e <- matrix(effects[, , j], r, k)
    data.frame(mu_star = colMeans(abs(e), na.rm = TRUE),
               mu = colMeans(e, na.rm = TRUE),
               sigma = apply(e, 2, stats::sd, na.rm = TRUE))
  }))
}

# Sobol indices by the estimators of Saltelli et al. (2010): two independent n x k samples A and
# B, and for each parameter i the matrix A with column i taken from B. With f the scores and V
# the variance of the scores of A and B together, the first-order index of i is
# mean(f(B) (f(AB_i) - f(A))) / V and the total index mean((f(A) - f(AB_i))^2) / (2 V).
.sobol <- function(score, k, n, cores, m = 1L) {
  a <- matrix(stats::runif(n * k), n, k)
  b <- matrix(stats::runif(n * k), n, k)
  ab <- do.call(rbind, lapply(seq_len(k), function(i) {
    x <- a
    x[, i] <- b[, i]
    x
  }))
  f <- .score_points(score, rbind(a, b, ab), cores, m)
  list(runs = nrow(f), indices = lapply(seq_len(m), function(j) {
    fa <- f[seq_len(n), j]
    fb <- f[n + seq_len(n), j]
    v <- stats::var(c(fa, fb), na.rm = TRUE)
    first <- total <- numeric(k)
    for (i in seq_len(k)) {
      fab <- f[2L * n + (i - 1L) * n + seq_len(n), j]
      first[i] <- mean(fb * (fab - fa), na.rm = TRUE) / v
      total[i] <- mean((fa - fab)^2, na.rm = TRUE) / (2 * v)
    }
    data.frame(first = first, total = total)
  }))
}

#' @export
print.pdm_sensitivity <- function(x, ...) {
  cat(sprintf("Global sensitivity (%s), %d model runs\n", attr(x, "method"), attr(x, "runs")))
  print(as.data.frame(x), digits = 3, row.names = FALSE)
  fix <- unique(x$parameter[x$negligible])
  if (length(fix)) cat("Negligible for some objective:", toString(fix), "\n")
  invisible(x)
}

#' @rdname pdm_sensitivity
#' @param x,object A `pdm_sensitivity` result.
#' @param ... Not used.
#' @export
plot.pdm_sensitivity <- function(x, ...) {
  .draw_base(.sensitivity_spec(x))
  invisible(x)
}

#' @rdname pdm_sensitivity
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_sensitivity <- function(object, ...) {
  .draw_gg(.sensitivity_spec(object))
}

# One panel per objective; each parameter a horizontal bar from 0 to its index, as a line, with
# Sobol's first-order index as a point on it.
.sensitivity_spec <- function(x) {
  morris <- identical(attr(x, "method"), "morris")
  objectives <- unique(x$objective)
  params <- unique(x$parameter)
  series <- NULL
  for (p in seq_along(objectives)) {
    t <- x[x$objective == objectives[p], ]
    y <- match(t$parameter, params)
    value <- if (morris) t$mu_star else t$total
    xs <- as.vector(rbind(0, value, NA))
    ys <- as.vector(rbind(y, y, NA))
    label <- if (morris) "mu* (mean absolute effect)" else "Total index"
    series <- rbind(series, .layer(xs, ys, label, .pdm_roles[["simulated"]], lwd = 3,
                                   panel = p))
    if (!morris) {
      series <- rbind(series, .layer(t$first, y, "First-order index",
                                     .pdm_roles[["alternative"]], geom = "point", lwd = 3,
                                     panel = p))
    }
    if (any(t$negligible)) {
      series <- rbind(series, .layer(value[t$negligible], y[t$negligible], "Negligible",
                                     .pdm_roles[["reference"]], geom = "open", lwd = 3.5,
                                     panel = p))
    }
  }
  single <- length(objectives) == 1L
  list(series = series, zero = TRUE, ncol = min(2L, length(objectives)),
       panels = data.frame(panel = seq_along(objectives), title = objectives),
       yticks = list(at = seq_along(params), labels = params),
       xlab = if (morris) "Mean absolute effect on the score, per unit of range" else
         "Share of the score's variance",
       ylab = "", title = if (single) paste("Sensitivity of", objectives) else
         "Global sensitivity of the scores",
       subtitle = sprintf("%s, %d model runs; hollow: negligible, a candidate to fix",
                          if (morris) "Morris screening" else "Sobol indices",
                          attr(x, "runs")))
}
