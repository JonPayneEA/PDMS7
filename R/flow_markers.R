# ============================================================ #
# Tool:         flow_markers
# Description:  Flow thresholds from the record itself, for catchments without warning
#               thresholds: QMED from water-year maxima, and flow duration exceedances
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-12
# Modified:     2026-11-12 - First version
# Tier:         1
# Inputs:       Observed flow (m3/s), its time step and optional times
# Outputs:      A thresholds table (name, value, unit, note) for register_data()
# Dependencies: stats
# ============================================================ #

#' Flow thresholds from the record: QMED and flow duration markers
#'
#' Where a catchment has no warning thresholds, the record itself gives flows worth scoring a
#' model against. `flow_markers()` computes them, in a table that [register_data()] takes as
#' `thresholds`; `register_data()` uses `QMED`, `Q1` and `Q5` itself when no thresholds are
#' given.
#'
#' | Marker | Flow | Crossed |
#' |---|---|---|
#' | `QMED` | Median annual maximum: the 2-year flood | One year in two |
#' | `0.5QMED`, multiples | Fraction of QMED; 0.5 is near a UK POT threshold | A few times a year |
#' | `Q1`, `Q5`, any `Q<p>` | Exceeded `p` per cent of the time | Above Q1 3.6 days a year |
#'
#' QMED follows the Flood Estimation Handbook: the median of the annual maxima of water years,
#' October to September, each year counted only if at least `complete` of its steps are
#' observed. From 15-minute or hourly data the maxima are near-instantaneous peaks, as the
#' Handbook intends; from daily means QMED is lower. With fewer than 10 years the median is
#' uncertain, and a warning says so; fewer than 2 complete years give no QMED. Without times,
#' years are taken as blocks of 365.25 days from the start of the record.
#'
#' Exceedance markers count time, not floods: a long wet winter spends many days above Q5
#' without a notable flood. QMED and its multiples count peaks.
#'
#' @param observed Observed flow, m3/s; missing values allowed.
#' @param dt Time step, hours.
#' @param time Optional times of the flows (POSIXct), for water years.
#' @param markers Markers to compute, from `QMED`, a multiple such as `0.5QMED`, or `Q<p>`
#'   with `p` a percentage between 0 and 100, such as `Q1` or `Q0.5`.
#' @param complete Smallest fraction of a water year's steps that must be observed for its
#'   maximum to count towards QMED.
#' @return A data frame with `name`, `value` (m3/s), `unit` (`flow`) and `note`, and the
#'   number of complete years as attribute `years`.
#' @examples
#' set.seed(1)
#' n <- 24 * 365 * 3
#' q <- exp(stats::filter(rnorm(n, 0, 0.05), 0.995, method = "recursive"))
#' flow_markers(q, dt = 1)
#' flow_markers(q, dt = 1, markers = c("0.5QMED", "Q10"))
#' @export
flow_markers <- function(observed, dt, time = NULL, markers = c("QMED", "Q1", "Q5"),
                         complete = 0.9) {
  .check(is.numeric(observed) && sum(is.finite(observed)) >= 2,
         "observed must be a numeric flow series with at least two values")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  .check(.scalar(complete, 0, 1) && complete > 0, "complete must lie in (0, 1]")
  .check(is.character(markers) && length(markers) > 0 && !anyDuplicated(markers),
         "markers must be distinct names such as QMED, 0.5QMED or Q1")
  parsed <- lapply(markers, .parse_marker)
  qmed <- NULL
  years <- NA_integer_
  if (any(vapply(parsed, function(m) m$kind == "qmed", logical(1)))) {
    maxima <- .annual_maxima(observed, dt, time, complete)
    years <- length(maxima)
    .check(years >= 2, paste(
      "QMED needs at least two complete water years;", years, "found. Use exceedance markers",
      "such as Q1 instead"
    ))
    if (years < 10) {
      warning(sprintf(paste("QMED from %d complete water years is uncertain; the Flood",
                            "Estimation Handbook prefers 10 or more."), years), call. = FALSE)
    }
    qmed <- stats::median(maxima)
  }
  flows <- observed[is.finite(observed)]
  value <- vapply(parsed, function(m) {
    if (m$kind == "qmed") return(m$multiple * qmed)
    stats::quantile(flows, 1 - m$percent / 100, names = FALSE, type = 7)
  }, numeric(1))
  note <- vapply(parsed, function(m) {
    if (m$kind == "qmed") {
      times <- if (m$multiple == 1) "" else paste0(format(m$multiple), " x ")
      sprintf("%sMedian of %d water-year maxima", times, years)
    } else {
      sprintf("Flow exceeded %s%% of the time", format(m$percent))
    }
  }, character(1))
  out <- data.frame(name = markers, value = signif(value, 6), unit = "flow", note = note)
  .check(all(is.finite(out$value) & out$value > 0),
         "Every marker must be a positive flow; the record may be too flat or too short")
  attr(out, "years") <- years
  out
}

