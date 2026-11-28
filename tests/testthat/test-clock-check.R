# The reference is random rain; each series is the reference itself moved by a known number of
# steps, so at the true lag the two are the same numbers and their correlation is exactly 1.

steps_of <- function(minutes, days = 366) {
  seq(as.POSIXct("2020-01-01", tz = "UTC"), by = paste(minutes, "min"),
      length.out = days * 24 * 60 / minutes)
}
rain_like <- function(n, seed = 1) {
  set.seed(seed)
  ifelse(stats::runif(n) < 0.05, stats::rexp(n, 1), 0)
}
# The series late by k steps where `where` is TRUE: its value at t is the reference's at t - k.
late_by <- function(x, k, where = rep(TRUE, length(x))) {
  y <- x
  moved <- c(rep(0, k), x)[seq_along(x)]
  y[where] <- moved[where]
  y
}

test_that("British Summer Time runs from 01:00 UTC on the last Sundays of March and October", {
  # 2020: the last Sunday of March is the 29th, of October the 25th.
  t <- as.POSIXct(c("2020-03-29 00:59", "2020-03-29 01:00", "2020-10-25 00:59",
                    "2020-10-25 01:00", "2021-03-28 01:00"), tz = "UTC")
  expect_identical(pdmS7:::.in_bst(t), c(FALSE, TRUE, TRUE, FALSE, TRUE))
})

test_that("a series that is the reference itself is in step, with r = 1 at lag 0", {
  time <- steps_of(15)
  x <- rain_like(length(time))
  ck <- clock_check(time, x, x)
  expect_identical(ck$verdict, "in step")
  expect_equal(ck$lags$r_zero, c(1, 1))
  expect_identical(ck$lags$lag_h, c(0, 0))
})

test_that("a logger on local time is an hour late in summer time only", {
  # 15-minute steps: an hour is four steps.
  time <- steps_of(15)
  x <- rain_like(length(time))
  ck <- clock_check(time, late_by(x, 4, pdmS7:::.in_bst(time)), x)
  expect_identical(ck$verdict, "logged in local time")
  expect_identical(ck$lags$lag_h, c(1, 0))
  expect_equal(ck$lags$r_best[1], 1, tolerance = 1e-3)
  expect_match(ck$why, "Move its summer-time stamps back an hour")
})

test_that("an early hour in summer time points at the reference keeping local time", {
  time <- steps_of(15)
  x <- rain_like(length(time))
  # The reference late by an hour in summer time, so the series reads early against it.
  ck <- clock_check(time, x, late_by(x, 4, pdmS7:::.in_bst(time)))
  expect_identical(ck$verdict, "an hour out in summer time")
  expect_identical(ck$lags$lag_h, c(-1, 0))
})

test_that("a series stamped at the step's end is one step late all year", {
  time <- steps_of(60)
  x <- rain_like(length(time), seed = 2)
  ck <- clock_check(time, late_by(x, 1), x)
  expect_identical(ck$verdict, "stamped at the step's end")
  expect_identical(ck$lags$lag_h, c(1, 1))
})

test_that("a fixed offset of two hours is out all year, and three hours is past the search", {
  time <- steps_of(15)
  x <- rain_like(length(time), seed = 3)
  ck <- clock_check(time, late_by(x, 8), x)
  expect_identical(ck$verdict, "out all year")
  expect_identical(ck$lags$lag_h, c(2, 2))
  expect_match(ck$why, "late by 2 h all year")
  # Lags 0 to 12 steps are tried with max_lag_h = 3; the correlogram has 25 lags a period.
  expect_identical(nrow(ck$correlogram), 2L * 25L)
})

test_that("different lags in the two periods are unsteady", {
  time <- steps_of(15)
  x <- rain_like(length(time), seed = 4)
  bst <- pdmS7:::.in_bst(time)
  y <- late_by(late_by(x, 8, bst), 2, !bst)
  ck <- clock_check(time, y, x)
  expect_identical(ck$verdict, "unsteady")
  expect_identical(ck$lags$lag_h, c(2, 0.5))
})

test_that("a lag that barely beats lag 0 does not count", {
  # Unrelated rain: the correlation is near 0 at every lag, so no lag beats lag 0 by 0.05.
  time <- steps_of(15)
  ck <- clock_check(time, rain_like(length(time), 5), rain_like(length(time), 6))
  expect_identical(ck$verdict, "in step")
  expect_false(any(ck$lags$lag_counts))
})

test_that("a period with too little rain is left unjudged, the other judged alone", {
  # January and February only: no summer time at all, so no wet steps there.
  time <- steps_of(60, days = 60)
  x <- rain_like(length(time))
  ck <- clock_check(time, x, x)
  expect_identical(ck$verdict, "in step")
  expect_identical(ck$lags$wet_steps[1], 0L)
  expect_match(ck$why, "Summer time had too little rain to judge")
  # Two steps late in winter alone: out in winter time, and local time cannot be told apart.
  out <- clock_check(time, late_by(x, 2), x)
  expect_identical(out$verdict, "out in winter time")
  expect_match(out$why, "late by 2 h in winter time")
  expect_match(out$why, "cannot be told from a fixed offset")
})

test_that("no rain at all is not judged", {
  time <- steps_of(60, days = 60)
  zero <- rep(0, length(time))
  ck <- clock_check(time, zero, rain_like(length(time)))
  expect_identical(ck$verdict, "not enough rain")
})

test_that("bad inputs are refused with the reason", {
  time <- steps_of(60, days = 2)
  x <- rep(0, length(time))
  expect_error(clock_check(as.character(time), x, x), "POSIXct")
  expect_error(clock_check(time, x[-1], x), "one value a step")
  expect_error(clock_check(time[c(1, 3, 4)], x[1:3], x[1:3]), "evenly spaced")
  expect_error(clock_check(time, x, x, max_lag_h = 0.5), "at least one step")
})

test_that("the print gives the verdict and the lags", {
  time <- steps_of(60)
  x <- rain_like(length(time))
  expect_output(print(clock_check(time, x, x)), "Clock check: in step")
})
