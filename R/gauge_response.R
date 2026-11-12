# gauge_response.R: which rain gauge the river answers to. For each gauge alone, the
#                   cross-correlation of its rain with the rises in flow, and, flood by flood,
#                   which gauge's rain best matches the rise.

#' Which rain gauge the river answers to
#'
#' Takes each rain gauge on its own and asks how closely the river's quick response follows
#' it, over the whole record and flood by flood. It is a check made before calibrating, from
#' the records alone: no model is run.
#'
#' **The fast response.** The rise in flow from one step to the next is moved almost only by
#' quick runoff, so the correlation of a gauge's rain with the rise a few steps later measures
#' how well that gauge explains the spikes. `lag_h` is the lag of the strongest
#' correlation, `r` its value.
#'
#' **Why not the slow response.** Baseflow answers to the rain of many storms over days or
#' weeks, and over such spans the gauges' totals converge: a correlation of gauge rain with
#' baseflow comes out much the same for every gauge, whichever drives it. Long-term drift
#' between gauges is a matter for the double-mass curve of [water_balance()].
#'
#' **Flood by flood.** For each of the `floods` largest events found on the catchment rain, by
#' peak flow, each gauge's rain is
#' correlated with the rise in flow across the event, at that gauge's own fast lag; the gauge
#' with the highest correlation wins the event. `event_wins` counts the wins, `event_share`
#' gives them as a share of the events with a winner. `size_r` is the correlation, across
#' events, of a gauge's event rain with the event's quick flow: whether the gauge sees the big
#' storms as big. `dry_events` counts events where a gauge recorded under a tenth of the
#' median gauge, when that median is at least `dry_mm`: a funnel blocked, a logger down, or a
#' storm that missed the gauge. A storm over one gauge alone leaves the median low and flags
#' nobody.
#'
#' **Reading it.** A gauge with a clearly higher `r` and most of the wins drives the
#' spike. Rain cannot follow the flow it causes, so a negative best lag means the gauge's clock
#' is late, or the flow's early; a gauge whose lag differs from its neighbours' by a whole
#' number of hours points the same way. A gauge with no wins, a low `size_r` or
#' many dry events is worth checking against its neighbours and the map. Correlations
#' between rain gauges blur the differences, as they do in any cross-correlation analysis
#' (Larocque et al., 1998): read the ranking and the gaps between gauges, not the values
#' alone.
#'
#' @param gauges A data frame or matrix of rain, mm per step, one column per gauge, named.
#'   Missing readings are allowed.
#' @param flow Observed flow, m3/s, the same length as the rows of `gauges`.
#' @param time Optional time stamps, for the event table.
#' @param dt Step length, hours.
#' @param rain Catchment rain for finding the events, mm per step. The mean of the gauges by
#'   default.
#' @param area_km2 Catchment area, km2, for the event quick flow. Without it `size_r` uses the
#'   peak flow.
#' @param max_lag_h Longest lag tried, hours.
#' @param lead_h Longest negative lag tried, hours: rain recorded after the rise it caused.
#' @param floods How many of the largest events, by peak flow, to judge flood by flood; `NULL`
#'   for every event.
#' @param dry_mm Event rain at the other gauges above which a near-empty gauge counts as dry.
#' @param events Events from [find_events()], if already found on the same record.
#' @return A `pdm_gauge_response` list: `summary`, one row per gauge as described above;
#'   `events`, one row per event with its winner and each gauge's rain (mm) and correlation;
#'   `correlation`, the cross-correlations by gauge, part and lag, for [plot()].
#' @references Larocque, M., Mangin, A., Razack, M. and Banton, O. (1998). Contribution of
#'   correlation and spectral analyses to the regional study of a large karst aquifer
#'   (Charente, France). Journal of Hydrology, 205, 217-231. doi:10.1016/S0022-1694(97)00155-8
#' @examples
#' river <- synthetic_catchment(years = 1, dt = 1, seed = 1)
#' set.seed(1)
#' gauges <- data.frame(a = river$forcing$rain * stats::rlnorm(nrow(river$forcing), 0, 0.3),
#'                      b = river$forcing$rain * stats::rlnorm(nrow(river$forcing), 0, 0.6))
#' gauge_response(gauges, river$observed, river$forcing$time, area_km2 = river$truth$area_km2)
#' @seealso [find_events()], [water_balance()]
#' @export
gauge_response <- function(gauges, flow, time = NULL, dt = 1, rain = NULL, area_km2 = NULL,
                           max_lag_h = 48, lead_h = 6, floods = 20, dry_mm = 5,
                           events = NULL) {
  labels <- colnames(gauges)
  .check(length(labels) >= 1 && all(nzchar(labels)) && !anyDuplicated(labels),
         "gauges must have one named column per gauge")
  gauges <- as.data.frame(gauges)
  .check(all(vapply(gauges, is.numeric, logical(1))), "gauges must be numeric, mm per step")
  .check(length(flow) == nrow(gauges), "flow must match the rows of gauges in length")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  .check(.scalar(max_lag_h, dt), "max_lag_h must be at least one step")
  .check(.scalar(lead_h, 0), "lead_h must be a nonnegative number of hours")
  .check(.scalar(dry_mm, 0), "dry_mm must be a nonnegative depth")
  .check(is.null(floods) || .scalar(floods, 1), "floods must be a positive count, or NULL")
  rain <- rain %||% rowMeans(gauges, na.rm = TRUE)
  rain[!is.finite(rain)] <- NA
  .check(length(rain) == nrow(gauges), "rain must match the rows of gauges in length")
  events <- events %||% find_events(.zero_missing(rain), flow, time, dt, area_km2 = area_km2)
  if (!is.null(floods) && nrow(events) > floods) {
    keep <- sort(order(events$peak_flow, decreasing = TRUE)[seq_len(floods)])
    events <- events[keep, , drop = FALSE]
  }
  lags <- seq.int(-as.integer(round(lead_h / dt)), as.integer(round(max_lag_h / dt)))
  rise <- c(NA, diff(flow))
  correlation <- do.call(rbind, lapply(names(gauges), function(g) {
    data.frame(gauge = g, lag_h = lags * dt, r = .lag_correlation(gauges[[g]], rise, lags))
  }))
  best <- function(g) {
    rows <- correlation[correlation$gauge == g, ]
    if (all(is.na(rows$r))) return(c(NA_real_, NA_real_))
    k <- which.max(rows$r)
    c(rows$lag_h[k], rows$r[k])
  }
  fast <- vapply(names(gauges), best, numeric(2))
  table <- .gauge_events(gauges, rise, events, round(fast[1, ] / dt), dry_mm)
  out <- list(summary = .gauge_summary(names(gauges), fast, table, events),
              events = table, correlation = correlation, dt = dt)
  class(out) <- "pdm_gauge_response"
  out
}

