# ============================================================ #
# Tool:         workbench
# Description:  Events workbench: a project's largest events, rerun at once as parameters
#               change, for calibrating peaks and timing by eye
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         3
# Inputs:       A calibration project and one of its model entries
# Outputs:      The events, their simulations before and after a change, scores and plots
# Dependencies: graphics
# ============================================================ #

#' Events workbench
#'
#' A hydrologist calibrating by eye looks at the largest floods, changes a parameter, and looks
#' again. `event_workbench()` sets that up for a calibration project: it finds the events in the
#' registered record with [find_events()], screens them with [screen_events()], and keeps the
#' `n` largest in the chosen window. `workbench_try()` reruns those events with some parameters
#' changed and scores each one; `plot_workbench()` draws them side by side, before and after.
#' The Events tab of [calibration_app()] puts the same on sliders, and saves a setting you
#' accept as a logged trial.
#'
#' **Speed.** A change to the surface stores or the time delay reruns only the event windows,
#' from states saved just before each ([event_states()]), with a lead-in long enough for the
#' slowest surface stores the bounds allow; that takes a fraction of a second. A change to
#' anything else, such as the store shape `b`, alters the soil and groundwater stores before
#' each event, so the whole record is rerun, which takes about a second for sixteen years of
#' 15-minute data.
#'
#' @param project A calibration project folder.
#' @param entry Id of the model entry to start from (structure, trial or calibration), or of a
#'   candidate, which stands for the entry it proposed. By default the latest candidate, or
#'   the latest model entry if there is none.
#' @param n Number of events, largest observed peak first.
#' @param window Window the events' peaks must lie in: `calibration`, `validation` or `all`.
#' @param screen Settings for [screen_events()]; `NULL` keeps every event.
#' @param wb A workbench from `event_workbench()`.
#' @param changes Named numeric vector of new parameter values by configuration path, such as
#'   `c(surface.k1 = 3, td = 1.5)`, as for [log_trial()].
#' @param trial A result of `workbench_try()` to draw beside the starting run.
#' @param ncol Panels per row.
#'
#' @return `event_workbench()`: a `pdm_workbench` list with the project path, the starting
#'   entry (`parent`) and its configuration, the chosen `events`, the saved states, the
#'   starting run's flow in each event window (`base`) and its `scores`. `workbench_try()`: a
#'   list with the changed `configuration`, the flow in each window (`runs`), `scores` (one row
#'   per event: observed and simulated peak, peak error, timing error in hours and event NSE),
#'   and `full_run`, whether the whole record had to be rerun. `plot_workbench()`: `wb`,
#'   invisibly.
#' @examples
#' \dontrun{
#' wb <- event_workbench("projects/beggearn_huish", n = 10)
#' faster <- workbench_try(wb, c(surface.k1 = 3, surface.k2 = 6, td = 1))
#' plot_workbench(wb, faster)
#' faster$scores
#' }
#' @seealso [calibration_app()], [event_states()], [screen_events()], [log_trial()]
#' @export
event_workbench <- function(project, entry = NULL, n = 10L,
                            window = c("calibration", "validation", "all"), screen = list()) {
  .check(.whole(n, 1, 200), "n must be a whole number of events from 1 to 200")
  window <- match.arg(window)
  path <- .project_path(project)
  entries <- .read_entries(path)
  node <- .workbench_node(entries, entry)
  registration <- .registration(entries)
  card <- registration$scorecard
  data <- .load_registration(path, registration)
  model <- pdm_from_config(node$configuration)
  start <- .workbench_start(model, card, data$observed)
  time <- if ("time" %in% names(data$forcing)) data$forcing$time else NULL
  events <- find_events(data$forcing$rain, data$observed, time, model@dt,
                        area_km2 = model@area_km2)
  if (!is.null(screen)) {
    events <- do.call(screen_events, c(list(events, data$observed), .project_screen(screen, card)))
  }
  chosen <- .workbench_events(events, card, window, n)
  saved <- event_states(model, data$forcing, chosen, start,
                        lead_h = .workbench_lead(node$configuration), tail_h = 24)
  base <- lapply(run_events(model, data$forcing, saved), `[[`, "q_m3s")
  wb <- structure(list(
    project = path, parent = node$id, configuration = node$configuration, model = model,
    card = card, forcing = data$forcing, observed = data$observed, time = time,
    events = chosen, saved = saved, base = base, window = window
  ), class = "pdm_workbench")
  wb$scores <- .workbench_scores(wb, base)
  wb
}

