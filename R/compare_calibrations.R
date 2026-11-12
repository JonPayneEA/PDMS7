# ============================================================ #
# Tool:         compare_calibrations
# Description:  Two or more calibrated PDMs, from any source (a configuration, a YAML file, a
#               PDM for PCs *.inp file or a calibration project), run on the same data and
#               scored side by side: parameters, scores by window, thresholds and largest events
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-12
# Modified:     2026-11-12 - First version
# Tier:         1
# Inputs:       Named list of models; forcing (rain, pet mm per step, optional time); flow, m3/s
# Outputs:      A pdm_comparison: parameter, score, threshold and event tables, and the series
# Dependencies: graphics, stats
# ============================================================ #

#' Compare calibrated models on the same data
#'
#' Runs two or more calibrated PDMs on the same forcing, from the same start rule, and sets
#' them side by side: their parameters, their scores in each window, their threshold scores and
#' their errors on the largest floods. Use it to compare a model calibrated in PDM for PCs with
#' one calibrated here, two candidates of one project, or a model before and after a change.
#'
#' Each model may be a configuration list, a `FlodePdmModel`, the path of a YAML configuration,
#' the path of a PDM for PCs `*.inp` file (read with [read_pdm_inp()] at the forcing's step), or
#' a calibration project folder (its candidate, from [candidate_model()]). Every model must have
#' the forcing's time step.
#'
#' Every model starts the same way: from the first observed flow (`start = "flow"`, see
#' [initial_state_from_flow()]) or from a soil fraction. Rows before `warmup` and outside the
#' windows are not scored. A model calibrated elsewhere was fitted to its own rainfall and
#' start; differences in the inputs show as differences in the scores, so give both models the
#' same catchment rainfall.
#'
#' @param models Named list of models (see above); at least two.
#' @param forcing Data frame with `rain` and `pet` (mm per step), and optionally `time` and
#'   `abstraction` (used only by models with the groundwater extension).
#' @param observed Observed flow, m3/s, aligned with `forcing`.
#' @param windows Named list of scoring windows, each `c(first, last)` as rows or as times when
#'   `forcing` has a `time` column; by default the whole record after the warm-up.
#' @param warmup Rows at the start that are never scored.
#' @param start,baseflow_fraction,soil_fraction How every model starts; see [calibrate_pdm()].
#' @param n_events Number of largest observed floods compared, from [find_events()].
#' @param markers Flow markers of [flow_markers()] the models are scored against as thresholds,
#'   worked out from the observed flow in the windows; `NULL` for none.
#' @param dt Time step, hours, when `forcing` has no `time` column.
#' @return A `pdm_comparison`: `parameters` (one row per parameter, one column per model, and
#'   `differs`), `scores` (one row per window and score), `thresholds` (per marker, window and
#'   model), `events` (the largest floods, with each model's peak and timing errors), `series`
#'   (observed and simulated flows) and `models`. Print it for a summary; plot it for the
#'   hydrographs of one flood or window.
#' @examples
#' set.seed(1)
#' n <- 24 * 120
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rexp(n, 0.3), 0), pet = 0.08)
#' a <- pdm_presets("standard")
#' a$area_km2 <- 20
#' b <- a
#' b$surface$k1 <- 4
#' observed <- run_pdm(pdm_from_config(a), forcing)$output$q_m3s
#' cmp <- compare_calibrations(list(original = a, slower = b), forcing, observed, warmup = 240,
#'                             dt = 1, markers = "Q5")
#' cmp
#' plot(cmp)
#' @seealso [read_pdm_inp()], [pdm_scorecard()], [event_scores()]
#' @export
compare_calibrations <- function(models, forcing, observed, windows = NULL, warmup = 0,
                                 start = c("flow", "soil"), baseflow_fraction = 0.7,
                                 soil_fraction = 0.5, n_events = 10, markers = c("QMED", "Q1"),
                                 dt = NULL) {
  start <- match.arg(start)
  .comparison_checks(models, forcing, observed, warmup, n_events)
  time <- if ("time" %in% names(forcing)) .parse_time(forcing$time)
  step <- if (!is.null(time)) as.numeric(difftime(time[2], time[1], units = "hours")) else dt
  .check(.scalar(step, 0, strict = TRUE),
         "Give dt, the time step in hours, when forcing has no time column")
  built <- .comparison_models(models, step)
  rows <- .comparison_windows(windows, forcing, warmup)
  first <- observed[is.finite(observed)][1L]
  sims <- lapply(built, function(model) {
    state <- suppressWarnings(.start_state(model, start, first, baseflow_fraction,
                                           soil_fraction))
    keep <- c("rain", "pet", "time",
              if (S7::S7_inherits(model@groundwater, FlodeExtendedGroundwater)) "abstraction")
    .quietly(run_pdm(model, forcing[intersect(names(forcing), keep)], state))$output$q_m3s
  })
  scored <- sort(unique(unlist(rows)))
  out <- list(
    parameters = .comparison_parameters(built),
    scores = .comparison_scores(sims, observed, rows),
    thresholds = .comparison_thresholds(sims, observed, rows, scored, step, time, markers),
    events = .comparison_events(sims, observed, forcing$rain, time, step, scored, n_events,
                                built[[1]]@area_km2),
    series = data.frame(time = if (is.null(time)) seq_along(observed) else time,
                        observed = observed, sims, check.names = FALSE),
    windows = rows, models = built, dt = step
  )
  structure(out, class = "pdm_comparison")
}

