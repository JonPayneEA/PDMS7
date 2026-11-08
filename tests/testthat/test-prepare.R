# Tests for data preparation: read_hydro_series(), align_series(), convert_units(),
# fill_gaps(), zero_negatives(), preparation_notes(), check_inputs(), and the notes reaching the
# log through register_data().

write_csv <- function(lines) {
  f <- tempfile(fileext = ".csv")
  writeLines(lines, f)
  f
}

# Guards: the layouts of hydrometric exports are read, in UTC, with the value column found
test_that("read_hydro_series reads split, single and paired time columns", {
  split <- read_hydro_series(write_csv(c(
    "Year,Months,Day,Hours,Min,Flow", "2021,3,1,9,0,1.2", "2021,3,1,9,15,1.3", "2021,3,1,9,30,"
  )))
  expect_s3_class(split, "pdm_hydro_series")
  expect_equal(split$time[2], as.POSIXct("2021-03-01 09:15", tz = "UTC"))
  expect_equal(split$value, c(1.2, 1.3, NA), ignore_attr = TRUE)
  expect_equal(attr(split, "source")$step_minutes, 15)
  expect_match(preparation_notes(split$value)$detail, "3 rows")
  iso <- read_hydro_series(write_csv(c("datetime,stage,q", "2021-03-01T09:00:00Z,0.3,2",
                                       "2021-03-01T09:15:00Z,0.3,2.5")))
  expect_equal(iso$value, c(2, 2.5), ignore_attr = TRUE)
  named <- read_hydro_series(write_csv(c("datetime,stage,q", "01/03/2021 09:00,0.3,2",
                                         "01/03/2021 09:15,0.4,2.5")), value_col = "stage")
  expect_equal(named$value, c(0.3, 0.4), ignore_attr = TRUE)
  paired <- read_hydro_series(write_csv(c("date,time,rain", "2021-03-01,23:45,0.2",
                                          "2021-03-02,00:00,0.4")))
  expect_equal(format(paired$time, "%d %H:%M"), c("01 23:45", "02 00:00"))
  bst <- read_hydro_series(write_csv(c("time,q", "2021-07-01 12:00,1", "2021-07-01 12:15,1")),
                           tz = "Europe/London")
  expect_equal(bst$time[1], as.POSIXct("2021-07-01 11:00", tz = "UTC"))
  expect_output(print(split), "3 rows")
})

# Guards: a file whose times repeat or cannot be read is refused, not half-read
test_that("read_hydro_series refuses repeated or unreadable times", {
  daily <- c("date,hour,q", paste0("2021-03-01,", 0:3, ",1"), paste0("2021-03-02,", 0:3, ",1"))
  expect_error(read_hydro_series(write_csv(daily), time_col = "date"), "repeat")
  expect_error(read_hydro_series(write_csv(c("time,q", "soon,1", "later,2"))), "Cannot read")
  expect_error(read_hydro_series("no-such-file.csv"), "not found")
})

# Guards: alignment keeps the shared period, leaves missing steps missing and notes coarse steps
test_that("align_series puts series on one grid", {
  t <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 900, length.out = 12)
  rain <- data.frame(time = t, value = 1:12)
  flow <- data.frame(time = t[c(2:6, 8:11)], value = 1:9)
  hourly <- data.frame(time = t[c(1, 5, 9)], value = c(1, 2, 3))
  a <- align_series(rain = rain, flow = flow)
  expect_equal(a$time, t[2:11])
  expect_equal(a$rain, 2:11, ignore_attr = TRUE)
  expect_equal(sum(is.na(a$flow)), 1)
  expect_match(preparation_notes(a)$detail[2], "1 of 10 steps missing")
  b <- align_series(rain = rain, hourly = hourly, dt = 0.25)
  expect_match(utils::tail(preparation_notes(b$hourly)$detail, 1), "recorded every 1 h")
  expect_error(align_series(rain), "name = series")
  expect_error(align_series(a = rain, b = data.frame(time = t + 86400, value = 1)), "share no")
})

# Guards: each unit converts by the right factor, and auto names only a unit it can prove
test_that("convert_units converts and guesses units", {
  expect_equal(convert_units(c(0, 4), "mm_per_hour", 0.25, "rain"), c(0, 1), ignore_attr = TRUE)
  expect_equal(convert_units(48, "mm_per_day", 0.5, "pet"), 1, ignore_attr = TRUE)
  expect_equal(convert_units(0.002, "m_per_step", 1, "rain"), 2, ignore_attr = TRUE)
  expect_equal(convert_units(1500, "ls", 1, "flow"), 1.5, ignore_attr = TRUE)
  expect_equal(convert_units(86.4, "mld", 1, "flow"), 1, ignore_attr = TRUE)
  per_step <- rep(c(0, 0, 0, 0.12), 365 * 24)          # about 1,050 mm a year at 15 minutes
  r <- convert_units(per_step, "auto", 0.25, "rain")
  expect_equal(r, per_step, ignore_attr = TRUE)
  expect_match(preparation_notes(r)$detail, "worked out: 1052 mm a year as mm_per_step")
  per_hour <- per_step * 4
  expect_match(preparation_notes(convert_units(per_hour, "auto", 0.25, "rain"))$detail,
               "as mm_per_hour")
  expect_error(convert_units(rep(50, 100), "auto", 0.25, "rain"), "Cannot tell")
  expect_match(preparation_notes(convert_units(rep(400, 5), "auto", 1, "flow"))$detail,
               "from ls")
  expect_error(convert_units(1, "ls", 1, "rain"), "from must be one of")
})

