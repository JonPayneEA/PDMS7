# Tests for event_states() and run_events(): events rerun on their own from saved states.

states_data <- function() {
  set.seed(31)
  n <- 24 * 200
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.05, stats::rgamma(n, 0.7, scale = 5), 0),
                        pet = 0.05)
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 20
  cfg$surface$k1 <- 4
  cfg$surface$k2 <- 6
  model <- pdm_from_config(cfg)
  start <- initial_state_from_flow(model, 0.2, 0.7)
  flow <- run_pdm(model, forcing, start)$output$q_m3s
  list(forcing = forcing, cfg = cfg, model = model, start = start, flow = flow,
       events = find_events(forcing$rain, flow, dt = 1))
}

# Guards: with the same model, event reruns reproduce the full run exactly
test_that("run_events reproduces the full run with the saved model", {
  d <- states_data()
  saved <- event_states(d$model, d$forcing, d$events, d$start)
  expect_length(saved$states, nrow(d$events))
  expect_true(all(saved$first <= pmin(d$events$rain_start, d$events$flow_start)))
  expect_true(all(saved$last >= d$events$flow_end))
  runs <- run_events(d$model, d$forcing, saved)
  for (r in runs) expect_equal(r$q_m3s, d$flow[r$rows], tolerance = 1e-12)
})

# Guards: after the fast parameters change, a long enough lead-in matches a full run
test_that("a lead-in absorbs a change of the surface stores and time delay", {
  d <- states_data()
  saved <- event_states(d$model, d$forcing, d$events, d$start, lead_h = 150)
  changed <- d$cfg
  changed$surface$k1 <- 10
  changed$surface$k2 <- 15
  changed$td <- 3
  model <- pdm_from_config(changed)
  full <- run_pdm(model, d$forcing, initial_state_from_flow(model, 0.2, 0.7))$output$q_m3s
  big <- order(-d$events$peak_flow)[1:10]
  runs <- run_events(model, d$forcing, saved, big)
  for (j in seq_along(big)) {
    e <- d$events[big[j], ]
    window <- seq.int(e$flow_start, e$flow_end)
    sim <- runs[[j]]$q_m3s[match(window, runs[[j]]$rows)]
    expect_lt(abs(max(sim) / max(full[window]) - 1), 0.01)
  }
})

# Guards: a short lead-in warns, and a changed slow parameter is refused
test_that("run_events warns on a short lead-in and refuses slow changes", {
  d <- states_data()
  saved <- event_states(d$model, d$forcing, d$events, d$start, lead_h = 24)
  slower <- d$cfg
  slower$surface$k1 <- 12
  slower$surface$k2 <- 24
  expect_warning(run_events(pdm_from_config(slower), d$forcing, saved, 1), "lead-in")
  soil <- d$cfg
  soil$distribution$cmax <- 200
  expect_error(run_events(pdm_from_config(soil), d$forcing, saved, 1), "distribution")
  expect_error(run_events(d$model, d$forcing, saved, 0), "which")
})

# Guards: resizing the delay queues keeps every drop of water
test_that("adapting a state to a new time delay keeps its water", {
  d <- states_data()
  delayed <- d$cfg
  delayed$td <- 4
  long_model <- pdm_from_config(delayed)
  state <- initial_state_from_flow(long_model, 0.2, 0.7)
  short <- .adapt_state(state, d$model)
  expect_length(short@delay_surface, 1L)
  expect_equal(sum(short@delay_surface), sum(state@delay_surface))
  back <- .adapt_state(short, long_model)
  expect_length(back@delay_surface, length(state@delay_surface))
  expect_equal(sum(back@delay_surface), sum(state@delay_surface))
})
