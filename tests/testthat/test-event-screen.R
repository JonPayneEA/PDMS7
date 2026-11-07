# Tests for screen_events() and its use in the events objective and the acceptance checks.

screen_data <- function(base = 0, n = 24 * 150) {
  set.seed(21)
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.05, stats::rgamma(n, 0.7, scale = 5), 0),
                        pet = 0.05)
  model <- pdm_model(area_km2 = 20)
  flow <- run_pdm(model, forcing)$output$q_m3s + base
  list(forcing = forcing, flow = flow,
       events = find_events(forcing$rain, flow, dt = 1, area_km2 = 20))
}

# Guards: a high, steady baseflow makes rises small relative to it, and the screen catches that
test_that("small rises over a high baseflow are screened out", {
  low <- screen_data()
  high <- screen_data(base = 20)
  a <- screen_events(low$events, low$flow, min_rise = 0.2)
  b <- screen_events(high$events, high$flow, min_rise = 0.2)
  expect_true(all(c("rise_ratio", "flags", "use") %in% names(b)))
  expect_gt(mean(grepl("small_rise", b$flags)), mean(grepl("small_rise", a$flags)))
  expect_true(all(!b$use[grepl("small_rise", b$flags)]))
  # The rise is measured above the baseflow line, so a constant offset leaves quick flow alone.
  expect_equal(b$rise_ratio, (b$peak_flow - attr(b, "baseflow")[b$peak_row]) /
                 attr(b, "baseflow")[b$peak_row])
})

# Guards: quick flow above rain, gaps and peaks above the rating are flagged as documented
test_that("each flag is raised and only the excluded ones drop an event", {
  d <- screen_data()
  ev <- d$events
  ev$runoff_ratio[1] <- 1.5
  flow <- d$flow
  flow[seq.int(ev$flow_start[2], ev$flow_end[2])] <- NA
  top <- max(ev$peak_flow)
  s <- screen_events(ev, flow, min_rise = 0, highest_gauged_m3s = top * 0.99)
  expect_match(s$flags[1], "quickflow_above_rain")
  expect_false(s$use[1])
  expect_match(s$flags[2], "gaps")
  expect_false(s$use[2])
  biggest <- which.max(ev$peak_flow)
  expect_match(s$flags[biggest], "above_gauging")
  expect_true(s$use[biggest] || grepl("quickflow|gaps", s$flags[biggest]))
  strict <- screen_events(ev, flow, min_rise = 0, highest_gauged_m3s = top * 0.99,
                          exclude = c("above_gauging"))
  expect_false(strict$use[biggest])
  expect_true(strict$use[1])
  expect_error(screen_events(ev, flow, exclude = "nonsense"), "exclude")
  expect_error(screen_events(as.data.frame(ev[, 1:3]), flow), "find_events")
  none <- screen_events(ev[0, ], d$flow)
  expect_equal(nrow(none), 0)
})

# Guards: the events objective leaves screened events out and says how many
test_that("the events objective uses the screen", {
  d <- screen_data(base = 1)
  scored <- .event_objective(NULL, d$forcing$rain, d$flow, 48, 1, area_km2 = 20,
                             screen = list(min_rise = 0.5))
  everything <- .event_objective(NULL, d$forcing$rain, d$flow, 48, 1, area_km2 = 20,
                                 screen = NULL)
  expect_lt(scored$found, everything$found)
  expect_match(scored$name, "screened out")
  expect_false(grepl("screened out", everything$name))
})