# The arguments compare_calibrations() needs before any model runs.
.comparison_checks <- function(models, forcing, observed, warmup, n_events) {
  .check(is.list(models) && length(models) >= 2L && !is.null(names(models)) &&
           all(nzchar(names(models))) && !anyDuplicated(names(models)),
         "models must be a named list of two or more models")
  .check(is.data.frame(forcing) && all(c("rain", "pet") %in% names(forcing)),
         "forcing must be a data frame with rain and pet")
  .check(is.numeric(observed) && length(observed) == nrow(forcing),
         "observed must be a flow series as long as forcing")
  .check(.scalar(warmup, 0) && warmup < nrow(forcing), "warmup must leave rows to score")
  .check(.scalar(n_events, 1), "n_events must be a positive number")
}

# One model from any source: a model, a configuration, a project folder, or a *.inp or YAML
# file.
.comparison_model <- function(x, name, step) {
  if (S7::S7_inherits(x, FlodePdmModel)) return(x)
  if (is.list(x)) return(pdm_from_config(x))
  .check(is.character(x) && length(x) == 1L, paste(
    "Model", name, "must be a configuration, a model, a YAML or *.inp file, or a project folder"
  ))
  if (dir.exists(x)) return(candidate_model(x))
  kind <- tolower(tools::file_ext(x))
  .check(kind %in% c("inp", "yml", "yaml"), paste("Model", name, "is not a *.inp or YAML file"))
  config <- if (kind == "inp") read_pdm_inp(x, dt = step) else read_pdm_config(x)
  pdm_from_config(config)
}

# Every model as a FlodePdmModel at the forcing's step.
.comparison_models <- function(models, step) {
  out <- lapply(names(models), function(name) {
    model <- .comparison_model(models[[name]], name, step)
    .check(abs(model@dt - step) < 1e-9, sprintf(
      "Model %s has a %g-hour step; the forcing's is %g hours", name, model@dt, step
    ))
    model
  })
  stats::setNames(out, names(models))
}

# The rows each window scores, by name.
.comparison_windows <- function(windows, forcing, warmup) {
  if (is.null(windows)) return(list(record = seq.int(warmup + 1L, nrow(forcing))))
  .check(is.list(windows) && !is.null(names(windows)) && all(nzchar(names(windows))),
         "windows must be a named list of c(first, last)")
  data <- .as_forcing(forcing)
  lapply(stats::setNames(names(windows), names(windows)), function(w) {
    r <- .window_rows(.resolve_window(windows[[w]], data, w))
    r[r > warmup]
  })
}

