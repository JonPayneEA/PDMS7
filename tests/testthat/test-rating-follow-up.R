# ============================================================ #
# Tool:         test-rating-follow-up
# Description:  rating_follow_up() reaches each verdict from findings built to call for it:
#               fit a candidate, get high-flow gaugings, ask the hydrometry team, nothing
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-27
# Tier:         1
# Inputs:       A balance diagnosis of daily synthetic data; hand-made gauging tables and
#               record checks
# Outputs:      None
# Dependencies: testthat
# ============================================================ #

days <- seq(as.POSIXct("2020-01-01", tz = "UTC"), as.POSIXct("2023-12-31", tz = "UTC"),
            by = 86400)
rain <- (seq_along(days) %% 7) + 1
pet <- rep(1.5, length(days))
floods <- data.frame(rain_start = seq(10, by = 80, length.out = 16), peak_flow = 1:16)
floods$rain_end <- floods$rain_start + 3
floods$peak_row <- floods$rain_end + 1
floods$quickflow_mm <- 2
# Flow 2.8 mm a day: inside Fu's range, so the balance closes and the rating is unlikely.
closes <- balance_diagnosis(days, rep(2.8 * 100 / 86.4, length(days)), list(ref = rain), pet,
                            100, floods, water_year_start = 1)

limbs <- function(residual, within, n) {
  data.frame(limb = 1:2, lower_level = c(0, 1), upper_level = c(1, 999), n_gaugings = n,
             gauged_max_stage = c(1, 2), median_residual_pct = residual,
             share_within_tol = within)
}

test_that("gaugings on the rating and nothing else leave no rating work", {
  f <- rating_follow_up(closes, gaugings = limbs(c(1, -2), c(0.95, 0.9), c(20, 15)))
  expect_identical(f$verdict, "no rating work needed")
  expect_false(f$action_needed)
  expect_true(all(f$findings$status[f$findings$check == "gaugings against the rating"] == "fine"))
})

test_that("a limb off the rating with enough gaugings calls for a candidate rating", {
  # The top limb's gaugings sit 12% above it, two in five within 10%, fifteen of them: off on
  # both counts and enough to fit (10 or more).
  f <- rating_follow_up(closes, gaugings = limbs(c(1, 12), c(0.95, 0.4), c(20, 15)))
  expect_identical(f$verdict, "fit a candidate rating")
  expect_true(f$action_needed)
  top <- f$findings[f$findings$check == "gaugings against the rating", ][2, ]
  expect_identical(top$status, "act")
  expect_match(top$finding, "limb 2 \\(1.00 to 99.00 m\\): 15 gaugings, median \\+12.0%")
})

test_that("a limb off with too few gaugings, or much flow above the top, calls for gaugings", {
  f <- rating_follow_up(closes, gaugings = limbs(c(1, 12), c(0.95, 0.4), c(20, 6)))
  expect_identical(f$verdict, "get high-flow gaugings")
  expect_match(f$findings$action[3], "too few to refit")
  # 20% of the flow above the top, with the gaugings on the rating below it.
  above <- closes
  above$record$above_top_share <- 0.2
  f <- rating_follow_up(above, gaugings = limbs(c(1, -2), c(0.95, 0.9), c(20, 15)))
  expect_identical(f$verdict, "get high-flow gaugings")
})

test_that("a record made with a rating not in the export, or summer weed, means asking", {
  record <- list(periods = data.frame(period = 1:2, assessed = TRUE,
                                      known_departing_share = c(0, 0.6)),
                 settings = list(known_fit_share = 0.05))
  f <- rating_follow_up(closes, record_check = record,
                        gaugings = limbs(c(1, -2), c(0.95, 0.9), c(20, 15)))
  expect_identical(f$verdict, "ask the hydrometry team")
  expect_match(f$findings$finding[f$findings$check == "record against the known ratings"],
               "1 period\\(s\\)")
  weed <- closes
  weed$record$dry_rise_months <- "2021-07"
  f <- rating_follow_up(weed, gaugings = limbs(c(1, -2), c(0.95, 0.9), c(20, 15)))
  expect_identical(f$verdict, "ask the hydrometry team")
})

test_that("a suspected rating with no gaugings to test it means asking for them", {
  suspected <- closes
  suspected$suspects$verdict[suspected$suspects$suspect == "rating"] <- "likely"
  f <- rating_follow_up(suspected)
  expect_identical(f$verdict, "ask the hydrometry team")
  expect_match(f$why, "no gaugings were given")
  expect_identical(f$findings$status[f$findings$check == "gaugings against the rating"],
                   "not assessed")
  expect_error(rating_follow_up(list()), "balance_diagnosis")
  expect_error(rating_follow_up(closes, gaugings = data.frame(a = 1)), "limbs table")
})

test_that("a question for the team is named in the verdict, not left to the table", {
  # 20% of the flow above the top makes the verdict more gaugings; a period no known rating
  # fits is a question for the team, and the verdict says so.
  above <- closes
  above$record$above_top_share <- 0.2
  record <- list(periods = data.frame(period = 1:2, assessed = TRUE,
                                      known_departing_share = c(0, 0.6)),
                 settings = list(known_fit_share = 0.05))
  f <- rating_follow_up(above, record_check = record,
                        gaugings = limbs(c(1, -2), c(0.95, 0.9), c(20, 15)))
  expect_identical(f$verdict, "get high-flow gaugings")
  expect_match(f$why, "Ask the hydrometry team too: record against the known ratings")
})

test_that("the candidate's band decides the refit in place of the rule of thumb", {
  # The rule of thumb flags the top limb (12% off, 15 gaugings), but the rating in force lies
  # inside the band everywhere: the gaugings cannot tell the two apart, so no refit, and the
  # limb is only noted.
  stages <- seq(0.3, 1.2, by = 0.1)
  inside <- data.frame(stage_m = stages, weight = 1, in_force_cms = 5,
                       lower_cms = 4.5, upper_cms = 5.5)
  f <- rating_follow_up(closes, gaugings = limbs(c(1, 12), c(0.95, 0.4), c(20, 15)),
                        band = inside)
  expect_false(f$verdict == "fit a candidate rating")
  expect_identical(f$findings$status[f$findings$check == "gaugings against the rating"][2],
                   "note")
  band_row <- f$findings[f$findings$check == "rating in force against the candidate's band", ]
  expect_identical(band_row$status, "fine")
  expect_match(band_row$finding, "for 0% of the flow")
  # Outside the band at the top six of ten stages, each weighted alike: 60% of the flow, over
  # the 10% allowed, so a refit is called for even with the limbs on the rule of thumb.
  outside <- inside
  outside$upper_cms[5:10] <- 4.9
  f <- rating_follow_up(closes, gaugings = limbs(c(1, -2), c(0.95, 0.9), c(20, 15)),
                        band = outside)
  expect_identical(f$verdict, "fit a candidate rating")
  expect_match(f$findings$finding[f$findings$check ==
                                    "rating in force against the candidate's band"],
               "for 60% of the flow")
  expect_error(rating_follow_up(closes, band = data.frame(a = 1)), "band needs")
})
