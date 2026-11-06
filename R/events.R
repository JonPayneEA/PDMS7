# ============================================================ #
# Tool:         events
# Description:  Rainfall-runoff events and catchment response time from the records alone
#               (DMCA-ESR, Giani et al. 2021, 2022), and model scores event by event
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-06
# Modified:     2026-11-06 - Record the check against the authors' reference code
# Tier:         3
# Inputs:       Rain (mm per step) and flow (any units; m3/s with an area for volumes)
# Outputs:      Response time; a table of events; per-event model scores
# Dependencies: stats
# ============================================================ #

#' Catchment response time from rain and flow records
#'
#' Estimates a catchment's response time, the average lag between the centre of mass of rain
#' and the centre of mass of the flow it produces, from the records alone, by detrending
#' moving-average cross-correlation analysis (DMCA; Giani et al., 2021). No model and no
#' baseflow separation are needed.
#'
#' Rain and flow are each accumulated, and each cumulative series has its centred moving
#' average of window `2h + 1` steps subtracted, leaving its fluctuations. The correlation
#' between the two fluctuation series is computed for every half-window `h`; the response time
#' is the `h` at which it is most negative. Rain and flow may be in any units: the correlation
#' does not depend on scale.
#'
#' The data must resolve the delay: with daily data, a catchment that responds within a day
#' shows a response time of one step or less. A minimum at the largest window searched means
#' the search was too short, and a warning says so.
#'
#' @param rain Rain per step (mm). Missing values count as zero.
#' @param flow Flow per step, in any units. Missing values count as zero in the cumulative
#'   series, as in the published method, so long gaps distort the estimate.
#' @param dt Time step, hours.
#' @param max_response_h Longest response time searched, hours. The default, 150 hours,
#'   follows the published example for hourly data.
#'
#' @return A list: `response_h` (hours), `response_steps`, `window` (the moving-average
#'   window, `2 * response_steps + 1`, in steps) and `curve`, a data frame of `response_h`
#'   and `rho`, the DMCA correlation at each half-window searched.
#' @references Giani, G., Rico-Ramirez, M. A. and Woods, R. A. (2021). A practical, objective,
#'   and robust technique to directly estimate catchment response time. Water Resources
#'   Research, 57, e2020WR028201. doi:10.1029/2020WR028201
#' @examples
#' set.seed(1)
#' rain <- ifelse(runif(3000) < 0.05, rexp(3000, 0.5), 0)
#' # Flow is the rain delayed by 10 steps and smoothed.
#' flow <- stats::filter(c(rep(0, 10), rain[1:2990]), rep(1 / 5, 5), sides = 1)
#' flow[is.na(flow)] <- 0
#' response_time_dmca(rain, flow)$response_h
#' @seealso [find_events()], [pdm_response_time()] for a model's own response
#' @export
response_time_dmca <- function(rain, flow, dt = 1, max_response_h = 150) {
  h_max <- .dmca_h_max(rain, flow, dt, max_response_h)
  # The C core (pdm_dmca_rho), unless options(pdmS7.engine = "r") asks for the R reference.
  rho <- if (.engine_wanted()) {
    dmca_rho(as.double(rain), as.double(flow), as.integer(h_max))
  } else {
    .dmca_rho_r(cumsum(.zero_missing(rain)), cumsum(.zero_missing(flow)), h_max)
  }
  .dmca_response(rho, dt)
}

# Checks the shared arguments of the response-time search and returns the largest half-window.
.dmca_h_max <- function(rain, flow, dt, max_response_h) {
  .check(is.numeric(rain) && is.numeric(flow) && length(rain) == length(flow),
         "rain and flow must be numeric vectors of the same length")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  .check(.scalar(max_response_h, dt), "max_response_h must be at least one time step")
  h_max <- min(floor(max_response_h / dt), floor((length(rain) - 2) / 2))
  .check(h_max >= 1, "The record is too short to search for a response time")
  as.integer(h_max)
}