# Each model's numeric parameters, one row per parameter: component properties named as
# configuration paths, then the catchment settings.
.comparison_parameters <- function(models) {
  flat <- lapply(models, function(m) {
    one <- function(x, prefix) {
      if (S7::S7_inherits(x, FlodeExtendedGroundwater)) {
        return(c(one(x@store, prefix), one_props(x, paste0(prefix, "extension."), "store")))
      }
      c(stats::setNames(class(x)[1L], paste0(prefix, "type")), one_props(x, prefix))
    }
    one_props <- function(x, prefix, skip = character(0)) {
      p <- S7::props(x)
      p <- p[setdiff(names(p), skip)]
      p <- p[vapply(p, function(v) is.numeric(v) && length(v) == 1L, logical(1))]
      stats::setNames(vapply(p, function(v) format(signif(v, 6)), ""), paste0(prefix, names(p)))
    }
    c(one(m@distribution, "distribution."), one(m@recharge, "recharge."),
      one(m@surface, "surface."), one(m@groundwater, "groundwater."),
      vapply(c(fc = m@fc, be = m@be, td = m@td, qc = m@qc, area_km2 = m@area_km2),
             function(v) format(signif(v, 6)), ""))
  })
  paths <- unique(unlist(lapply(flat, names)))
  table <- data.frame(parameter = paths,
                      lapply(flat, function(f) sub("^pdmS7::Flode", "", unname(f[paths]))),
                      check.names = FALSE)
  table$differs <- apply(table[names(models)], 1, function(v) length(unique(v)) > 1)
  table
}

# Scores by window: one row per window and score, one column per model.
.comparison_scores <- function(sims, observed, rows) {
  out <- lapply(names(rows), function(w) {
    r <- rows[[w]]
    each <- lapply(sims, function(s) pdm_scorecard(s[r], observed[r]))
    data.frame(window = w, score = names(each[[1]]), each, check.names = FALSE,
               row.names = NULL)
  })
  do.call(rbind, out)
}

# Threshold scores against flow markers worked out from the observed flow in the windows.
.comparison_thresholds <- function(sims, observed, rows, scored, dt, time, markers) {
  if (!length(markers)) return(NULL)
  seen <- rep(NA_real_, length(observed))
  seen[scored] <- observed[scored]
  # Each marker on its own, so one that cannot be worked out (QMED from a short record) does
  # not lose the others.
  levels <- do.call(rbind, lapply(markers, function(m) {
    tryCatch(suppressWarnings(flow_markers(seen, dt, time, markers = m)),
             error = function(e) NULL)
  }))
  if (is.null(levels)) return(NULL)
  flows <- stats::setNames(levels$value, levels$name)
  keep <- c("threshold", "flow_m3s", "observed_events", "hits", "misses", "false_alarms", "csi",
            "peak_error", "crossing_error_h")
  out <- lapply(names(rows), function(w) {
    r <- rows[[w]]
    do.call(rbind, lapply(names(sims), function(m) {
      t <- as.data.frame(pdm_threshold_scores(sims[[m]][r], observed[r], flows, dt_hours = dt))
      t$threshold <- names(flows)
      cbind(window = w, model = m, t[intersect(keep, names(t))])
    }))
  })
  do.call(rbind, out)
}

# The largest observed floods in the scored rows, with each model's peak and timing errors.
.comparison_events <- function(sims, observed, rain, time, dt, scored, n_events, area_km2) {
  events <- tryCatch(find_events(rain, observed, time = time, dt = dt, area_km2 = area_km2,
                                 independent = TRUE), error = function(e) NULL)
  if (is.null(events) || !nrow(events)) return(NULL)
  inside <- events$flow_start >= min(scored) & events$flow_end <= max(scored)
  events <- events[inside, , drop = FALSE]
  if (!nrow(events)) return(NULL)
  peaks <- vapply(seq_len(nrow(events)), function(i) {
    max(observed[events$flow_start[i]:events$flow_end[i]], na.rm = TRUE)
  }, numeric(1))
  top <- order(-peaks)[seq_len(min(n_events, nrow(events)))]
  events <- events[top, , drop = FALSE]
  out <- data.frame(event = seq_along(top), flow_start = events$flow_start,
                    flow_end = events$flow_end, observed_peak = signif(peaks[top], 4))
  if (!is.null(time)) out$peak_time <- time[events$flow_start]
  for (m in names(sims)) {
    s <- event_scores(events, sims[[m]], observed, dt = dt)
    out[[paste0(m, ".peak_error")]] <- signif(s$peak_error, 3)
    out[[paste0(m, ".timing_error_h")]] <- s$timing_error_h
  }
  out
}

