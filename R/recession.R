# ============================================================ #
# Tool:         recession
# Description:  Recession analysis: how fast flow falls against how high it is, the slope of
#               that relation, and the groundwater store it points to
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         3
# Inputs:       Flow (m3/s); optionally rain (mm per step)
# Outputs:      The recession slope with a confidence interval, the stores consistent with it,
#               and the points and bins behind it
# Dependencies: stats; graphics for the plot
# ============================================================ #

# Recession slopes of the groundwater stores the package offers. A power store q = k S^m gives
# -dq/dt = m k^(1/m) q^((2m - 1)/m); an exponential store q = exp(aS + gamma) gives a q^2.
.store_slopes <- c(linear = 1, quadratic = 1.5, cubic = 5 / 3, exponential = 2)

#' Recession analysis: which groundwater store does the flow record point to?
#'
#' Once the surface stores have emptied after rain, the flow is the groundwater store
#' draining, and how fast it falls for a given flow depends on the store's form. Plotted on
#' logarithmic axes, the rate of fall `-dQ/dt` against the flow `Q` lies along a line whose
#' slope identifies the store (Brutsaert and Nieber, 1977; Kirchner, 2009):
#'
#' | Store | Outflow | Slope |
#' |---|---|---|
#' | linear | q = S / kb | 1 |
#' | quadratic | q = S^2 / kb | 1.5 |
#' | cubic | q = S^3 / kb | 1.67 |
#' | exponential | q = exp(a S + gamma) | 2 |
#'
#' A power store q = k S^m has slope (2m - 1) / m, so a measured slope b also gives the
#' exponent m = 1 / (2 - b) of [power_routing()].
#'
#' **Which points count.** The flow is averaged over `aggregate_h` hours (daily by default:
#' at 15-minute steps the rate of fall is mostly noise). A step counts when the flow falls,
#' no rain above `rain_tol` fell in it, and at least `dry_h` hours have passed since the last
#' rain, so that the surface stores have drained; by default three response times of the
#' catchment ([response_time_dmca()]), or `aggregate_h` where none can be found. Runs of
#' falling steps shorter than `min_steps` are left out, and the first `skip_steps` of each run.
#' `months` keeps only recessions in those months: evaporation steepens summer recessions, so
#' winter ones show the store more cleanly.
#'
#' **The fit.** The points are binned by flow on a log scale, and a straight line is fitted to
#' the logs of the bins' mean flow and mean rate, weighted by their counts, as Kirchner (2009)
#' recommends; bins with fewer than three points are dropped. The confidence interval comes
#' from refitting on `boot` resamples of whole recession runs, which keeps the dependence
#' within a run. Every store whose slope lies inside the interval is consistent with the
#' record. Where several are, the record cannot choose between them, and that is the answer.
#'
#' **Recharge between events flattens the slope.** The table holds for a store that only
#' drains. With standard recharge, the soil store keeps feeding groundwater through every
#' recession, and the flow falls more slowly than the store alone would let it. On made-up
#' catchments with ten years of hourly rain, with split recharge (none between events) the
#' fitted slopes were 0.98, 1.50, 1.63 and 1.92 for the four stores, close to the table; with
#' standard recharge they were 0.25 to 0.65 lower, by an amount depending on the recharge rate,
#' and the stores ran together. Fitting the steepest points instead did not remove the bias.
#' So read a store straight from the slope only where recharge stops between events. Otherwise
#' compare the record's slope with that of each fitted model, run with the same settings on
#' its simulated flow ([plot_recession()] draws both): the fitted model carries its own
#' recharge, so a store that matches the record's recessions is a candidate, and one that does
#' not is getting its low flows right for the wrong reason.
#'
#' @param flow Flow, m3/s, at a regular step.
#' @param rain Optional rain, mm per step, aligned with `flow`. Without it, only falling flow
#'   selects the points.
#' @param dt Step of `flow`, hours.
#' @param time Optional times of `flow` (POSIXct), needed for `months`.
#' @param aggregate_h Hours over which flow is averaged and rain summed before the analysis; a
#'   whole number of steps.
#' @param dry_h Hours since rain before a step counts; by default three response times, at
#'   least `aggregate_h`.
#' @param rain_tol Largest rain, mm per aggregated step, that still counts as dry.
#' @param min_steps Fewest falling steps a recession run must have.
#' @param skip_steps Steps left out at the start of each run.
#' @param months Months (1 to 12) whose recessions count; all by default.
#' @param bins Number of flow bins.
#' @param boot Bootstrap resamples for the confidence interval; 0 for none.
#' @param seed Seed for the bootstrap; the caller's random state is restored.
#'
#' @return A list of class `pdm_recession` with `slope`, `ci` (2.5% and 97.5%), `intercept`,
#'   `power_m` (the power-store exponent the slope implies; `Inf` at a slope of 2 or more),
#'   `stores` (each store's slope and whether it lies in the interval), `nearest` (the store
#'   whose slope is closest), `points` (`run`, `flow`, `rate` in m3/s per hour, and `time`
#'   when given), `bins`, and the settings used.
#' @references Brutsaert, W. and Nieber, J. L. (1977). Regionalized drought flow hydrographs
#'   from a mature glaciated plateau. Water Resources Research 13(3), 637-643.
#'
#'   Kirchner, J. W. (2009). Catchments as simple dynamical systems: catchment
#'   characterization, rainfall-runoff modeling, and doing hydrology backward. Water
#'   Resources Research 45, W02429, doi:10.1029/2008WR006912.
#' @examples
#' set.seed(2)
#' n <- 24 * 365 * 3
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.03, rgamma(n, 0.7, scale = 6), 0),
#'                       pet = 0.05)
#' model <- pdm_model(area_km2 = 50, groundwater = quadratic_routing(kb = 2000),
#'                    recharge = FlodeStandardRecharge(kg = 300, bg = 1, st = 0))
#' flow <- run_pdm(model, forcing)$output$q_m3s
#' r <- recession_analysis(flow, forcing$rain, dt = 1, boot = 50)
#' r$slope
#' r$stores
#' plot_recession(r)
#' @seealso [plot_recession()], [power_routing()], [find_events()]
#' @export
recession_analysis <- function(flow, rain = NULL, dt = 1, time = NULL, aggregate_h = 24,
                               dry_h = NULL, rain_tol = 0.1, min_steps = 3L, skip_steps = 1L,
                               months = NULL, bins = 20L, boot = 200L, seed = 1L) {
  .check_recession_args(flow, rain, dt, time, aggregate_h, rain_tol, min_steps, skip_steps,
                        months, bins, boot)
  dry_h <- dry_h %||% if (is.null(rain)) {
    aggregate_h
  } else {
    response <- tryCatch(suppressWarnings(response_time_dmca(rain, flow, dt)$response_h),
                         error = function(e) NA_real_)
    max(aggregate_h, 3 * response, na.rm = TRUE)
  }
  .check(.scalar(dry_h, 0), "dry_h must be a nonnegative number of hours")
  series <- .aggregate_series(flow, rain, time, dt, aggregate_h)
  points <- .recession_points(series, aggregate_h, dry_h, rain_tol, min_steps, skip_steps,
                              months)
  .check(nrow(points) >= 10, paste(
    "Fewer than ten recession points; lower dry_h, min_steps or aggregate_h, or use a longer",
    "record"
  ))
  fit <- .recession_fit(points, bins)
  ci <- .recession_ci(points, bins, boot, seed)
  stores <- data.frame(store = names(.store_slopes), slope = unname(.store_slopes),
                       within_ci = .store_slopes >= ci[1] & .store_slopes <= ci[2])
  rownames(stores) <- NULL
  out <- list(
    slope = fit$slope, ci = ci, intercept = fit$intercept,
    power_m = if (fit$slope < 2) 1 / (2 - fit$slope) else Inf,
    stores = stores, nearest = names(which.min(abs(.store_slopes - fit$slope))),
    points = points, bins = fit$bins,
    settings = list(aggregate_h = aggregate_h, dry_h = dry_h, rain_tol = rain_tol,
                    min_steps = min_steps, skip_steps = skip_steps, months = months,
                    bins = bins, boot = boot)
  )
  class(out) <- "pdm_recession"
  out
}

