# ============================================================ #
# Tool:         visuals_calibration
# Description:  Standard calibration and event plots: the path through the stages, starts,
#               windows, parameters within their bounds, event rain against quick flow, peaks
#               and timing, in base R (plot) and ggplot2 (autoplot)
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-08
# Modified:     2026-11-08 - First version (standard visuals, part 2)
# Tier:         3
# Inputs:       A calibration project; event tables; calibration_checks() results
# Outputs:      Plots in the pdmS7 house style
# Dependencies: graphics; ggplot2 (suggested)
# ============================================================ #

# ---- Events ------------------------------------------------------------------------------

# Event tables carry the class pdm_events, so plot() and autoplot() find them.
.as_events <- function(x) {
  class(x) <- unique(c("pdm_events", setdiff(class(x), "pdm_events")))
  x
}

#' Plot a table of events
#'
#' Event tables from [find_events()], [screen_events()], [event_scores()] and the `events` of
#' [calibration_checks()] draw three standard plots:
#'
#' | `type` | Shows | Needs |
#' |---|---|---|
#' | `balance` | each event's rain against its quick flow, runoff-ratio lines | [find_events()] |
#' | `peaks` | simulated against observed peak, with 1:1 and a 20% band | [event_scores()] |
#' | `timing` | the timing error of each peak against its size | [event_scores()] |
#'
#' **The balance plot** is a check on the data before it is a check on the model. An event
#' can shed no more quick flow than the rain that fell, so a point above the runoff-ratio line
#' of `max_ratio` means the rain record missed that storm, the area is wrong, or the flow is.
#' Points far below the rest mark rain the gauges recorded but the river did not feel. Screened
#' events ([screen_events()]) are drawn hollow; when the table has a `period` column (from
#' [calibration_checks()]), events are coloured by window.
#'
#' @param x,object An event table.
#' @param type One of the plots above.
#' @param max_ratio Runoff ratio drawn as the limit on the balance plot.
#' @param ... Not used.
#' @return `plot()`: `x`, invisibly. `autoplot()`: a ggplot.
#' @examples
#' rain <- synthetic_rain("2021-01-01", years = 1, dt = 1, seed = 2)
#' config <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(config), rain[c("rain", "pet")])$output$q_m3s
#' events <- find_events(rain$rain, flow, rain$time, dt = 1, area_km2 = 20)
#' plot(events)
#' plot(event_scores(events, flow * 0.9, flow), type = "peaks")
#' @seealso [find_events()], [calibration_checks()], [pdm_colours()]
#' @export
plot.pdm_events <- function(x, type = c("balance", "peaks", "timing"), max_ratio = 1, ...) {
  .draw_base(.events_spec(x, match.arg(type), max_ratio))
  invisible(x)
}

#' @rdname plot.pdm_events
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_events <- function(object, type = c("balance", "peaks", "timing"), max_ratio = 1,
                                ...) {
  .draw_gg(.events_spec(object, match.arg(type), max_ratio))
}

.events_spec <- function(x, type, max_ratio) {
  need <- switch(type, balance = c("rain_mm", "quickflow_mm"),
                 peaks = c("observed_peak", "simulated_peak"),
                 timing = c("observed_peak", "timing_error_h"))
  .check(all(need %in% names(x)), paste0(
    "A ", type, " plot needs ", paste(need, collapse = " and "), ": ",
    if (type == "balance") "events from find_events()" else "events scored by event_scores()"
  ))
  groups <- .event_groups(x)
  switch(type,
    balance = .spec_balance(x, groups, max_ratio),
    peaks = .spec_peaks(x, groups),
    timing = .spec_timing(x, groups)
  )
}

# Which group each event is drawn in: its window when known, hollow when screened out.
.event_groups <- function(x) {
  used <- if ("use" %in% names(x)) x$use %in% TRUE else rep(TRUE, nrow(x))
  window <- if ("period" %in% names(x)) x$period else rep("events", nrow(x))
  colour <- c(calibration = "#000000", validation = .pdm_roles[["validation"]],
              wettest = .pdm_roles[["alternative"]], outside = .pdm_roles[["reference"]],
              events = .pdm_roles[["observed"]])
  label <- ifelse(used, ifelse(window == "events", "Events",
                               paste(toupper(substring(window, 1, 1)), substring(window, 2),
                                     sep = "")), "Screened out")
  data.frame(label = label, colour = ifelse(used, unname(colour[window]),
                                            .pdm_roles[["reference"]]),
             geom = ifelse(used, "point", "open"))
}

# Points in groups, one layer per group, in a fixed order.
.event_points <- function(xv, yv, groups) {
  order <- c("Events", "Calibration", "Validation", "Wettest", "Outside", "Screened out")
  present <- intersect(order, unique(groups$label))
  do.call(rbind, lapply(rev(present), function(g) {
    k <- groups$label == g
    .layer(xv[k], yv[k], g, groups$colour[k][1], geom = groups$geom[k][1], lwd = 2.2)
  }))
}

