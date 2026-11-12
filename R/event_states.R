# ============================================================ #
# Tool:         event_states
# Description:  Model states saved just before each event, so that events can be rerun on
#               their own, in a fraction of the time of the whole record
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         1
# Inputs:       A model; forcing (mm per step); events from find_events(); a starting state
# Outputs:      Saved states and event windows; simulated flow per event
# Dependencies: none
# ============================================================ #

#' Rerun events on their own, from saved states
#'
#' Looking at how a model handles the largest events, while changing its parameters, needs
#' each change to show at once. Rerunning a 15-minute record of sixteen years takes seconds; the
#' events in it are a small part of the record. `event_states()` runs the record once and saves
#' the model's state at the start of each event's window. `run_events()` then runs only the
#' windows, from those states.
#'
#' **Same parameters, same answer.** With the model the states were saved from, `run_events()`
#' reproduces the full run exactly.
#'
#' **Changed fast parameters: a lead-in.** A saved state belongs to the parameters it was saved
#' with. When the surface stores or the time delay change, the surface store and delay queues at
#' the event's start would be those of the old parameters. So each window starts `lead_h` hours
#' before its event, and the fast stores settle to the new parameters before the rain arrives.
#' A lead-in five times the sum of the surface time constants is enough: on a 15-minute record,
#' slowing the stores from 6 and 10 hours to 12 and 24 hours left peaks 15% out after a 24-hour
#' lead-in, 2% after 72 hours and 0.02% after 180 hours. `run_events()` warns when the lead-in is
#' shorter than that. Save with a lead-in long enough for the slowest stores you will try. A
#' time delay that changes the length of the delay queues has its queues resized, with any water
#' past the new end added to the last place.
#'
#' **Changed slow parameters: save again.** The soil and groundwater stores are kept from the
#' saved run, and they depend on every other parameter: changing `b` or `cmax` moved event
#' peaks by 50 to 130% in the same test, however long the lead-in. `run_events()` therefore
#' refuses a model that differs from the saved one in anything but the surface stores and the
#' time delay.
#'
#' The default lead-in is three response times of the catchment, and at least a day.
#'
#' @param model A model from [pdm_model()] or [pdm_from_config()].
#' @param forcing Forcing as for [run_pdm()].
#' @param events Events from [find_events()] on the same record.
#' @param state Starting state of the full run; by default [initial_state()].
#' @param lead_h Hours before each event (the earlier of its rain and flow starts) at which its
#'   window starts.
#' @param tail_h Hours after each event's flow window that its window runs on.
#' @param saved Saved states from `event_states()`.
#' @param which Events to run, by row of `events`; all by default.
#'
#' @return `event_states()`: a list with `first` and `last` (each window's first and last row
#'   of the record), `states` (the state before each window's first row), `lead_h`, `tail_h`,
#'   `events` and the `model` the states were saved from. `run_events()`: a list with one
#'   element per event run, each a list of
#'   `rows` (rows of the record) and `q_m3s` (simulated flow on those rows).
#' @examples
#' set.seed(4)
#' n <- 24 * 120
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.05, rgamma(n, 0.7, scale = 5), 0),
#'                       pet = 0.05)
#' model <- pdm_model(area_km2 = 20)
#' flow <- run_pdm(model, forcing)$output$q_m3s
#' events <- find_events(forcing$rain, flow, dt = 1)
#' saved <- event_states(model, forcing, events)
#' faster <- pdm_model(area_km2 = 20, surface = FlodeCascadeRouting(k1 = 1, k2 = 2))
#' reruns <- run_events(faster, forcing, saved, which = 1:3)
#' lengths(lapply(reruns, `[[`, "q_m3s"))
#' @seealso [find_events()], [event_scores()]
#' @export
event_states <- function(model, forcing, events, state = NULL, lead_h = NULL, tail_h = 12) {
  .check(S7::S7_inherits(model, FlodePdmModel), "model must be a FlodePdmModel")
  .check(is.data.frame(events) && all(c("rain_start", "flow_start", "flow_end") %in%
                                        names(events)), "events must come from find_events()")
  n <- nrow(forcing)
  .check(!nrow(events) || max(events$flow_end) <= n, "events run past the end of the forcing")
  response_h <- attr(events, "response")$response_h %||% NA_real_
  lead_h <- lead_h %||% max(24, 3 * response_h, na.rm = TRUE)
  .check(.scalar(lead_h, 0), "lead_h must be a nonnegative number of hours")
  .check(.scalar(tail_h, 0), "tail_h must be a nonnegative number of hours")
  dt <- model@dt
  first <- pmax(1L, pmin(events$rain_start, events$flow_start) - as.integer(ceiling(lead_h / dt)))
  last <- pmin(n, events$flow_end + as.integer(ceiling(tail_h / dt)))
  current <- state %||% initial_state(model)
  states <- vector("list", nrow(events))
  # One pass through the record, stopping at each window's first row in turn to save the state.
  # Windows may overlap, so the stops are taken in order of first row.
  done <- 0L
  for (e in order(first)) {
    if (first[e] - 1L > done) {
      rows <- seq.int(done + 1L, first[e] - 1L)
      current <- .quietly(run_pdm(model, forcing[rows, , drop = FALSE], current))$state
      done <- first[e] - 1L
    }
    states[[e]] <- current
  }
  list(first = first, last = last, states = states, lead_h = lead_h, tail_h = tail_h,
       events = events, model = model)
}

