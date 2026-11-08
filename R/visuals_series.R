# ============================================================ #
# Tool:         visuals_series
# Description:  Standard run diagnostics: hydrograph, flow duration curve, cumulative volume
#               and residuals, in base R (plot) and ggplot2 (autoplot)
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-08
# Modified:     2026-11-08 - First version
# Tier:         3
# Inputs:       Simulated and observed flow (m3/s), rain (mm per step), times, windows,
#               thresholds; or a calibration project entry
# Outputs:      A pdm_series object and its plots
# Dependencies: graphics; stats; ggplot2 (suggested)
# ============================================================ #

#' Series for the standard run plots
#'
#' Gathers a simulation and what belongs with it (observed flow, rain, times, the calibration
#' and validation windows, warning thresholds and an optional second run) for the standard run
#' plots. `plot()` draws them in base R and `autoplot()` returns a ggplot; both draw the same
#' figure in the pdmS7 house style ([pdm_colours()]).
#'
#' | `type` | Shows |
#' |---|---|
#' | `hydrograph` | flow against time; rain hangs from the top, windows shaded, thresholds dashed |
#' | `duration` | flow duration curves: the share of time each flow is exceeded, on a log scale |
#' | `volume` | cumulative volume, to see where the water balance drifts |
#' | `residuals` | simulated minus observed flow, with its 30-day running mean |
#'
#' `project_series()` builds the series for a model entry of a calibration project from the
#' registered data, so a logged run can be drawn without rerunning it by hand.
#'
#' Long records are thinned for drawing only: rain is summed into at most 1,500 bars and the
#' duration curves are drawn from 500 quantiles. Lines keep every step.
#'
#' @param simulated Simulated flow, m3/s.
#' @param observed Observed flow, m3/s, the same length; optional.
#' @param rain Rain, mm per step; optional.
#' @param time POSIXct times of each step (the end of the step); optional. Without times, the
#'   x axis is hours from the start.
#' @param dt Step length in hours.
#' @param windows Named list of windows to shade, such as
#'   `list(calibration = c(first, last), validation = c(first, last))`, each a pair of row
#'   numbers or of times.
#' @param thresholds Named numeric vector of threshold flows, m3/s.
#' @param alternative A second simulation to compare, such as the run before a change.
#' @param labels Named character vector of legend labels for `observed`, `simulated` and
#'   `alternative`.
#' @param project A calibration project folder.
#' @param entry Model entry to draw (structure, trial, calibration or candidate); by default
#'   the latest candidate, or the latest model entry.
#' @param compare Optional second entry, drawn as the alternative.
#' @param x,object A `pdm_series`.
#' @param type Which plot: `hydrograph`, `duration`, `volume` or `residuals`.
#' @param period Rows to draw: `NULL` for all, a window name such as `"validation"`, or a pair
#'   of row numbers or times.
#' @param ... Not used.
#'
#' @return `pdm_series()` and `project_series()`: a `pdm_series` list. `plot()`: `x`,
#'   invisibly. `autoplot()`: a ggplot.
#' @examples
#' rain <- synthetic_rain("2021-01-01", years = 1, dt = 1, seed = 2)
#' forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
#' model <- pdm_from_config(modifyList(pdm_presets("standard"), list(area_km2 = 30)))
#' sim <- run_pdm(model, forcing)$output$q_m3s
#' obs <- sim * exp(rnorm(length(sim), 0, 0.1))
#' s <- pdm_series(sim, obs, rain = forcing$rain, time = forcing$time,
#'                 windows = list(calibration = c(1, 6000), validation = c(6001, 8760)),
#'                 thresholds = c(Alert = 2))
#' plot(s)
#' plot(s, period = c(3000, 3400))
#' plot(s, type = "duration")
#' if (requireNamespace("ggplot2", quietly = TRUE)) ggplot2::autoplot(s, type = "volume")
#' @seealso [pdm_colours()], [pdm_save()]
#' @export
pdm_series <- function(simulated, observed = NULL, rain = NULL, time = NULL, dt = 1,
                       windows = NULL, thresholds = NULL, alternative = NULL, labels = NULL) {
  n <- length(simulated)
  .check(is.numeric(simulated) && n > 1L, "simulated must be a numeric series")
  for (arg in c("observed", "rain", "alternative")) {
    v <- get(arg)
    .check(is.null(v) || (is.numeric(v) && length(v) == n),
           paste(arg, "must be numeric and as long as simulated"))
  }
  .check(is.null(time) || (inherits(time, "POSIXt") && length(time) == n),
         "time must be POSIXct and as long as simulated")
  .check(is.numeric(dt) && length(dt) == 1L && dt > 0, "dt must be a positive number of hours")
  .check(is.null(thresholds) || (is.numeric(thresholds) && !is.null(names(thresholds))),
         "thresholds must be a named numeric vector of flows")
  defaults <- c(observed = "Observed", simulated = "Simulated", alternative = "Alternative")
  labels <- c(labels, defaults[setdiff(names(defaults), names(labels))])[names(defaults)]
  structure(list(
    simulated = as.numeric(simulated), observed = observed, rain = rain,
    time = if (is.null(time)) NULL else as.POSIXct(time, tz = "UTC"), dt = dt,
    windows = .series_windows(windows, time, n), thresholds = thresholds,
    alternative = alternative, labels = labels
  ), class = "pdm_series")
}