.check_recession_args <- function(flow, rain, dt, time, aggregate_h, rain_tol, min_steps,
                                  skip_steps, months, bins, boot) {
  .check(is.numeric(flow) && length(flow) > 2, "flow must be a numeric series")
  .check(is.null(rain) || (is.numeric(rain) && length(rain) == length(flow)),
         "rain must be NULL or match flow in length")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  .check(is.null(time) || length(time) == length(flow), "time must match flow in length")
  .check(.scalar(aggregate_h, 0, strict = TRUE) &&
           abs(aggregate_h / dt - round(aggregate_h / dt)) < 1e-9,
         "aggregate_h must be a whole number of steps")
  .check(.scalar(rain_tol, 0), "rain_tol must be a nonnegative depth")
  .check(.whole(min_steps, 1, Inf), "min_steps must be a positive whole number")
  .check(.whole(skip_steps, 0, Inf), "skip_steps must be a nonnegative whole number")
  .check(is.null(months) || (is.null(time) == FALSE && all(months %in% 1:12)),
         "months needs time, and must lie in 1 to 12")
  .check(.whole(bins, 3, Inf), "bins must be a whole number of at least 3")
  .check(.whole(boot, 0, Inf), "boot must be a nonnegative whole number")
}

# Flow averaged and rain summed over blocks of aggregate_h hours. A block with more than a tenth
# of its flow missing is missing; missing rain counts as none.
.aggregate_series <- function(flow, rain, time, dt, aggregate_h) {
  k <- as.integer(round(aggregate_h / dt))
  n <- length(flow) %/% k
  idx <- seq_len(n * k)
  block <- rep(seq_len(n), each = k)
  present <- tapply(is.finite(flow[idx]), block, mean)
  q <- tapply(flow[idx], block, mean, na.rm = TRUE)
  q[present < 0.9] <- NA
  r <- if (is.null(rain)) rep(0, n) else tapply(.zero_missing(rain[idx]), block, sum)
  t <- if (is.null(time)) NULL else time[seq(1L, n * k, by = k)]
  list(flow = unname(as.numeric(q)), rain = unname(as.numeric(r)), time = t)
}

