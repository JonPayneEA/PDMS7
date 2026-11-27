# ============================================================ #
# Tool:         test-balance-diagnosis
# Description:  balance_diagnosis() sets the gap against Fu's range and the rain's and the
#               flow's bounds, tells floods above the top of the rating from those below, dates
#               a change, and ranks the suspects as each case is built to show
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-27
# Tier:         1
# Inputs:       Four calendar years of daily synthetic rain, evaporation and flow
# Outputs:      None
# Dependencies: testthat
# ============================================================ #

# Four calendar years, daily. Rain 1 to 7 mm a day in a weekly cycle (mean 4, so about
# 1,461 mm a year), potential evaporation 1.5 mm a day (about 548), and flow set in mm a day,
# turned into m3/s on 100 km2 (1 mm a day is 100 / 86.4 m3/s). At an aridity of 0.375, Fu's
# curve allows flow of about 926 mm a year (w = 3.5) to 1,129 (w = 1.5): 2.5 to 3.1 mm a day.
days <- seq(as.POSIXct("2020-01-01", tz = "UTC"), as.POSIXct("2023-12-31", tz = "UTC"),
            by = 86400)
rain <- (seq_along(days) %% 7) + 1
pet <- rep(1.5, length(days))
as_flow <- function(mm_a_day) rep(mm_a_day, length.out = length(days)) * 100 / 86.4

# Fu's flow for rain P and evaporation E with parameter w, written out.
fu_flow <- function(P, E, w) P - P * (1 + E / P - (1 + (E / P)^w)^(1 / w))

# Sixteen floods, each a rain window of 2 to 9 days: quick flow 0.1 x rain^1.3 (a runoff ratio
# of 0.1 x rain^0.3, exactly a power law of rain). Peaks rise with the window, so the last four
# are the largest.
make_floods <- function(boost_top = 1) {
  starts <- seq(10, by = 80, length.out = 16)
  lengths <- rep(2:9, 2)
  ends <- starts + lengths - 1
  event_rain <- vapply(seq_along(starts), function(e) sum(rain[starts[e]:ends[e]]), 0)
  peak <- seq(5, 20, length.out = 16)
  ratio <- 0.1 * event_rain^0.3 * ifelse(peak > 16, boost_top, 1)
  data.frame(rain_start = starts, rain_end = ends, peak_row = ends + 1, peak_flow = peak,
             quickflow_mm = ratio * event_rain)
}

whole_years <- function(d) d$gap$years

test_that("flow below Fu's range with the rain at its lowest is a slow loss, by the formula", {
  # Flow 0.3 mm a day. The second series is 10% higher, so the reference is the lowest: the
  # rain cannot be too high, and the whole gap is left for a slow loss.
  flow <- as_flow(0.3)
  d <- balance_diagnosis(days, flow, list(ref = rain, other = 1.1 * rain), pet, 100,
                         make_floods(), water_year_start = 1)
  expect_identical(whole_years(d), 4L)
  P <- mean(tapply(rain, format(days, "%Y"), sum))
  E <- mean(tapply(pet, format(days, "%Y"), sum))
  Q <- mean(tapply(rep(0.3, length(days)), format(days, "%Y"), sum))
  expect_equal(d$gap$gap_mm, fu_flow(P, E, 3.5) - Q)
  expect_identical(d$gap$kind, "deficit")
  expect_equal(d$gap$rain_could_be_high_mm, 0)
  expect_equal(d$gap$left_after_bounds_mm, d$gap$gap_mm)
  expect_identical(d$suspects$suspect[1], "slow loss (groundwater out, abstraction, area too large)")
  expect_identical(d$suspects$verdict[1], "likely")
  expect_identical(d$suspects$verdict[d$suspects$suspect == "rain"], "unlikely")
})

test_that("rain too high by enough to close the gap makes rain the likely cause", {
  # Flow 2 mm a day (730 a year), below Fu's least. The other series is 30% lower than the
  # reference: the rain could be too high by 0.3 P, and Fu's least flow at 0.7 P (about 506)
  # is below the observed flow, so the gap closes.
  flow <- as_flow(2)
  d <- balance_diagnosis(days, flow, list(ref = rain, other = 0.7 * rain), pet, 100,
                         make_floods(), water_year_start = 1)
  P <- d$gap$rain_mm
  expect_equal(d$gap$rain_could_be_high_mm, 0.3 * P)
  expect_lte(fu_flow(0.7 * P, d$gap$pet_mm, 3.5), d$gap$flow_mm)
  expect_equal(d$gap$gap_after_rain_mm, 0)
  expect_identical(d$suspects$verdict[d$suspects$suspect == "rain"], "likely")
  expect_identical(d$suspects$verdict[grepl("^slow loss", d$suspects$suspect)], "possible")
})