#' @rdname event_states
#' @export
run_events <- function(model, forcing, saved, which = NULL) {
  .check(is.list(saved) && all(c("first", "last", "states") %in% names(saved)),
         "saved must come from event_states()")
  .check(S7::S7_inherits(model, FlodePdmModel), "model must be a FlodePdmModel")
  .check_same_slow(model, saved$model)
  needed <- 5 * .surface_time_h(model)
  moved <- !identical(model@surface, saved$model@surface) || model@td != saved$model@td
  if (moved && is.finite(needed) && needed > saved$lead_h) {
    warning(sprintf(paste0(
      "The surface stores need a lead-in of about %.0f h to settle, longer than the %.0f h ",
      "saved; event peaks may be several percent out. Save the states with a longer lead_h"
    ), needed, saved$lead_h), call. = FALSE)
  }
  which <- which %||% seq_along(saved$first)
  .check(is.numeric(which) && all(which %in% seq_along(saved$first)),
         "which must name events by row")
  lapply(which, function(e) {
    rows <- seq.int(saved$first[e], saved$last[e])
    state <- .adapt_state(saved$states[[e]], model)
    out <- .quietly(run_pdm(model, forcing[rows, , drop = FALSE], state))$output
    list(rows = rows, q_m3s = out$q_m3s)
  })
}

# Refuses a model that differs from the saved one in anything but the surface stores and the
# time delay, whose effects a lead-in can absorb.
.check_same_slow <- function(model, saved) {
  if (is.null(saved)) return(invisible(TRUE))
  slow <- c("distribution", "recharge", "groundwater", "be", "fc", "qc", "area_km2", "dt")
  changed <- slow[!vapply(slow, function(p) {
    identical(S7::prop(model, p), S7::prop(saved, p))
  }, logical(1))]
  .check(!length(changed), paste0(
    "The saved states belong to a model with other ", toString(changed), "; only the surface ",
    "stores and the time delay may change. Save the states again with event_states()"
  ))
}

# The sum of the surface stores' time constants, hours; NA for a store without them.
.surface_time_h <- function(model) {
  s <- model@surface
  names <- intersect(c("k", "k1", "k2"), S7::prop_names(s))
  if (!length(names)) return(NA_real_)
  sum(vapply(names, function(p) S7::prop(s, p), numeric(1)))
}

# A saved state made fit for a model with other parameters: the soil store capped at the new
# capacity, and the delay queues resized to the new time delay (water past a shortened queue's
# end is added to its last place, so none is lost). The stores' shapes must match.
.adapt_state <- function(state, model) {
  n <- floor(model@td / model@dt) + 1L
  resize <- function(v) {
    if (length(v) == n) return(v)
    if (length(v) < n) return(c(v, rep(0, n - length(v))))
    out <- v[seq_len(n)]
    out[n] <- out[n] + sum(v[-seq_len(n)])
    out
  }
  adapted <- FlodePdmState(
    soil = min(state@soil, capacity_mean(model@distribution)),
    surface = state@surface, groundwater = state@groundwater,
    delay_surface = resize(state@delay_surface),
    delay_groundwater = resize(state@delay_groundwater),
    delay_surface_end = resize(state@delay_surface_end),
    delay_groundwater_end = resize(state@delay_groundwater_end),
    step = state@step
  )
  .validate_state(model, adapted)
  adapted
}