# The response time from a correlation curve: the half-window with the most negative value.
.dmca_response <- function(rho, dt) {
  .check(any(is.finite(rho)), "Rain or flow does not vary; no response time can be found")
  steps <- which.min(rho)
  h_max <- length(rho)
  if (steps == h_max && h_max > 1) {
    warning("The response time is at the longest searched (", h_max * dt, " h); ",
            "raise max_response_h", call. = FALSE)
  }
  list(response_h = steps * dt, response_steps = steps, window = 2L * steps + 1L,
       curve = data.frame(response_h = seq_len(h_max) * dt, rho = rho))
}

#' Rainfall-runoff events from rain and flow records
#'
#' Finds rainfall-runoff events in continuous records objectively, with the DMCA-based event
#' separation routine (DMCA-ESR) of Giani et al. (2022). It needs no baseflow separation and
#' one setting, `rain_min`, and applies at any time step that resolves the delay between rain
#' and flow. Each event has a rain window and a flow window; a baseflow line joining the flow
#' windows' ends gives each event's quick flow afterwards.
#'
#' The routine, in brief:
#' 1. Estimate the response time with [response_time_dmca()], and take the rain and flow
#'    fluctuations at its window. Rain fluctuations smaller than the largest that `rain_min`
#'    alone could cause are set to zero.
#' 2. An event's core is a run of steps where both fluctuations are non-zero; two steps where
#'    either is zero end it.
#' 3. Move the core's ends outwards to where the rain starts and stops (rain at or below
#'    `rain_min` delimits it), then to where the flow starts to rise and finishes receding
#'    (from the signs of the flow fluctuations, which are negative before the centre of mass
#'    and positive after it).
#' 4. Discard events with no dry spell around their rain, or whose flow window does not start
#'    before the flow's centre of mass and end after it; merge events that overlap.
#'
#' This is an independent implementation from the published description and its reference
#' code. One detail differs: overlapping events merge into one spanning all of them, where the
#' reference code takes the end of the last. Rain windows that would run off either end of the
#' record are discarded.
#'
#' It was checked against the authors' reference code
#' (\url{https://github.com/giuliagiani/DMCA-ESR}), run in Octave, on three synthetic records:
#' two years of hourly data from a fast and a slow catchment, and ten years of daily data. The
#' response times and all 663 event windows were identical. None of those records had
#' overlapping events, so the one deliberate difference above was not exercised.
#'
#' The work is done by the C core (`pdm_find_events()` and `pdm_event_summary()` in
#' `src/pdm_core.h`), which other languages can call directly; `options(pdmS7.engine = "r")`
#' runs the R reference implementation instead.
#'
#' @param rain Rain per step (mm). Missing values count as zero.
#' @param flow Flow per step, m3/s (or any units if `area_km2` is not given).
#' @param time Optional times of the steps, carried into the result.
#' @param dt Time step, hours.
#' @param rain_min Smallest rain intensity that counts at this time step, mm/h. By default
#'   0.2 mm/h at an hourly step, scaled by `dt^-0.5` (0.04 mm/h for daily data, 0.4 mm/h for
#'   15-minute data), following the guidance of Giani et al. (2022) for British catchments.
#'   They found results insensitive between about 0.1 and 1 mm/h at hourly scale.
#' @param max_response_h Passed to [response_time_dmca()].
#' @param area_km2 Optional catchment area, km2. With it, flow volumes are in mm and each event
#'   has a runoff ratio.
#'
#' @return A data frame with one row per event: `event`, the first and last rows of its rain
#'   window (`rain_start`, `rain_end`) and flow window (`flow_start`, `flow_end`), their times
#'   when `time` is given, `rain_mm`, `peak_row` and `peak_flow` (the largest flow in the flow
#'   window), and with `area_km2`, `flow_mm` and `quickflow_mm` (flow above the baseflow line)
#'   and `runoff_ratio` (quick flow over rain). Attributes: `response` (from
#'   [response_time_dmca()]), `rain_min`, `dt` and `baseflow`, the baseflow line.
#' @references Giani, G., Tarasova, L., Woods, R. A. and Rico-Ramirez, M. A. (2022). An
#'   objective time-series-analysis method for rainfall-runoff event identification. Water
#'   Resources Research, 58, e2021WR031283. doi:10.1029/2021WR031283
#' @examples
#' river <- synthetic_catchment(years = 2, dt = 1, seed = 1)
#' events <- find_events(river$forcing$rain, river$observed, river$forcing$time, dt = 1,
#'                       area_km2 = river$truth$area_km2)
#' attr(events, "response")$response_h
#' head(events[, c("rain_start_time", "flow_end_time", "rain_mm", "runoff_ratio")])
#' @seealso [event_scores()], [batch_events()], [response_time_dmca()]
#' @export
find_events <- function(rain, flow, time = NULL, dt = 1, rain_min = NULL,
                        max_response_h = 150, area_km2 = NULL) {
  rain_min <- rain_min %||% (0.2 * dt^-0.5)
  .check(.scalar(rain_min, 0, strict = TRUE), "rain_min must be a positive intensity, mm/h")
  .check(is.null(time) || length(time) == length(rain), "time must match rain in length")
  .check(is.null(area_km2) || .scalar(area_km2, 0, strict = TRUE),
         "area_km2 must be a positive number, or NULL")
  h_max <- .dmca_h_max(rain, flow, dt, max_response_h)
  columns <- c("rain_start", "rain_end", "flow_start", "flow_end")
  if (.engine_wanted()) {
    found <- tryCatch(
      find_events_engine(as.double(rain), as.double(flow), dt, rain_min, h_max),
      error = function(e) {
        # The core refuses a record whose rain or flow does not vary; say so as R does.
        .check(FALSE, conditionMessage(e))
      }
    )
    response <- .dmca_response(found$rho, dt)
    rows <- matrix(as.integer(found$events), ncol = 4, dimnames = list(NULL, columns))
  } else {
    response <- response_time_dmca(rain, flow, dt, max_response_h)
    intensity <- .zero_missing(rain) / dt
    h <- response$response_steps
    fl <- .event_fluctuations(intensity, flow, h, rain_min)
    rows <- .dmca_esr(intensity, fl$rain, fl$flow, h, rain_min)
  }
  .event_table(rows, rain, flow, time, dt, area_km2, response, rain_min)
}