#' @rdname event_workbench
#' @export
workbench_try <- function(wb, changes) {
  .check(inherits(wb, "pdm_workbench"), "wb must come from event_workbench()")
  changed <- .apply_changes(wb$configuration, changes)$config
  model <- pdm_from_config(changed)
  fast <- tryCatch({
    .check_same_slow(model, wb$model)
    TRUE
  }, error = function(e) FALSE)
  runs <- if (fast) {
    lapply(suppressWarnings(run_events(model, wb$forcing, wb$saved)), `[[`, "q_m3s")
  } else {
    full <- .workbench_full_run(wb, changed)
    lapply(seq_along(wb$saved$first), function(e) {
      full[seq.int(wb$saved$first[e], wb$saved$last[e])]
    })
  }
  list(configuration = changed, changes = changes, runs = runs,
       scores = .workbench_scores(wb, runs), full_run = !fast)
}

#' @rdname event_workbench
#' @export
plot_workbench <- function(wb, trial = NULL, ncol = 2L) {
  .check(inherits(wb, "pdm_workbench"), "wb must come from event_workbench()")
  n <- nrow(wb$events)
  old <- graphics::par(mfrow = c(ceiling(n / ncol), ncol), mar = c(2.2, 3.6, 2.2, 0.6),
                       oma = c(0, 0, 1.6, 0))
  on.exit(graphics::par(old), add = TRUE)
  for (e in seq_len(n)) .plot_workbench_event(wb, trial, e)
  label <- if (is.null(trial)) "" else
    paste0("  |  orange: ", paste(names(trial$changes), signif(trial$changes, 3), sep = " = ",
                                  collapse = ", "))
  graphics::mtext(paste0("Entry ", wb$parent, " (blue)", label), outer = TRUE, cex = 0.85)
  invisible(wb)
}

#' @export
print.pdm_workbench <- function(x, ...) {
  s <- x$scores
  cat(sprintf(paste0("Events workbench: %d largest events in the %s window, from entry %s\n",
                     "Median peak error %+.0f%%, timing %+.1f h, event NSE %.2f\n"),
              nrow(x$events), x$window, x$parent, 100 * stats::median(s$peak_error),
              stats::median(s$timing_error_h), stats::median(s$nse)))
  invisible(x)
}

# ---- Helpers -----------------------------------------------------------------------------

# The model entry to start from: the one named (a candidate stands for the entry it proposed),
# or the latest candidate's, or the latest model entry.
.workbench_node <- function(entries, entry) {
  if (!is.null(entry)) {
    hit <- .find_entry(entries, entry)
    if (identical(hit$type, "candidate")) hit <- .find_entry(entries, hit$entry)
    return(.model_node(entries, hit$id))
  }
  candidate <- .latest(entries, "candidate")
  if (!is.null(candidate)) return(.model_node(entries, candidate$entry))
  nodes <- Filter(function(e) e$type %in% .model_entry_types, entries)
  .check(length(nodes) > 0, "The project has no model entry yet; select a structure first")
  nodes[[length(nodes)]]
}

# The state a project run starts from, as .run_registered() builds it.
.workbench_start <- function(model, card, observed) {
  suppressWarnings(.start_state(model, card$start %||% "soil", .first_observed(observed),
                                card$baseflow_fraction %||% 0.7, card$soil_fraction))
}

# The n largest usable events whose peaks lie in the window.
.workbench_events <- function(events, card, window, n) {
  rows <- switch(window,
    calibration = .scored_rows(card, "calibration"),
    validation = {
      .check(!is.null(card$validation), "The project registered no validation window")
      .scored_rows(card, "validation")
    },
    all = seq_len(max(events$flow_end, 0L))
  )
  use <- if ("use" %in% names(events)) events$use else rep(TRUE, nrow(events))
  keep <- which(use & is.finite(events$peak_flow) & events$peak_row %in% rows)
  .check(length(keep) > 0, paste("No usable event has its peak in the", window, "window"))
  keep <- keep[order(-events$peak_flow[keep])][seq_len(min(n, length(keep)))]
  out <- events[sort(keep), ]
  out <- out[order(-out$peak_flow), ]
  attributes(out)[c("response", "dt", "baseflow")] <- attributes(events)[c("response", "dt",
                                                                          "baseflow")]
  out
}