test_that("flow above Fu's range is a slow gain, and under-catch alone cannot close it", {
  # Flow 3.5 mm a day against rain of 4: far above Fu's most at w = 1.5. Rain too low by up
  # to 5% of P (under-catch; the reference is the highest series) does not reach it.
  d <- balance_diagnosis(days, as_flow(3.5), list(ref = rain, other = 0.95 * rain), pet, 100,
                         make_floods(), water_year_start = 1)
  P <- d$gap$rain_mm
  E <- d$gap$pet_mm
  expect_identical(d$gap$kind, "excess")
  expect_equal(d$gap$gap_mm, d$gap$flow_mm - fu_flow(P, E, 1.5))
  expect_equal(d$gap$rain_could_be_low_mm, 0.05 * P)
  expect_equal(d$gap$gap_after_rain_mm, d$gap$flow_mm - fu_flow(1.05 * P, E, 1.5))
  expect_identical(d$suspects$suspect[1], "slow gain (groundwater in, effluent, area too small)")
  expect_identical(d$suspects$verdict[1], "likely")
})

test_that("flow inside Fu's range closes, and nothing is suspected", {
  # Flow 2.8 mm a day, about 1,022 a year: inside 926 to 1,129.
  d <- balance_diagnosis(days, as_flow(2.8), list(ref = rain), pet, 100, make_floods(),
                         water_year_start = 1)
  expect_identical(d$gap$kind, "closes")
  expect_equal(d$gap$gap_mm, 0)
  expect_true(all(d$suspects$verdict == "unlikely"))
})

test_that("floods above the top of the rating with 30% more runoff count against the rating", {
  # The floods below the top follow log ratio = log 0.1 + 0.3 log rain exactly, so the fit is
  # exact and each flood above sits log 1.3 above it: an excess of 0.3. A rise of ratio with
  # peak alone is not counted: without the top, the same floods leave the rating unlikely.
  floods <- make_floods(boost_top = 1.3)
  d <- balance_diagnosis(days, as_flow(0.3), list(ref = rain), pet, 100, floods,
                         water_year_start = 1, top_flow = 16)
  expect_identical(d$flood_summary$floods_above_top, 4L)
  expect_equal(d$flood_summary$above_top_excess, 0.3)
  expect_identical(d$suspects$verdict[d$suspects$suspect == "rating"], "likely")
  # With the rating suspected, a slow loss is only possible.
  expect_identical(d$suspects$verdict[grepl("^slow loss", d$suspects$suspect)], "possible")
  untested <- balance_diagnosis(days, as_flow(0.3), list(ref = rain), pet, 100, floods,
                                water_year_start = 1)
  expect_identical(untested$suspects$verdict[untested$suspects$suspect == "rating"], "unlikely")
  expect_match(untested$suspects$evidence[untested$suspects$suspect == "rating"],
               "top of the rating was not given")
})

# A record check as reach.rate::check_flow_record() returns it, with only what is read.
record_stub <- function(revisions = as.POSIXct(character(0), tz = "UTC"), raised = 0.2,
                        lowered = -0.2) {
  list(revisions = data.frame(time = revisions, kind = rep("stage shift", length(revisions))),
       periods = data.frame(period = 1L, assessed = TRUE),
       steps = data.frame(period = 1L, discharge_cms = 1),
       off_curve = data.frame(volume_m3 = numeric(0)),
       above = structure(data.frame(limit = character(0)), shares = c(top = NA, bankfull = NA)),
       stage_error = data.frame(year = "all", band = "all", share_raised = raised,
                                share_lowered = lowered),
       dry_rises = NULL, curves = list(),
       settings = list(step_seconds = 86400, stage_uncertainty_m = 0.01,
                       dry_rise_m_per_day = 0.001))
}

test_that("a stage error that could close the gap makes the rating likely", {
  # Flow 2.3 mm a day (840 a year): a small deficit below Fu's least (926). A stage error
  # moving the flow up by 20% (to 1,008) closes it: max(fu_flow(P, E, 3.5) - 1.2 Q, 0) = 0.
  d <- balance_diagnosis(days, as_flow(2.3), list(ref = rain), pet, 100, make_floods(),
                         water_year_start = 1, record_check = record_stub())
  expect_identical(d$gap$kind, "deficit")
  expect_equal(d$gap$flow_could_be_low_mm, 0.2 * d$gap$flow_mm)
  expect_equal(d$gap$gap_after_flow_mm,
               max(fu_flow(d$gap$rain_mm, d$gap$pet_mm, 3.5) - 1.2 * d$gap$flow_mm, 0))
  expect_equal(d$gap$gap_after_flow_mm, 0)
  expect_identical(d$suspects$verdict[d$suspects$suspect == "rating"], "likely")
})

test_that("a lasting change is dated and matched to a rating revision", {
  # Flow 2.4 mm a day for two years, then 3.84: the runoff ratio rises 60% after 2021. Both
  # are high enough that no year loses more than its potential evaporation, which would flag
  # the year and leave it out of the search for a change.
  flow <- as_flow(ifelse(days < as.POSIXct("2022-01-01", tz = "UTC"), 2.4, 3.84))
  rev <- as.POSIXct("2022-01-01", tz = "UTC")
  d <- balance_diagnosis(days, flow, list(ref = rain), pet, 100, make_floods(),
                         water_year_start = 1, record_check = record_stub(rev))
  expect_identical(d$change$after_year, "2021")
  change <- d$suspects[d$suspects$suspect == "change over time", ]
  expect_identical(change$verdict, "likely")
  expect_match(change$evidence, "revised then (2022-01-01)", fixed = TRUE)
  expect_match(d$suspects$evidence[d$suspects$suspect == "rating"], "revised 1 time")
})