# One marker name, as a list: kind "qmed" with a multiple, or "exceedance" with a percentage.
.parse_marker <- function(name) {
  m <- regmatches(name, regexec("^([0-9]*\\.?[0-9]+)?QMED$", name))[[1]]
  if (length(m)) {
    multiple <- if (nzchar(m[2])) as.numeric(m[2]) else 1
    .check(is.finite(multiple) && multiple > 0, paste("Invalid marker", name))
    return(list(kind = "qmed", multiple = multiple))
  }
  m <- regmatches(name, regexec("^Q([0-9]*\\.?[0-9]+)$", name))[[1]]
  .check(length(m) > 0, paste0(
    "Unknown marker ", name, "; use QMED, a multiple such as 0.5QMED, or Q<p> such as Q1"
  ))
  percent <- as.numeric(m[2])
  .check(percent > 0 && percent < 100, paste("The percentage in", name, "must lie in (0, 100)"))
  list(kind = "exceedance", percent = percent)
}

# The maxima of complete water years (October to September), or of 365.25-day blocks from the
# start of the record when there are no times.
.annual_maxima <- function(observed, dt, time, complete) {
  per_year <- 365.25 * 24 / dt
  if (is.null(time)) {
    year <- floor((seq_along(observed) - 1) / per_year)
  } else {
    .check(length(time) == length(observed), "time must be as long as observed")
    t <- as.POSIXlt(time, tz = "UTC")
    year <- t$year + 1900 + (t$mon >= 9)
  }
  counts <- tapply(is.finite(observed), year, sum)
  full <- names(counts)[counts >= complete * per_year]
  keep <- as.character(year) %in% full & is.finite(observed)
  if (!any(keep)) return(numeric(0))
  as.numeric(tapply(observed[keep], year[keep], max))
}

# The flow floor of an event selection given as a marker or a registered threshold's name
# (character), or as c(peak = flow): events whose observed peak reaches it are fitted. NULL for
# a share, which picks the largest fraction of events instead.
.event_floor <- function(share, observed, dt, time = NULL) {
  if (is.numeric(share) && identical(names(share), "peak")) {
    .check(.scalar(unname(share), 0, strict = TRUE), "An event floor must be a positive flow")
    return(unname(share))
  }
  if (!is.character(share)) {
    .check(.scalar(share, 0, 1) && share > 0, paste(
      "event_share must lie in (0, 1], or name a flow marker such as Q1 or 0.5QMED, or a",
      "registered threshold"
    ))
    return(NULL)
  }
  .check(length(share) == 1L, "event_share must be one value")
  suppressWarnings(flow_markers(observed, dt, time, markers = share)$value)
}

# In a project, a selection that names a registered threshold, or a multiple of one (such as
# 0.5QMED when QMED is registered), becomes its registered flow, so the calibration and the
# scorecard use the same value. Anything else is passed on unchanged.
.project_event_share <- function(share, card) {
  if (!is.character(share) || length(share) != 1L) return(share)
  known <- vapply(card$thresholds, function(t) t$name, character(1))
  flows <- vapply(card$thresholds, function(t) t$flow_m3s, numeric(1))
  if (share %in% known) return(c(peak = flows[[match(share, known)]]))
  m <- regmatches(share, regexec("^([0-9]*\\.?[0-9]+)(.+)$", share))[[1]]
  if (length(m) && m[3] %in% known) {
    return(c(peak = as.numeric(m[2]) * flows[[match(m[3], known)]]))
  }
  share
}

# The markers register_data() records when no thresholds are given, from the observed flow it
# is given: a thresholds table, or NULL. QMED needs times (for water years and the step) and is
# dropped without them; any marker that cannot be worked out is dropped too.
.record_markers <- function(markers, forcing, observed) {
  if (!length(markers)) return(NULL)
  time <- if ("time" %in% names(forcing)) forcing$time
  dt <- if (!is.null(time) && length(time) > 1L) {
    as.numeric(difftime(time[2L], time[1L], units = "hours"))
  }
  rows <- lapply(markers, function(m) {
    if (.parse_marker(m)$kind == "qmed" && is.null(dt)) return(NULL)
    tryCatch(suppressWarnings(flow_markers(observed, dt %||% 1, time, markers = m)),
             error = function(e) NULL)
  })
  out <- do.call(rbind, rows)
  if (is.null(out) || !nrow(out)) return(NULL)
  out[!duplicated(out$value), ]
}

# The flow markers a project registers when no thresholds are given, from the calibration rows
# only (rows), each marked with its source. The other rows are blanked, so QMED counts only
# water years complete within the calibration window.
.marker_levels <- function(markers, forcing, observed, rows) {
  seen <- rep(NA_real_, length(observed))
  seen[rows] <- observed[rows]
  levels <- .resolve_thresholds(.record_markers(markers, forcing, seen), NULL)
  lapply(levels, function(t) c(t, list(source = "flow marker")))
}
