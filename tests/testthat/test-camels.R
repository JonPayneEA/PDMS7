# ============================================================ #
# Tool:         test_camels
# Description:  CAMELS-GB v2 input: trimming to the rain years, filling short gaps, the
#               water-year windows, and the basin folders for a batch
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-19
# Modified:     2026-11-19 - First version
# Tier:         1
# Inputs:       Small synthetic tables built in each test
# Outputs:      testthat expectations
# Dependencies: testthat; yaml; data.table
# ============================================================ #

hours <- function(start, n) as.POSIXct(start, tz = "UTC") + 3600 * (seq_len(n) - 1)

camels_table <- function(start = "2001-01-01", n = 48, rain = rep(0.5, n)) {
  data.frame(time = hours(start, n), rain_mm = rain, rain_gradgb_mm = 0.6, pet_mm = 0.1,
             temperature_c = 6, flow_m3s = 2, flow_flag = "100")
}

test_that("the record is cut to the hours with rain", {
  # 48 hours; rain missing in the first 3 and the last 5, as when CEH-GEAR ends before the flow.
  # Kept: hours 4 to 43, 40 hours, starting at 03:00.
  t <- camels_table(rain = c(rep(NA, 3), rep(0.5, 40), rep(NA, 5)))
  x <- camels_forcing(t)
  expect_equal(nrow(x$forcing), 40)
  expect_equal(x$summary$start, as.POSIXct("2001-01-01 03:00", tz = "UTC"))
  expect_equal(x$summary$end, as.POSIXct("2001-01-02 18:00", tz = "UTC"))
  expect_equal(sum(x$forcing$rain), 40 * 0.5)
  expect_length(x$observed, 40)
  expect_equal(x$summary$years, 40 / 8766)
  # GradGB has no gaps, so its record is the whole 48 hours at 0.6 mm
  g <- camels_forcing(t, rain = "rain_gradgb_mm")
  expect_equal(sum(g$forcing$rain), 48 * 0.6)
  # Another evaporation product by its column: 40 kept hours at 0.2 mm
  t$pet_chess_mm <- 0.2
  expect_equal(sum(camels_forcing(t, pet = "pet_chess_mm")$forcing$pet), 40 * 0.2)
  expect_error(camels_forcing(t, pet = "peti_chess_mm"), "needs time, rain_mm, peti_chess_mm")
})

test_that("short gaps inside the rain years are filled and long ones stop", {
  # Two missing hours (11 and 12) between rain: zero rain when fill_gaps_h is 2 or more
  r <- rep(1, 24)
  r[11:12] <- NA
  t <- camels_table(n = 24, rain = r)
  expect_error(camels_forcing(t), "2 hours of rain missing.*longest run 2 hours")
  x <- camels_forcing(t, fill_gaps_h = 2)
  expect_equal(sum(x$forcing$rain), 22)
  expect_equal(x$summary$rain_filled_h, 2)
  # Evaporation interpolated: 0.1 and 0.4 either side of a gap of two give 0.2 and 0.3
  t$rain_mm <- 1
  t$pet_mm <- c(rep(0.1, 10), NA, NA, rep(0.4, 12))
  y <- camels_forcing(t, fill_gaps_h = 2)
  expect_equal(y$forcing$pet[11:12], c(0.2, 0.3))
  expect_equal(y$summary$pet_filled_h, 2)
})

test_that("flow gaps are kept and counted", {
  t <- camels_table(n = 40)
  t$flow_m3s[1:10] <- NA
  x <- camels_forcing(t)
  expect_equal(sum(is.na(x$observed)), 10)
  expect_equal(x$summary$flow_missing_pct, 25)   # 10 of 40 hours
})

test_that("tables that are not hourly are refused", {
  t <- camels_table()[-5, ]
  expect_error(camels_forcing(t), "hourly")
  expect_error(camels_forcing(camels_table()[, -2]), "needs time, rain_mm")
})