#' @rdname pdm_series
#' @export
project_series <- function(project, entry = NULL, compare = NULL) {
  path <- .project_path(project)
  entries <- .read_entries(path)
  registration <- .registration(entries)
  card <- registration$scorecard
  data <- .load_registration(path, registration)
  node <- .workbench_node(entries, entry)
  run <- function(config) {
    model <- pdm_from_config(config)
    start <- .workbench_start(model, card, data$observed)
    .quietly(run_pdm(model, data$forcing, start))$output$q_m3s
  }
  other <- if (is.null(compare)) NULL else .workbench_node(entries, compare)
  windows <- Filter(Negate(is.null), lapply(card[c("calibration", "validation")], function(w) {
    if (is.null(w)) NULL else c(w$first_row, w$last_row)
  }))
  thresholds <- if (length(card$thresholds)) {
    stats::setNames(vapply(card$thresholds, function(t) t$flow_m3s, numeric(1)),
                    vapply(card$thresholds, function(t) t$name, character(1)))
  }
  pdm_series(
    run(node$configuration), data$observed, rain = data$forcing$rain,
    time = if ("time" %in% names(data$forcing)) data$forcing$time else NULL,
    dt = pdm_from_config(node$configuration)@dt, windows = windows, thresholds = thresholds,
    alternative = if (is.null(other)) NULL else run(other$configuration),
    labels = c(simulated = paste("Entry", node$id),
               alternative = if (is.null(other)) "Alternative" else paste("Entry", other$id))
  )
}

#' @rdname pdm_series
#' @export
plot.pdm_series <- function(x, type = c("hydrograph", "duration", "volume", "residuals"),
                            period = NULL, ...) {
  .draw_base(.series_spec(x, match.arg(type), period))
  invisible(x)
}

#' @rdname pdm_series
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_series <- function(object, type = c("hydrograph", "duration", "volume",
                                                 "residuals"),
                                period = NULL, ...) {
  .draw_gg(.series_spec(object, match.arg(type), period))
}

#' @export
print.pdm_series <- function(x, ...) {
  span <- if (is.null(x$time)) sprintf("%d steps of %g h", length(x$simulated), x$dt) else
    sprintf("%s to %s", format(min(x$time), "%Y-%m-%d %H:%M"),
            format(max(x$time), "%Y-%m-%d %H:%M"))
  has <- c(observed = !is.null(x$observed), rain = !is.null(x$rain),
           alternative = !is.null(x$alternative))
  cat(sprintf("Series for the standard run plots: %s\nWith %s; windows: %s; thresholds: %s\n",
              span, if (any(has)) paste(names(has)[has], collapse = ", ") else "simulation only",
              if (length(x$windows)) paste(names(x$windows), collapse = ", ") else "none",
              if (length(x$thresholds)) paste(names(x$thresholds), collapse = ", ") else "none"))
  invisible(x)
}

# ---- Descriptions ------------------------------------------------------------------------

# Windows as row pairs, from row numbers or times.
.series_windows <- function(windows, time, n) {
  if (is.null(windows)) return(list())
  .check(is.list(windows) && !is.null(names(windows)) && all(nzchar(names(windows))),
         "windows must be a named list of pairs")
  lapply(windows, function(w) {
    .check(length(w) == 2L, "each window must be a pair: first and last")
    rows <- .series_rows_of(w, time, n)
    .check(rows[1] <= rows[2], "a window must not end before it starts")
    rows
  })
}

