# ============================================================ #
# Tool:         test-extrapolation
# Description:  Tests for the wettest-year hold-out, the rating flag and equally good sets
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-02
# Modified:     2026-11-02 - Add extrapolation tests
# Tier:         3
# Inputs:       Synthetic daily records; temporary calibration projects
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Seven water years of daily data, with two storms that make 2012-13 and 2015-16 the wettest.
daily_record <- function(boost = 1) {
  set.seed(3)
  n <- 365 * 7
  time <- seq(as.POSIXct("2010-10-01", tz = "UTC"), by = 86400, length.out = n)
  rain <- ifelse(stats::runif(n) < 0.4, stats::rgamma(n, 0.8, scale = 8), 0)
  rain[c(800, 801, 1900)] <- c(90, 60, 120)
  forcing <- data.frame(time = .fmt(time), rain = rain, pet = 1.5)
  truth <- pdm_presets("standard")
  truth$dt <- 24
  truth$area_km2 <- 50
  truth$fc <- 1.1
  model <- pdm_from_config(truth)
  observed <- run_pdm(model, forcing[, -1], initial_state_from_flow(model, 1, 0.7))$output$q_m3s
  list(time = time, forcing = forcing, observed = observed, truth = truth)
}

.fmt <- function(t) format(t, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

daily_project <- function(d = daily_record(), env = parent.frame(), test = TRUE, ...) {
  folder <- tempfile("extrapolation-")
  defer_to(function() unlink(folder, recursive = TRUE), env) # nolint: object_usage_linter.
  as_person("Ann Custodian", "custodian", "ann", env) # nolint: object_usage_linter.
  start_calibration_project(folder, "Wet Brook", "1", "Testing", 50, "O", "Sam Steward")
  register_data(folder, d$forcing, d$observed, calibration = c("2011-01-01", "2014-09-30"),
                validation = c("2014-10-01", "2016-09-30"),
                test = if (test) c("2016-10-01", "2017-09-28"), ...)
  start <- d$truth
  start$fc <- 0.9
  select_structure(folder, start, "Standard")
  folder
}

quick_auto <- function(folder, maxit = 6) {
  log_auto_calibration(folder, 3, lower = c(fc = 0.7, surface.k1 = 1),
                       upper = c(fc = 1.4, surface.k1 = 40), control = list(maxit = maxit),
                       starts = 2, seed = 1, reasoning = "Quick")
}

# Guards: water years run October to September and are ranked by their peak
test_that("wettest_years labels, ranks and holds back the largest years", {
  d <- daily_record()
  expect_equal(pdmS7:::.water_year(as.POSIXct(c("2012-09-30", "2012-10-01"), tz = "UTC")),
               c("2011-12", "2012-13"))
  w <- wettest_years(d$time, d$observed, 2)
  expect_equal(w$water_year[w$held], c("2012-13", "2015-16"))
  expect_equal(w$peak_m3s, sort(w$peak_m3s, decreasing = TRUE))
  first <- w[w$water_year == "2012-13", ]
  expect_equal(first$peak_m3s, max(d$observed[first$first_row:first$last_row]))
  expect_equal(.fmt(d$time[first$first_row]), "2012-10-01T00:00:00Z")
  expect_false(any(wettest_years(d$time, d$observed, 0)$held))
  # A year with less than half of it observed does not count, so cannot be held back.
  gappy <- d$observed
  gappy[first$first_row:(first$first_row + 200)] <- NA
  expect_false("2012-13" %in% wettest_years(d$time, gappy, 2)$water_year)
  expect_error(wettest_years(d$time, d$observed, 5), "would leave fewer than 3")
  expect_error(wettest_years(d$time, d$observed, 1.5), "whole number")
})

# Guards: registration records the held years and the rating check, and refuses what it cannot do
test_that("registration holds back the wettest years and flags flows above the rating", {
  d <- daily_record()
  limit <- 25
  folder <- daily_project(d, highest_gauged_m3s = limit)
  reg <- read_entry(folder, 2)
  years <- reg$scorecard$wettest$years
  expect_equal(vapply(years, function(y) y$water_year, ""), c("2012-13", "2015-16"))
  expect_equal(reg$scorecard$highest_gauged_m3s, limit)
  expect_equal(reg$scorecard$tie_tolerance, 0.02)
  held <- pdmS7:::.held_rows(reg$scorecard)
  check <- reg$rating_check$windows
  expect_equal(check$wettest$steps_above, sum(d$observed[held] > limit))
  expect_equal(check$calibration$highest_m3s,
               max(d$observed[pdmS7:::.scored_rows(reg$scorecard, "calibration")]))
  # Held rows are scored by nothing but the test.
  for (w in c("calibration", "validation")) {
    expect_length(intersect(pdmS7:::.scored_rows(reg$scorecard, w), held), 0)
  }
  # Older projects record no held years and hold nothing back.
  expect_length(pdmS7:::.held_rows(list(calibration = list(first_row = 1, last_row = 9))), 0)
  as_person("Ann Custodian", "custodian", "ann")
  bad <- function(...) {
    f <- tempfile("bad-")
    on.exit(unlink(f, recursive = TRUE))
    start_calibration_project(f, "B", "1", "t", 50, "O", "S")
    register_data(f, ...)
  }
  expect_error(bad(d$forcing[, -1], d$observed, c(100, 1400), c(1401, 2192)), "time column")
  expect_error(bad(d$forcing, d$observed, c("2011-01-01", "2015-09-30"),
                   c("2015-10-01", "2016-09-30")), "leaves the validation window")
  expect_error(bad(d$forcing, d$observed, c(100, 1400), highest_gauged_m3s = -1),
               "highest_gauged_m3s")
  expect_error(bad(d$forcing, d$observed, c(100, 1400), tie_tolerance = -1), "tie_tolerance")
})

# Guards: the search never sees the held years: changing them changes nothing it fits
test_that("calibration ignores the held-back years entirely", {
  d <- daily_record()
  bigger <- d
  w <- wettest_years(d$time, d$observed, 2)
  for (i in which(w$held)) {
    rows <- w$first_row[i]:w$last_row[i]
    bigger$observed[rows] <- bigger$observed[rows] * 1.3
  }
  a <- quick_auto(daily_project(d))
  b <- quick_auto(daily_project(bigger))
  expect_equal(a$configuration, b$configuration)
  expect_equal(a$scores, b$scores)
  expect_equal(a$equally_good, b$equally_good)
})

# Guards: the archive records each trial's score; equally good sets are within tolerance and apart
test_that("calibrate_pdm archives trials and equally good sets are thinned", {
  d <- daily_record()
  cfg <- d$truth
  cfg$fc <- 0.9
  nse <- function(sim) 1 - sum((sim - d$observed)^2) / sum((d$observed - mean(d$observed))^2)
  fit <- calibrate_pdm(cfg, d$forcing[, -1], d$observed, lower = c(fc = 0.7), upper = c(fc = 1.4),
                       objective = "nse", control = list(maxit = 5), archive = nse)
  trials <- fit$trials
  expect_gt(nrow(trials), 3)
  expect_equal(nrow(attr(trials, "unit")), nrow(trials))
  one <- cfg
  one$fc <- trials$fc[2]
  sim <- run_pdm(pdm_from_config(one), d$forcing[, -1],
                 initial_state_from_flow(pdm_from_config(one), d$observed[1], 0.7))$output$q_m3s
  expect_equal(trials$score[2], nse(sim), tolerance = 1e-10)
  expect_null(calibrate_pdm(cfg, d$forcing[, -1], d$observed, lower = c(fc = 0.7),
                            upper = c(fc = 1.4), control = list(maxit = 2))$trials)
  # Thinning: best first, all within tolerance, at most max_sets, and no two the same.
  set.seed(2)
  tr <- data.table::data.table(score = c(0.9, 0.95, 0.94, 0.5, 0.949999), a = c(1, 2, 3, 4, 2))
  unit <- matrix(c(0.1, 0.2, 0.3, 0.4, 0.2), ncol = 1)
  good <- pdmS7:::.equally_good(tr, unit, "higher", 0.02)
  expect_equal(vapply(good$sets, function(s) s$score, 0), c(0.95, 0.94))
  expect_equal(good$within, 3L)
  expect_length(pdmS7:::.equally_good(tr, unit, "higher", 0.5, max_sets = 2)$sets, 2)
  low <- pdmS7:::.equally_good(tr, unit, "lower", 0.1)
  expect_equal(low$sets[[1]]$score, 0.5)
  expect_null(pdmS7:::.equally_good(tr[0], unit[0, , drop = FALSE], "higher", 0.1))
})

# Guards: the test reveals the held years once, with peaks, spread and the rating flag
test_that("the test scores the held years with the spread of equally good sets", {
  d <- daily_record()
  limit <- 40
  folder <- daily_project(d, highest_gauged_m3s = limit)
  auto <- quick_auto(folder)
  expect_gt(length(auto$equally_good$sets), 1)
  scores <- vapply(auto$equally_good$sets, function(s) s$score, 0)
  expect_true(all(scores >= max(scores) - 0.02))
  propose_candidate(folder, auto$id, "Best")
  validate_candidate(folder, "Fine")
  test <- test_candidate(folder, "Final")
  card <- read_entry(folder, 2)$scorecard
  held <- pdmS7:::.held_rows(card)
  sim <- read.csv(file.path(folder, test$series$file))$simulated_m3s
  expect_equal(test$wettest$scores$nse, pdm_scorecard(sim[held], d$observed[held])[["nse"]])
  y <- test$wettest$years[[1]]
  rows <- intersect(card$wettest$years[[1]]$first_row:card$wettest$years[[1]]$last_row, held)
  expect_equal(y$observed_peak_m3s, max(d$observed[rows]))
  expect_equal(y$simulated_peak_m3s, max(sim[rows]))
  expect_lte(y$spread_low_m3s, y$simulated_peak_m3s)
  expect_gte(y$spread_high_m3s, y$simulated_peak_m3s)
  expect_lt(y$spread_low_m3s, y$spread_high_m3s)
  expect_equal(vapply(test$wettest$years, function(y) y$above_gauged, TRUE),
               vapply(test$wettest$years, function(y) y$observed_peak_m3s > limit, TRUE))
  expect_equal(test$wettest$sets, length(auto$equally_good$sets))
  expect_error(test_candidate(folder, "Again"), "already been tested")
  expect_true(all(verify_project(folder, rerun = TRUE)$ok))
  html <- paste(readLines(build_report(folder, sensitivity = FALSE)), collapse = "\n")
  expect_match(html, "Held-back wettest years")
  expect_match(html, "Peaks in the held-back wettest years")
  expect_match(html, "above the highest gauged flow")
})

# Guards: held years alone make a test required, and a manual candidate has no spread
test_that("held years without a test window are still tested before sign-off", {
  folder <- daily_project(test = FALSE)
  log_trial(folder, 3, c(fc = 1.05), "better", "Closer")
  propose_candidate(folder, 4, "Manual")
  validate_candidate(folder, "Fine")
  as_person("Sam Steward", "steward", "sam")
  expect_error(sign_off_project(folder, "OK", all_reviewed), "run test_candidate")
  as_person("Ann Custodian", "custodian", "ann")
  test <- test_candidate(folder, "Final")
  expect_null(test$test_scores)
  expect_equal(test$wettest$sets, 0L)
  y <- test$wettest$years[[1]]
  expect_equal(y$spread_low_m3s, y$simulated_peak_m3s)
  expect_null(y$above_gauged)
  expect_true(all(verify_project(folder, rerun = TRUE)$ok))
  html <- paste(readLines(build_report(folder, sensitivity = FALSE)), collapse = "\n")
  expect_match(html, "No equally good sets were recorded")
  as_person("Sam Steward", "steward", "sam")
  expect_equal(sign_off_project(folder, "OK", all_reviewed)$type, "sign_off")
})