.spec_balance <- function(x, groups, max_ratio) {
  ok <- is.finite(x$rain_mm) & x$rain_mm > 0 & is.finite(x$quickflow_mm) & x$quickflow_mm > 0
  .check(any(ok), "No event has both rain and quick flow to plot")
  pts <- .event_points(x$rain_mm[ok], x$quickflow_mm[ok], groups[ok, ])
  line <- range(pts$x)
  ratios <- unique(c(max_ratio, 0.5, 0.1))
  guides <- do.call(rbind, lapply(ratios, function(r) {
    limit <- r == max_ratio
    .layer(line, line * r,
           if (limit) sprintf("Runoff ratio %g (limit)", r) else paste0(".ratio ", r),
           if (limit) .pdm_roles[["threshold"]] else .pdm_roles[["grid"]],
           lty = if (limit) 2 else 1, lwd = 1.2)
  }))
  above <- sum(x$runoff_ratio[ok] > max_ratio, na.rm = TRUE)
  list(series = rbind(guides, pts), log = "xy", xlab = "Event rain (mm)",
       ylab = "Event quick flow (mm)", title = "Event rain and quick flow",
       subtitle = sprintf(paste("%d events, %d above a runoff ratio of %g%s.",
                                "Grey lines: ratios 0.5 and 0.1"),
                          sum(ok), above, max_ratio,
                          if (sum(!ok)) sprintf("; %d without rain or quick flow", sum(!ok)) else
                            ""))
}

.spec_peaks <- function(x, groups) {
  ok <- is.finite(x$observed_peak) & is.finite(x$simulated_peak)
  pts <- .event_points(x$observed_peak[ok], x$simulated_peak[ok], groups[ok, ])
  top <- max(c(pts$x, pts$y)) * 1.05
  band <- rbind(.layer(c(0, top), c(0, top), "1:1", .pdm_roles[["reference"]], lwd = 1.2),
                .layer(c(0, top, NA, 0, top), c(0, top * 1.2, NA, 0, top * 0.8),
                       "Within 20%", .pdm_roles[["reference"]], lty = 2, lwd = 1))
  ratio <- x$simulated_peak[ok] / x$observed_peak[ok]
  within <- abs(ratio - 1) <= 0.2
  list(series = rbind(band, pts), log = "", ylim = c(0, top),
       xlab = "Observed peak (m3/s)", ylab = "Simulated peak (m3/s)", title = "Event peaks",
       subtitle = sprintf("%d of %d peaks within 20%%; median error %+.0f%%", sum(within),
                          sum(ok), 100 * stats::median(ratio - 1)))
}

.spec_timing <- function(x, groups) {
  ok <- is.finite(x$observed_peak) & is.finite(x$timing_error_h)
  list(series = .event_points(x$observed_peak[ok], x$timing_error_h[ok], groups[ok, ]),
       hlines = data.frame(panel = 1L, y = 0, label = "", colour = .pdm_roles[["reference"]]),
       log = "", xlab = "Observed peak (m3/s)", ylab = "Simulated peak late by (h)",
       title = "Event timing",
       subtitle = sprintf("Median %+.1f h; positive is late",
                          stats::median(x$timing_error_h[ok])))
}

# ---- Calibration checks ------------------------------------------------------------------

#' Plot the acceptance checks of a calibration
#'
#' `plot()` and `autoplot()` draw the checks of [calibration_checks()]:
#'
#' | `type` | Shows |
#' |---|---|
#' | `bounds` | where each parameter sits within its search range; one at an end is flagged |
#' | `peaks`, `timing`, `balance` | the project's events by window, as [plot.pdm_events()] draws |
#'
#' A parameter at an end of its range is the clearest warning sign a calibration gives: the
#' search wanted to go further than a sensible value, usually to make up for something the
#' structure cannot do.
#'
#' @param x,object A result of [calibration_checks()].
#' @param type One of the plots above.
#' @param ... Passed to [plot.pdm_events()] for the event plots.
#' @return `plot()`: `x`, invisibly. `autoplot()`: a ggplot.
#' @examples
#' \dontrun{
#' checks <- calibration_checks("projects/beggearn_huish")
#' plot(checks)
#' plot(checks, type = "peaks")
#' }
#' @seealso [calibration_checks()], [plot.pdm_events()]
#' @export
plot.pdm_calibration_checks <- function(x, type = c("bounds", "peaks", "timing", "balance"),
                                        ...) {
  type <- match.arg(type)
  if (type == "bounds") .draw_base(.bounds_spec(x)) else plot(.as_events(x$events), type, ...)
  invisible(x)
}