# A lead-in long enough for the slowest surface stores the bounds allow: five times the sum of
# their largest time constants, and at least a day.
.workbench_lead <- function(config) {
  b <- calibration_bounds(config)
  k <- b$upper[b$path %in% c("surface.k", "surface.k1", "surface.k2")]
  max(24, 5 * sum(k))
}

# The whole record rerun with a configuration, from the project's start rule.
.workbench_full_run <- function(wb, config) {
  model <- pdm_from_config(config)
  start <- .workbench_start(model, wb$card, wb$observed)
  .quietly(run_pdm(model, wb$forcing, start))$output$q_m3s
}

# Scores of each event over its flow window, as event_scores() gives them.
.workbench_scores <- function(wb, runs) {
  dt <- wb$model@dt
  do.call(rbind, lapply(seq_along(runs), function(e) {
    ev <- wb$events[e, ]
    window <- seq.int(ev$flow_start, ev$flow_end)
    sim <- runs[[e]][match(window, seq.int(wb$saved$first[e], wb$saved$last[e]))]
    obs <- wb$observed[window]
    ok <- is.finite(obs) & is.finite(sim)
    data.frame(
      event = e, peak_row = ev$peak_row,
      observed_peak = max(obs[ok]), simulated_peak = max(sim[ok]),
      peak_error = max(sim[ok]) / max(obs[ok]) - 1,
      timing_error_h = (window[ok][which.max(sim[ok])] - window[ok][which.max(obs[ok])]) * dt,
      nse = 1 - sum((sim[ok] - obs[ok])^2) / sum((obs[ok] - mean(obs[ok]))^2)
    )
  }))
}

# One panel: rain hanging from the top, observed flow, the starting run and the trial, from the
# start of the rain to the end of the event's tail.
.plot_workbench_event <- function(wb, trial, e) {
  ev <- wb$events[e, ]
  rows <- seq.int(wb$saved$first[e], wb$saved$last[e])
  shown <- rows >= min(ev$rain_start, ev$flow_start) - round(12 / wb$model@dt)
  x <- if (is.null(wb$time)) rows[shown] else wb$time[rows[shown]]
  obs <- wb$observed[rows[shown]]
  base <- wb$base[[e]][shown]
  tri <- if (is.null(trial)) NULL else trial$runs[[e]][shown]
  top <- max(c(obs, base, tri), na.rm = TRUE)
  graphics::plot(x, obs, type = "n", ylim = c(0, top * 1.35), xlab = "", ylab = "m3/s",
                 las = 1, cex.axis = 0.8)
  rain <- wb$forcing$rain[rows[shown]]
  if (any(rain > 0)) {
    scale <- 0.3 * top / max(rain)
    graphics::rect(x, top * 1.35 - rain * scale, c(x[-1], x[length(x)]), top * 1.35,
                   col = grDevices::adjustcolor(.pal[["blue"]], 0.35), border = NA)
  }
  graphics::points(x, obs, pch = 16, cex = 0.5, col = .pal[["grey"]])
  graphics::lines(x, base, col = .pal[["blue"]], lwd = 1.5)
  s <- wb$scores[e, ]
  title <- sprintf("%s  peak %+.0f%%, %+.1f h",
                   if (is.null(wb$time)) paste("row", ev$peak_row) else
                     format(wb$time[ev$peak_row], "%d %b %Y"),
                   100 * s$peak_error, s$timing_error_h)
  if (!is.null(tri)) {
    graphics::lines(x, tri, col = .pal[["orange"]], lwd = 1.5)
    t <- trial$scores[e, ]
    title <- sprintf("%s -> %+.0f%%, %+.1f h", title, 100 * t$peak_error, t$timing_error_h)
  }
  graphics::title(title, cex.main = 0.85, font.main = 1)
}