test_that("the CEH-GEAR years split into warm-up, calibration, validation and test", {
  # October 1990 09:00 to December 2016: the 1 Octobers inside are 1991 to 2016, 26 of them.
  # Warm-up to the 1st (1991), test from 4 before the last (2012), validation 5 before (2007).
  w <- camels_windows(as.POSIXct(c("1990-10-01 09:00", "2016-12-31 23:00"), tz = "UTC"))
  expect_equal(w$warmup, c("1990-10-01T09:00:00Z", "1991-09-30T23:00:00Z"))
  expect_equal(w$calibration, c("1991-10-01T00:00:00Z", "2007-09-30T23:00:00Z"))
  expect_equal(w$validation, c("2007-10-01T00:00:00Z", "2012-09-30T23:00:00Z"))
  expect_equal(w$test, c("2012-10-01T00:00:00Z", "2016-12-31T23:00:00Z"))
  # Two warm-up years and no test: calibration from 1992; validation ends at the last October
  v <- camels_windows(as.POSIXct(c("1990-10-01 09:00", "2016-12-31 23:00"), tz = "UTC"),
                      warmup_years = 2, test_years = 0)
  expect_equal(v$calibration, c("1992-10-01T00:00:00Z", "2011-09-30T23:00:00Z"))
  expect_equal(v$validation, c("2011-10-01T00:00:00Z", "2016-09-30T23:00:00Z"))
  expect_null(v$test)
  # Eight years cannot hold 1 + 5 + 5 + 4
  expect_error(camels_windows(as.POSIXct(c("2000-10-01", "2008-10-01"), tz = "UTC")),
               "Too short")
  expect_error(camels_windows(Sys.time() + c(0, 1e9), warmup_years = 0), "at least 1")
})

test_that("basin folders are written for the screened gauges and read by the batch", {
  # Mock Parquet with RDS, so the test needs neither arrow nor nanoparquet
  local_mocked_bindings(.read_parquet = function(path) readRDS(sub("parquet$", "rds", path)))
  store <- withr::local_tempdir()
  dir <- file.path(store, "gold", "camels_gb_v2")
  dir.create(file.path(dir, "hourly"), recursive = TRUE)
  # Water years 2000 to 2012 hourly: 1 Octobers 2001 to 2012 inside, 12 of them
  n <- as.numeric(difftime(as.POSIXct("2012-12-31 23:00", tz = "UTC"),
                           as.POSIXct("2000-10-01", tz = "UTC"), units = "hours")) + 1
  for (g in c("1001", "2002")) saveRDS(camels_table("2000-10-01", n), file.path(dir, "hourly",
                                                                             paste0(g, ".rds")))
  saveRDS(data.frame(gauge_id = c("1001", "2002"), gauge_name = c("A at B", "C at D"),
                     area = c(50, 80)), file.path(dir, "descriptors.rds"))
  data.table::fwrite(data.frame(gauge_id = c("1001", "2002", "3003"),
                                use = c("True", "False", "True")),
                     file.path(dir, "screening.csv"))
  basins <- file.path(store, "basins")
  out <- camels_batch_folders(store, basins, windows = list(validation_years = 3,
                                                            test_years = 2))
  # 1001 written; 2002 screened out; 3003 kept by the screening but has no table
  expect_equal(out$gauge, c("1001", "3003"))
  expect_equal(out$state, c("written", "failed"))
  expect_match(out$message[2], "No (file|positive area)")
  meta <- yaml::read_yaml(file.path(basins, "1001", "basin.yml"))
  expect_equal(meta$area_km2, 50)
  expect_equal(meta$catchment, "A at B")
  # 1 Octobers 2001 to 2012: calibration from 2001, validation 2007 to 2010, test from 2010
  expect_equal(meta$calibration, c("2001-10-01T00:00:00Z", "2007-09-30T23:00:00Z"))
  expect_equal(meta$test, c("2010-10-01T00:00:00Z", "2012-12-31T23:00:00Z"))
  f <- data.table::fread(file.path(basins, "1001", "forcing.csv"))
  expect_equal(nrow(f), n)
  expect_equal(names(f), c("time", "rain", "pet", "temperature"))
  q <- data.table::fread(file.path(basins, "1001", "flow.csv"))
  expect_equal(names(q), c("time", "q_m3s", "flag"))
  # A second call leaves the written folder alone
  again <- camels_batch_folders(store, basins, gauges = "1001")
  expect_equal(again$state, "kept")
  # The batch's own reader accepts the folder
  expect_silent(pdmS7:::.basin_meta("1001", list(basins = basins)))
})

test_that("Parquet tables written by the pipeline are read", {
  skip_if_not_installed("arrow")
  store <- withr::local_tempdir()
  dir <- file.path(store, "gold", "camels_gb_v2", "hourly")
  dir.create(dir, recursive = TRUE)
  arrow::write_parquet(camels_table(), file.path(dir, "1001.parquet"))
  t <- camels_read(store, "1001")
  expect_equal(nrow(t), 48)
  expect_equal(attr(t$time, "tzone"), "UTC")
})
