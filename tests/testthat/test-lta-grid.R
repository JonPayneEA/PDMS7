# ============================================================ #
# Tool:         test-lta-grid
# Description:  read_lta_grid() reads a long-term average grid laid out as HadUK-Grid's 30-year
#               averages are, crops it, keeps every cell in its place; lta_at() looks up points
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-26
# Tier:         1
# Inputs:       Synthetic NetCDF grids written to a temporary folder
# Outputs:      None
# Dependencies: testthat, ncdf4
# ============================================================ #

# A grid as HadUK-Grid's annual 30-year average is laid out: rainfall in mm on
# projection_x_coordinate and projection_y_coordinate (1 km cells, centres at 500 m), one time
# layer, a fill value of 1e20, and latitude on the same grid beside it. Here y runs north to
# south, to check the flip. Each cell's value encodes its place: 600 + x km + 10 * y km, taking
# the cell's lower-left corner in km.
write_lta <- function(path, units = "mm", layers = 1) {
  x <- 400500 + 1000 * (0:5)
  y <- rev(300500 + 1000 * (0:4))
  dx <- ncdf4::ncdim_def("projection_x_coordinate", "m", x)
  dy <- ncdf4::ncdim_def("projection_y_coordinate", "m", y)
  dt <- ncdf4::ncdim_def("time", "hours since 1800-01-01 00:00:00", seq_len(layers))
  rain <- ncdf4::ncvar_def("rainfall", units, list(dx, dy, dt), missval = 1e20)
  lat <- ncdf4::ncvar_def("latitude", "degrees_north", list(dx, dy), missval = -999)
  nc <- ncdf4::nc_create(path, list(rain, lat))
  v <- outer(600 + (x - 500) / 1000, 10 * (y - 500) / 1000, "+")
  v[1, 1] <- NA
  ncdf4::ncvar_put(nc, rain, array(rep(v, layers), c(6, 5, layers)))
  ncdf4::ncvar_put(nc, lat, matrix(52, 6, 5))
  ncdf4::nc_close(nc)
}

test_that("read_lta_grid() reads a HadUK-Grid layout, cropped, with every cell in its place", {
  skip_if_not_installed("ncdf4")
  path <- tempfile(fileext = ".nc")
  write_lta(path)
  g <- read_lta_grid(path)
  expect_s3_class(g, "pdm_lta_grid")
  expect_identical(g$variable, "rainfall")
  expect_equal(g$x, 400500 + 1000 * (0:5))
  expect_equal(g$y, 300500 + 1000 * (0:4))
  expect_equal(g$cell, 1000)
  # The cell with centre (402500, 303500): 600 + 402 + 10 * 303 = 4032.
  expect_equal(g$values[3, 4], 4032)
  # The filled cell: the first x and, in the file, the first y (the northernmost, 304500), so
  # the last row here once y is increasing.
  expect_true(is.na(g$values[1, 5]))
  # Cropped to centres within 401000 to 403000 and 300000 to 302000: 2 columns by 2 rows.
  w <- read_lta_grid(path, extent = c(401000, 403000, 300000, 302000))
  expect_equal(w$x, c(401500, 402500))
  expect_equal(w$y, c(300500, 301500))
  expect_equal(w$values[2, 2], 600 + 402 + 10 * 301)
  # Points: inside a cell, on the edge of the grid, and beyond it.
  expect_equal(lta_at(g, c(402900, 405999, 410000), c(303100, 300000, 300000)),
               c(4032, 600 + 405 + 10 * 300, NA))
  expect_output(print(g), "6 by 5 cells of 1000 m")
})

test_that("read_lta_grid() refuses a grid in other units or with more than one layer", {
  skip_if_not_installed("ncdf4")
  in_cm <- tempfile(fileext = ".nc")
  write_lta(in_cm, units = "cm")
  expect_error(read_lta_grid(in_cm), "not mm")
  monthly <- tempfile(fileext = ".nc")
  write_lta(monthly, layers = 12)
  expect_error(read_lta_grid(monthly), "more than one layer")
  expect_error(read_lta_grid(in_cm, extent = c(0, 1, 0, 1)), "not mm")
})
