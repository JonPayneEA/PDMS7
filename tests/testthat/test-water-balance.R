# Tests for water_balance(): water-year totals, the Budyko limits, flags for single bad years and
# for lasting changes, gaps, and the plots.

balance_record <- function(years = 6) {
  rain <- synthetic_rain("2018-10-01", years = years, dt = 1, seed = 4)
  forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
  config <- pdm_presets("standard")
  config$area_km2 <- 20
  model <- pdm_from_config(config)
  flow <- run_pdm(model, forcing, initial_state_from_flow(model, 0.3, 0.7))$output$q_m3s
  list(forcing = forcing, flow = flow)
}

in_year <- function(time, ending) {
  time >= as.POSIXct(sprintf("%d-10-01", ending - 1), tz = "UTC") &
    time < as.POSIXct(sprintf("%d-10-01", ending), tz = "UTC")
}

# Guards: totals are right, a sound record raises no flag, and the baseflow index is a share
test_that("water_balance totals a sound record and flags nothing", {
  d <- balance_record()
  wb <- water_balance(d$forcing, d$flow, 20)
  expect_s3_class(wb, "pdm_water_balance")
  expect_equal(wb$years$period, as.character(2019:2024))
  expect_equal(sum(wb$years$rain_mm), sum(d$forcing$rain), tolerance = 1e-9)
  expect_equal(wb$record$flow_mm, sum(d$flow) * 3.6 / 20, tolerance = 1e-9)
  expect_equal(wb$record$runoff_ratio, wb$record$flow_mm / wb$record$rain_mm)
  expect_length(wb$flags, 0)
  expect_true(wb$bfi > 0 && wb$bfi < 1)
  expect_output(print(wb), "Nothing implausible")
})

# Guards: a rain gauge under-recording for one year flags that year alone, not a lasting change
test_that("one bad year is flagged on its own", {
  d <- balance_record()
  k <- in_year(d$forcing$time, 2021)
  d$forcing$rain[k] <- d$forcing$rain[k] * 0.45
  wb <- water_balance(d$forcing, d$flow, 20)
  expect_match(wb$years$flags[wb$years$period == "2021"], "flow above rain")
  expect_match(wb$years$flags[wb$years$period == "2021"], "apart from other years")
  expect_true(all(!nzchar(wb$years$flags[wb$years$period != "2021"])))
  expect_null(wb$change$message)
  expect_output(print(wb), "CHECK")
})

# Guards: a new rating from one year on leaves no single year apart, but is found as a change
test_that("a lasting change in the runoff ratio is found", {
  d <- balance_record()
  late <- d$forcing$time >= as.POSIXct("2021-10-01", tz = "UTC")
  d$flow[late] <- d$flow[late] * 1.5
  wb <- water_balance(d$forcing, d$flow, 20)
  expect_equal(wb$change$after_year, "2021")
  expect_gt(wb$change$change, 0.25)
  expect_true(any(grepl("changes after water year 2021", wb$flags)))
})

# Guards: missing flow leaves rain out too, so a gap is not a dry year; part years are not judged
test_that("gaps and part years are handled", {
  d <- balance_record(years = 4)
  k <- which(in_year(d$forcing$time, 2020))
  d$flow[k[1:2000]] <- NA
  wb <- water_balance(d$forcing, d$flow, 20)
  y <- wb$years[wb$years$period == "2020", ]
  expect_lt(y$complete, 0.9)
  expect_equal(y$flags, "incomplete")
  whole <- balance_record(years = 4)
  full <- water_balance(whole$forcing, whole$flow, 20)
  ratio <- full$years$runoff_ratio[full$years$period == "2020"]
  expect_equal(y$runoff_ratio, ratio, tolerance = 0.15)
  part <- water_balance(d$forcing[-(1:3000), ], d$flow[-(1:3000)], 20)
  expect_equal(part$years$flags[1], "incomplete")
  expect_error(water_balance(d$forcing[c("rain", "pet")], d$flow, 20), "time, rain and pet")
  expect_error(water_balance(d$forcing, d$flow[-1], 20), "as long as")
  expect_error(water_balance(d$forcing, d$flow, 20, water_year_start = 13), "month")
})

# Guards: the plots draw in both engines, with the limits and Fu's curve on the Budyko plot
test_that("water balance plots draw in both engines", {
  d <- balance_record(years = 4)
  wb <- water_balance(d$forcing, d$flow, 20)
  spec <- .balance_spec(wb, "budyko")
  limits <- spec$series[spec$series$label == "Limits: water and energy", ]
  expect_equal(limits$y, c(0, 1, 1))
  expect_equal(.fu(0), 0)
  expect_lt(.fu(5), 1)
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (type in c("budyko", "years", "double_mass")) expect_identical(plot(wb, type = type), wb)
  skip_if_not_installed("ggplot2")
  for (type in c("budyko", "years", "double_mass")) {
    expect_silent(ggplot2::ggplot_build(ggplot2::autoplot(wb, type = type)))
  }
})
