# ============================================================ #
# Tool:         thresholds
# Description:  Threshold-crossing verification: events, contingency scores, timing errors
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add threshold scores
# Tier:         3
# Inputs:       Aligned simulated and observed discharge (m3/s); thresholds as flows (m3/s)
# Outputs:      data.table of scores, one row per threshold
# Dependencies: data.table; stats
# ============================================================ #

.event_metrics <- c(
  "pod", "far", "csi", "bias", "observed_events", "simulated_events", "hits", "misses",
  "false_alarms", "crossing_error_h", "abs_crossing_error_h", "peak_timing_error_h",
  "peak_error", "duration_error_h", "volume_error"
)
.step_metrics <- c("pod_step", "far_step", "csi_step", "bias_step", "pofd_step", "ets_step",
                   "pss_step")
.threshold_headlines <- c(pod = "higher", far = "lower", csi = "higher", pod_step = "higher",
                          far_step = "lower", csi_step = "higher", ets_step = "higher",
                          pss_step = "higher")

#' Score threshold crossings
#'
#' Verifies a simulation against observed flow at one or more thresholds, such as flood
#' alert and flood warning flows, as a forecaster would: did the model cross the threshold
#' when the river did, and how far out was it?
#'
#' **Events.** An event is an episode above the threshold. Exceedances separated by less
#' than `gap_h` are merged, so flow flickering about the threshold is one event, and events
#' shorter than `min_duration_h` are ignored. A simulated event whose first crossing lies
#' within `tolerance_h` of an observed event's crossing is a hit; pairs are matched one to
#' one, closest first, with ties going to the earlier observed event. Unmatched observed
#' events are misses and unmatched simulated events
#' false alarms. Missing observations count as below the threshold.
#'
#' | Score | Meaning | Best |
#' |---|---|---|
#' | `pod` | Probability of detection: hits / observed events | 1 |
#' | `far` | False alarm ratio: false alarms / simulated events | 0 |
#' | `csi` | Critical success index: hits / (hits + misses + false alarms) | 1 |
#' | `bias` | Frequency bias: simulated events / observed events | 1 |
#' | `crossing_error_h` | Mean crossing time error over hits, simulated minus observed | 0 |
#' | `abs_crossing_error_h` | Mean absolute crossing time error | 0 |
#' | `peak_timing_error_h` | Mean simulated minus observed time of each event's peak | 0 |
#' | `peak_error` | Mean relative error of each event's peak flow | 0 |
#' | `duration_error_h` | Mean simulated minus observed time above the threshold | 0 |
#' | `volume_error` | Relative error of the total volume above the threshold over hits | 0 |
#'
#' Crossing and peak timing errors are positive when the simulation is late. Event scores
#' need no correct negatives, which events do not define. **Steps**: the same
#' contingency is also counted step by step (`pod_step`, `far_step`, `csi_step`,
#' `bias_step`) with the scores that need correct negatives: probability of false detection
#' (`pofd_step`), equitable threat score (`ets_step`) and Peirce skill score (`pss_step`).
#'
#' Scores with an empty denominator, such as POD when nothing was observed above the
#' threshold, are `NA`.
#'
#' @param simulated,observed Aligned discharge vectors, m3/s.
#' @param thresholds Named numeric vector of threshold flows, m3/s.
#' @param dt_hours Time step, hours.
#' @param tolerance_h,gap_h,min_duration_h Matching tolerance, minimum gap between separate
#'   events, and minimum event duration, hours.
#' @return A data.table with one row per threshold: `threshold`, `flow_m3s`, then the scores.
#' @references Jolliffe and Stephenson (2012), Forecast Verification, 2nd edition, Wiley.
#' @examples
#' obs <- c(1, 2, 6, 8, 5, 2, 1, 1, 3, 7, 4, 1)
#' sim <- c(1, 1, 3, 7, 9, 4, 2, 1, 1, 2, 2, 1)
#' pdm_threshold_scores(sim, obs, c(alert = 4, warning = 7.5), tolerance_h = 1, gap_h = 1)
#' @export
pdm_threshold_scores <- function(simulated, observed, thresholds, dt_hours = 1,
                                 tolerance_h = 6, gap_h = 24, min_duration_h = 0) {
  .check(is.numeric(observed) && is.numeric(simulated) &&
           length(observed) == length(simulated), "Flow vectors must have equal length")
  .check(all(is.finite(simulated)), "Simulated flow must be finite")
  .check(.valid_thresholds(thresholds), "thresholds must be a named vector of positive flows")
  .check(.scalar(dt_hours, 0, strict = TRUE), "dt_hours must be positive")
  for (v in list(tolerance_h, gap_h, min_duration_h)) {
    .check(.scalar(v, 0), "Event settings must be nonnegative hours")
  }
  settings <- list(dt = dt_hours, tolerance = tolerance_h / dt_hours, gap = gap_h / dt_hours,
                   min_duration = min_duration_h / dt_hours)
  rows <- lapply(names(thresholds), function(name) {
    scores <- .threshold_row(simulated, observed, thresholds[[name]], settings)
    cbind(data.table::data.table(threshold = name, flow_m3s = thresholds[[name]]),
          data.table::as.data.table(as.list(scores)))
  })
  data.table::rbindlist(rows)
}

