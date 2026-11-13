# Tests for gauge_response(): the gauge that drives the quick response is found, a late clock
# shows as a negative lag, a dry gauge is counted, and bad inputs are refused.

# A catchment whose fast zone sees gauge "town" and whose main zone sees "hill" and "moor".
gauge_river <- function() {
  make <- function(seed) synthetic_rain("2019-10-01", years = 1, dt = 1, seed = seed)
  common <- make(1)
  g <- data.frame(town = 0.5 * common$rain + 0.5 * make(2)$rain,
                  hill = 0.5 * common$rain + 0.5 * make(3)$rain,
                  moor = 0.5 * common$rain + 0.5 * make(4)$rain)
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 30
  two <- two_zone_config(cfg, share = 0.15)
  two$zones$fast$surface$kb <- 0.6
  m <- pdm_from_config(two)
  st <- initial_state_from_flow(m, 0.5, 0.7)
  main <- data.frame(time = common$time, rain = (g$hill + g$moor) / 2, pet = common$pet)
  fast <- data.frame(time = common$time, rain = g$town, pet = common$pet)
  q <- run_pdm(m@zones$main, main, st@states$main)$output$q_m3s +
    run_pdm(m@zones$fast, fast, st@states$fast)$output$q_m3s
  list(gauges = g, flow = q, time = common$time)
}

test_that("the gauge driving the quick response comes first", {
  r <- gauge_river()
  x <- gauge_response(r$gauges, r$flow, r$time, area_km2 = 30)
  expect_s3_class(x, "pdm_gauge_response")
  expect_identical(x$summary$gauge, c("town", "hill", "moor"))
  expect_identical(x$summary$gauge[which.max(x$summary$r)], "town")
  expect_true(all(x$summary$lag_h == 0))
  expect_lte(nrow(x$events), 20)
  expect_identical(sum(x$summary$event_wins), sum(!is.na(x$events$winner)))
  expect_true(all(c("town.rain_mm", "moor.r", "winner", "dry") %in% names(x$events)))
  expect_output(print(x), "3 gauges")
  expect_silent(plot(x))
})

test_that("a late clock shows as a negative lag", {
  r <- gauge_river()
  late <- r$gauges
  late$moor <- c(0, late$moor[-length(late$moor)])
  x <- gauge_response(late, r$flow, dt = 1)
  expect_identical(x$summary$lag_h[x$summary$gauge == "moor"], -1)
  expect_identical(x$summary$lag_h[x$summary$gauge == "town"], 0)
})

test_that("a gauge that missed the storms is counted dry", {
  r <- gauge_river()
  x0 <- gauge_response(r$gauges, r$flow, floods = 5)
  broken <- r$gauges
  for (e in seq_len(nrow(x0$events))) {
    ev <- find_events(rowMeans(r$gauges), r$flow)
    row <- ev[ev$event == x0$events$event[e], ]
    broken$hill[row$rain_start:row$rain_end] <- 0
  }
  x <- gauge_response(broken, r$flow, floods = 5,
                      events = find_events(rowMeans(r$gauges), r$flow))
  hill <- x$summary[x$summary$gauge == "hill", ]
  expect_identical(hill$dry_events, 5L)
  expect_identical(hill$event_wins, 0L)
})

test_that("missing readings are allowed and bad inputs refused", {
  r <- gauge_river()
  g <- r$gauges
  g$hill[100:400] <- NA
  expect_s3_class(gauge_response(g, r$flow), "pdm_gauge_response")
  expect_error(gauge_response(unname(as.matrix(g)), r$flow), "named column")
  expect_error(gauge_response(g, r$flow[-1]), "flow must match")
  expect_error(gauge_response(g, r$flow, floods = 0), "floods")
  expect_error(gauge_response(g, r$flow, lead_h = -1), "lead_h")
})
