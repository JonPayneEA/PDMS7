# Every gauge total is 5 mm, every day of two whole water years (2016-10-01 to 2018-09-30,
# 365 days each, so the folds are equal), and the radar reads a fixed share of the gauge in
# each: so each fold's factor is exactly one over its share, and every score follows by hand.
two_years <- function(share_a, share_b) {
  date <- seq(as.Date("2016-10-01"), as.Date("2018-09-30"), by = "day")
  share <- ifelse(date < as.Date("2017-10-01"), share_a, share_b)
  data.frame(date = date, gauge_mm = 5, radar_mm = 5 * share)
}

test_that("a radar that reads 80% every year: the factors hold, with no error left", {
  ft <- test_season_factors(two_years(0.8, 0.8))
  expect_identical(ft$verdict, "the factors hold")
  s <- ft$scores
  # Raw: 0.8 of the gauges, -20%; each day |log 0.8| out, exp(-log 0.8) - 1 = 25%.
  expect_equal(s$total_bias_pct, c(-20, 0, 0))
  expect_equal(s$daily_error_pct, c(25, 0, 0))
  expect_equal(ft$months$factor_a, rep(1.25, 12))
  expect_equal(ft$months$fold_change, rep(0, 12))
  expect_identical(ft$folds$days, c(365L, 365L))
})

test_that("a radar that reads 80% one year and 125% the next: the factors do not help", {
  ft <- test_season_factors(two_years(0.8, 1.25))
  expect_identical(ft$verdict, "the factors do not help")
  s <- ft$scores
  # Raw: (0.8 + 1.25) / 2 = 1.025, +2.5%. In sample: one factor, 1 / 1.025, so 0%.
  # Out of sample: year A scaled by B's 0.8 gives 0.64; year B by A's 1.25 gives 1.5625;
  # (0.64 + 1.5625) / 2 = 1.10125, +10.125%.
  expect_equal(s$total_bias_pct, c(2.5, 0, 10.125))
  # The folds' factors, 1.25 and 0.8, differ by 0.45 over 1 / 1.025: 0.46125, every month.
  expect_equal(ft$months$fold_change, rep(0.45 * 1.025, 12))
  expect_match(ft$why, "Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec")
  expect_match(ft$why, "rests on the years")
})

test_that("factors that help but not as much as in sample say so", {
  ft <- test_season_factors(two_years(0.9, 0.5))
  expect_identical(ft$verdict, "the factors help, less than in sample")
  # Raw: (0.9 + 0.5) / 2 = 0.7, -30%. Folds' factors 1 / 0.9 and 2 (at the limit). Out of
  # sample: 0.9 x 2 = 1.8 and 0.5 / 0.9 = 0.5556; their mean is 1.17778, +17.78%.
  expect_equal(ft$scores$total_bias_pct[c(1, 3)], c(-30, 100 * ((1.8 + 0.5 / 0.9) / 2 - 1)))
})

test_that("too few days in a fold is not tested", {
  d <- two_years(0.8, 0.8)
  d <- d[d$date < as.Date("2017-11-01"), ]
  # Fold B, water year 2018, has only October 2017: 31 days, under 60.
  ft <- test_season_factors(d)
  expect_identical(ft$verdict, "not tested")
  expect_identical(ft$folds$days, c(365L, 31L))
  expect_null(ft$scores)
})

test_that("bad inputs are refused with the reason", {
  d <- two_years(0.8, 0.8)
  expect_error(test_season_factors(d[, c("gauge_mm", "radar_mm")]), "needs date")
  d$date <- as.character(d$date)
  expect_error(test_season_factors(d), "must be a Date")
  expect_output(print(test_season_factors(two_years(0.8, 0.8))), "the factors hold")
})
