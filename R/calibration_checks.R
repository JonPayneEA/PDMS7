# ============================================================ #
# Tool:         calibration_checks
# Description:  Acceptance checks of a calibration: parameters at their bounds, and how the
#               model does on the largest events in each window
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-06
# Modified:     2026-11-06 - First version
# Tier:         3
# Inputs:       A calibration project and one of its model entries
# Outputs:      Tables of parameters, events and a summary by window
# Dependencies: stats
# ============================================================ #

#' Acceptance checks of a calibration
#'
#' A calibration can score well over the whole record and still be wrong where it matters.
#' NSE over a long record weighs time steps, not events, so a model whose flood peaks are late
#' and low can score 0.9 when its recessions are right. These checks look for two warning signs
#' the headline score hides.
#'
#' **Parameters at a bound.** A parameter that ends at the edge of its search range is usually
#' being bent to make up for something the structure cannot do, not estimating a property of
#' the catchment. Each parameter is checked against the widest range any calibration on the way
#' to the entry searched it over, on a log scale where it was searched on one. A lower bound of
#' zero, such as no time delay, is a natural limit rather than an imposed one, and is not flagged.
#'
#' **The largest events.** Events are found with [find_events()] from the registered rain and
#' observed flow and scored with [event_scores()]. In each window (calibration, validation, the
#' held-back wettest years, and any outside them), the `top` largest by observed peak are
#' summarised: median peak error, median timing error, the share of peaks within 20% of the
#' observed, and median event NSE. Events are first screened with [screen_events()]; those it
#' leaves out are kept in `events` with their flags, but not summarised.
#'
#' @param project A calibration project folder.
#' @param entry Id of a model entry (structure, trial or calibration) or candidate; by default
#'   the latest candidate.
#' @param top Largest events summarised in each window.
#' @param edge Distance from a bound, as a share of the searched range, within which a parameter
#'   counts as at the bound.
#' @param rain_min,max_response_h Passed to [find_events()].
#' @param screen Settings for [screen_events()], with the project's highest gauged flow unless
#'   they name one; `NULL` summarises every event.
#'
#' @return A `pdm_calibration_checks` list of three data frames and the response times; printing it
#'   shows the parameters at a bound and the event summary. `parameters`: `path`, `value`,
#'   `lower`, `upper`, `scale` and `at_bound` (`"lower"`, `"upper"` or `NA`). `events`: every
#'   event with its `period` and the columns of [event_scores()]. `summary`: one row per window
#'   with `events` (the number summarised), `median_peak_error`, `median_timing_error_h`,
#'   `share_peak_within_20pct` and `median_event_nse`, and `screened_out`, the events of that
#'   window the screen left out. `response_h`: the response times
#'   estimated from the observed and the simulated flow.
#' @examples
#' \dontrun{
#' checks <- calibration_checks("projects/beggearn_huish")
#' checks$parameters[!is.na(checks$parameters$at_bound), ]
#' checks$summary
#' }
#' @seealso [find_events()], [event_scores()], [pdm_stages()]
#' @export
calibration_checks <- function(project, entry = NULL, top = 20L, edge = 0.01, rain_min = NULL,
                               max_response_h = 150, screen = list()) {
  .check(.whole(top, 1, Inf), "top must be a positive whole number")
  .check(.scalar(edge, 0, 0.5), "edge must lie between 0 and 0.5")
  path <- .project_path(project)
  entries <- .read_entries(path)
  node <- if (is.null(entry)) {
    .check(!is.null(.latest(entries, "candidate")), "No candidate yet; name an entry")
    .latest(entries, "candidate")
  } else {
    .find_entry(entries, entry)
  }
  .check(!is.null(node$configuration), paste("Entry", node$id, "holds no model"))
  parameters <- .bound_flags(entries, node, edge)
  scored <- .basin_events(path, basename(path), rain_min, max_response_h, node$configuration,
                          screen)
  events <- scored$events
  summary <- do.call(rbind, lapply(c("calibration", "validation", "wettest", "outside"),
                                   function(period) .event_summary(events, period, top)))
  structure(list(parameters = parameters, events = events, summary = summary,
                 response_h = c(observed = scored$basin$response_observed_h,
                                simulated = scored$basin$response_simulated_h)),
            class = "pdm_calibration_checks")
}

# Every calibrated parameter of an entry with the widest range searched for it on the way to the
# entry, and whether it ended within `edge` of either end of that range.
.bound_flags <- function(entries, node, edge) {
  chain <- .entry_chain(entries, node)
  searched <- Filter(function(e) identical(e$type, "auto_calibration"), chain)
  empty <- data.frame(path = character(0), value = numeric(0), lower = numeric(0),
                      upper = numeric(0), scale = character(0), at_bound = character(0))
  if (!length(searched)) return(empty)
  rows <- do.call(rbind, lapply(searched, function(e) {
    data.frame(path = names(e$bounds$lower), lower = unlist(e$bounds$lower),
               upper = unlist(e$bounds$upper),
               logged = names(e$bounds$lower) %in% unlist(e$log_scale))
  }))
  paths <- unique(rows$path)
  out <- data.frame(
    path = paths,
    value = vapply(paths, function(p) .path_get(node$configuration, p), numeric(1)),
    lower = vapply(paths, function(p) min(rows$lower[rows$path == p]), numeric(1)),
    upper = vapply(paths, function(p) max(rows$upper[rows$path == p]), numeric(1)),
    scale = ifelse(vapply(paths, function(p) any(rows$logged[rows$path == p]), logical(1)),
                   "log", "linear")
  )
  tr <- function(x, logged) ifelse(logged, log(pmax(x, .Machine$double.xmin)), x)
  logged <- out$scale == "log"
  z <- (tr(out$value, logged) - tr(out$lower, logged)) /
    (tr(out$upper, logged) - tr(out$lower, logged))
  out$at_bound <- ifelse(z <= edge & out$lower != 0, "lower",
                         ifelse(z >= 1 - edge, "upper", NA_character_))
  rownames(out) <- NULL
  out
}

# The entry and its ancestors, following parent links to the root. A candidate's model entry is
# its `entry`.
.entry_chain <- function(entries, node) {
  chain <- list()
  current <- if (identical(node$type, "candidate")) .find_entry(entries, node$entry) else node
  while (!is.null(current)) {
    chain[[length(chain) + 1L]] <- current
    current <- if (!is.null(current$parent)) .find_entry(entries, current$parent)
  }
  chain
}

# One window's largest events, summarised; NULL when the window has none.
.event_summary <- function(events, period, top) {
  used <- if ("use" %in% names(events)) events$use else rep(TRUE, nrow(events))
  in_period <- events$period == period
  e <- events[in_period & used & is.finite(events$peak_error), ]
  if (!nrow(e)) return(NULL)
  e <- e[order(-e$observed_peak), ][seq_len(min(top, nrow(e))), ]
  data.frame(period = period, events = nrow(e),
             median_peak_error = stats::median(e$peak_error),
             median_timing_error_h = stats::median(e$timing_error_h),
             share_peak_within_20pct = mean(abs(e$peak_error) <= 0.2),
             median_event_nse = stats::median(e$nse, na.rm = TRUE),
             screened_out = sum(in_period & !used))
}