#' @rdname plot.pdm_calibration_checks
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_calibration_checks <- function(object, type = c("bounds", "peaks", "timing",
                                                             "balance"), ...) {
  type <- match.arg(type)
  if (type == "bounds") .draw_gg(.bounds_spec(object)) else
    autoplot.pdm_events(.as_events(object$events), type, ...)
}

# Each parameter's place in its range, 0 at the lower end and 1 at the upper, on the scale the
# search used (logarithmic for those searched on logs).
.bounds_spec <- function(x) {
  p <- x$parameters
  logs <- p$scale %in% "log"
  pos <- ifelse(logs, log(p$value / p$lower) / log(p$upper / p$lower),
                (p$value - p$lower) / (p$upper - p$lower))
  y <- rev(seq_len(nrow(p)))
  flagged <- !is.na(p$at_bound)
  series <- rbind(
    .layer(rep(c(0, 1, NA), nrow(p)), rep(y, each = 3) + c(0, 0, NA), ".range",
           .pdm_roles[["grid"]], lwd = 3),
    if (any(!flagged)) .layer(pos[!flagged], y[!flagged], "Within its range",
                              .pdm_roles[["simulated"]], geom = "point", lwd = 2.6),
    if (any(flagged)) .layer(pos[flagged], y[flagged], "At a bound", .pdm_roles[["flag"]],
                             geom = "point", lwd = 3)
  )
  labels <- sprintf("%s = %s", p$path, signif(p$value, 3))
  list(series = series, log = "", xlab = "Place in the search range (0 lower, 1 upper)",
       ylab = "", title = "Parameters within their bounds", xlim = c(-0.02, 1.02),
       ylim = c(0.5, nrow(p) + 0.5), yticks = list(at = y, labels = labels),
       subtitle = if (any(flagged)) sprintf("%d at a bound: review before use", sum(flagged))
       else "None at a bound")
}

# ---- The calibration path ----------------------------------------------------------------

#' The path of a calibration through its stages
#'
#' Gathers the automatic calibrations of a project in the order they ran, with each stage's
#' scores, every start's result, and the candidate's scores in each window, for three
#' standard plots:
#'
#' | `type` | Shows |
#' |---|---|
#' | `stages` | NSE, log NSE and volume error after each stage |
#' | `starts` | each start's objective in each stage, the best filled |
#' | `windows` | the candidate's scores in the calibration, validation and test windows |
#'
#' @param project A calibration project folder.
#' @param x,object A `pdm_calibration_path`.
#' @param type One of the plots above.
#' @param ... Not used.
#' @return `calibration_path()`: a `pdm_calibration_path` list with `stages` (one row per
#'   automatic calibration entry), `starts` (one row per start) and `windows` (the candidate's
#'   scores by window, or `NULL`). `plot()`: `x`, invisibly. `autoplot()`: a ggplot.
#' @examples
#' \dontrun{
#' path <- calibration_path("projects/beggearn_huish")
#' plot(path)
#' plot(path, type = "windows")
#' }
#' @seealso [log_staged_calibration()], [calibration_checks()]
#' @export
calibration_path <- function(project) {
  entries <- .read_entries(.project_path(project))
  fits <- Filter(function(e) e$type == "auto_calibration", entries)
  .check(length(fits) > 0, "The project has no automatic calibration yet")
  stages <- do.call(rbind, lapply(seq_along(fits), function(i) {
    e <- fits[[i]]
    data.frame(step = i, id = e$id, stage = e$stage %||% paste("Calibration", e$id),
               objective = e$objective_name %||% e$objective, evaluations = e$evaluations,
               nse = e$scores$nse %||% NA_real_, log_nse = e$scores$log_nse %||% NA_real_,
               volume_error = e$scores$volume_error %||% NA_real_)
  }))
  starts <- do.call(rbind, lapply(seq_along(fits), function(i) {
    s <- as.data.frame(lapply(fits[[i]]$start_results[c("start", "objective", "best")],
                              unlist))
    data.frame(step = i, id = fits[[i]]$id, start = s$start, objective = s$objective,
               best = s$best %in% TRUE)
  }))
  structure(list(stages = stages, starts = starts, windows = .path_windows(entries)),
            class = "pdm_calibration_path")
}

# The candidate's scores in each window it has been scored on.
.path_windows <- function(entries) {
  validation <- .latest(entries, "validation")
  test <- .latest(entries, "test")
  sets <- list(calibration = validation$calibration_scores,
               validation = validation$validation_scores,
               test = test$test_scores %||% test$scores)
  sets <- Filter(Negate(is.null), sets)
  if (!length(sets)) return(NULL)
  do.call(rbind, lapply(names(sets), function(w) {
    s <- sets[[w]]
    data.frame(window = w, metric = c("nse", "log_nse", "kge"),
               value = c(s$nse %||% NA_real_, s$log_nse %||% NA_real_, s$kge %||% NA_real_))
  }))
}

