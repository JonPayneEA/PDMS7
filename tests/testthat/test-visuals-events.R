# Tests for the event plots (plot.pdm_events(), autoplot.pdm_events()) and the pdm_events class
# that event tables carry through screening and scoring.

visuals_events <- function() {
  set.seed(9)
  n <- 24 * 200
  rain <- ifelse(stats::runif(n) < 0.05, stats::rexp(n, 0.3), 0)
  flow <- as.numeric(stats::filter(rain, 0.96, method = "recursive")) / 8 + 0.2
  time <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600, length.out = n)
  list(rain = rain, flow = flow,
       events = find_events(rain, flow, time, dt = 1, area_km2 = 15))
}

# Guards: the class survives screening and scoring, so plot() finds every event table
test_that("event tables carry the pdm_events class", {
  d <- visuals_events()
  expect_s3_class(d$events, c("pdm_events", "data.frame"))
  screened <- screen_events(d$events, d$flow)
  expect_s3_class(screened, "pdm_events")
  scored <- event_scores(screened, d$flow * 0.9, d$flow)
  expect_s3_class(scored, "pdm_events")
  expect_true(all(c("use", "peak_error") %in% names(scored)))
})

# Guards: the balance plot puts each event's rain against its quick flow, draws the limit line
# and counts the events above it; screened events are hollow
test_that("the balance description holds rain, quick flow and the limit", {
  d <- visuals_events()
  ev <- screen_events(d$events, d$flow)
  ev$quickflow_mm[1] <- ev$rain_mm[1] * 3
  ev$runoff_ratio[1] <- 3
  spec <- .events_spec(ev, "balance", 1)
  expect_equal(spec$log, "xy")
  expect_match(spec$subtitle, "1 above a runoff ratio of 1")
  limit <- spec$series[spec$series$label == "Runoff ratio 1 (limit)", ]
  expect_equal(limit$y, limit$x)
  if (any(!ev$use)) expect_true("open" %in% spec$series$geom)
  expect_error(.events_spec(ev[, c("event", "peak_row")], "balance", 1), "needs rain_mm")
})

# Guards: peaks and timing need scored events, count the peaks within 20%, and colour by
# window when the table says which window each event is in
test_that("peak and timing descriptions use scored events", {
  d <- visuals_events()
  expect_error(.events_spec(d$events, "peaks", 1), "event_scores")
  scored <- event_scores(d$events, d$flow * 1.1, d$flow)
  peaks <- .events_spec(scored, "peaks", 1)
  expect_match(peaks$subtitle, sprintf("%d of %d peaks within 20%%", nrow(scored), nrow(scored)))
  scored$period <- rep(c("calibration", "validation"), length.out = nrow(scored))
  windows <- .events_spec(scored, "timing", 1)
  expect_setequal(unique(windows$series$label), c("Calibration", "Validation"))
})

# Guards: every type draws in base R, and in ggplot2 when it is installed
test_that("event plots draw in both engines", {
  d <- visuals_events()
  scored <- event_scores(screen_events(d$events, d$flow), d$flow * 0.95, d$flow)
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (type in c("balance", "peaks", "timing")) expect_identical(plot(scored, type = type), scored)
  skip_if_not_installed("ggplot2")
  for (type in c("balance", "peaks", "timing")) {
    g <- ggplot2::autoplot(scored, type = type)
    expect_s3_class(g, "ggplot")
    expect_silent(ggplot2::ggplot_build(g))
  }
})
