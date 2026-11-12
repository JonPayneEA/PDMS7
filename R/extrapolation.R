# ============================================================ #
# Tool:         extrapolation
# Description:  Checks of how a calibration extrapolates: the wettest water years held back
#               from calibration, flows above the highest gauged flow, and the spread of
#               equally good parameter sets on the held-back years
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-02
# Modified:     2026-11-02 - Add wettest-year hold-out, rating flag and equally good sets
# Tier:         1
# Inputs:       Times, observed flow (m3/s), a registered scorecard
# Outputs:      Held-back years, scoring masks, rating flags, thinned parameter sets
# Dependencies: none beyond base R
# ============================================================ #

# The UK water year runs from 1 October to 30 September: October 2012 to September 2013 is
# "2012-13".
.water_year <- function(time) {
  lt <- as.POSIXlt(time, tz = "UTC")
  first <- lt$year + 1900L - (lt$mon < 9L)
  sprintf("%d-%02d", first, (first + 1L) %% 100L)
}

#' Wettest water years
#'
#' Ranks the water years (1 October to 30 September) of a record by their highest observed
#' flow and marks the `n` largest. A calibration project holds these years back: they are left
#' out of calibration and validation scoring and scored once, with the test, so the record
#' shows how the calibration does on floods larger than those it was fitted to. This is
#' Klemes's (1986) differential split-sample test.
#'
#' The ranking holds even where the rating is extrapolated: a rating rises with stage, so it
#' keeps the order of floods even when it gets their size wrong.
#'
#' A year counts only if its rows within `rows` hold at least half a year of observed flow,
#' so a sliver of a year at the edge of a window cannot be held back or count towards those
#' left.
#'
#' @param time Times of the record (POSIXct or ISO 8601 text, UTC), regularly spaced.
#' @param observed Observed flow, m3/s, aligned with `time`.
#' @param n Number of years to hold back.
#' @param rows Rows to consider, by default the whole record.
#' @param min_left Fewest counted years that must remain once `n` are held back.
#'
#' @return A data frame with one row per counted year, wettest first: `water_year`,
#'   `first_row`, `last_row` (within `rows`), `start`, `end`, `peak_m3s` and `held`.
#' @references Klemes, V. (1986) Operational testing of hydrological simulation models.
#'   Hydrological Sciences Journal 31(1), 13-24.
#' @examples
#' time <- seq(as.POSIXct("2010-10-01", tz = "UTC"), by = 86400, length.out = 5 * 365)
#' set.seed(1)
#' flow <- rgamma(length(time), 2)
#' flow[400] <- 60
#' wettest_years(time, flow, n = 1)
#' @export
wettest_years <- function(time, observed, n = 2, rows = seq_along(observed), min_left = 3) {
  time <- if (inherits(time, "POSIXt")) as.POSIXct(time, tz = "UTC") else .parse_time(time)
  .check(length(time) == length(observed), "time and observed must have equal length")
  .check(.scalar(n, 0) && n == floor(n), "n must be a whole number of years, 0 or more")
  .check(length(time) > 1L, "wettest_years needs at least two times")
  step_h <- as.numeric(time[2L] - time[1L], units = "hours")
  rows <- sort(unique(as.integer(rows)))
  year <- .water_year(time[rows])
  # One row per water year: its span within rows, how much of it is observed, and its peak.
  table <- do.call(rbind, lapply(split(rows, year), function(r) {
    q <- observed[r]
    seen <- sum(is.finite(q))
    data.frame(water_year = .water_year(time[r[1L]]), first_row = min(r), last_row = max(r),
               start = .format_time(time[min(r)]), end = .format_time(time[max(r)]),
               peak_m3s = if (seen) max(q, na.rm = TRUE) else NA_real_,
               observed_h = seen * step_h)
  }))
  table <- table[table$observed_h >= 0.5 * 8766, setdiff(names(table), "observed_h")]
  .check(nrow(table) >= n + min_left, paste0(
    "Only ", nrow(table), " water years have at least half a year of observed flow; holding ",
    "back ", n, " would leave fewer than ", min_left, ". Hold back fewer years, or none with 0"
  ))
  table <- table[order(-table$peak_m3s), ]
  table$held <- seq_len(nrow(table)) <= n
  rownames(table) <- NULL
  table
}

# The held-back years of a scorecard, as entries record them: label, rows, times and peak.
.held_years <- function(card) card$wettest$years %||% list()

# Every row a scorecard holds back, limited to the calibration and validation windows they were
# chosen from. Empty for projects without held years, including those registered before 0.5.0.
.held_rows <- function(card) {
  years <- .held_years(card)
  if (!length(years)) return(integer(0))
  windows <- unlist(lapply(card[c("calibration", "validation")], function(w) {
    if (is.null(w)) integer(0) else .window_rows(w)
  }))
  rows <- unlist(lapply(years, function(y) seq.int(y$first_row, y$last_row)))
  sort(intersect(rows, windows))
}

# The rows a window scores: its own rows less any held-back year; for "wettest", the held rows.
.scored_rows <- function(card, window) {
  if (identical(window, "wettest")) return(.held_rows(card))
  setdiff(.window_rows(card[[window]]), .held_rows(card))
}

# Observed flow with everything blank except the rows a window scores, for calibrate_pdm(),
# which leaves blank rows out of its objective.
.scoring_observed <- function(observed, card, window) {
  out <- rep(NA_real_, length(observed))
  rows <- .scored_rows(card, window)
  out[rows] <- observed[rows]
  out
}

