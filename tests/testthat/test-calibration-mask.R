# The calibration mask and the peak tolerance (calibration-mask-design.md). Expected values come
# from the dead band's closed form and from hand counts.

test_that("the dead band: inside scores as the observed, outside from the nearer edge", {
  band <- data.frame(lower = rep(-0.1, 6), upper = rep(0.2, 6))
  obs <- c(10, 10, 10, 10, 10, NA)
  # Inside (11), on the upper edge (12), above (13: 13 - 10 x 0.2 = 11), on the lower edge (9),
  # below (8: 8 + 10 x 0.1 = 9), and a missing observation left as it is.
  expect_equal(tolerate(c(11, 12, 13, 9, 8, 7), obs, band), c(10, 10, 11, 10, 9, 7))
  # A zero band changes nothing.
  zero <- data.frame(lower = rep(0, 6), upper = rep(0, 6))
  expect_equal(tolerate(c(11, 12, 13, 9, 8, 7), obs, zero), c(11, 12, 13, 9, 8, 7))
})

test_that("the band is interpolated on log flow, scaled and capped", {
  band <- data.frame(q = c(1, 100), lower = c(-0.1, -0.3), upper = c(0.1, 0.8))
  # At 10 m3/s, halfway in log flow: lower -0.2, upper 0.45; times 0.5: -0.1 and 0.225.
  b <- peak_band(c(1, 10, 100, NA), band)
  expect_equal(b$lower, c(-0.05, -0.1, -0.15, 0))
  expect_equal(b$upper, c(0.05, 0.225, 0.4, 0))
  expect_identical(attr(b, "capped"), 0L)
  # The full band twice over at 100 m3/s: 1.6, capped at 0.5; and beyond the table, held flat.
  b2 <- peak_band(c(100, 1000), band, factor = 2)
  expect_equal(b2$upper, c(0.5, 0.5))
  expect_identical(attr(b2, "capped"), 2L)
  expect_equal(peak_band(c(1, 100), band, factor = 0)$upper, c(0, 0))
  expect_error(peak_band(1, data.frame(q = 1, lower = 0.1, upper = 0.1)), "lower 0 or below")
})

test_that("the mask leaves out the periods given, inclusive, and the quality codes asked for", {
  time <- seq(as.POSIXct("2020-01-01", tz = "UTC"), by = "hour", length.out = 48)
  quality <- rep("Good", 48)
  quality[c(30, 31)] <- "Suspect"
  quality[40] <- "Estimated"
  periods <- data.frame(from = "2020-01-01 06:00", to = "2020-01-01 11:00",
                        reason = "flow off the applied rating")
  # Hours 6 to 11 inclusive are steps 7 to 12: 6 steps.
  m <- calibration_mask(time, periods)
  expect_identical(which(!m$keep), 7:12)
  expect_equal(m$share, 6 / 48)
  # The quality codes only when asked: Suspect adds steps 30 and 31.
  expect_identical(which(!calibration_mask(time, periods, quality)$keep), 7:12)
  mq <- calibration_mask(time, periods, quality, mask_quality = "Suspect")
  expect_identical(which(!mq$keep), c(7:12, 30L, 31L))
  expect_identical(mq$masked$reason, c("flow off the applied rating", "quality code Suspect"))
  expect_identical(mq$masked$steps, c(6L, 2L))
  # The share is of the calibration window: within the first 24 steps, 6 of 24.
  within <- seq_len(48) <= 24
  expect_equal(calibration_mask(time, periods, within = within)$share, 0.25)
})

test_that("masking more than a quarter of the window warns, and nothing given masks nothing", {
  time <- seq(as.POSIXct("2020-01-01", tz = "UTC"), by = "hour", length.out = 40)
  # 11 of 40 steps: 27.5%.
  big <- data.frame(from = "2020-01-01 00:00", to = "2020-01-01 10:00", reason = "by hand")
  expect_warning(calibration_mask(time, big), "leaves out 28%")
  # The rule that high flows are never masked: the mask does not look at the flow at all, so a
  # record with no periods and no codes asked for masks nothing, however high its peaks.
  expect_true(all(calibration_mask(time)$keep))
  expect_error(calibration_mask(time, data.frame(from = "x", to = "y")), "times")
})