#' @export
print.pdm_calibration_path <- function(x, ...) {
  cat(sprintf("Calibration path: %d automatic calibration%s\n", nrow(x$stages),
              if (nrow(x$stages) == 1L) "" else "s"))
  s <- x$stages
  for (i in seq_len(nrow(s))) {
    cat(sprintf("  %s  %-34s NSE %.3f, log NSE %.3f, volume %+.1f%%, %d runs\n", s$id[i],
                s$stage[i], s$nse[i], s$log_nse[i], 100 * s$volume_error[i], s$evaluations[i]))
  }
  if (!is.null(x$windows)) {
    w <- x$windows[x$windows$metric == "nse", ]
    cat("Candidate NSE by window:", paste(sprintf("%s %.3f", w$window, w$value),
                                          collapse = ", "), "\n")
  }
  invisible(x)
}

#' @rdname calibration_path
#' @export
plot.pdm_calibration_path <- function(x, type = c("stages", "starts", "windows"), ...) {
  .draw_base(.path_spec(x, match.arg(type)))
  invisible(x)
}

#' @rdname calibration_path
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_calibration_path <- function(object, type = c("stages", "starts", "windows"),
                                          ...) {
  .draw_gg(.path_spec(object, match.arg(type)))
}

.path_spec <- function(x, type) {
  switch(type, stages = .spec_stages(x), starts = .spec_starts(x), windows = .spec_windows(x))
}

# Short names for the stage axis: "1 volume and baseflow" from "1 of 4: volume and baseflow".
.stage_labels <- function(s) {
  short <- sub("^([0-9]+) of [0-9]+: ", "\\1 ", s$stage)
  ifelse(nchar(short) > 22, paste0(substr(short, 1, 20), "..."), short)
}

.spec_stages <- function(x) {
  s <- x$stages
  pal <- pdm_palette(3)
  series <- rbind(
    .layer(s$step, s$nse, "NSE", pal[[1]], lwd = 1.8),
    .layer(s$step, s$nse, ".nse points", pal[[1]], geom = "point", lwd = 2.4),
    .layer(s$step, s$log_nse, "log NSE", pal[[3]], lwd = 1.8),
    .layer(s$step, s$log_nse, ".log points", pal[[3]], geom = "point", lwd = 2.4),
    .layer(s$step, 1 - abs(s$volume_error), "1 - |volume error|", pal[[2]], lty = 2,
           lwd = 1.5)
  )
  list(series = series, log = "", xlab = "", ylab = "Score on the calibration window",
       title = "Scores after each stage", xlim = c(0.7, nrow(s) + 0.3),
       xticks = list(at = s$step, labels = .stage_labels(s)),
       subtitle = "Higher is better; 1 is perfect")
}

.spec_starts <- function(x) {
  s <- x$starts
  stages <- x$stages
  series <- rbind(
    if (any(!s$best)) .layer(s$step[!s$best], s$objective[!s$best], "Other starts",
                             .pdm_roles[["reference"]], geom = "open", lwd = 2.4),
    .layer(s$step[s$best], s$objective[s$best], "Best start", .pdm_roles[["simulated"]],
           geom = "point", lwd = 2.6)
  )
  list(series = series, log = "", xlab = "", ylab = "Objective (lower is better)",
       title = "Each start's result in each stage", xlim = c(0.7, nrow(stages) + 0.3),
       xticks = list(at = stages$step, labels = .stage_labels(stages)),
       subtitle = "Starts that end far apart mean the search has more than one valley")
}

.spec_windows <- function(x) {
  w <- x$windows
  .check(!is.null(w), "The candidate has not been validated yet")
  metrics <- c("nse", "log_nse", "kge")
  colours <- c(calibration = "#000000", validation = .pdm_roles[["validation"]],
               test = .pdm_roles[["alternative"]])
  windows <- intersect(names(colours), unique(w$window))
  offset <- (seq_along(windows) - (length(windows) + 1) / 2) * 0.12
  series <- do.call(rbind, lapply(seq_along(windows), function(i) {
    one <- w[w$window == windows[i], ]
    .layer(match(one$metric, metrics) + offset[i], one$value,
           paste(toupper(substring(windows[i], 1, 1)), substring(windows[i], 2), sep = ""),
           colours[[windows[i]]], geom = "point", lwd = 3)
  }))
  list(series = series, log = "", zero = FALSE, xlab = "", ylab = "Score",
       title = "The candidate in each window",
       xlim = c(0.5, 3.5), xticks = list(at = 1:3, labels = c("NSE", "log NSE", "KGE")),
       subtitle = paste("A large fall from calibration to validation means the model learnt",
                        "the years, not the catchment"))
}
