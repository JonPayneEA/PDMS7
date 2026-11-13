# ============================================================ #
# Tool:         test-events
# Description:  Tests for the DMCA response time, event identification and event scores
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-06
# Modified:     2026-11-06 - Add event tests
# Tier:         1
# Inputs:       Constructed rain and flow with known responses; a small synthetic batch
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Rain passed through a kernel: kernel[j] is the share of rain arriving j - 1 steps later.
respond <- function(rain, kernel) {
  pad <- length(kernel) - 1L
  as.numeric(stats::filter(c(rep(0, pad), rain), kernel, sides = 1))[-seq_len(pad)]
}
triangle <- function(k) {
  w <- c(seq(0, 1, length.out = k + 1), seq(1, 0, length.out = k + 1)[-1])
  w / sum(w)
}
random_rain <- function(n, seed) {
  set.seed(seed)
  ifelse(stats::runif(n) < 0.03, stats::rexp(n, 0.3), 0)
}

# Guards: the response time of a symmetric response is its centre of mass, the lag the
# method is defined to estimate
test_that("response_time_dmca recovers the lag of a symmetric response", {
  rain <- random_rain(20000, 1)
  for (k in c(6, 12)) {
    expect_equal(response_time_dmca(rain, respond(rain, triangle(k)))$response_h, k)
  }
  half_hourly <- response_time_dmca(rain, respond(rain, triangle(6)), dt = 0.5)
  expect_equal(half_hourly$response_h, 3)
  expect_equal(half_hourly$window, 13L)
})

# Guards: the compiled search agrees with the R reference
test_that("the compiled DMCA search matches the R reference", {
  rain <- random_rain(5000, 2)
  flow <- 0.3 + respond(rain, triangle(4)) + 0.05 * sin(seq_len(5000) / 50)
  compiled <- response_time_dmca(rain, flow, max_response_h = 60)
  old <- options(pdmS7.engine = "r")
  on.exit(options(old), add = TRUE)
  reference <- response_time_dmca(rain, flow, max_response_h = 60)
  expect_equal(compiled$response_steps, reference$response_steps)
  expect_lt(max(abs(compiled$curve$rho - reference$curve$rho)), 1e-12)
})

# Guards: the moving mean shrinks its window at the ends, as the published method's does
test_that("the moving mean shrinks at the ends", {
  x <- c(3, 1, 4, 1, 5, 9, 2, 6)
  brute <- vapply(seq_along(x), function(i) mean(x[max(1, i - 2):min(8, i + 2)]), numeric(1))
  expect_equal(pdmS7:::.moving_mean(x, 2), brute)
})

# Guards: a search that ends at its longest window warns, and bad input is refused
test_that("response_time_dmca warns at the search limit and checks its input", {
  rain <- random_rain(3000, 3)
  expect_warning(response_time_dmca(rain, respond(rain, triangle(20)), max_response_h = 5),
                 "longest searched")
  expect_error(response_time_dmca(1:3, 1:4), "same length")
  expect_error(response_time_dmca(rain, rain, dt = 0), "dt")
  expect_error(response_time_dmca(rep(0, 100), rep(1, 100)), "does not vary")
})

# Guards: two separate storms on a receding baseflow are two events, with rain windows on the
# storms and flow peaks where the response puts them
test_that("find_events finds known storms", {
  n <- 600
  rain <- numeric(n)
  rain[100:105] <- c(2, 5, 8, 6, 3, 1)
  rain[350:352] <- c(4, 10, 4)
  flow <- 0.5 * exp(-seq_len(n) / 3000) + respond(rain, triangle(6))
  time <- seq(as.POSIXct("2020-01-01", tz = "UTC"), by = 3600, length.out = n)
  ev <- find_events(rain, flow, time, dt = 1, rain_min = 0.2, max_response_h = 30,
                    area_km2 = 10)
  expect_equal(nrow(ev), 2L)
  expect_equal(ev$rain_start, c(100L, 350L))
  expect_equal(ev$rain_end, c(105L, 352L))
  expect_equal(ev$rain_mm, c(25, 18))
  expect_equal(ev$peak_row, c(108L, 357L))
  expect_true(all(ev$flow_start >= ev$rain_start & ev$flow_end > ev$rain_end))
  expect_true(all(ev$flow_end[1] < ev$flow_start[2]))
  expect_equal(ev$rain_start_time, time[ev$rain_start])
  expect_true(all(ev$quickflow_mm > 0 & ev$quickflow_mm < ev$flow_mm))
  expect_true(all(attr(ev, "baseflow") <= flow))
  expect_equal(attr(ev, "rain_min"), 0.2)
  # The default rain_min scales with the step: 0.2 mm/h hourly, 0.04 mm/h daily.
  expect_equal(attr(find_events(rain, flow, dt = 1, max_response_h = 30), "rain_min"), 0.2)
  # When no rain is intense enough to count, there are no events: an empty table.
  quiet <- find_events(rain, flow, dt = 1, rain_min = 100, max_response_h = 30, area_km2 = 10)
  expect_equal(nrow(quiet), 0L)
  expect_true(all(c("rain_start", "flow_end", "runoff_ratio") %in% names(quiet)))
})

