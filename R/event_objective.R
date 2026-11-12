# ============================================================ #
# Tool:         event_objective
# Description:  The events objective for calibrate_pdm(): pooled event NSE, peak error and
#               timing error over the largest events in the scored period
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-06
# Modified:     2026-11-06 - First version
#               2026-11-10 - One event per flood (find_events(independent = TRUE))
# Tier:         1
# Inputs:       Events from find_events(); rain (mm per step); observed flow (m3/s)
# Outputs:      A scoring function of the simulated flow, and its description
# Dependencies: stats
# ============================================================ #

# The default weights of the three terms of the events objective.
.default_event_weights <- c(nse = 1, peak = 0.5, timing = 0.5)

# Builds the events objective. The events come from find_events() on the observed rain and flow
# (or are given), screened with screen_events() unless `screen` is NULL; given events that
# already carry a `use` column keep it. Only events whose flow window lies wholly after the
# warm-up are scored, and of
# those only the largest share by observed peak, so that small, noisy events do not dominate the
# peak and timing terms. The objective, to be minimised, is
#   w_nse * (1 - pooled event NSE) + w_peak * mean |peak error| + w_timing * mean |timing| / Tr
# where the pooled event NSE sums squared errors over every chosen window and divides by the sum
# of squared deviations from each window's own mean flow; the peak error is the simulated over the
# observed window peak, less one; the timing error is the hours between the two peaks; and Tr is
# the catchment's response time (DMCA), so a peak one response time late costs as much as a peak
# 100% too high, at equal weights. Peak and timing follow event_scores().
.event_objective <- function(events, rain, observed, warmup, dt,
                             weights = .default_event_weights, share = 0.5, screen = list(),
                             area_km2 = NULL) {
  .check(is.numeric(weights) && setequal(names(weights), names(.default_event_weights)) &&
           all(is.finite(weights) & weights >= 0) && sum(weights) > 0,
         "event_weights must be nonnegative numbers named nse, peak and timing, not all zero")
  .check(.scalar(share, 0, 1) && share > 0, "event_share must lie in (0, 1]")
  chosen <- .event_windows(events, rain, observed, warmup, dt, share, screen, area_km2)
  windows <- chosen$windows
  rows <- unlist(windows)
  obs <- observed[rows]
  group <- rep(seq_along(windows), lengths(windows))
  ss_tot <- sum((obs - stats::ave(obs, group))^2)
  .check(ss_tot > 0, "The chosen events have no variation in observed flow")
  obs_peak <- vapply(windows, function(i) max(observed[i]), numeric(1))
  obs_at <- vapply(windows, function(i) i[which.max(observed[i])], numeric(1))
  scale_h <- max(c(chosen$response_h, dt), na.rm = TRUE)
  w <- weights[names(.default_event_weights)]
  score <- function(sim) {
    s <- sim[rows]
    if (!all(is.finite(s))) return(1e+30)
    sim_peak <- vapply(windows, function(i) max(sim[i]), numeric(1))
    sim_at <- vapply(windows, function(i) i[which.max(sim[i])], numeric(1))
    w[["nse"]] * sum((s - obs)^2) / ss_tot +
      w[["peak"]] * mean(abs(sim_peak / obs_peak - 1)) +
      w[["timing"]] * mean(abs(sim_at - obs_at)) * dt / scale_h
  }
  name <- sprintf(paste0(
    "events: %g x (1 - pooled event NSE) + %g x mean |peak error| + %g x mean |timing error| ",
    "/ %.3g h, over the %d largest of %d events%s"
  ), w[["nse"]], w[["peak"]], w[["timing"]], scale_h, length(windows), chosen$found,
  if (chosen$screened_out) sprintf(" (%d screened out)", chosen$screened_out) else "")
  list(score = score, name = name, events = length(windows), found = chosen$found,
       response_h = scale_h)
}

# The rows of the events the objective scores: found (unless given) and screened (unless the
# screen is NULL or the events carry a use column), wholly after the warm-up, with at least two
# observed flows, and of those the largest share by observed peak.
.event_windows <- function(events, rain, observed, warmup, dt, share, screen, area_km2) {
  if (is.null(events)) {
    .check(!is.null(rain), "The events objective needs rain in forcing, or events")
    # One event per flood: fragments of a long flood would otherwise each count as an event,
    # and the largest share would fit one flood many times over.
    events <- find_events(rain, observed, dt = dt, area_km2 = area_km2, independent = TRUE)
  }
  .check(is.data.frame(events) && all(c("flow_start", "flow_end") %in% names(events)),
         "events must come from find_events()")
  .check(is.null(screen) || is.list(screen), "event_screen must be a list of settings, or NULL")
  if (!is.null(screen) && !"use" %in% names(events)) {
    events <- do.call(screen_events, c(list(events, observed), screen))
  }
  use <- if ("use" %in% names(events)) events$use else rep(TRUE, nrow(events))
  usable <- use & events$flow_start > warmup & events$flow_end <= length(observed)
  windows <- lapply(which(usable), function(e) {
    i <- seq.int(events$flow_start[e], events$flow_end[e])
    i[is.finite(observed[i])]
  })
  windows <- windows[lengths(windows) >= 2L]
  .check(length(windows) > 0, paste(
    "No event lies wholly in the scored period with at least two observed flows; the events",
    "objective has nothing to score"
  ))
  peaks <- vapply(windows, function(i) max(observed[i]), numeric(1))
  chosen <- order(-peaks)[seq_len(max(1L, ceiling(share * length(windows))))]
  list(windows = windows[chosen], found = length(windows), screened_out = sum(!use),
       response_h = attr(events, "response")$response_h %||% NA_real_)
}
