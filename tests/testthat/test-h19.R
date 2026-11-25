# Tests for h19_radar(): daily NetCDF files written in the layout of the H19 archive.

# Writes one day of 15-minute layers on a 1 km British National Grid, with values that encode
# their own position and time: 1000 * layer + 10 * column + row, so orientation can be checked.
# `stamp` "end" stamps each layer at the end of its 15 minutes (the first at 00:15), "start" at
# the start (the first at 00:00).
write_h19_day <- function(path, day, varname = "rainfall_radar_amount", x0 = 300500,
                          y0 = 140500, nx = 6, ny = 5, layers = 4, stamp = "end",
                          units = "mm") {
  x <- x0 + 1000 * (seq_len(nx) - 1)
  y <- y0 + 1000 * (seq_len(ny) - 1)
  minutes <- as.numeric(difftime(as.POSIXct(day, tz = "UTC"),
                                 as.POSIXct("1970-01-01", tz = "UTC"), units = "mins")) +
    15 * (seq_len(layers) - (stamp == "start"))
  dx <- ncdf4::ncdim_def("x", "m", x)
  dy <- ncdf4::ncdim_def("y", "m", y)
  dt <- ncdf4::ncdim_def("time", "minutes since 1970-01-01 00:00:00", minutes, unlim = TRUE)
  v <- ncdf4::ncvar_def(varname, units, list(dx, dy, dt), missval = -1)
  nc <- ncdf4::nc_create(path, v)
  values <- array(0, c(nx, ny, layers))
  for (k in seq_len(layers)) values[, , k] <- outer(10 * seq_len(nx), seq_len(ny), "+") + 1000 * k
  ncdf4::ncvar_put(nc, v, values)
  ncdf4::nc_close(nc)
  invisible(list(x = x, y = y, values = values))
}

h19_files <- function(env = parent.frame()) {
  dir <- tempfile("h19-")
  dir.create(dir)
  defer_to(function() unlink(dir, recursive = TRUE), env) # nolint: object_usage_linter.
  a <- write_h19_day(file.path(dir, "20240102.nc"), "2024-01-02")
  write_h19_day(file.path(dir, "20240101.nc"), "2024-01-01")
  list(dir = dir, files = list.files(dir, full.names = TRUE), truth = a)
}

# Guards: steps come out in time order, on an increasing grid, with each cell in its place
test_that("h19_radar indexes days in order and keeps every cell in its place", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ncdf4")
  d <- h19_files()
  h <- h19_radar(rev(d$files), extent = c(300000, 306000, 140000, 145000))
  expect_s3_class(h, "pdm_h19")
  expect_length(h$time, 8)
  expect_true(all(diff(h$time) > 0))
  expect_equal(format(h$time[1], "%Y-%m-%d %H:%M", tz = "UTC"), "2024-01-01 00:15")
  expect_equal(h$grid$x, d$truth$x)
  expect_equal(h$grid$y, d$truth$y)
  step <- h$radar(6)
  expect_equal(dim(step), c(6, 5))
  expect_equal(step, d$truth$values[, , 2])
  expect_equal(h$radar(1), d$truth$values[, , 1])
  expect_output(print(h), "8 steps")
})

# Guards: cropping keeps the cells inside the extent, and the radar feeds merge_rainfall()
test_that("a cropped H19 grid feeds conditional merging", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ncdf4")
  d <- h19_files()
  h <- h19_radar(d$files, extent = c(301000, 305000, 141000, 144000))
  expect_true(all(h$grid$x > 301000 & h$grid$x < 305000))
  expect_true(all(h$grid$y > 141000 & h$grid$y < 144000))
  mask <- catchment_mask(h$grid$x, h$grid$y,
                         data.frame(x = c(301500, 304500, 304500, 301500),
                                    y = c(141500, 141500, 143500, 143500)))
  gauges <- data.frame(id = 1:3, x = c(301500, 303500, 304500), y = c(141500, 143500, 142500))
  at <- .gauge_cells(gauges, h$grid)
  gauge_rain <- t(vapply(seq_along(h$time), function(t) h$radar(t)[cbind(at$i, at$j)],
                         numeric(3)))
  merged <- merge_rainfall(gauges, gauge_rain, h$grid, mask, radar = h$radar,
                           method = "conditional", c = 1000)
  direct <- vapply(seq_along(h$time), function(t) mean(h$radar(t)[mask]), numeric(1))
  expect_equal(merged$rain, direct, tolerance = 1e-8)
})

# Guards: the older variable name is found, and unknown names and bad inputs are refused
test_that("h19_radar finds the variable and checks its inputs", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ncdf4")
  dir <- tempfile("h19-old-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  old <- file.path(dir, "20150101.nc")
  write_h19_day(old, "2015-01-01", varname = "radar rain-accum H19")
  h <- h19_radar(old, extent = c(300000, 306000, 140000, 145000))
  expect_equal(dim(h$radar(1)), c(6, 5))
  other <- file.path(dir, "other.nc")
  write_h19_day(other, "2015-01-02", varname = "precip")
  expect_error(h19_radar(other, extent = c(300000, 306000, 140000, 145000)), "No H19 variable")
  expect_error(h19_radar(old, extent = c(1, 0, 0, 1)), "extent")
  expect_error(h19_radar(file.path(dir, "missing.nc"), extent = c(0, 1, 0, 1)), "existing")
  expect_error(h$radar(99), "No such step")
})