#' @export
print.pdm_comparison <- function(x, ...) {
  names <- names(x$models)
  cat("Comparison of", length(names), "models:", paste(names, collapse = ", "), "\n\n")
  diff <- x$parameters[x$parameters$differs, c("parameter", names)]
  cat("Parameters that differ\n")
  if (nrow(diff)) print(diff, row.names = FALSE) else cat("  none\n")
  cat("\nScores\n")
  key <- c("nse", "log_nse", "kge", "volume_error", "peak_error", "fdc_high", "fdc_low")
  s <- x$scores[x$scores$score %in% key, ]
  s[names] <- lapply(s[names], function(v) signif(v, 4))
  print(s, row.names = FALSE)
  if (!is.null(x$thresholds)) {
    cat("\nThresholds (CSI)\n")
    t <- stats::reshape(x$thresholds[c("window", "threshold", "model", "csi")],
                        idvar = c("window", "threshold"), timevar = "model",
                        direction = "wide")
    names(t) <- sub("^csi\\.", "", names(t))
    print(t, row.names = FALSE)
  }
  if (!is.null(x$events)) {
    cat(sprintf("\nLargest %d floods: median |peak error| and |timing error| (h)\n",
                nrow(x$events)))
    for (m in names) {
      cat(sprintf("  %-20s %6.3f  %6.2f\n", m,
                  stats::median(abs(x$events[[paste0(m, ".peak_error")]]), na.rm = TRUE),
                  stats::median(abs(x$events[[paste0(m, ".timing_error_h")]]), na.rm = TRUE)))
    }
  }
  invisible(x)
}

#' @rdname compare_calibrations
#' @param x A `pdm_comparison`.
#' @param event Which of the largest floods to plot, 1 for the largest.
#' @param window Instead, a window to plot, by name.
#' @param ... Unused.
#' @export
plot.pdm_comparison <- function(x, event = 1, window = NULL, ...) {
  names <- names(x$models)
  rows <- if (!is.null(window)) {
    .check(window %in% names(x$windows), "window must name one of the comparison's windows")
    x$windows[[window]]
  } else {
    .check(!is.null(x$events) && event >= 1 && event <= nrow(x$events),
           "event must be one of the largest floods found")
    e <- x$events[event, ]
    pad <- max(2L, round((e$flow_end - e$flow_start) / 4))
    seq.int(max(1L, e$flow_start - pad), min(nrow(x$series), e$flow_end + pad))
  }
  s <- x$series[rows, ]
  colours <- c("#236b83", "#a26421", "#5b8c3a", "#8a3b6b", "#5f5f5f")
  ylim <- range(unlist(s[c("observed", names)]), na.rm = TRUE)
  graphics::plot(s$time, s$observed, type = "l", lwd = 2, col = "black", ylim = ylim,
                 xlab = "", ylab = "Flow (m3/s)",
                 main = if (is.null(window)) sprintf("Flood %d", event) else window)
  for (i in seq_along(names)) {
    graphics::lines(s$time, s[[names[i]]], col = colours[(i - 1) %% 5 + 1], lwd = 1.5)
  }
  graphics::legend("topright", c("observed", names), bty = "n", lwd = c(2, rep(1.5, length(names))),
                   col = c("black", colours[(seq_along(names) - 1) %% 5 + 1]))
  invisible(x)
}