.valid_thresholds <- function(x) {
  if (!is.numeric(x) || !length(x) || is.null(names(x))) return(FALSE)
  all(nzchar(names(x)), !duplicated(names(x)), is.finite(x), x > 0)
}

.ratio <- function(a, b) if (b > 0) a / b else NA_real_

.threshold_row <- function(sim, obs, flow, s) {
  obs_above <- !is.na(obs) & obs > flow
  sim_above <- sim > flow
  obs_events <- .find_events(obs_above, s$gap, s$min_duration)
  sim_events <- .find_events(sim_above, s$gap, s$min_duration)
  pairs <- .match_events(obs_events, sim_events, s$tolerance)
  hits <- nrow(pairs)
  misses <- nrow(obs_events) - hits
  false_alarms <- nrow(sim_events) - hits
  c(
    pod = .ratio(hits, hits + misses), far = .ratio(false_alarms, hits + false_alarms),
    csi = .ratio(hits, hits + misses + false_alarms),
    bias = .ratio(hits + false_alarms, hits + misses),
    observed_events = nrow(obs_events), simulated_events = nrow(sim_events), hits = hits,
    misses = misses, false_alarms = false_alarms,
    .hit_errors(pairs, obs_events, sim_events, sim, obs, flow, s$dt),
    .step_scores(sim_above[!is.na(obs)], obs_above[!is.na(obs)])
  )
}

# Episodes above the threshold as rows of first and last index, merged across short gaps.
.find_events <- function(above, gap, min_duration) {
  empty <- data.frame(start = integer(0), end = integer(0))
  if (!any(above)) return(empty)
  runs <- rle(above)
  ends <- cumsum(runs$lengths)
  starts <- ends - runs$lengths + 1L
  start <- starts[runs$values]
  end <- ends[runs$values]
  keep <- 1L
  if (length(start) > 1L) {
    for (i in 2:length(start)) {
      last <- keep[length(keep)]
      if (start[i] - end[last] - 1L < gap) end[last] <- end[i] else keep <- c(keep, i)
    }
  }
  out <- data.frame(start = start[keep], end = end[keep])
  out[out$end - out$start + 1L >= min_duration, , drop = FALSE]
}

# One-to-one matching on crossing time, closest pairs first.
.match_events <- function(obs_events, sim_events, tolerance) {
  pairs <- data.frame(obs = integer(0), sim = integer(0))
  if (!nrow(obs_events) || !nrow(sim_events)) return(pairs)
  grid <- expand.grid(obs = seq_len(nrow(obs_events)), sim = seq_len(nrow(sim_events)))
  grid$gap <- abs(sim_events$start[grid$sim] - obs_events$start[grid$obs])
  grid <- grid[grid$gap <= tolerance, , drop = FALSE]
  grid <- grid[order(grid$gap, grid$obs), , drop = FALSE]
  used_obs <- integer(0)
  used_sim <- integer(0)
  for (k in seq_len(nrow(grid))) {
    if (!grid$obs[k] %in% used_obs && !grid$sim[k] %in% used_sim) {
      used_obs <- c(used_obs, grid$obs[k])
      used_sim <- c(used_sim, grid$sim[k])
    }
  }
  data.frame(obs = used_obs, sim = used_sim)
}

.hit_errors <- function(pairs, obs_events, sim_events, sim, obs, flow, dt) {
  none <- c(crossing_error_h = NA_real_, abs_crossing_error_h = NA_real_,
            peak_timing_error_h = NA_real_, peak_error = NA_real_, duration_error_h = NA_real_,
            volume_error = NA_real_)
  if (!nrow(pairs)) return(none)
  o <- obs_events[pairs$obs, , drop = FALSE]
  s <- sim_events[pairs$sim, , drop = FALSE]
  peak_at <- function(x, ev) {
    vapply(seq_len(nrow(ev)), function(i) {
      idx <- ev$start[i]:ev$end[i]
      idx[which.max(replace(x[idx], is.na(x[idx]), -Inf))]
    }, integer(1))
  }
  excess <- function(x, ev) {
    sum(vapply(seq_len(nrow(ev)), function(i) {
      sum(pmax(x[ev$start[i]:ev$end[i]] - flow, 0), na.rm = TRUE)
    }, numeric(1)))
  }
  crossing <- (s$start - o$start) * dt
  obs_peak <- peak_at(obs, o)
  sim_peak <- peak_at(sim, s)
  c(crossing_error_h = mean(crossing), abs_crossing_error_h = mean(abs(crossing)),
    peak_timing_error_h = mean((sim_peak - obs_peak) * dt),
    peak_error = mean(sim[sim_peak] / obs[obs_peak] - 1),
    duration_error_h = mean(((s$end - s$start) - (o$end - o$start)) * dt),
    volume_error = .ratio(excess(sim, s), excess(obs, o)) - 1)
}