# Guards: overlapping events merge into one spanning both
test_that("overlapping events merge", {
  ev <- cbind(rain_start = c(10L, 15L, 40L), rain_end = c(20L, 25L, 45L),
              flow_start = c(12L, 18L, 42L), flow_end = c(30L, 28L, 60L))
  merged <- pdmS7:::.merge_overlaps(ev)
  expect_equal(unname(merged[, "rain_start"]), c(10L, 40L))
  expect_equal(unname(merged[, "flow_end"]), c(30L, 60L))
})

# Guards: event scores are zero for a perfect model and measure a lagged one exactly
test_that("event_scores measures peaks, timing and volume", {
  n <- 600
  rain <- numeric(n)
  rain[100:105] <- c(2, 5, 8, 6, 3, 1)
  rain[350:352] <- c(4, 10, 4)
  flow <- 0.5 * exp(-seq_len(n) / 3000) + respond(rain, triangle(6))
  ev <- find_events(rain, flow, dt = 1, max_response_h = 30)
  perfect <- event_scores(ev, flow, flow)
  expect_equal(perfect$peak_error, c(0, 0))
  expect_equal(perfect$timing_error_h, c(0, 0))
  expect_equal(perfect$nse, c(1, 1))
  late <- event_scores(ev, c(rep(flow[1], 2), flow[1:(n - 2)]), flow)
  expect_equal(late$timing_error_h, c(2, 2))
  high <- event_scores(ev, 1.1 * flow, flow)
  expect_equal(high$peak_error, c(0.1, 0.1))
  expect_equal(high$volume_error, c(0.1, 0.1))
  expect_equal(event_scores(ev, flow, flow, dt = 0.25)$timing_error_h, c(0, 0))
  expect_error(event_scores(data.frame(a = 1), flow, flow), "find_events")
  expect_error(event_scores(ev, flow[-1], flow), "length")
})

# Guards: a batch's events are found and scored in every basin, each labelled with its window
test_that("batch_events scores the candidates of a batch event by event", {
  root <- tempfile("events-")
  output <- tempfile("events-batch-")
  on.exit(unlink(c(root, output), recursive = TRUE), add = TRUE)
  synthetic_basins(root, n = 2, years = 2, dt = 1, seed = 4)
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  status <- calibrate_batch(root, output, starts = 1, control = list(maxit = 3))
  expect_equal(status$state, c("done", "done"))
  out <- batch_events(output)
  expect_setequal(out$basins$basin, c("S001", "S002"))
  expect_true(all(out$basins$response_observed_h >= 1))
  expect_true(all(out$basins$events > 10))
  expect_true(all(out$events$period %in% c("calibration", "validation", "wettest", "outside")))
  expect_true(all(c("calibration", "validation") %in% out$events$period))
  expect_true(all(is.finite(out$events$peak_error)))
  expect_error(batch_events(tempfile()), "")
})

