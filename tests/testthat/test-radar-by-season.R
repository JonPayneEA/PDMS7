# ============================================================ #
# Tool:         test-radar-by-season
# Description:  radar_by_season() reaches each verdict from daily pairs built to show it,
#               with each half-year's ratio equal to the factor it was built with
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-27
# Tier:         1
# Inputs:       Synthetic daily radar and gauge totals
# Outputs:      None
# Dependencies: testthat
# ============================================================ #

# Twenty rain days a month; the radar is the gauge times a factor that may differ by half-year
# (winter October to March). Every daily ratio is then the factor itself, so each half-year's
# median is exactly it.
pairs_with <- function(winter, summer) {
  month <- rep(1:12, each = 20)
  gauge <- 1 + (seq_along(month) %% 7)
  data.frame(month = month, gauge_mm = gauge,
             radar_mm = gauge * ifelse(month %in% c(10:12, 1:3), winter, summer))
}

test_that("each half-year's ratio is the factor the radar was built with", {
  r <- radar_by_season(pairs_with(0.7, 1))
  expect_equal(r$seasons$ratio[r$seasons$season == "winter"], 0.7)
  expect_equal(r$seasons$ratio[r$seasons$season == "summer"], 1)
  expect_equal(r$monthly$ratio[r$monthly$month == 1], 0.7)
  expect_equal(r$monthly$ratio[r$monthly$month == 7], 1)
  expect_identical(r$monthly$days, rep(20L, 12))
})

test_that("each cause gives its verdict", {
  # Winter 0.7 against summer 1: 0.7 is under 1 / 1.15, the radar under-reads in winter.
  expect_identical(radar_by_season(pairs_with(0.7, 1))$verdict, "radar under-reads in winter")
  # Winter 1.25 against 1: over 1.15, the gauges under-catch in winter.
  expect_identical(radar_by_season(pairs_with(1.25, 1))$verdict, "gauges under-catch in winter")
  # 0.8 in both: alike by season, 0.8 under 1 / 1.15, the radar reads low.
  expect_identical(radar_by_season(pairs_with(0.8, 0.8))$verdict, "radar reads low")
  expect_identical(radar_by_season(pairs_with(1.2, 1.2))$verdict, "radar reads high")
  # 1.02 and 0.98: within both allowances.
  expect_identical(radar_by_season(pairs_with(1.02, 0.98))$verdict, "no clear fault")
  # A fifth of the steps missing: not judged, whatever the ratios.
  r <- radar_by_season(pairs_with(0.7, 1), missing_share = 0.2)
  expect_identical(r$verdict, "missing data")
  expect_match(r$why, "20%")
})

test_that("the events' rain by season is set beside the days", {
  events <- data.frame(season = rep(c("winter", "summer"), each = 4),
                       radar_mm = c(6, 7, 8, 9, 10, 10, 10, 10),
                       reference_mm = c(10, 10, 10, 10, 10, 10, 10, 10))
  r <- radar_by_season(pairs_with(0.7, 1), events = events)
  # Winter radar 6 to 9 of 10: median 0.75; summer 1.
  expect_equal(r$seasons$event_ratio[r$seasons$season == "winter"], 0.75)
  expect_equal(r$seasons$event_ratio[r$seasons$season == "summer"], 1)
  expect_match(r$why, "-25% of the gauges' in winter")
  expect_output(print(r), "radar under-reads in winter")
})

test_that("too few days are not judged, and bad inputs are refused", {
  # January and February only: no summer days, but the year's ratio over them is 0.7.
  few <- pairs_with(0.7, 1)[1:40, ]
  r <- radar_by_season(few)
  expect_identical(r$verdict, "not assessed")
  expect_match(r$why, "Under 10 days in summer")
  expect_match(r$why, "reads -30% of the gauges")
  expect_error(radar_by_season(data.frame(a = 1)), "pairs needs")
  expect_error(radar_by_season(pairs_with(1, 1), events = data.frame(a = 1)), "events needs")
})

test_that("the monthly factors scale the radar to the gauges, smoothly through the year", {
  # Radar 0.7 of the gauges in winter (October to March), 1 in summer. Twenty days a month and
  # the same gauge totals in every month (each month's days run 1 to 7 mm alike), so a month
  # whose neighbours share its season has factor 1 / 0.7 exactly; October, blended with
  # September (summer), sits between: (G + 2G + G) / (R_sep + 2 R_oct + R_nov) with R = 0.7 G
  # in winter and G in summer, (4 G) / (G + 1.4 G + 0.7 G) = 4 / 3.1.
  month <- rep(1:12, each = 20)
  gauge <- rep(1 + (0:19 %% 7), 12)
  radar <- gauge * ifelse(month %in% c(10:12, 1:3), 0.7, 1)
  f <- radar_season_factors(data.frame(month = month, gauge_mm = gauge, radar_mm = radar))
  expect_equal(f$factor[f$month %in% c(11, 12, 1, 2)], rep(1 / 0.7, 4))
  expect_equal(f$factor[f$month %in% c(5, 6, 7, 8)], rep(1, 4))
  expect_equal(f$factor[f$month == 10], 4 / 3.1)
  expect_true(all(f$basis == "month"))
})

test_that("a thin month takes its half-year's factor, and factors are held within the limits", {
  month <- c(rep(1:12, each = 20), 1)
  pairs <- data.frame(month = month, gauge_mm = 5, radar_mm = 2.5)
  # Drop all but two of January's days: January falls back to the winter half-year's 2.
  pairs <- pairs[!(pairs$month == 1 & seq_len(nrow(pairs)) > 2), ]
  f <- radar_season_factors(pairs)
  expect_identical(f$basis[f$month == 1], "half-year")
  expect_equal(f$factor[f$month == 1], 2)
  # A factor of 4 is held at the default top limit of 2.
  f <- radar_season_factors(data.frame(month = rep(1:12, each = 20), gauge_mm = 4,
                                       radar_mm = 1))
  expect_equal(f$factor, rep(2, 12))
  expect_error(radar_season_factors(data.frame(a = 1)), "pairs needs")
})
