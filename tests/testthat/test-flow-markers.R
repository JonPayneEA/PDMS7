# Tests for flow_markers() and the event floor: QMED from water-year maxima, flow duration
# exceedances, registration without thresholds, and events chosen by a flow.

hourly_record <- function(years = 4, seed = 1) {
  set.seed(seed)
  n <- 24 * 365 * years
  time <- as.POSIXct("2010-10-01", tz = "UTC") + 3600 * (seq_len(n) - 1)
  q <- 1 + 20 * exp(stats::filter(stats::rnorm(n, 0, 0.03), 0.995, method = "recursive"))
  list(time = time, q = as.numeric(q))
}

# Guards: QMED is the median of water-year maxima, and Q<p> the flow exceeded p% of the time
test_that("markers follow their definitions", {
  r <- hourly_record()
  wy <- as.POSIXlt(r$time)$year + 1900 + (as.POSIXlt(r$time)$mon >= 9)
  m <- suppressWarnings(flow_markers(r$q, 1, r$time, markers = c("QMED", "0.5QMED", "Q1", "Q5")))
  expect_equal(m$name, c("QMED", "0.5QMED", "Q1", "Q5"))
  qmed <- stats::median(tapply(r$q, wy, max))
  expect_equal(m$value[1], signif(qmed, 6))
  expect_equal(m$value[2], signif(qmed / 2, 6))
  expect_equal(mean(r$q > m$value[3]), 0.01, tolerance = 0.01)
  expect_equal(mean(r$q > m$value[4]), 0.05, tolerance = 0.01)
  expect_identical(attr(m, "years"), 4L)
  expect_true(all(m$unit == "flow"))
  # An incomplete year does not count: blank most of the first
  gappy <- r$q
  gappy[1:(24 * 200)] <- NA
  expect_identical(attr(suppressWarnings(flow_markers(gappy, 1, r$time, "QMED")), "years"), 3L)
  # Short records: a warning under 10 years, an error under 2
  expect_warning(flow_markers(r$q, 1, r$time, "QMED"), "uncertain")
  expect_error(flow_markers(r$q[1:5000], 1, r$time[1:5000], "QMED"), "two complete")
  expect_error(flow_markers(r$q, 1, markers = "Q100"), "\\(0, 100\\)")
  expect_error(flow_markers(r$q, 1, markers = "Peak"), "Unknown marker")
})

# Guards: without thresholds, a project registers QMED, Q1 and Q5 from the record, marked as
# such, and scores every run against them; given thresholds replace them
test_that("register_data registers flow markers when no thresholds are given", {
  r <- hourly_record(years = 3)
  folder <- file.path(tempdir(), "markers-project")
  unlink(folder, recursive = TRUE)
  old <- options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
  on.exit(options(old), add = TRUE)
  start_calibration_project(folder, catchment = "Example", gauge = "0", purpose = "Test",
                            area_km2 = 50, owner = "Owner", steward = "Steward")
  forcing <- data.frame(time = r$time, rain = 0.1, pet = 0.05)
  reg <- register_data(folder, forcing, r$q, calibration = c(1, 24 * 365 * 2),
                       wettest_years = 0)
  card <- reg$scorecard
  names <- vapply(card$thresholds, function(t) t$name, "")
  expect_equal(names, c("QMED", "Q1", "Q5"))
  expect_true(all(vapply(card$thresholds, function(t) t$source, "") == "flow marker"))
  expect_equal(pdmS7:::.project_event_share("0.5QMED", card),
               c(peak = card$thresholds[[1]]$flow_m3s / 2))
  expect_equal(pdmS7:::.project_event_share("Q1", card), c(peak = card$thresholds[[2]]$flow_m3s))
  expect_identical(pdmS7:::.project_event_share(0.5, card), 0.5)
  unlink(folder, recursive = TRUE)
  start_calibration_project(folder, catchment = "Example", gauge = "0", purpose = "Test",
                            area_km2 = 50, owner = "Owner", steward = "Steward")
  given <- data.frame(name = "Flood Warning", value = 15, unit = "flow")
  reg <- register_data(folder, forcing, r$q, calibration = c(1, 24 * 365 * 2), thresholds = given,
                       wettest_years = 0)
  expect_equal(vapply(reg$scorecard$thresholds, function(t) t$name, ""), "Flood Warning")
  unlink(folder, recursive = TRUE)
})

# Guards: an event floor scores every event whose observed peak reaches it, and no others
test_that("the events objective can choose events by a flow floor", {
  set.seed(4)
  n <- 24 * 120
  rain <- ifelse(stats::runif(n) < 0.04, stats::rexp(n, 0.2), 0)
  model <- pdm_from_config(pdm_presets("standard"))
  q <- run_pdm(model, data.frame(rain = rain, pet = 0.05))$output$q_m3s
  share <- pdmS7:::.event_objective(NULL, rain, q, 48, 1, share = 0.5)
  floor <- stats::quantile(q, 0.95, names = FALSE)
  by_flow <- pdmS7:::.event_objective(NULL, rain, q, 48, 1, share = c(peak = floor))
  chosen <- pdmS7:::.event_windows(NULL, rain, q, 48, 1, c(peak = floor), list(), NULL)
  peaks <- vapply(chosen$windows, function(i) max(q[i]), numeric(1))
  expect_true(all(peaks >= floor))
  expect_equal(by_flow$floor_m3s, floor)
  expect_match(by_flow$name, "peaking at")
  marker <- pdmS7:::.event_objective(NULL, rain, q, 48, 1, share = "Q5")
  expect_equal(marker$events, by_flow$events)
  expect_match(marker$name, "\\(Q5\\)")
  expect_null(share$floor_m3s)
  expect_error(pdmS7:::.event_objective(NULL, rain, q, 48, 1, share = c(peak = 1e6)), "No event")
  expect_error(pdmS7:::.event_objective(NULL, rain, q, 48, 1, share = 2), "event_share")
})
