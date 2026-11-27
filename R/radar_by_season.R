# ============================================================ #
# Tool:         radar_by_season
# Description:  Why raw radar rain sits apart from the gauges: winter under-reading (beam
#               height, bright band), gauges under-catching in winter (wind), a level offset
#               all year, or missing data; from daily pairs of radar and gauge rain, the
#               events' rain by season and the share of radar steps missing
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-27
# Tier:         1
# Inputs:       Daily radar and gauge totals (at the gauges or over the catchment); optionally
#               the events' rain on the radar and on a gauge average, and the radar's missing
#               share
# Outputs:      A pdm_radar_season list
# Dependencies: stats
# ============================================================ #

#' Why radar rain sits apart from the gauges, season by season
#'
#' Raw radar rain is often biased in total, and the bias usually has a season. The ratio of the
#' radar's daily total to the gauge's, month by month, tells the usual causes apart:
#'
#' - **Radar under-reads in winter.** Winter rain is shallow and the freezing level low: at
#'   range the beam passes over the rain, and the melting layer (the bright band) distorts the
#'   conversion from echo to rain. The radar's share falls in winter.
#' - **Gauges under-catch in winter.** Wind carries rain past a gauge's rim, more in winter
#'   (stronger winds, lighter rain, snow). The radar's share rises in winter.
#' - **A level offset.** The radar's share is away from 1 by much the same all year: its own
#'   scaling.
#' - **Missing data.** Steps the radar is missing are not rain it missed, but a total taken
#'   over fewer steps.
#'
#' The half-years are winter (October to March) and summer (April to September). Each
#' half-year's ratio is the median of the daily ratios, over days with at least 1 mm in both.
#' The events' rain on the radar against a gauge average, by the season of each event's peak,
#' is set beside it: it should lean the same way.
#'
#' @param pairs A data frame of daily totals: `month` (1 to 12), `gauge_mm` and `radar_mm`,
#'   one row per day (and gauge, at the gauges), with at least 1 mm in both.
#' @param events Optional: a data frame of the events' rain, `season` (`"winter"` or
#'   `"summer"`), `radar_mm` and `reference_mm` (a gauge average's).
#' @param missing_share Optional: the share of steps the radar is missing where the gauges have
#'   rain data.
#' @param shift How far, as a share, winter's ratio must stand from summer's to count as a
#'   seasonal fault.
#' @param offset How far, as a share, the year's ratio must stand from 1 to count as a level
#'   offset.
#' @param max_missing The missing share above which the radar's totals are not judged.
#' @param min_days The fewest days a month or a half-year needs for its ratio.
#' @return A `pdm_radar_season` list: `verdict` (`"missing data"`, `"radar under-reads in
#'   winter"`, `"gauges under-catch in winter"`, `"radar reads high"`, `"radar reads low"` or
#'   `"no clear fault"`), `why` (one sentence), `seasons` (each half-year and the year: days,
#'   the median daily ratio, events and their median ratio) and `monthly` (each month's days
#'   and median daily ratio).
#' @examples
#' set.seed(1)
#' month <- rep(1:12, each = 20)
#' gauge <- rexp(240, 1 / 6) + 1
#' # Radar reading 70% of the gauges in winter, all of it in summer.
#' radar <- gauge * ifelse(month %in% c(10:12, 1:3), 0.7, 1)
#' radar_by_season(data.frame(month = month, gauge_mm = gauge, radar_mm = radar))
#' @seealso [balance_diagnosis()]
#' @export
radar_by_season <- function(pairs, events = NULL, missing_share = NA_real_, shift = 0.15,
                            offset = 0.15, max_missing = 0.1, min_days = 10) {
  .check(is.data.frame(pairs) && all(c("month", "gauge_mm", "radar_mm") %in% names(pairs)),
         "pairs needs month, gauge_mm and radar_mm, one row per day")
  .check(is.null(events) ||
           (is.data.frame(events) &&
              all(c("season", "radar_mm", "reference_mm") %in% names(events))),
         "events needs season, radar_mm and reference_mm")
  .check(length(missing_share) == 1 && (is.na(missing_share) || .scalar(missing_share, 0)),
         "missing_share must be one share, or NA")
  ok <- is.finite(pairs$gauge_mm) & is.finite(pairs$radar_mm) & pairs$gauge_mm > 0 &
    pairs$radar_mm > 0 & pairs$month %in% 1:12
  p <- pairs[ok, , drop = FALSE]
  p$ratio <- p$radar_mm / p$gauge_mm
  half <- ifelse(p$month %in% c(10:12, 1:3), "winter", "summer")
  med <- function(x) if (length(x) >= min_days) stats::median(x) else NA_real_

  monthly <- data.frame(month = 1:12,
                        days = vapply(1:12, function(m) sum(p$month == m), 0L),
                        ratio = vapply(1:12, function(m) med(p$ratio[p$month == m]), 0))
  ev_ratio <- function(s) {
    if (is.null(events)) return(c(NA_real_, 0))
    e <- events[(s == "year" | events$season == s) & is.finite(events$radar_mm) &
                  is.finite(events$reference_mm) & events$reference_mm >= 2, , drop = FALSE]
    c(if (nrow(e)) stats::median(e$radar_mm / e$reference_mm) else NA_real_, nrow(e))
  }
  seasons <- do.call(rbind, lapply(c("winter", "summer", "year"), function(s) {
    x <- if (s == "year") p$ratio else p$ratio[half == s]
    e <- ev_ratio(s)
    data.frame(season = s, days = length(x), ratio = med(x), events = as.integer(e[2]),
               event_ratio = e[1])
  }))
  w <- seasons$ratio[1]
  s <- seasons$ratio[2]
  y <- seasons$ratio[3]
  ws <- w / s
  pct <- function(r) sprintf("%+.0f%%", 100 * (r - 1))
  ev_w <- seasons$event_ratio[1]
  ev_s <- seasons$event_ratio[2]
  event_note <- if (is.finite(ev_w) && is.finite(ev_s)) {
    sprintf(paste(" Over the events, the radar's rain was %s of the gauges' in winter and %s",
                  "in summer."),
            pct(ev_w), pct(ev_s))
  } else {
    ""
  }

  verdict <- if (isTRUE(missing_share > max_missing)) {
    "missing data"
  } else if (!is.finite(ws)) {
    "not assessed"
  } else if (ws <= 1 / (1 + shift)) {
    "radar under-reads in winter"
  } else if (ws >= 1 + shift) {
    "gauges under-catch in winter"
  } else if (is.finite(y) && y >= 1 + offset) {
    "radar reads high"
  } else if (is.finite(y) && y <= 1 / (1 + offset)) {
    "radar reads low"
  } else {
    "no clear fault"
  }
  why <- switch(
    verdict,
    "missing data" = sprintf(paste("The radar is missing %.0f%% of the steps the gauges cover:",
                                   "its totals rest on less data, so they are not judged.",
                                   "See radar_skipped_files.csv."), 100 * missing_share),
    "not assessed" = sprintf(paste("Under %d days in %s, so the seasons cannot be compared.%s"),
                             min_days,
                             paste(seasons$season[1:2][!is.finite(seasons$ratio[1:2])],
                                   collapse = " and "),
                             if (is.finite(y)) {
                               sprintf(paste(" Over the days there are, the radar reads",
                                             "%s of the gauges."), pct(y))
                             } else {
                               ""
                             }),
    "radar under-reads in winter" = sprintf(paste(
      "The radar reads %s of the gauges in winter and %s in summer: in winter the beam passes",
      "over shallow rain, and the bright band distorts it. Use the radar for pattern, with its",
      "level from the gauges (h19_bias, multiquadric_h19, ked_h19).%s"),
      pct(w), pct(s), event_note),
    "gauges under-catch in winter" = sprintf(paste(
      "The radar reads %s of the gauges in winter and %s in summer: the gauges lose rain to",
      "wind in winter. The gauge averages may be low in winter; check the gauges' exposure.%s"),
      pct(w), pct(s), event_note),
    "radar reads high" = sprintf(paste(
      "The radar reads %s of the gauges all year, alike in both seasons: its own scaling. Take",
      "its level from the gauges.%s"), pct(y), event_note),
    "radar reads low" = sprintf(paste(
      "The radar reads %s of the gauges all year, alike in both seasons: its own scaling. Take",
      "its level from the gauges.%s"), pct(y), event_note),
    "no clear fault" = sprintf(paste(
      "The radar reads %s of the gauges in winter and %s in summer: within the %.0f%% allowed.",
      "Its rank more likely reflects timing or pattern than its level.%s"),
      pct(w), pct(s), 100 * shift, event_note))
  structure(list(verdict = verdict, why = why, seasons = seasons, monthly = monthly,
                 missing_share = missing_share),
            class = "pdm_radar_season")
}

#' @export
print.pdm_radar_season <- function(x, ...) {
  cat(sprintf("Radar by season: %s\n  %s\n", x$verdict, x$why))
  print(x$seasons, row.names = FALSE)
  invisible(x)
}