# Guards: the C core and the R reference find the same events, totals and scores, including on
# a record with gaps, where rounding in the running sums decides which steps are quiet
test_that("the C core matches the R reference event for event", {
  river <- synthetic_catchment(years = 1, dt = 1, seed = 9)
  flow <- river$observed
  flow[c(500:700, 6000:6100)] <- NA
  rain <- river$forcing$rain
  rain[3000:3010] <- NA
  run <- function() {
    ev <- find_events(rain, flow, dt = 1, area_km2 = river$truth$area_km2)
    list(events = ev, scores = event_scores(ev, river$true_flow, flow))
  }
  core <- run()
  old <- options(pdmS7.engine = "r")
  on.exit(options(old), add = TRUE)
  reference <- run()
  positions <- c("rain_start", "rain_end", "flow_start", "flow_end", "peak_row")
  expect_identical(as.matrix(core$events[positions]), as.matrix(reference$events[positions]))
  numbers <- c("rain_mm", "peak_flow", "flow_mm", "quickflow_mm", "runoff_ratio")
  expect_equal(core$events[numbers], reference$events[numbers], tolerance = 1e-12)
  expect_equal(attr(core$events, "baseflow"), attr(reference$events, "baseflow"),
               tolerance = 1e-12)
  scores <- c("observed_peak", "simulated_peak", "peak_error", "timing_error_h",
              "volume_error", "nse")
  expect_equal(core$scores[scores], reference$scores[scores], tolerance = 1e-12)
})

# Guards: fragments of one flood merge into one event; independent floods stay apart
test_that("independent events merge the fragments of one flood", {
  rows <- function(...) {
    m <- rbind(...)
    colnames(m) <- c("rain_start", "rain_end", "flow_start", "flow_end")
    m
  }
  # One long flood: a rise to 10 from row 20 to 60 and a fall back by row 100, hourly steps
  q <- c(rep(1, 20), seq(1, 10, length.out = 40), seq(10, 1, length.out = 40), rep(1, 100))
  # Three slices of it, as DMCA-ESR cuts a multi-burst flood: overlapping windows, peaks close
  parts <- rows(c(18, 25, 20, 55), c(40, 45, 50, 62), c(55, 58, 61, 95))
  one <- .independent_rows(parts, q, dt = 1, response_h = 4, separation = 3, trough = 2 / 3)
  expect_equal(nrow(one), 1)
  expect_equal(unname(one[1, ]), c(18, 58, 20, 95))
  # Two floods apart: the flow falls back between them, and the peaks are far apart
  q2 <- c(q[1:110], q[11:110], rep(1, 10))
  two <- .independent_rows(rows(c(18, 25, 20, 100), c(118, 125, 120, 200)), q2, dt = 1,
                           response_h = 4, separation = 3, trough = 2 / 3)
  expect_equal(nrow(two), 2)
  # Close peaks with no real trough between them are one flood even without overlap
  q3 <- c(rep(1, 20), rep(8, 5), 7, rep(9, 5), rep(1, 50))
  near <- .independent_rows(rows(c(18, 22, 20, 25), c(24, 28, 26, 40)), q3, dt = 1,
                            response_h = 4, separation = 3, trough = 2 / 3)
  expect_equal(nrow(near), 1)
  expect_identical(.independent_rows(parts[1, , drop = FALSE], q, 1, 4, 3, 2 / 3),
                   parts[1, , drop = FALSE])
})

# Guards: find_events merges the events of one flood by default, and not when told not to
test_that("find_events merges the events of one flood by default", {
  river <- synthetic_catchment(years = 2, dt = 1, seed = 1)
  args <- list(river$forcing$rain, river$observed, river$forcing$time, dt = 1,
               area_km2 = river$truth$area_km2)
  published <- do.call(find_events, c(args, independent = FALSE))
  floods <- do.call(find_events, args)
  expect_false(attr(published, "independent"))
  expect_true(attr(floods, "independent"))
  expect_lte(nrow(floods), nrow(published))
  # No two floods overlap, and every published event lies inside a flood
  expect_true(all(utils::head(floods$flow_end, -1) < utils::tail(floods$flow_start, -1)))
  inside <- vapply(seq_len(nrow(published)), function(e) {
    any(floods$flow_start <= published$flow_start[e] & floods$flow_end >= published$flow_end[e])
  }, logical(1))
  expect_true(all(inside))
  expect_error(do.call(find_events, c(args, trough = 2)), "trough")
})