# The recession points: consecutive falling steps, dry and long enough after rain, grouped into
# runs; short runs and the start of each run are dropped. Each point is the mean of two
# successive flows and the rate of fall between them.
.recession_points <- function(series, step_h, dry_h, rain_tol, min_steps, skip_steps, months) {
  q <- series$flow
  n <- length(q)
  wet <- series$rain > rain_tol
  last_wet <- cummax(ifelse(wet, seq_len(n), 0L))
  since <- ifelse(last_wet > 0, (seq_len(n) - last_wet) * step_h, Inf)
  ok <- c(is.finite(q[-n]) & is.finite(q[-1]) & q[-1] > 0 & q[-1] < q[-n] &
            !wet[-1] & since[-n] >= dry_h, FALSE)
  if (!is.null(months)) {
    ok <- ok & as.integer(format(series$time, "%m", tz = "UTC")) %in% months
  }
  idx <- which(ok)
  run <- cumsum(c(1L, diff(idx) != 1L))
  size <- tabulate(run)[run]
  pos <- seq_along(idx) - match(run, run) + 1L
  chosen <- size >= min_steps & pos > skip_steps
  keep <- idx[chosen]
  out <- data.frame(run = as.integer(factor(run[chosen])), flow = (q[keep] + q[keep + 1]) / 2,
                    rate = (q[keep] - q[keep + 1]) / step_h)
  if (!is.null(series$time)) out$time <- series$time[keep]
  out
}

# The binned log-log fit of rate against flow, weighted by bin counts.
.recession_fit <- function(points, bins) {
  lq <- log(points$flow)
  edges <- seq(min(lq), max(lq), length.out = bins + 1L)
  bin <- findInterval(lq, edges, rightmost.closed = TRUE)
  count <- tabulate(bin, bins)
  used <- which(count >= 3L)
  b <- data.frame(
    flow = exp(vapply(used, function(i) mean(lq[bin == i]), numeric(1))),
    rate = vapply(used, function(i) mean(points$rate[bin == i]), numeric(1)),
    n = count[used]
  )
  if (nrow(b) < 3L) return(list(slope = NA_real_, intercept = NA_real_, bins = b))
  fit <- stats::lm(log(rate) ~ log(flow), data = b, weights = b$n)
  list(slope = unname(stats::coef(fit)[2]), intercept = unname(stats::coef(fit)[1]), bins = b)
}