# The DMCA correlation for half-windows 1..h_max, in R: the reference for the compiled
# pdm_dmca_rho() in the C core (src/pdm_core.c). Only steps with a full window are scored.
.dmca_rho_r <- function(cum_rain, cum_flow, h_max) {
  n <- length(cum_rain)
  vapply(seq_len(h_max), function(h) {
    keep <- (h + 1L):(n - h)
    fr <- (cum_rain - .moving_mean(cum_rain, h))[keep]
    fq <- (cum_flow - .moving_mean(cum_flow, h))[keep]
    sum(fr * fq) / sqrt(sum(fr^2) * sum(fq^2))
  }, numeric(1))
}

# Missing values as zeros, as the cumulative series of the published method treat them.
.zero_missing <- function(x) {
  x[!is.finite(x)] <- 0
  x
}

# Centred moving average with a window of 2h + 1, shrinking at the ends as MATLAB's movmean
# does, from cumulative sums so each window costs one pass.
.moving_mean <- function(x, h) {
  n <- length(x)
  sums <- c(0, cumsum(x))
  i <- seq_len(n)
  lo <- pmax(1L, i - h)
  hi <- pmin(n, i + h)
  (sums[hi + 1L] - sums[lo]) / (hi - lo + 1L)
}

# Rain and flow fluctuations at the response-time window. Rain fluctuations no larger than
# rain_min could cause, (rain_min / L) (L - 1) / 2 with L = 2h + 1 (Eq. 1 of Giani et al.,
# 2022), are zeroed; flow fluctuations are zeroed only below rounding.
.event_fluctuations <- function(intensity, flow, h, rain_min) {
  cum_rain <- cumsum(intensity)
  cum_flow <- cumsum(.zero_missing(flow))
  rain <- cum_rain - .moving_mean(cum_rain, h)
  flow_fl <- cum_flow - .moving_mean(cum_flow, h)
  window <- 2 * h + 1
  rain[abs(rain) < rain_min / window * (window - 1) / 2] <- 0
  flow_fl[abs(flow_fl) < cum_flow[length(cum_flow)] / 1e15] <- 0
  list(rain = rain, flow = flow_fl)
}

