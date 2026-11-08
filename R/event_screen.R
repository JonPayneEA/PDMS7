# ============================================================ #
# Tool:         event_screen
# Description:  Screens events found by find_events() for ones a hydrologist would not trust:
#               a rise lost in the baseflow, more quick flow than rain, gaps, or a peak above
#               the highest gauging
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         3
# Inputs:       Events from find_events(); observed flow (m3/s)
# Outputs:      The events with their rise above baseflow, flags and whether to use them
# Dependencies: none
# ============================================================ #

#' Screen events before scoring a model on them
#'
#' A hydrologist calibrating by eye discounts events they do not trust. The optimiser does not,
#' unless told. `screen_events()` flags them, so the event objective and the acceptance checks
#' can leave them out and a reviewer can see why.
#'
#' | Flag | Meaning | Leaves the event out by default |
#' |---|---|---|
#' | `small_rise` | The peak rises less than `min_rise` times the baseflow beneath it | Yes |
#' | `quickflow_above_rain` | More quick flow than rain (runoff ratio above `max_ratio`) | Yes |
#' | `gaps` | More than `max_gap` of the flow window is missing | Yes |
#' | `above_gauging` | The peak is above the highest gauged flow | No |
#'
#' Every test works on flow above the baseflow line that [find_events()] draws between the
#' events' start and end points, not on total flow, so that a high, steady baseflow is neither
#' counted as event runoff nor mistaken for a rise. In a groundwater-fed catchment a small rise
#' on a large baseflow carries little information about peak size or timing: a few percent of
#' noise moves the peak by hours. `min_rise` is the share of the baseflow the rise must reach
#' for the event's peak and timing to count; raise it where baseflow dominates.
#'
#' A peak above the highest gauged flow is flagged but kept: the rating may get its size wrong,
#' but rarely its timing, and these are usually the events that matter most. Add
#' `"above_gauging"` to `exclude` to leave them out.
#'
#' @param events Events from [find_events()], with its `baseflow` attribute; with an area, the
#'   runoff ratio is also tested.
#' @param observed Observed flow, m3/s, as passed to [find_events()].
#' @param min_rise Smallest rise of the peak above the baseflow beneath it, as a share of that
#'   baseflow.
#' @param max_ratio Largest plausible runoff ratio: quick flow over rain.
#' @param max_gap Largest share of the flow window that may be missing.
#' @param highest_gauged_m3s Optional highest gauged flow, m3/s.
#' @param exclude Flags that leave an event out (`use = FALSE`).
#'
#' @return `events` with `rise_ratio` (the peak's rise above the baseflow beneath it, over that
#'   baseflow; `Inf` where the baseflow is zero), `flags` (the flags raised, separated by
#'   `"; "`, or `""`) and `use`.
#' @examples
#' set.seed(4)
#' n <- 24 * 120
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.05, rgamma(n, 0.7, scale = 5), 0),
#'                       pet = 0.05)
#' flow <- run_pdm(pdm_model(area_km2 = 20), forcing)$output$q_m3s
#' events <- find_events(forcing$rain, flow, dt = 1, area_km2 = 20)
#' screened <- screen_events(events, flow, min_rise = 0.5)
#' table(screened$flags)
#' @seealso [find_events()], [calibrate_pdm()], [calibration_checks()]
#' @export
screen_events <- function(events, observed, min_rise = 0.2, max_ratio = 1, max_gap = 0.1,
                          highest_gauged_m3s = NULL,
                          exclude = c("small_rise", "quickflow_above_rain", "gaps")) {
  .check(is.data.frame(events) && all(c("flow_start", "flow_end", "peak_row") %in% names(events)),
         "events must come from find_events()")
  baseflow <- attr(events, "baseflow")
  .check(is.numeric(baseflow) && length(baseflow) == length(observed),
         "events must carry the baseflow line of find_events() for the same flow series")
  .check(.scalar(min_rise, 0), "min_rise must be a nonnegative number")
  .check(.scalar(max_ratio, 0, strict = TRUE), "max_ratio must be a positive number")
  .check(.scalar(max_gap, 0, 1), "max_gap must lie between 0 and 1")
  .check(is.null(highest_gauged_m3s) || .scalar(highest_gauged_m3s, 0, strict = TRUE),
         "highest_gauged_m3s must be a positive flow, or NULL")
  known <- c("small_rise", "quickflow_above_rain", "gaps", "above_gauging")
  .check(is.character(exclude) && all(exclude %in% known),
         paste("exclude must name flags among", toString(known)))
  peak <- events$peak_row
  under <- baseflow[peak]
  rise <- events$peak_flow - under
  events$rise_ratio <- ifelse(under > 0, rise / under, Inf)
  missing_share <- vapply(seq_len(nrow(events)), function(e) {
    mean(!is.finite(observed[seq.int(events$flow_start[e], events$flow_end[e])]))
  }, numeric(1))
  raised <- list(
    small_rise = is.finite(events$rise_ratio) & events$rise_ratio < min_rise,
    quickflow_above_rain = if ("runoff_ratio" %in% names(events)) {
      is.finite(events$runoff_ratio) & events$runoff_ratio > max_ratio
    } else {
      rep(FALSE, nrow(events))
    },
    gaps = missing_share > max_gap,
    above_gauging = if (is.null(highest_gauged_m3s)) {
      rep(FALSE, nrow(events))
    } else {
      is.finite(events$peak_flow) & events$peak_flow > highest_gauged_m3s
    }
  )
  flags <- do.call(cbind, raised)
  events$flags <- if (nrow(events)) {
    apply(flags, 1L, function(row) paste(known[row], collapse = "; "))
  } else {
    character(0)
  }
  events$use <- if (nrow(events)) !apply(flags[, exclude, drop = FALSE], 1L, any) else logical(0)
  .as_events(events)
}
