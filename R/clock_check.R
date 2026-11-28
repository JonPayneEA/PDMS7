# ============================================================ #
# Tool:         clock_check
# Description:  Whether a rain series' clock is out against a reference series over the same
#               place: logged in local time (an hour out in British Summer Time only), stamped
#               at the step's end, or out by a fixed offset all year; from the lag at which the
#               two series agree best, in summer time and in winter time separately
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-28
# Tier:         1
# Inputs:       Step-start times in UTC; a rain series (such as a gauge) and a reference over
#               the same place (such as the radar over the gauge), mm per step
# Outputs:      A pdm_clock_check list
# Dependencies: stats
# ============================================================ #

# Whether each time falls in British Summer Time: from 01:00 UTC on the last Sunday of March
# to 01:00 UTC on the last Sunday of October.
.in_bst <- function(time) {
  year <- as.integer(format(time, "%Y", tz = "UTC"))
  last_sunday <- function(y, month) {
    end <- as.Date(sprintf("%d-%02d-31", y, month))
    end - (as.integer(format(end, "%u")) %% 7)
  }
  edge <- function(y, month) {
    as.POSIXct(paste(last_sunday(y, month), "01:00:00"), tz = "UTC")
  }
  years <- unique(year)
  starts <- stats::setNames(edge(years, 3), years)
  ends <- stats::setNames(edge(years, 10), years)
  key <- as.character(year)
  unname(time >= starts[key] & time < ends[key])
}