# The ten steps of DMCA-ESR on row numbers. Returns a matrix of rain_start, rain_end,
# flow_start and flow_end, one row per event.
.dmca_esr <- function(rain, fr, ff, h, rain_min) {
  n <- length(rain)
  cores <- .event_cores(fr * ff)
  bc <- cores$begin
  ec <- cores$end
  k <- length(bc)
  none <- matrix(integer(0), 0, 4, dimnames = list(NULL, c("rain_start", "rain_end",
                                                           "flow_start", "flow_end")))
  if (!k) return(none)
  # A core ends (or starts) on zero rain fluctuations when the two steps after (before) it
  # have them; otherwise it ends on zero flow fluctuations.
  rain_quiet_after <- vapply(ec, function(e) e + 2L < n && all(fr[e + 1:2] == 0), logical(1))
  rain_quiet_before <- vapply(bc, function(b) b > 2L && all(fr[b - 2:1] == 0), logical(1))
  er <- .rain_ends(rain, bc, ec, rain_quiet_after, rain_min)
  br <- .rain_starts(rain, bc, er, rain_quiet_before, rain_min)
  # Step 6: a rain event must start no later than it ends, and be bounded by dry steps.
  ok <- br <= er & br > 1L & er < n
  ok[ok] <- rain[br[ok] - 1L] <= rain_min & rain[er[ok] + 1L] <= rain_min
  br[!ok] <- NA_integer_
  er[!ok] <- NA_integer_
  ef <- .flow_ends(ff, n, bc, ec, br, er, rain_quiet_after, h)
  bf <- .flow_starts(ff, bc, br, ef, rain_quiet_before)
  # Step 9: a flow window must end after it starts, start on a rising (negative) fluctuation
  # and end on a falling (positive) one, and not lead its rain.
  ok <- !is.na(br) & !is.na(bf) & !is.na(ef) & bf <= n & ef <= n
  ok[ok] <- ef[ok] > bf[ok] & ff[bf[ok]] <= 0 & ff[ef[ok]] >= 0 & bf[ok] >= br[ok] &
    ef[ok] >= er[ok]
  if (!any(ok)) return(none)
  .merge_overlaps(cbind(rain_start = br[ok], rain_end = er[ok], flow_start = bf[ok],
                        flow_end = ef[ok]))
}

# Step 3: runs of non-zero bivariate fluctuations; two consecutive zero steps end a run (one
# can be a change of sign at the centre of mass).
.event_cores <- function(fb) {
  n <- length(fb)
  begin <- end <- integer(n %/% 2L + 1L)
  g <- 0L
  q <- 1L
  while (q + 1L <= n) {
    if (abs(fb[q]) > 0) {
      g <- g + 1L
      begin[g] <- q
      while (q + 1L < n && (abs(fb[q]) + abs(fb[q + 1L])) > 0) {
        q <- q + 1L
      }
      end[g] <- q - 1L
    }
    q <- q + 1L
  }
  list(begin = begin[seq_len(g)], end = end[seq_len(g)])
}

# Moves from step i by `by` (1 or -1) for as long as keep(i) holds; returns where it stops.
# Every edge search of DMCA-ESR is such a walk.
.walk <- function(i, by, keep) {
  while (keep(i)) i <- i + by
  i
}

# Step 4: the end of each rain event. Ended on quiet rain: back to the last wet step, or, if
# still raining, on to the last step above rain_min before the next core. Ended on quiet flow:
# back through the rain to the last step above rain_min, within the core.
.rain_ends <- function(rain, bc, ec, quiet, rain_min) {
  n <- length(rain)
  vapply(seq_along(ec), function(g) {
    e <- ec[g]
    if (!quiet[g]) return(.back_to_rain(rain, e, bc[g], rain_min))
    if (rain[e] == 0) return(.walk(e, -1L, function(i) i > 1L && rain[i] == 0))
    limit <- if (g < length(bc)) bc[g + 1L] else n
    .walk(e, 1L, function(i) i + 1L < n && rain[i] > rain_min && i < limit) - 1L
  }, integer(1))
}

# For a core that ended on quiet flow: back from e through any rain above rain_min, then through
# the light rain below it, to the last step above rain_min, not before the core's start.
.back_to_rain <- function(rain, e, core_start, rain_min) {
  e <- .walk(e, -1L, function(i) i > 1L && rain[i] > rain_min && i >= core_start)
  .walk(e, -1L, function(i) i > 1L && rain[i] < rain_min && i >= core_start)
}