# Guards: every gap rule does what it says, and notes the gaps and what it filled
test_that("fill_gaps applies its rules and notes them", {
  x <- c(1, NA, NA, 4, NA, 6, NA, NA, NA, NA, 11)
  time <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600, length.out = 11)
  expect_error(fill_gaps(x, "stop", time, "rain"), "2021-01-01 06:00 for 4 steps")
  expect_equal(fill_gaps(x, "zero"), c(1, 0, 0, 4, 0, 6, 0, 0, 0, 0, 11), ignore_attr = TRUE)
  short <- fill_gaps(x, "interpolate", label = "pet", max_gap_h = 2)
  expect_equal(short[1:6], 1:6, ignore_attr = TRUE)
  expect_true(all(is.na(short[7:10])))
  expect_match(preparation_notes(short)$detail, "7 missing steps in 3 gaps.*3 filled, 4 left")
  expect_equal(fill_gaps(x, "interpolate"), 1:11, ignore_attr = TRUE)
  expect_match(preparation_notes(fill_gaps(1:3))$detail, "no gaps")
  expect_match(preparation_notes(fill_gaps(x, "none"))$detail, "0 filled, 7 left")
})

# Guards: negatives become zero, with a note; clean series pass untouched
test_that("zero_negatives zeroes and notes", {
  z <- zero_negatives(c(0.2, -0.01, 0.5, -0.03), "rain")
  expect_equal(z, c(0.2, 0, 0.5, 0), ignore_attr = TRUE)
  expect_match(preparation_notes(z)$detail, "2 negative values \\(smallest -0.03, total -0.04\\)")
  expect_null(attr(zero_negatives(1:3), "pdm_prep"))
})

# Guards: the input check flags implausible totals, gaps, negative rain and runoff ratios
test_that("check_inputs reports totals, ratios and flags", {
  n <- 24 * 365
  forcing <- data.frame(time = seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600,
                                   length.out = n),
                        rain = rep(c(0, 0, 0, 0.45), n / 4), pet = 0.06)
  ok <- check_inputs(forcing, observed = rep(0.3, n), area_km2 = 20)
  expect_s3_class(ok, "pdm_input_check")
  expect_equal(ok$table$annual[1], 0.1125 * 8766, tolerance = 1e-9)
  expect_equal(ok$runoff_ratio, 0.3 * 3.6 * 8766 / 20 / (0.1125 * 8766), tolerance = 1e-9)
  expect_length(ok$flags, 0)
  expect_output(print(ok), "Nothing implausible")
  bad <- forcing
  bad$rain <- bad$rain * 8
  bad$rain[5] <- NA
  bad$rain[9] <- -1
  flagged <- check_inputs(bad, observed = rep(30, n), area_km2 = 20)
  expect_true(any(grepl("rain totals", flagged$flags)))
  expect_true(any(grepl("gaps", flagged$flags)))
  expect_true(any(grepl("negative", flagged$flags)))
  expect_true(any(grepl("runoff is", flagged$flags)))
  expect_output(print(flagged), "CHECK:")
  expect_error(check_inputs(forcing[c("rain", "pet")]), "Give dt")
})

# Guards: the notes on prepared series are written into the registration entry and reported,
# and unprepared data register exactly as before
test_that("register_data records preparation notes in the log", {
  folder <- tempfile("prep-")
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  as_person("Ann Custodian", "custodian", "ann")
  n <- 24 * 60
  time <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600, length.out = n)
  rain <- rep(c(0, 0, 0, 0.5), n / 4)
  rain[10:12] <- NA
  pet <- rep(0.05, n)
  pet[5] <- -0.01
  forcing <- data.frame(time = time, rain = fill_gaps(rain, "zero", label = "rain"),
                        pet = zero_negatives(pet, "pet"))
  flow <- convert_units(rep(300, n), "ls", 1, "flow")
  start_calibration_project(folder, "Prep Brook", "1", "Testing", 20, "Owner", "Steward")
  reg <- register_data(folder, forcing, flow, calibration = c(200, 1000), wettest_years = 0)
  prep <- do.call(rbind, lapply(read_entry(folder, reg$id)$preparation, as.data.frame))
  expect_equal(prep$series, c("rain", "pet", "flow"))
  expect_equal(prep$step, c("gaps", "negatives", "units"))
  plain <- tempfile("plain-")
  on.exit(unlink(plain, recursive = TRUE), add = TRUE)
  start_calibration_project(plain, "Plain Brook", "2", "Testing", 20, "Owner", "Steward")
  reg2 <- register_data(plain, data.frame(rain = rep(0.1, 100), pet = 0.05), rep(0.2, 100),
                        calibration = c(10, 90), wettest_years = 0)
  expect_null(read_entry(plain, reg2$id)$preparation)
})