# A bootstrap interval for the slope from resampling whole recession runs.
.recession_ci <- function(points, bins, boot, seed) {
  if (boot == 0L) return(c(NA_real_, NA_real_))
  runs <- split(seq_len(nrow(points)), points$run)
  slopes <- .with_seed(seed, vapply(seq_len(boot), function(i) {
    pick <- runs[sample.int(length(runs), length(runs), replace = TRUE)]
    .recession_fit(points[unlist(pick), ], bins)$slope
  }, numeric(1)))
  unname(stats::quantile(slopes, c(0.025, 0.975), na.rm = TRUE))
}

#' Plot a recession analysis
#'
#' The recession points and bins on logarithmic axes, with the fitted line and, for reference,
#' lines of the slopes of the linear, cubic and exponential stores through the middle of the
#' bins. A second analysis, such as one of simulated flow, is drawn over the first.
#'
#' @param x A result of [recession_analysis()].
#' @param y Optional second result to compare, drawn in orange.
#' @param main Plot title.
#' @return `x`, invisibly.
#' @examples
#' # See recession_analysis().
#' @export
plot_recession <- function(x, y = NULL, main = "Recession analysis") {
  .check(inherits(x, "pdm_recession"), "x must come from recession_analysis()")
  .check(is.null(y) || inherits(y, "pdm_recession"), "y must come from recession_analysis()")
  all <- c(list(x), if (!is.null(y)) list(y))
  q <- unlist(lapply(all, function(r) r$points$flow))
  rate <- unlist(lapply(all, function(r) r$points$rate))
  graphics::plot(q, rate, log = "xy", type = "n", xlab = "Flow Q (m3/s)",
                 ylab = "Rate of fall -dQ/dt (m3/s per hour)", main = main, las = 1)
  draw <- function(r, col, label) {
    graphics::points(r$points$flow, r$points$rate, pch = 16, cex = 0.35,
                     col = grDevices::adjustcolor(col, 0.25))
    graphics::points(r$bins$flow, r$bins$rate, pch = 21, bg = col, col = "white", cex = 1.2)
    graphics::abline(r$intercept, r$slope, col = col, lwd = 2, untf = FALSE)
    sprintf("%s: slope %.2f (%.2f to %.2f)", label, r$slope, r$ci[1], r$ci[2])
  }
  # abline on log axes takes the line in log10 units; refit the intercept to base 10.
  to10 <- function(r) {
    r$intercept <- r$intercept / log(10)
    r
  }
  labels <- draw(to10(x), "#236b83", if (is.null(y)) "observed" else "first")
  if (!is.null(y)) labels <- c(labels, draw(to10(y), "#a26421", "second"))
  mid <- exp(mean(log(x$bins$flow)))
  at <- x$bins$rate[which.min(abs(log(x$bins$flow) - log(mid)))]
  for (s in c(linear = 1, cubic = 5 / 3, exponential = 2)) {
    graphics::abline(log10(at) - s * log10(mid), s, lty = 3, col = "grey50")
  }
  graphics::legend("topleft", c(labels, "store slopes 1, 1.67, 2"), bty = "n", cex = 0.8,
                   text.col = c("#236b83", if (!is.null(y)) "#a26421", "grey40"))
  invisible(x)
}

#' @export
print.pdm_recession <- function(x, ...) {
  cat(sprintf("Recession slope %.2f (95%% interval %.2f to %.2f), from %d points in %d runs\n",
              x$slope, x$ci[1], x$ci[2], nrow(x$points), length(unique(x$points$run))))
  consistent <- x$stores$store[x$stores$within_ci]
  cat(sprintf("Nearest store: %s. Consistent with the record: %s\n", x$nearest,
              if (length(consistent)) paste(consistent, collapse = ", ") else "none"))
  invisible(x)
}