test_that("calibrate_pdm scores only what the mask keeps, and a zero band changes nothing", {
  # A one-parameter search with lower and upper a hair apart, so the fit is fixed and the
  # objective is the model's RMSE over the scored steps, worked out here directly.
  forcing <- make_forcing() # nolint: object_usage_linter.
  config <- pdm_presets("standard")
  truth <- config
  truth$fc <- 1.2
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s
  n <- length(observed)
  lower <- c(fc = 1)
  upper <- c(fc = 1 + 1e-9)
  run <- function(...) {
    calibrate_pdm(config, forcing, observed, lower, upper, objective = "rmse", start = "soil",
                  control = list(maxit = 3), ...)
  }
  sim <- run_pdm(pdm_from_config(config), forcing,
                 pdmS7:::.start_state(pdm_from_config(config), "soil", observed[1], 0.7,
                                      0.5))$output$q_m3s
  plain <- run()
  expect_equal(plain$objective, sqrt(mean((sim - observed)^2)), tolerance = 1e-6)
  # Half the steps masked: the RMSE over the other half.
  mask <- seq_len(n) %% 2 == 0
  half <- run(mask = mask)
  expect_equal(half$objective, sqrt(mean((sim[mask] - observed[mask])^2)), tolerance = 1e-6)
  expect_identical(half$scoring$masked_steps, sum(!mask))
  # A zero band and a mask of all TRUE: the same objective, to the last digit.
  zero <- data.frame(lower = rep(0, n), upper = rep(0, n))
  same <- run(mask = rep(TRUE, n), band = zero)
  expect_identical(same$objective, plain$objective)
  # A band wide enough to hold every simulated flow scores as a perfect fit.
  wide <- data.frame(lower = rep(-0.99, n), upper = rep(10, n))
  expect_equal(run(band = wide)$objective, 0)
  expect_error(run(mask = mask[-1]), "TRUE or FALSE for each observed flow")
})

test_that("an event whose peak is masked is dropped whole; one masked in its recession is kept", {
  observed <- c(1, 1, 5, 9, 6, 3, 1, 1, 4, 8, 5, 2, 1, 1)
  events <- data.frame(flow_start = c(2, 8), flow_end = c(7, 13))
  rain <- rep(0, length(observed))
  win <- function(mask) {
    pdmS7:::.event_windows(events, rain, observed, warmup = 0, dt = 1, share = 1,
                           screen = NULL, area_km2 = NULL, mask = mask)$windows
  }
  # No mask: two windows, rows 2 to 7 and 8 to 13.
  expect_identical(lapply(win(NULL), as.integer), list(2:7, 8:13))
  # The first event's peak (row 4) masked: that event is gone. The second's recession (row 12)
  # masked: it keeps its other rows.
  mask <- rep(TRUE, length(observed))
  mask[c(4, 12)] <- FALSE
  expect_identical(lapply(win(mask), as.integer), list(c(8:11, 13L)))
})

test_that("a project registers the mask and the tolerance, and every search scores by them", {
  folder <- tempfile("mask-")
  defer_to(function() unlink(folder, recursive = TRUE), environment()) # nolint: object_usage_linter.
  as_person("Ann Custodian", "custodian", "ann") # nolint: object_usage_linter.
  d <- log_data() # nolint: object_usage_linter.
  start_calibration_project(folder, "Test", "1", "Testing", 20, "Owner", "Steward")
  time <- d$forcing$time
  # Ten hours of the calibration window, rows 300 to 309, left out by hand. (Rows 200 to 210 of
  # this record are missing already, so they would add nothing.)
  m <- calibration_mask(time, data.frame(from = time[300], to = time[309], reason = "by hand"))
  band <- data.frame(q = c(0.1, 10), lower = c(-0.1, -0.2), upper = c(0.1, 0.3))
  register_data(folder, d$forcing, d$observed, calibration = c(121, 700),
                validation = c(701, nrow(d$forcing)), wettest_years = 0, mask = m,
                peak_tolerance = list(band = band, factor = 0.5, cap = 0.5,
                                      source = "test band", reason = "a test"))
  card <- pdmS7:::.registration(pdmS7:::.read_entries(pdmS7:::.project_path(folder)))$scorecard
  # The mask is stored as one run, rows 300 to 309, with its reason; the tolerance as given.
  expect_identical(as.integer(unlist(card$mask$first_row)), 300L)
  expect_identical(as.integer(unlist(card$mask$last_row)), 309L)
  expect_identical(unlist(card$mask$reason), "by hand")
  expect_identical(card$peak_tolerance$factor, 0.5)
  expect_identical(card$peak_tolerance$source, "test band")
  sc <- pdmS7:::.card_scoring(card, d$observed, 700)
  expect_identical(which(!sc$mask), 300:309)
  expect_equal(sc$band, peak_band(d$observed[seq_len(700)], band, 0.5, 0.5),
               ignore_attr = TRUE)
  # An automatic calibration records what its score left out: the ten rows.
  start <- d$truth
  start$fc <- 0.9
  parent <- select_structure(folder, start, "Start.")$id
  e <- log_auto_calibration(folder, parent, lower = c(fc = 0.8), upper = c(fc = 1.2),
                            objective = "nse", control = list(maxit = 5), reasoning = "Test.")
  expect_identical(as.integer(e$scoring$masked_steps), 10L)
  expect_true(isTRUE(e$scoring$peak_tolerance))
})