#' Whether a rain series' clock is out
#'
#' A gauge whose logger keeps local time stamps rain an hour late through British Summer Time
#' and on time in winter. One that stamps each step at its end, not its start, is one step late
#' all year. Either quietly spoils every test of timing: the quick response, the events, any
#' merge with radar. Both show as a lag between the series and a reference over the same place,
#' such as the radar over the gauge: rain cannot fall at two times in one place.
#'
#' For summer time and winter time apart, the correlation of the series with the reference is
#' worked out at each lag from `-max_lag_h` to `max_lag_h`. A positive lag means the series'
#' stamps are later than the reference's. The best lag counts only if its correlation beats the
#' correlation at lag 0 by `margin`; otherwise the period is in step. Then:
#'
#' - **logged in local time**: late by an hour (to within a step) in summer time, in step in
#'   winter time;
#' - **an hour out in summer time**: any other one-hour lag in summer time alone, such as an
#'   early one, which points at the reference being in local time;
#' - **stamped at the step's end**: late by one step in both;
#' - **out all year**: the same other lag in both;
#' - **unsteady**: different lags, neither pattern above;
#' - **in step**: no lag counts in either;
#' - **not enough rain**: under `min_wet` steps with rain in either series in both periods.
#'
#' A period with too little rain is not judged. With only one period judged, the verdict is
#' **in step** or **out in summer time** (or winter time), and `why` says the other period was
#' not judged: an hour out in summer time alone could then be local time or a fixed offset.
#'
#' British Summer Time runs from 01:00 UTC on the last Sunday of March to 01:00 UTC on the last
#' Sunday of October.
#'
#' @param time Step-start times, POSIXct in UTC, evenly spaced.
#' @param series The rain series to check, mm per step, NA where missing.
#' @param reference The reference over the same place, mm per step, NA where missing.
#' @param max_lag_h The largest lag tried either way, hours.
#' @param margin How much the best lag's correlation must beat lag 0's to count.
#' @param min_wet The fewest steps with rain, in each series, a period needs to be judged.
#' @return A `pdm_clock_check` list: `verdict`, `why` (one sentence), `lags` (for summer time
#'   and winter time: `wet_steps`, `lag_h`, `r_best`, `r_zero` and whether the lag counts) and
#'   `correlogram` (`period`, `lag_h`, `r`).
#' @examples
#' time <- seq(as.POSIXct("2020-01-01", tz = "UTC"), by = "15 min", length.out = 4 * 24 * 366)
#' set.seed(1)
#' radar <- ifelse(runif(length(time)) < 0.05, rexp(length(time), 1), 0)
#' # A gauge logged in local time: an hour (four steps) late in summer time only.
#' bst <- format(time, "%m") %in% sprintf("%02d", 4:9)
#' gauge <- radar
#' gauge[bst] <- c(rep(0, 4), radar)[which(bst)]
#' clock_check(time, gauge, radar)
#' @seealso [gauge_response()]
#' @export
clock_check <- function(time, series, reference, max_lag_h = 3, margin = 0.05, min_wet = 30) {
  .check(inherits(time, "POSIXct") && length(time) >= 2 && !anyNA(time),
         "time must be POSIXct step-start times, with no gaps in the times themselves")
  n <- length(time)
  .check(is.numeric(series) && length(series) == n, "series must be numeric, one value a step")
  .check(is.numeric(reference) && length(reference) == n,
         "reference must be numeric, one value a step")
  dt <- diff(as.numeric(time))
  .check(all(dt > 0) && all(abs(dt - dt[1]) < 1e-6), "time must be evenly spaced and increasing")
  step_h <- dt[1] / 3600
  .check(.scalar(max_lag_h, step_h), "max_lag_h must be at least one step")
  .check(.scalar(margin, 0, 1), "margin must be between 0 and 1")
  .check(.scalar(min_wet, 1), "min_wet must be at least 1")
  k_max <- floor(max_lag_h / step_h + 1e-9)
  lags <- -k_max:k_max
  bst <- .in_bst(time)

  one_period <- function(in_period) {
    idx <- which(in_period)
    # Wet steps: the fewer of the two series' counts of steps with rain. Steps wet in both at
    # once would be too few for a series out of step, the very fault being looked for.
    both <- is.finite(series[idx]) & is.finite(reference[idx])
    wet <- min(sum(both & series[idx] > 0), sum(both & reference[idx] > 0))
    r <- vapply(lags, function(k) {
      j <- idx + k
      ok <- j >= 1 & j <= n
      a <- reference[idx[ok]]
      b <- series[j[ok]]
      keep <- is.finite(a) & is.finite(b)
      if (sum(keep) < 3 || stats::sd(a[keep]) == 0 || stats::sd(b[keep]) == 0) return(NA_real_)
      stats::cor(a[keep], b[keep])
    }, numeric(1))
    list(wet = wet, r = r)
  }
  periods <- list(summer = one_period(bst), winter = one_period(!bst))

  row <- function(name) {
    p <- periods[[name]]
    r0 <- p$r[lags == 0]
    best <- if (all(is.na(p$r))) NA_integer_ else lags[which.max(p$r)]
    rb <- if (is.na(best)) NA_real_ else p$r[lags == best]
    counts <- p$wet >= min_wet && !is.na(best) && best != 0 && is.finite(r0) &&
      rb - r0 >= margin
    data.frame(period = name, wet_steps = p$wet, lag_h = if (counts) best * step_h else 0,
               r_best = rb, r_zero = r0, lag_counts = counts)
  }
  tab <- rbind(row("summer"), row("winter"))
  correlogram <- do.call(rbind, lapply(names(periods), function(name) {
    data.frame(period = name, lag_h = lags * step_h, r = periods[[name]]$r)
  }))

  s <- tab$lag_h[1]
  w <- tab$lag_h[2]
  near <- function(x, y) abs(x - y) <= step_h / 2 + 1e-9
  hour <- function(x) abs(abs(x) - 1) <= step_h + 1e-9
  judged <- tab$wet_steps >= min_wet
  one_only <- sum(judged) == 1
  only <- if (one_only) tab$period[judged] else NA_character_
  lag_only <- if (one_only) tab$lag_h[judged] else NA_real_
  verdict <- if (!any(judged)) {
    "not enough rain"
  } else if (one_only && lag_only == 0) {
    "in step"
  } else if (one_only) {
    paste("out in", only, "time")
  } else if (s == 0 && w == 0) {
    "in step"
  } else if (w == 0 && s > 0 && hour(s)) {
    "logged in local time"
  } else if (w == 0 && hour(s)) {
    "an hour out in summer time"
  } else if (near(s, step_h) && near(w, step_h)) {
    "stamped at the step's end"
  } else if (near(s, w)) {
    "out all year"
  } else {
    "unsteady"
  }
  fmt <- function(x) {
    if (x == 0) return("in step")
    sprintf("%s by %s h", if (x > 0) "late" else "early", format(abs(x)))
  }
  other <- if (one_only) setdiff(c("summer", "winter"), only) else NA_character_
  unjudged <- if (one_only) {
    sprintf(paste0(" %s time had too little rain to judge (%d steps; %d needed), so a ",
                   "logger on local time cannot be told from a fixed offset."),
            paste0(toupper(substr(other, 1, 1)), substring(other, 2)),
            tab$wet_steps[tab$period == other], as.integer(min_wet))
  } else {
    ""
  }
  why <- switch(sub("^out in (summer|winter) time$", "out in one period", verdict),
    "not enough rain" = sprintf(paste0(
      "Too few steps with rain to judge the clock (summer time %d, winter ",
      "time %d; %d needed in each)."), tab$wet_steps[1], tab$wet_steps[2], as.integer(min_wet)),
    "in step" = if (one_only) {
      paste0("The series agrees best with the reference at lag 0 in ", only, " time.", unjudged)
    } else {
      "The series agrees best with the reference at lag 0, in summer and winter time."
    },
    "out in one period" = paste0("The series is ", fmt(lag_only), " in ", only, " time.",
                                 unjudged),
    "logged in local time" = sprintf(paste0(
      "The series is late by %s h in summer time and in step in winter time: its logger keeps ",
      "local time. Move its summer-time stamps back an hour."), format(s)),
    "an hour out in summer time" = sprintf(paste0(
      "The series is %s in summer time and in step in winter time: one of the two keeps local ",
      "time, the reference if the series is early."), fmt(s)),
    "stamped at the step's end" = paste0(
      "The series is one step late all year: it stamps each step at its end, not its start. ",
      "Move every stamp back a step."),
    "out all year" = sprintf("The series is %s all year: a fixed offset in its clock.", fmt(s)),
    "unsteady" = sprintf(paste0(
      "The series is %s in summer time and %s in winter time: its clock is not steady, or ",
      "the two series are not over the same place."), fmt(s), fmt(w)))
  structure(list(verdict = verdict, why = why, lags = tab, correlogram = correlogram,
                 step_hours = step_h),
            class = "pdm_clock_check")
}

#' @export
print.pdm_clock_check <- function(x, ...) {
  cat("Clock check: ", x$verdict, "\n", x$why, "\n", sep = "")
  t <- x$lags
  t$r_best <- round(t$r_best, 3)
  t$r_zero <- round(t$r_zero, 3)
  print(t, row.names = FALSE)
  invisible(x)
}