# Row numbers of a pair given as rows or times.
.series_rows_of <- function(w, time, n) {
  if (is.numeric(w) && !inherits(w, "POSIXt")) {
    .check(all(w >= 1 & w <= n), "window rows must lie within the series")
    return(as.integer(round(w)))
  }
  .check(!is.null(time), "windows given as times need time")
  w <- as.POSIXct(w, tz = "UTC")
  c(which(time >= w[1])[1], utils::tail(which(time <= w[2]), 1))
}

# The rows a plot draws.
.series_period <- function(x, period) {
  n <- length(x$simulated)
  if (is.null(period)) return(seq_len(n))
  if (is.character(period) && length(period) == 1L && !grepl("^[0-9]", period)) {
    .check(period %in% names(x$windows),
           paste("No window", period, "; windows are", paste(names(x$windows), collapse = ", ")))
    w <- x$windows[[period]]
    return(seq.int(w[1], w[2]))
  }
  .check(length(period) == 2L, "period must be a window name or a pair")
  w <- .series_rows_of(period, x$time, n)
  .check(all(is.finite(w)) && w[1] <= w[2], "period selects no rows")
  seq.int(w[1], w[2])
}

.series_spec <- function(x, type, period) {
  rows <- .series_period(x, period)
  .check(type == "hydrograph" || !is.null(x$observed),
         paste("A", type, "plot needs observed flow"))
  switch(type,
    hydrograph = .spec_hydrograph(x, rows),
    duration = .spec_duration(x, rows),
    volume = .spec_volume(x, rows),
    residuals = .spec_residuals(x, rows)
  )
}

# The x values of rows: times, or hours from the start.
.series_x <- function(x, rows) if (is.null(x$time)) rows * x$dt else x$time[rows]

# The flows present: observed, simulated and alternative, with their labels and colours.
.series_flows <- function(x) {
  out <- list(observed = x$observed, simulated = x$simulated, alternative = x$alternative)
  out[!vapply(out, is.null, logical(1))]
}

.spec_hydrograph <- function(x, rows) {
  xv <- .series_x(x, rows)
  flows <- .series_flows(x)
  lwd <- c(observed = 0.9, simulated = 1.5, alternative = 1.5)
  # Runs first and observed last, so the measured line sits on top.
  series <- do.call(rbind, lapply(rev(names(flows)), function(r) {
    .layer(xv, flows[[r]][rows], x$labels[[r]], .pdm_roles[[r]], lwd = lwd[[r]])
  }))
  peak <- max(c(series$y, x$thresholds), na.rm = TRUE)
  rain <- if (is.null(x$rain)) NULL else .series_rain(x, rows, xv, peak)
  list(
    series = series, bands = .series_bands(x, rows, xv), rain = rain$layer, rain_axis = TRUE,
    hlines = if (length(x$thresholds)) {
      data.frame(panel = 1L, y = unname(x$thresholds), label = names(x$thresholds),
                 colour = .pdm_roles[["threshold"]])
    },
    xlab = if (is.null(x$time)) "Hours" else "", ylab = "Flow (m3/s)", log = "",
    title = "Hydrograph", subtitle = rain$note, legend = unname(x$labels[names(flows)])
  )
}

# Rain summed into at most 1,500 bars, each spanning its steps.
.series_rain <- function(x, rows, xv, peak) {
  bin <- max(1L, ceiling(length(rows) / 1500))
  group <- (seq_along(rows) - 1L) %/% bin
  depth <- as.numeric(tapply(x$rain[rows], group, sum, na.rm = TRUE))
  first <- as.integer(tapply(seq_along(rows), group, min))
  last <- as.integer(tapply(seq_along(rows), group, max))
  step <- if (is.null(x$time)) x$dt else x$dt * 3600
  list(layer = .rain_layer(xv[first] - step, xv[last], depth, peak),
       note = if (bin > 1L) sprintf("Rain summed over %g h", bin * x$dt))
}

.series_bands <- function(x, rows, xv) {
  bands <- lapply(names(x$windows), function(name) {
    w <- x$windows[[name]]
    lo <- max(w[1], rows[1])
    hi <- min(w[2], rows[length(rows)])
    if (lo > hi) return(NULL)
    role <- if (name %in% names(.band_alpha)) name else "calibration"
    data.frame(panel = 1L, xmin = xv[lo - rows[1] + 1L], xmax = xv[hi - rows[1] + 1L],
               label = paste(toupper(substring(name, 1, 1)), substring(name, 2), sep = ""),
               fill = grDevices::adjustcolor(.pdm_roles[[role]], .band_alpha[[role]]))
  })
  out <- do.call(rbind, bands)
  if (is.null(out) || !nrow(out)) NULL else out
}