# Step 5: the start of each rain event. Started from quiet rain with no rain at the core's
# start: on to the first wet step. Otherwise back to the first step above rain_min, not before
# the previous rain event's end.
.rain_starts <- function(rain, bc, er, quiet, rain_min) {
  n <- length(rain)
  vapply(seq_along(bc), function(g) {
    b <- bc[g]
    if (quiet[g] && rain[b] == 0) return(.walk(b, 1L, function(i) i + 1L < n && rain[i] == 0))
    previous <- if (g > 1L) er[g - 1L] else 0L
    .walk(b, -1L, function(i) i > 1L && rain[i] > rain_min && i > previous) + 1L
  }, integer(1))
}

# Step 7: the end of each flow event. Core ended on quiet rain: from the rain's end, through
# any remaining rise (negative fluctuations) and then the recession (positive ones), not past
# the next rain event's start plus the response time. Core ended on quiet flow: back from the
# core's end to the last falling step.
.flow_ends <- function(ff, n, bc, ec, br, er, quiet, h) {
  valid <- which(!is.na(br) & !is.na(er))
  out <- rep(NA_integer_, length(bc))
  for (g in valid) {
    if (!quiet[g]) {
      out[g] <- .walk(ec[g], -1L, function(i) i > bc[g] && ff[i] <= 0)
      next
    }
    later <- valid[valid > g]
    limit <- if (length(later)) br[later[1L]] + h else Inf
    f <- .walk(er[g], 1L, function(i) i + 1L < n && ff[i] <= 0 && i < limit)
    out[g] <- .walk(f, 1L, function(i) i + 1L < n && ff[i] > 0 && i < limit) - 1L
  }
  out
}

# Step 8: the start of each flow event, the first rising step (negative fluctuation) from the
# rain's start, or from the core's start when the core began on quiet flow.
.flow_starts <- function(ff, bc, br, ef, quiet) {
  out <- rep(NA_integer_, length(bc))
  for (g in which(!is.na(br) & !is.na(ef))) {
    out[g] <- if (quiet[g]) {
      .walk(br[g], 1L, function(i) ff[i] > 0 && i < ef[g])
    } else {
      .walk(bc[g], 1L, function(i) i <= ef[g] && ff[i] >= 0)
    }
  }
  out
}

# Step 10: events whose rain or flow windows overlap the next event's merge into one spanning
# them all.
.merge_overlaps <- function(ev) {
  if (nrow(ev) < 2L) return(ev)
  group <- cumsum(c(TRUE, !(ev[-nrow(ev), "rain_end"] > ev[-1L, "rain_start"] |
                              ev[-nrow(ev), "flow_end"] > ev[-1L, "flow_start"])))
  cbind(rain_start = tapply(ev[, "rain_start"], group, min),
        rain_end = tapply(ev[, "rain_end"], group, max),
        flow_start = tapply(ev[, "flow_start"], group, min),
        flow_end = tapply(ev[, "flow_end"], group, max))
}

# A baseflow line joining the flow events' delimiters in turn, never above the flow (as in
# the reference code's BASEFLOW_CURVE); outside the joined span it is the flow itself.
.baseflow_line <- function(flow, starts, ends) {
  base <- flow
  knots <- as.vector(rbind(starts, ends))
  for (i in seq_len(max(0L, length(knots) - 1L))) {
    a <- knots[i]
    b <- knots[i + 1L]
    if (b - a > 1L && is.finite(flow[a]) && is.finite(flow[b])) {
      base[(a + 1L):(b - 1L)] <- flow[a] + (flow[b] - flow[a]) * seq_len(b - a - 1L) / (b - a)
    }
  }
  pmin(base, flow)
}

