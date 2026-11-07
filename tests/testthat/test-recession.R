# Tests for recession_analysis() and plot_recession().

recession_record <- function(store, recharge = list(type = "split", alpha = 0.6), years = 6) {
  r <- synthetic_rain("2000-10-01", years = years, dt = 1, seed = 5)
  forcing <- data.frame(rain = r$rain, pet = r$pet, time = r$time)
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 50
  cfg$groundwater <- store
  cfg$recharge <- recharge
  list(forcing = forcing, flow = run_pdm(pdm_from_config(cfg), forcing)$output$q_m3s)
}

# Guards: with no recharge between events, the slope recovers each store's theoretical value
test_that("the recession slope identifies stores that only drain", {
  linear <- recession_record(list(type = "linear", kb = 1500))
  a <- recession_analysis(linear$flow, linear$forcing$rain, dt = 1, boot = 50)
  expect_equal(a$slope, 1, tolerance = 0.1)
  expect_equal(a$nearest, "linear")
  expect_true(a$stores$within_ci[a$stores$store == "linear"])
  quadratic <- recession_record(list(type = "quadratic", kb = 30000))
  b <- recession_analysis(quadratic$flow, quadratic$forcing$rain, dt = 1, boot = 0)
  expect_equal(b$slope, 1.5, tolerance = 0.1)
  expect_equal(b$power_m, 1 / (2 - b$slope))
  expect_true(all(is.na(b$ci)))
})

# Guards: the points are falling, dry, and grouped into runs long enough to count
test_that("recession points are dry, falling and in long enough runs", {
  d <- recession_record(list(type = "linear", kb = 1500))
  a <- recession_analysis(d$flow, d$forcing$rain, dt = 1, time = d$forcing$time, boot = 0,
                          min_steps = 4, skip_steps = 1)
  expect_true(all(a$points$rate > 0))
  expect_true(all(table(a$points$run) >= 3))
  expect_s3_class(a$points$time, "POSIXct")
  winter <- recession_analysis(d$flow, d$forcing$rain, dt = 1, time = d$forcing$time,
                               boot = 0, months = c(11, 12, 1, 2))
  expect_true(all(as.integer(format(winter$points$time, "%m")) %in% c(11, 12, 1, 2)))
  expect_lt(nrow(winter$points), nrow(a$points))
  expect_output(print(a), "Recession slope")
})

# Guards: arguments are checked, and a record without recessions says so
test_that("recession_analysis checks its arguments", {
  d <- recession_record(list(type = "linear", kb = 1500), years = 2)
  expect_error(recession_analysis(d$flow, d$forcing$rain, dt = 1, aggregate_h = 1.5),
               "whole number")
  expect_error(recession_analysis(d$flow, d$forcing$rain[-1], dt = 1), "match flow")
  expect_error(recession_analysis(d$flow, d$forcing$rain, dt = 1, months = 1), "months needs")
  expect_error(recession_analysis(d$flow, rep(5, length(d$flow)), dt = 1), "Fewer than ten")
})

# Guards: the plot draws one or two analyses without error
test_that("plot_recession draws observed and simulated analyses", {
  d <- recession_record(list(type = "linear", kb = 1500), years = 3)
  a <- recession_analysis(d$flow, d$forcing$rain, dt = 1, boot = 20)
  b <- recession_analysis(d$flow * 1.1, d$forcing$rain, dt = 1, boot = 20)
  file <- tempfile(fileext = ".pdf")
  grDevices::pdf(file)
  on.exit({
    grDevices::dev.off()
    unlink(file)
  }, add = TRUE)
  expect_identical(plot_recession(a, b), a)
  expect_error(plot_recession(list()), "recession_analysis")
})