# Flow duration curves from 500 quantiles of the steps where observed and simulated both exist.
.spec_duration <- function(x, rows) {
  flows <- .series_flows(x)
  ok <- Reduce(`&`, lapply(flows, function(f) is.finite(f[rows]) & f[rows] > 0))
  .check(sum(ok) > 10, "Too few steps with flow to draw duration curves")
  p <- seq(0.1, 99.9, length.out = 500)
  series <- do.call(rbind, lapply(names(flows), function(r) {
    q <- stats::quantile(flows[[r]][rows][ok], 1 - p / 100, names = FALSE)
    .layer(p, q, x$labels[[r]], .pdm_roles[[r]], lwd = 1.5)
  }))
  list(series = series, xlab = "Percentage of time flow is exceeded", ylab = "Flow (m3/s)",
       log = "y", title = "Flow duration curve",
       subtitle = sprintf("%s steps with every series present", format(sum(ok), big.mark = ",")))
}

# Cumulative volume over the steps where every series is present; gaps add nothing.
.spec_volume <- function(x, rows) {
  flows <- .series_flows(x)
  ok <- Reduce(`&`, lapply(flows, function(f) is.finite(f[rows])))
  xv <- .series_x(x, rows)
  to_mm3 <- x$dt * 3600 / 1e6
  totals <- vapply(flows, function(f) sum(f[rows][ok]) * to_mm3, numeric(1))
  series <- do.call(rbind, lapply(names(flows), function(r) {
    .layer(xv, cumsum(ifelse(ok, flows[[r]][rows], 0)) * to_mm3, x$labels[[r]],
           .pdm_roles[[r]], lwd = 1.5)
  }))
  note <- paste(vapply(setdiff(names(flows), "observed"), function(r) {
    sprintf("%s %+.1f%%", x$labels[[r]], 100 * (totals[[r]] / totals[["observed"]] - 1))
  }, character(1)), collapse = "; ")
  list(series = series, bands = .series_bands(x, rows, xv),
       xlab = if (is.null(x$time)) "Hours" else "", ylab = "Cumulative volume (million m3)",
       log = "", title = "Cumulative volume", subtitle = paste("Total against observed:", note))
}

# Simulated minus observed, with a 30-day centred running mean.
.spec_residuals <- function(x, rows) {
  xv <- .series_x(x, rows)
  span <- max(1L, round(720 / x$dt))
  runs <- intersect(c("simulated", "alternative"), names(.series_flows(x)))
  series <- do.call(rbind, lapply(runs, function(r) {
    res <- x[[r]][rows] - x$observed[rows]
    rbind(.layer(xv, res, x$labels[[r]], grDevices::adjustcolor(.pdm_roles[[r]], 0.35),
                 lwd = 0.6),
          .layer(xv, .running_mean(res, span), paste(x$labels[[r]], "30-day mean"),
                 .pdm_roles[[r]], lwd = 1.8))
  }))
  # Storm spikes would flatten the running means, which are the point: the axis spans the
  # middle 98% of the residuals.
  raw <- series$y[!grepl("30-day mean$", series$label)]
  ylim <- stats::quantile(raw, c(0.01, 0.99), na.rm = TRUE, names = FALSE)
  ylim <- range(ylim, 0, series$y[grepl("30-day mean$", series$label)], na.rm = TRUE)
  list(series = series, bands = .series_bands(x, rows, xv), ylim = ylim,
       hlines = data.frame(panel = 1L, y = 0, label = "", colour = .pdm_roles[["reference"]]),
       xlab = if (is.null(x$time)) "Hours" else "", ylab = "Simulated - observed (m3/s)",
       log = "", title = "Residuals",
       subtitle = "Axis spans the middle 98% of residuals; storm peaks run off the scale")
}

# A centred running mean that ignores missing values and needs half the window present.
.running_mean <- function(v, span) {
  ok <- is.finite(v)
  k <- rep(1, span)
  total <- stats::filter(ifelse(ok, v, 0), k, sides = 2)
  count <- stats::filter(as.numeric(ok), k, sides = 2)
  out <- as.numeric(total / count)
  out[!is.finite(out) | as.numeric(count) < span / 2] <- NA_real_
  out
}