# One row per event with its windows, totals and peak.
.event_table <- function(rows, rain, flow, time, dt, area_km2, response, rain_min) {
  out <- data.frame(event = seq_len(nrow(rows)), rows, row.names = NULL)
  if (!is.null(time)) {
    for (w in c("rain_start", "rain_end", "flow_start", "flow_end")) {
      out[[paste0(w, "_time")]] <- time[out[[w]]]
    }
  }
  # Totals from the C core (pdm_event_summary), or from the R reference.
  totals <- if (.engine_wanted()) {
    t <- event_summary_engine(as.double(rain), as.double(flow), dt, area_km2 %||% 0,
                              as.double(rows))
    list(summary = matrix(t$summary, ncol = 6), baseflow = t$baseflow)
  } else {
    .event_totals_r(rows, rain, flow, dt, area_km2)
  }
  sm <- totals$summary
  out$rain_mm <- sm[, 1]
  out$peak_row <- as.integer(sm[, 2] + 1)
  out$peak_flow <- sm[, 3]
  if (!is.null(area_km2)) {
    out$flow_mm <- sm[, 4]
    out$quickflow_mm <- sm[, 5]
    out$runoff_ratio <- sm[, 6]
  }
  attr(out, "response") <- response
  attr(out, "rain_min") <- rain_min
  attr(out, "dt") <- dt
  attr(out, "baseflow") <- totals$baseflow
  out
}

# The R reference for pdm_event_summary(): per event, rain depth, the peak's 0-based row, the
# peak, and the flow and quick-flow volumes (mm) and runoff ratio (NA without an area); and
# the baseflow line.
.event_totals_r <- function(rows, rain, flow, dt, area_km2) {
  span <- function(a, b) Map(seq.int, a, b)
  rain_spans <- span(rows[, "rain_start"], rows[, "rain_end"])
  flow_spans <- span(rows[, "flow_start"], rows[, "flow_end"])
  baseflow <- .baseflow_line(flow, rows[, "flow_start"], rows[, "flow_end"])
  to_mm <- if (is.null(area_km2)) NA_real_ else 3.6 * dt / area_km2
  summary <- vapply(seq_len(nrow(rows)), function(e) {
    i <- flow_spans[[e]]
    rain_mm <- sum(.zero_missing(rain[rain_spans[[e]]]))
    peak <- if (any(is.finite(flow[i]))) i[which.max(flow[i])] else NA
    quick <- sum(flow[i] - baseflow[i], na.rm = TRUE) * to_mm
    peak_flow <- if (is.na(peak)) NA_real_ else flow[peak]
    c(rain_mm, peak - 1, peak_flow, sum(flow[i], na.rm = TRUE) * to_mm, quick, quick / rain_mm)
  }, numeric(6))
  list(summary = matrix(summary, ncol = 6, byrow = TRUE), baseflow = baseflow)
}

#' Model scores event by event
#'
#' Scores simulated flow against observed flow within each event's flow window, as found by
#' [find_events()]: how well a model reproduces the peaks, their timing and the volumes of
#' individual events, which a score over the whole record hides.
#'
#' @param events Events from [find_events()].
#' @param simulated,observed Simulated and observed flow, aligned with the record the events
#'   were found in.
#' @param dt Time step, hours. By default, the step the events were found at.
#'
#' @return `events` with the observed and simulated peaks and these scores added:
#'   `peak_error` (simulated over observed peak, less one), `timing_error_h` (hours from the
#'   observed to the simulated peak within the window; positive when the model is late),
#'   `volume_error` (relative error in flow volume over the window) and `nse` (over the
#'   window). Steps with no observation are left out.
#' @examples
#' river <- synthetic_catchment(years = 2, dt = 1, seed = 1)
#' events <- find_events(river$forcing$rain, river$observed, dt = 1)
#' scores <- event_scores(events, river$true_flow, river$observed)
#' summary(scores$peak_error)
#' @seealso [find_events()], [batch_events()]
#' @export
event_scores <- function(events, simulated, observed, dt = attr(events, "dt") %||% 1) {
  .check(is.data.frame(events) && all(c("flow_start", "flow_end") %in% names(events)),
         "events must come from find_events()")
  .check(length(simulated) == length(observed), "simulated and observed must match in length")
  .check(!nrow(events) || max(events$flow_end) <= length(observed),
         "events run past the end of the flow series")
  # The C core (pdm_event_scores), or the R reference.
  scores <- if (.engine_wanted()) {
    windows <- cbind(events$flow_start, events$flow_end, events$flow_start, events$flow_end)
    matrix(event_scores_engine(as.double(simulated), as.double(observed), dt,
                               as.double(windows)), ncol = 6)
  } else {
    .event_scores_r(events, simulated, observed, dt)
  }
  colnames(scores) <- c("observed_peak", "simulated_peak", "peak_error", "timing_error_h",
                        "volume_error", "nse")
  out <- cbind(events, as.data.frame(scores))
  attributes(out)[c("response", "rain_min", "dt")] <- attributes(events)[c("response",
                                                                           "rain_min", "dt")]
  out
}