# The held years for a registration, or NULL when none are held back.
.choose_wettest <- function(n, forcing, observed, cal, val) {
  if (n == 0) return(NULL)
  .check("time" %in% names(forcing), paste(
    "Holding back the wettest years needs a time column in forcing; set wettest_years = 0",
    "to register without it"
  ))
  rows <- unlist(lapply(list(cal, val), function(w) if (!is.null(w)) .window_rows(w)))
  table <- wettest_years(forcing$time, observed, n, rows)
  held <- table[table$held, setdiff(names(table), "held")]
  years <- lapply(seq_len(nrow(held)), function(i) as.list(held[i, ]))
  card <- list(calibration = cal, validation = val, wettest = list(n = n, years = years))
  for (w in Filter(function(w) !is.null(card[[w]]), c("calibration", "validation"))) {
    .check(sum(is.finite(observed[.scored_rows(card, w)])) >= 2, paste(
      "Holding back the wettest years leaves the", w, "window with fewer than two observed",
      "values; lengthen it or hold back fewer years"
    ))
  }
  list(n = as.integer(n), years = years)
}

# Flows above the highest gauged flow, window by window: how many observed steps, what share,
# and the window's highest flow. Above that flow the rating is extrapolated, so the size of the
# observed flow is uncertain even though its order is not.
.rating_check <- function(limit, observed, card) {
  if (is.null(limit)) return(NULL)
  windows <- Filter(function(w) length(.window_or_held(card, w)),
                    c("calibration", "validation", "test", "wettest"))
  out <- lapply(windows, function(w) {
    q <- observed[.window_or_held(card, w)]
    q <- q[is.finite(q)]
    list(steps_above = sum(q > limit), share_above = if (length(q)) mean(q > limit) else NA,
         highest_m3s = if (length(q)) max(q) else NA)
  })
  list(highest_gauged_m3s = limit, windows = stats::setNames(out, windows))
}

# The rows a window covers for the rating check; a window not registered covers none.
.window_or_held <- function(card, w) {
  if (identical(w, "wettest")) return(.held_rows(card))
  if (is.null(card[[w]])) integer(0) else .scored_rows(card, w)
}

# The headline score of one simulation over the given rows, as the scorecard defines it.
.headline_score <- function(sim, obs, card, dt) {
  name <- card$headline
  scores <- if (grepl(":", name, fixed = TRUE)) {
    .flat_threshold_scores(sim, obs, card, dt)
  } else {
    pdm_scorecard(sim, obs, card$log_offset)
  }
  .num_or_na(scores[[name]])
}

# Parameter sets the search found that score within tolerance of its best, thinned to at most
# max_sets that are spread out: starting from the best, each next set is the one farthest (in
# the search's unit box) from those already chosen. Near-duplicates, such as the finite-difference
# steps of L-BFGS-B, are dropped. Returns NULL when the search recorded no trials.
.equally_good <- function(trials, unit, direction, tolerance, max_sets = 50L) {
  if (is.null(trials) || !nrow(trials)) return(NULL)
  score <- trials$score
  ok <- is.finite(score)
  if (!any(ok)) return(NULL)
  sign <- if (direction == "higher") 1 else -1
  best <- max(sign * score[ok])
  within <- which(ok & sign * score >= best - tolerance)
  within <- within[order(-sign * score[within])]
  u <- unit[within, , drop = FALSE]
  chosen <- 1L
  far <- sqrt(rowSums((u - matrix(u[1L, ], nrow(u), ncol(u), byrow = TRUE))^2))
  while (length(chosen) < max_sets) {
    nxt <- which.max(far)
    if (far[nxt] < 1e-3) break
    chosen <- c(chosen, nxt)
    far <- pmin(far, sqrt(rowSums((u - matrix(u[nxt, ], nrow(u), ncol(u), byrow = TRUE))^2)))
  }
  rows <- within[chosen]
  values <- trials[rows, setdiff(names(trials), "score"), with = FALSE]
  list(
    tolerance = tolerance, within = length(within),
    sets = lapply(seq_along(rows), function(i) {
      list(score = score[rows[i]], parameters = as.list(values[i, ]))
    })
  )
}

# Peaks of each held year: observed, the candidate's, and the range across the equally good
# sets of the calibration the candidate came from. Each year is flagged when its observed peak
# lies above the highest gauged flow.
.score_wettest <- function(info, registration, candidate, entries, data) {
  card <- registration$scorecard
  run <- .run_registered(NULL, info, registration, candidate$configuration, "wettest", data)
  source <- .find_entry(entries, candidate$entry)
  sets <- source$equally_good$sets %||% list()
  held <- .held_rows(card)
  span <- function(y) intersect(seq.int(y$first_row, y$last_row), held)
  peak <- function(sim, y) max(sim[span(y)])
  set_peaks <- lapply(sets, function(s) {
    cfg <- candidate$configuration
    for (p in names(s$parameters)) cfg <- .path_set(cfg, p, s$parameters[[p]])
    sim <- .run_registered(NULL, info, registration, cfg, "wettest", data)$simulated
    vapply(.held_years(card), function(y) peak(sim, y), numeric(1))
  })
  limit <- card$highest_gauged_m3s
  years <- lapply(seq_along(.held_years(card)), function(i) {
    y <- .held_years(card)[[i]]
    obs <- max(data$observed[span(y)], na.rm = TRUE)
    sim <- peak(run$simulated, y)
    spread <- range(c(sim, vapply(set_peaks, function(p) p[i], numeric(1))))
    list(water_year = y$water_year, observed_peak_m3s = obs, simulated_peak_m3s = sim,
         spread_low_m3s = spread[1L], spread_high_m3s = spread[2L],
         above_gauged = if (is.null(limit)) NULL else obs > limit)
  })
  list(scores = run$scores, sets = length(sets), tolerance = source$equally_good$tolerance,
       years = years, run = run)
}