# Correlation of x with y at each lag in steps (positive: y after x), pairwise complete.
.lag_correlation <- function(x, y, lags) {
  n <- length(x)
  vapply(lags, function(k) {
    if (n - abs(k) < 3L) return(NA_real_)
    a <- if (k >= 0) x[seq_len(n - k)] else x[(1L - k):n]
    b <- if (k >= 0) y[(k + 1L):n] else y[seq_len(n + k)]
    ok <- is.finite(a) & is.finite(b)
    if (sum(ok) < 3L || stats::sd(a[ok]) == 0 || stats::sd(b[ok]) == 0) return(NA_real_)
    stats::cor(a[ok], b[ok])
  }, numeric(1))
}

# Per event: each gauge's rain and its correlation with the rise at its own lag, the winner,
# and the dry flags.
.gauge_events <- function(gauges, rise, events, lags, dry_mm) {
  names_g <- names(gauges)
  rows <- lapply(seq_len(nrow(events)), function(e) {
    r0 <- events$rain_start[e]
    r1 <- events$flow_end[e]
    depth <- vapply(names_g, function(g) {
      sum(gauges[[g]][events$rain_start[e]:events$rain_end[e]], na.rm = TRUE)
    }, numeric(1))
    fit <- vapply(names_g, function(g) {
      k <- lags[[g]]
      if (!is.finite(k) || r1 - r0 - abs(k) < 2L) return(NA_real_)
      .lag_correlation(gauges[[g]][r0:r1], rise[r0:r1], k)
    }, numeric(1))
    typical <- stats::median(depth)
    dry <- length(depth) > 1L & is.finite(typical) & typical >= dry_mm & depth < 0.1 * typical
    winner <- if (all(is.na(fit))) NA_character_ else names_g[which.max(fit)]
    data.frame(event = events$event[e], winner = winner,
               dry = paste(names_g[dry], collapse = ";"),
               t(stats::setNames(depth, paste0(names_g, ".rain_mm"))),
               t(stats::setNames(fit, paste0(names_g, ".r"))), check.names = FALSE)
  })
  out <- if (length(rows)) do.call(rbind, rows) else data.frame(event = integer(0))
  for (col in intersect(c("rain_start_time", "peak_flow", "quickflow_mm"), names(events))) {
    out[[col]] <- events[[col]]
  }
  out
}