# The R reference for pdm_event_scores(): one row of six scores per event.
.event_scores_r <- function(events, simulated, observed, dt) {
  scores <- vapply(seq_len(nrow(events)), function(e) {
    i <- seq.int(events$flow_start[e], events$flow_end[e])
    i <- i[is.finite(observed[i]) & is.finite(simulated[i])]
    if (length(i) < 2L) return(rep(NA_real_, 6))
    o <- observed[i]
    s <- simulated[i]
    c(max(o), max(s), max(s) / max(o) - 1, (i[which.max(s)] - i[which.max(o)]) * dt,
      sum(s) / sum(o) - 1, 1 - sum((s - o)^2) / sum((o - mean(o))^2))
  }, numeric(6))
  matrix(scores, ncol = 6, byrow = TRUE)
}

#' Events and event scores across a batch
#'
#' Finds the events in every basin of a [calibrate_batch()] output, from its registered rain
#' and observed flow, and scores the candidate model on each, so model performance during
#' events can be compared across a large sample. Each basin's response time is estimated from
#' the observed and from the simulated flow, which shows whether the model responds too fast
#' or too slow.
#'
#' @param output A batch output folder.
#' @param rain_min,max_response_h Passed to [find_events()].
#'
#' @return A list of two data frames. `events`: one row per event in every basin with a
#'   candidate, with `basin`, `period` (the window holding the observed peak: `calibration`,
#'   `validation`, `wettest` for a held-back wettest year, or `outside`) and the columns of
#'   [event_scores()]. `basins`: one row per basin, with `response_observed_h`,
#'   `response_simulated_h`, the number of events, and the median absolute peak error and
#'   timing error.
#' @seealso [find_events()], [event_scores()], [batch_results()]
#' @export
batch_events <- function(output, rain_min = NULL, max_response_h = 150) {
  results <- batch_results(output)
  results <- results[!is.na(results$candidate), ]
  .check(nrow(results) > 0, "No basin in this batch has a candidate yet")
  per_basin <- lapply(results$project, function(id) {
    .basin_events(file.path(output, id), id, rain_min, max_response_h)
  })
  list(events = do.call(rbind, lapply(per_basin, `[[`, "events")),
       basins = do.call(rbind, lapply(per_basin, `[[`, "basin")))
}

# The events of one project, scored on its candidate, with its observed and simulated
# response times.
.basin_events <- function(path, id, rain_min, max_response_h, configuration = NULL) {
  entries <- .read_entries(path)
  registration <- .registration(entries)
  card <- registration$scorecard
  data <- .load_registration(path, registration)
  configuration <- configuration %||% read_entry(path, read_projects(path)$candidate)$configuration
  run <- .run_registered(path, .project_info(entries), registration, configuration, data = data)
  model <- pdm_from_config(configuration)
  rain <- data$forcing$rain
  events <- find_events(rain, data$observed, run$time, model@dt, rain_min, max_response_h,
                        model@area_km2)
  scored <- event_scores(events, run$simulated, data$observed)
  held <- .held_rows(card)
  period <- ifelse(scored$peak_row %in% held, "wettest",
                   ifelse(scored$peak_row %in% .scored_rows(card, "calibration"), "calibration",
                          ifelse(!is.null(card$validation) &
                                   scored$peak_row %in% .scored_rows(card, "validation"),
                                 "validation", "outside")))
  simulated_response <- suppressWarnings(response_time_dmca(rain, run$simulated, model@dt,
                                                            max_response_h))
  list(
    events = data.frame(basin = id, period = period, as.data.frame(scored)),
    basin = data.frame(
      basin = id, response_observed_h = attr(events, "response")$response_h,
      response_simulated_h = simulated_response$response_h, events = nrow(scored),
      median_abs_peak_error = stats::median(abs(scored$peak_error), na.rm = TRUE),
      median_abs_timing_error_h = stats::median(abs(scored$timing_error_h), na.rm = TRUE)
    )
  )
}