# Guards: a change of layout part way through an archive (the variable renamed, the time stamp
# moved from the end of each step to its start, a rate in place of a depth) is found and
# reported, with the shift and factor that put every file on the same footing.
test_that("h19_layouts finds each layout and how to line it up", {
  skip_if_not_installed("ncdf4")
  dir <- tempfile("h19-layouts-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  # Two days the old way: the old name, stamped at the end of each step, in mm.
  for (d in c("2019-12-30", "2019-12-31")) {
    write_h19_day(file.path(dir, paste0(gsub("-", "", d), "_old.nc")), d,
                  varname = "radar rain-accum H19", stamp = "end")
  }
  # Two days the new way: the new name, stamped at the start, as a rate in mm per hour.
  for (d in c("2021-01-01", "2021-01-02")) {
    write_h19_day(file.path(dir, paste0(gsub("-", "", d), "_new.nc")), d,
                  varname = "rainfall_radar_amount", stamp = "start", units = "mm/h")
  }
  lay <- h19_layouts(list.files(dir, full.names = TRUE))
  expect_s3_class(lay, "pdm_h19_layouts")
  expect_equal(nrow(lay$layouts), 2)
  expect_equal(lay$layouts$files, c(2, 2))
  expect_equal(lay$layouts$variable, c("radar rain-accum H19", "rainfall_radar_amount"))
  expect_equal(lay$layouts$stamp, c("end", "start"))
  expect_equal(lay$layouts$first_day, c("2019-12-30", "2021-01-01"))
  # Both pass: 1 km cells, aligned alike, layers 15 minutes apart, units understood.
  expect_equal(lay$layouts$problems, c("", ""))
  expect_equal(lay$layouts$cell_x, c(1000, 1000))
  # End stamps move back 15 minutes; a rate in mm per hour times 0.25 h gives mm per step.
  old <- grepl("_old", lay$files$file)
  expect_equal(lay$files$shift_minutes, ifelse(old, 15, 0))
  expect_equal(lay$files$factor, ifelse(old, 1, 0.25))
  # Four layers a day here, so every day counts as short of the 96.
  expect_equal(lay$layouts$short_days, c(2, 2))
  expect_output(print(lay), "2 layouts")
})

# Guards: a grid that does not line up, and units it cannot read, are problems, not silence
test_that("h19_layouts reports a misaligned grid and unknown units", {
  skip_if_not_installed("ncdf4")
  dir <- tempfile("h19-bad-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  write_h19_day(file.path(dir, "a.nc"), "2024-01-01")
  # Cell centres on whole kilometres, not at 500 m: half a cell from the first file's.
  write_h19_day(file.path(dir, "b.nc"), "2024-01-02", x0 = 300000, units = "kg m-2")
  lay <- h19_layouts(file.path(dir, c("a.nc", "b.nc")))
  expect_equal(nrow(lay$layouts), 2)
  expect_equal(lay$layouts$problems[1], "")
  expect_match(lay$layouts$problems[2], "not aligned")
  expect_match(lay$layouts$problems[2], "units 'kg m-2' not understood")
  expect_true(is.na(lay$files$factor[2]))
})

# Guards (regression): where the time stamp changed from the end of each step to its start,
# the last layer before and the first after both read midnight. Without the layouts the
# reader refused them as the same time; with them, each is moved to its own step's start, and
# a rate is put in mm per step.
test_that("h19_radar lines up an archive whose time stamp and units changed", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ncdf4")
  dir <- tempfile("h19-change-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  old <- write_h19_day(file.path(dir, "20240331.nc"), "2024-03-31", stamp = "end",
                       layers = 96)
  new <- write_h19_day(file.path(dir, "20240401.nc"), "2024-04-01", stamp = "start",
                       layers = 96, units = "mm/h")
  files <- file.path(dir, c("20240331.nc", "20240401.nc"))
  extent <- c(300000, 306000, 140000, 145000)
  expect_error(h19_radar(files, extent), "same time")
  h <- h19_radar(files, extent, layouts = h19_layouts(files))
  # 192 steps, 15 minutes apart, from 00:00 on 31 March to 23:45 on 1 April.
  expect_length(h$time, 192)
  expect_true(all(as.numeric(diff(h$time), units = "mins") == 15))
  expect_equal(format(range(h$time), "%Y-%m-%d %H:%M", tz = "UTC"),
               c("2024-03-31 00:00", "2024-04-01 23:45"))
  # The old file's values as they are; the new file's rate times 0.25 h.
  expect_equal(h$radar(96), old$values[, , 96])
  expect_equal(h$radar(97), 0.25 * new$values[, , 1])
})