# One row per gauge: the best lag and correlation, the wins, the size match and the dry
# events.
.gauge_summary <- function(names_g, fast, table, events) {
  size <- events$quickflow_mm %||% events$peak_flow
  decided <- sum(!is.na(table$winner))
  data.frame(
    gauge = names_g,
    lag_h = unname(fast[1, ]), r = unname(fast[2, ]),
    event_wins = vapply(names_g, function(g) sum(table$winner == g, na.rm = TRUE), integer(1),
                        USE.NAMES = FALSE),
    event_share = vapply(names_g, function(g) {
      if (decided == 0L) NA_real_ else sum(table$winner == g, na.rm = TRUE) / decided
    }, numeric(1), USE.NAMES = FALSE),
    size_r = vapply(names_g, function(g) {
      depth <- table[[paste0(g, ".rain_mm")]]
      ok <- is.finite(depth) & is.finite(size)
      if (sum(ok) < 3L || stats::sd(depth[ok]) == 0) NA_real_ else stats::cor(depth[ok], size[ok])
    }, numeric(1), USE.NAMES = FALSE),
    dry_events = vapply(names_g, function(g) {
      sum(vapply(strsplit(table$dry, ";", fixed = TRUE), function(d) g %in% d, logical(1)))
    }, integer(1), USE.NAMES = FALSE),
    row.names = NULL
  )
}

#' @export
print.pdm_gauge_response <- function(x, ...) {
  s <- x$summary
  cat(sprintf("Gauge response: %d gauges, %d events\n", nrow(s), nrow(x$events)))
  shown <- s
  for (col in c("r", "event_share", "size_r")) shown[[col]] <- round(s[[col]], 2)
  print(shown, row.names = FALSE)
  invisible(x)
}

#' @export
plot.pdm_gauge_response <- function(x, ...) {
  old <- graphics::par(mar = c(4, 4.2, 0.8, 0.6))
  on.exit(graphics::par(old))
  rows <- x$correlation
  gauges <- unique(rows$gauge)
  cols <- grDevices::hcl.colors(max(3L, length(gauges)), "Dark 3")[seq_along(gauges)]
  graphics::plot(range(rows$lag_h), range(c(0, rows$r), na.rm = TRUE), type = "n", las = 1,
                 xlab = "Lag of the rise in flow behind the rain (hours)", ylab = "Correlation")
  graphics::abline(h = 0, v = 0, col = "grey80")
  for (i in seq_along(gauges)) {
    g <- rows[rows$gauge == gauges[i], ]
    graphics::lines(g$lag_h, g$r, col = cols[i], lwd = 1.6)
    k <- which.max(g$r)
    if (length(k)) graphics::points(g$lag_h[k], g$r[k], col = cols[i], pch = 19)
  }
  graphics::legend("topright", gauges, col = cols, lwd = 1.6, bty = "n", cex = 0.8)
  invisible(x)
}
