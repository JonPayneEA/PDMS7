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
