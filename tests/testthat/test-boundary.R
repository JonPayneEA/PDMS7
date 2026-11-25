# ============================================================ #
# Tool:         test-boundary
# Description:  read_boundary() reads a CSV or a shapefile onto British National Grid with the
#               centroid and area; distance_to_boundary() measures how far points lie outside
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-25
# Tier:         1
# Inputs:       Boundaries written to a temporary folder
# Outputs:      None
# Dependencies: testthat; sf for the shapefile tests
# ============================================================ #

# An L-shaped catchment: a 4 km by 2 km block with a 2 km by 2 km block on its left end, on
# top. Area 8 + 4 = 12 km2. Centroid: the area-weighted mean of the blocks' centres,
# (8 x (2000, 1000) + 4 x (1000, 3000)) / 12 = (20000 / 12, 20000 / 12) = (1666.67, 1666.67).
l_shape <- data.frame(x = 400000 + c(0, 4000, 4000, 2000, 2000, 0),
                      y = 200000 + c(0, 0, 2000, 2000, 4000, 4000))

test_that("read_boundary() reads a CSV with its centroid and area", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(l_shape, path, row.names = FALSE)
  b <- read_boundary(path)
  expect_equal(b$x, l_shape$x)
  expect_equal(attr(b, "area_km2"), 12)
  expect_equal(unname(attr(b, "centroid")), c(400000, 200000) + 20000 / 12)
  # A ring closed by repeating its first corner gives the same.
  utils::write.csv(rbind(l_shape, l_shape[1, ]), path, row.names = FALSE)
  expect_equal(nrow(read_boundary(path)), 6)
  utils::write.csv(data.frame(e = 1:3, n = 1:3), path, row.names = FALSE)
  expect_error(read_boundary(path), "columns x and y")
  expect_error(read_boundary(file.path(tempdir(), "none.csv")), "Cannot find")
})

test_that("read_boundary() reads a shapefile and moves it onto British National Grid", {
  skip_if_not_installed("sf")
  ring <- as.matrix(rbind(l_shape, l_shape[1, ]))
  shape <- sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_polygon(list(ring)), crs = 27700))
  dir <- tempfile("shp")
  dir.create(dir)
  # Written in latitude and longitude, so the reader has to move it back.
  sf::st_write(sf::st_transform(shape, 4326), file.path(dir, "lshape.shp"), quiet = TRUE)
  b <- read_boundary(file.path(dir, "lshape.shp"))
  # The same area and centroid, to within the round trip through degrees (well under 1 m).
  expect_equal(attr(b, "area_km2"), 12, tolerance = 1e-4)
  expect_equal(unname(attr(b, "centroid")), c(400000, 200000) + 20000 / 12, tolerance = 1e-6)
  # Two parts: the larger (12 km2) is kept, the 1 km2 island dropped with a message.
  island <- as.matrix(data.frame(x = 410000 + c(0, 1000, 1000, 0, 0),
                                 y = 200000 + c(0, 0, 1000, 1000, 0)))
  two <- sf::st_sf(id = 1:2, geometry = sf::st_sfc(sf::st_polygon(list(ring)),
                                                   sf::st_polygon(list(island)), crs = 27700))
  sf::st_write(two, file.path(dir, "two.gpkg"), quiet = TRUE)
  expect_message(b2 <- read_boundary(file.path(dir, "two.gpkg")), "dropping 7.7% of the area")
  expect_equal(attr(b2, "area_km2"), 12)
})

test_that("distance_to_boundary() is zero inside and the nearest edge outside", {
  # Inside the L; 1 km right of its right edge; in the notch of the L; above the notch.
  x <- 400000 + c(1000, 5000, 3000, 3000)
  y <- 200000 + c(1000, 1000, 3000, 5000)
  d <- distance_to_boundary(x, y, l_shape)
  # (3000, 3000) is in the notch: 1 km right of the edge x = 2000 and 1 km above y = 2000.
  # (3000, 5000) is outside both: nearest the corner (2000, 4000), sqrt(1000^2 + 1000^2) away.
  expect_equal(d, c(0, 1000, 1000, sqrt(2) * 1000))
  expect_error(distance_to_boundary(1, 1:2, l_shape), "same length")
})