test_that("bad inputs are refused", {
  floods <- make_floods()
  expect_error(balance_diagnosis(days, as_flow(1), list(rain), pet, 100, floods), "named list")
  expect_error(balance_diagnosis(days, as_flow(1)[-1], list(ref = rain), pet, 100, floods),
               "flow must be numeric")
  expect_error(balance_diagnosis(days, as_flow(1), list(ref = rain), pet, 100,
                                 floods[, -5]), "quickflow_mm")
  expect_error(balance_diagnosis(days, as_flow(1), list(ref = rain), pet, 100, floods,
                                 reference = "none"), "reference")
  expect_error(balance_diagnosis(days, as_flow(1), list(ref = rain), pet, 100, floods,
                                 omega = c(3, 2)), "omega")
  expect_error(balance_diagnosis(days, as_flow(1), list(ref = rain), pet, 100, floods,
                                 record_check = list(a = 1)), "check_flow_record")
})

test_that("without a complete year the balance is not judged, but the rating's evidence is", {
  # Two months: storage moves water about over so short a time, so no gap is judged. The
  # floods above the top of the rating still count against it.
  short <- days < as.POSIXct("2020-03-01", tz = "UTC")
  floods <- make_floods(boost_top = 1.3)
  floods <- floods[floods$rain_end < sum(short), ]
  floods$peak_flow <- seq(5, 20, length.out = nrow(floods))
  d <- balance_diagnosis(days[short], as_flow(2)[short], list(ref = rain[short]), pet[short],
                         100, floods, water_year_start = 1)
  expect_identical(d$gap$kind, "not assessed")
  expect_identical(d$suspects$verdict[d$suspects$suspect == "rain"], "not assessed")
  expect_identical(d$suspects$verdict[grepl("^slow", d$suspects$suspect)], "not assessed")
  expect_output(print(d), "not judged")
})

test_that("a dry-weather rise counts against the rating in summer, not in winter", {
  # Stage rising in dry July is weed's mark; in dry January, groundwater still answering
  # earlier rain. Only the summer month makes the rating possible.
  stub <- function(months) {
    r <- record_stub(raised = NA, lowered = NA)
    r$stage_error <- NULL
    r$dry_rises <- data.frame(month = months, stage_change_m_per_day = 0.005)
    r
  }
  winter <- balance_diagnosis(days, as_flow(2.8), list(ref = rain), pet, 100, make_floods(),
                              water_year_start = 1, record_check = stub("2021-01"))
  rating <- winter$suspects[winter$suspects$suspect == "rating", ]
  expect_identical(rating$verdict, "unlikely")
  expect_match(rating$evidence, "dry winter weather in 2021-01")
  summer <- balance_diagnosis(days, as_flow(2.8), list(ref = rain), pet, 100, make_floods(),
                              water_year_start = 1, record_check = stub("2021-07"))
  rating <- summer$suspects[summer$suspects$suspect == "rating", ]
  expect_identical(rating$verdict, "possible")
  expect_match(rating$evidence, "dry summer weather in 2021-07")
})

test_that("the rating's own band is a flow bound, combined with the stage error", {
  # Flow 2.3 mm a day (840 a year), below Fu's least (926). No stage error, but the rating's
  # band says the flow could be 15% higher: 1.15 x 840 = 966 clears 926, so the rating alone
  # could close the gap.
  d <- balance_diagnosis(days, as_flow(2.3), list(ref = rain), pet, 100, make_floods(),
                         water_year_start = 1, rating_band = c(-0.05, 0.15))
  expect_equal(d$gap$flow_could_be_low_mm, 0.15 * d$gap$flow_mm)
  expect_equal(d$gap$rating_could_be_low_mm, 0.15 * d$gap$flow_mm)
  expect_equal(d$gap$gap_after_flow_mm, 0)
  expect_identical(d$suspects$verdict[d$suspects$suspect == "rating"], "likely")
  expect_match(d$suspects$evidence[d$suspects$suspect == "rating"], "sampling uncertainty")
  # With a stage error of 10% as well, the two independent: sqrt(0.1^2 + 0.1^2) of the flow.
  both <- balance_diagnosis(days, as_flow(2.3), list(ref = rain), pet, 100, make_floods(),
                            water_year_start = 1, rating_band = c(-0.1, 0.1),
                            record_check = record_stub(raised = 0.1, lowered = -0.1))
  expect_equal(both$gap$flow_could_be_low_mm, sqrt(0.02) * both$gap$flow_mm)
  expect_equal(both$gap$flow_could_be_high_mm, sqrt(0.02) * both$gap$flow_mm)
  expect_error(balance_diagnosis(days, as_flow(2.3), list(ref = rain), pet, 100, make_floods(),
                                 rating_band = c(0.1, 0.2)), "rating_band")
})