.step_scores <- function(sim_above, obs_above) {
  a <- sum(sim_above & obs_above)
  b <- sum(sim_above & !obs_above)
  c <- sum(!sim_above & obs_above)
  d <- sum(!sim_above & !obs_above)
  n <- a + b + c + d
  random <- if (n > 0) (a + b) * (a + c) / n else NA_real_
  c(pod_step = .ratio(a, a + c), far_step = .ratio(b, a + b), csi_step = .ratio(a, a + b + c),
    bias_step = .ratio(a + b, a + c), pofd_step = .ratio(b, b + d),
    ets_step = .ratio(a - random, a + b + c - random),
    pss_step = .ratio(a, a + c) - .ratio(b, b + d))
}

# ---- Thresholds in the calibration log ---------------------------------------------------

# Accepts a data frame with name, value and unit ("flow" in m3/s or "level" in m).
.resolve_thresholds <- function(thresholds, rating) {
  if (is.null(thresholds)) return(NULL)
  .check(is.data.frame(thresholds) && all(c("name", "value", "unit") %in% names(thresholds)) &&
           nrow(thresholds) > 0,
         "thresholds must be a data frame with name, value and unit (flow or level)")
  names <- trimws(as.character(thresholds$name))
  units <- tolower(trimws(as.character(thresholds$unit)))
  values <- as.numeric(thresholds$value)
  .check(all(nzchar(names)) && !anyDuplicated(names) && !any(grepl(":", names, fixed = TRUE)),
         "Threshold names must be unique, non-empty and contain no colon")
  .check(all(units %in% c("flow", "level")), "Threshold unit must be flow (m3/s) or level (m)")
  .check(all(is.finite(values)), "Threshold values must be finite")
  flows <- values
  if (any(units == "level")) {
    .check(!is.null(rating), "Level thresholds need a rating table (stage_m, q_m3s)")
    flows[units == "level"] <- .level_to_flow(values[units == "level"], rating)
  }
  .check(all(flows > 0), "Threshold flows must be positive")
  lapply(seq_along(names), function(i) {
    list(name = names[i], value = values[i], unit = units[i], flow_m3s = flows[i])
  })
}

.as_rating <- function(rating) {
  if (is.character(rating)) {
    .check(length(rating) == 1L && file.exists(rating), "rating file not found")
    rating <- data.table::fread(rating)
  }
  .check(is.data.frame(rating) && all(c("stage_m", "q_m3s") %in% names(rating)) &&
           nrow(rating) >= 2, "rating needs stage_m and q_m3s columns and two or more rows")
  out <- data.frame(stage_m = as.numeric(rating$stage_m), q_m3s = as.numeric(rating$q_m3s))
  out <- out[order(out$stage_m), ]
  .check(all(is.finite(as.matrix(out))) && all(out$q_m3s > 0) && all(diff(out$stage_m) > 0) &&
           all(diff(out$q_m3s) > 0), "rating must rise strictly, with positive flows")
  out
}

# Linear in stage, logarithmic in flow, between rated points; never extrapolated.
.level_to_flow <- function(levels, rating) {
  inside <- levels >= min(rating$stage_m) & levels <= max(rating$stage_m)
  .check(all(inside), paste0(
    "Level threshold outside the rating (", min(rating$stage_m), " to ", max(rating$stage_m),
    " m); extend the rating rather than extrapolate"
  ))
  exp(stats::approx(rating$stage_m, log(rating$q_m3s), xout = levels)$y)
}

# Threshold scores for one run, flattened as "metric:name" for the run's score list.
.flat_threshold_scores <- function(sim, obs, card, dt_hours) {
  if (!length(card$thresholds)) return(list())
  flows <- stats::setNames(vapply(card$thresholds, function(t) t$flow_m3s, numeric(1)),
                           vapply(card$thresholds, function(t) t$name, character(1)))
  events <- card$events
  table <- pdm_threshold_scores(sim, obs, flows, dt_hours, events$tolerance_h, events$gap_h,
                                events$min_duration_h)
  out <- list()
  for (i in seq_len(nrow(table))) {
    for (m in c(.event_metrics, .step_metrics)) {
      out[[paste0(m, ":", table$threshold[i])]] <- table[[m]][i]
    }
  }
  out
}

.valid_headline <- function(headline, thresholds) {
  if (headline %in% names(.headline_scores())) return(TRUE)
  parts <- strsplit(headline, ":", fixed = TRUE)[[1L]]
  names <- vapply(thresholds, function(t) t$name, character(1))
  length(parts) == 2L && parts[1L] %in% names(.threshold_headlines) && parts[2L] %in% names
}

.headline_direction <- function(headline) {
  base <- .headline_scores()
  if (headline %in% names(base)) return(base[[headline]])
  .threshold_headlines[[strsplit(headline, ":", fixed = TRUE)[[1L]][1L]]]
}
