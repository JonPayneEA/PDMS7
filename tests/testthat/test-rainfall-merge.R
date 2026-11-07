# Tests for merge_rainfall(), rainfall_cross_validation() and catchment_mask().

# Moving storm cells on a 30 km grid, ten gauges reading the true field with a little error, and
# a radar that reads it with a bias rising from west (0.6) to east (1.2) and cell-by-cell noise.
merge_case <- function(nt = 200) {
  set.seed(4)
  grid <- list(x = seq(500, 29500, by = 1000), y = seq(500, 29500, by = 1000))
  nx <- length(grid$x)
  ny <- length(grid$y)
  gx <- matrix(grid$x, nx, ny)
  gy <- matrix(grid$y, nx, ny, byrow = TRUE)
  truth <- array(0, c(nx, ny, nt))
  for (k in 1:25) {
    t0 <- sample.int(nt - 12, 1)
    cx <- stats::runif(1, 0, 30000)
    cy <- stats::runif(1, 0, 30000)
    r <- stats::runif(1, 2000, 6000)
    peak <- stats::rexp(1, 1 / 4)
    for (s in 0:11) {
      truth[, , t0 + s] <- truth[, , t0 + s] +
        peak * exp(-((gx - cx - 800 * s)^2 + (gy - cy)^2) / (2 * r^2)) * exp(-s / 4)
    }
  }
  bias <- 0.6 + 0.6 * (gx / 30000)
  radar <- truth * as.vector(bias) * exp(stats::rnorm(length(truth), 0, 0.25))
  gauges <- data.frame(id = LETTERS[1:10], x = stats::runif(10, 2000, 28000),
                       y = stats::runif(10, 2000, 28000))
  at <- .gauge_cells(gauges, grid)
  gauge_rain <- t(vapply(seq_len(nt), function(t) truth[cbind(at$i, at$j, t)], numeric(10))) *
    exp(stats::rnorm(nt * 10, 0, 0.05))
  mask <- catchment_mask(grid$x, grid$y, data.frame(x = c(11000, 18000, 19000, 12000),
                                                    y = c(11000, 10500, 17000, 17500)))
  true_rain <- vapply(seq_len(nt), function(t) mean(truth[, , t][mask]), numeric(1))
  radar_rain <- vapply(seq_len(nt), function(t) mean(radar[, , t][mask]), numeric(1))
  list(grid = grid, radar = radar, gauges = gauges, gauge_rain = gauge_rain, mask = mask,
       true_rain = true_rain, radar_rain = radar_rain, at = at)
}

# Guards: the multiquadric surface passes through the gauges and stays bounded far from them
test_that("the multiquadric surface is exact at the gauges and bounded far away", {
  gx <- c(0, 1000, 0, 1000, 500)
  gy <- c(0, 0, 1000, 1000, 500)
  z <- c(1, 2, 3, 4, 10)
  expect_equal(.multiquadric(gx, gy, z, gx, gy, 300, 0), z, tolerance = 1e-8)
  far <- .multiquadric(gx, gy, z, c(1e6, 1e7), c(1e6, 1e7), 300, 0)
  expect_lt(abs(diff(far)), 0.01)
  expect_lt(max(abs(far)), 10 * max(abs(z)))
  smoothed <- .multiquadric(gx, gy, z, gx, gy, 300, 1e4)
  expect_gt(max(abs(smoothed - z)), 0.01)
  expect_equal(.multiquadric(0, 0, 5, c(1, 2), c(1, 2), 300, 0), c(5, 5))
  expect_equal(.multiquadric(gx, gy, rep(2, 5), c(9, 8), c(9, 8), 300, 0), c(2, 2))
})

# Guards: rain is never negative, a missing gauge is left out, and a dry step stays dry
test_that("fields are nonnegative and handle missing and dry steps", {
  gauges <- data.frame(id = 1:4, x = c(0, 1000, 0, 1000), y = c(0, 0, 1000, 1000))
  target <- list(x = c(-3000, 500, 4000), y = c(-3000, 500, 4000), w = c(1, 1, 1))
  field <- .rain_field(gauges, c(0, 0, 0, 8), target, "multiquadric", 200, 0, NULL)
  expect_true(all(field >= 0))
  expect_equal(.rain_field(gauges, c(0, 0, 0, 0), target, "multiquadric", 200, 0, NULL),
               c(0, 0, 0))
  thiessen <- .rain_field(gauges, c(1, NA, 3, 4), target, "thiessen", NULL, 0, NULL)
  expect_equal(thiessen, c(1, 1, 4))
  expect_true(all(is.na(.rain_field(gauges, rep(NA_real_, 4), target, "thiessen", NULL, 0,
                                    NULL))))
})

# Guards: conditional merging keeps the radar's rain where all the gauges are dry, removes it
# where the radar over a dry gauge saw rain, and equals a gauge in its own cell
test_that("conditional merging follows the gauges at the gauges and the radar between", {
  gauges <- data.frame(id = 1:4, x = c(0, 1000, 0, 1000), y = c(0, 0, 1000, 1000))
  at_gauges <- list(x = gauges$x, y = gauges$y, w = rep(1, 4))
  radar <- list(cells = c(2, 2, 2, 2), gauges = c(2, 2, 2, 2))
  merged <- .rain_field(gauges, c(1, 3, 2, 4), at_gauges, "conditional", 500, 0, radar)
  expect_equal(merged, c(1, 3, 2, 4), tolerance = 1e-8)
  between <- list(x = 500, y = 500, w = 1)
  missed <- .rain_field(gauges, c(0, 0, 0, 0), between, "conditional", 500, 0,
                        list(cells = 6, gauges = c(0, 0, 0, 0)))
  expect_equal(missed, 6)
  false_echo <- .rain_field(gauges, c(0, 0, 0, 0), between, "conditional", 500, 0,
                            list(cells = 3, gauges = c(3, 3, 3, 3)))
  expect_equal(false_echo, 0, tolerance = 1e-8)
})

# Guards: on a synthetic storm field, merging beats Thiessen, and the radar's volume is corrected
test_that("conditional merging improves the catchment rainfall", {
  d <- merge_case()
  thiessen <- merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask, method = "thiessen")
  mq <- merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask, method = "multiquadric")
  cm <- merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask, radar = d$radar,
                       method = "conditional")
  rmse <- function(s) sqrt(mean((s - d$true_rain)^2))
  expect_s3_class(cm, "pdm_rainfall")
  expect_length(cm$rain, length(d$true_rain))
  expect_true(all(cm$rain >= 0))
  expect_lt(rmse(cm$rain), min(rmse(mq$rain), rmse(thiessen$rain)))
  expect_lt(abs(sum(cm$rain) / sum(d$true_rain) - 1),
            abs(sum(d$radar_rain) / sum(d$true_rain) - 1))
  expect_true(cm$c %in% cm$checks$c)
  expect_equal(cm$c, cm$checks$c[which.min(cm$checks$rmse)])
  expect_null(thiessen$checks)
  expect_output(print(mq), "Leave-one-gauge-out")
  by_step <- merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask,
                            radar = function(t) d$radar[, , t], method = "conditional", c = cm$c)
  expect_equal(by_step$rain, cm$rain)
})

# Guards: cross-validation leaves each gauge out, samples long records, and checks its inputs
test_that("rainfall_cross_validation scores the left-out gauges", {
  d <- merge_case(nt = 120)
  cv <- rainfall_cross_validation(d$gauges, d$gauge_rain, d$grid, method = "multiquadric",
                                  c = c(1000, 5000))
  expect_equal(nrow(cv), 2)
  expect_true(all(c("mae", "rmse", "bias", "correlation") %in% names(cv)))
  few <- rainfall_cross_validation(d$gauges, d$gauge_rain, d$grid, method = "thiessen",
                                   max_steps = 5)
  expect_equal(nrow(few), 1)
  expect_error(rainfall_cross_validation(d$gauges[1:2, ], d$gauge_rain[, 1:2], d$grid),
               "three gauges")
  expect_error(rainfall_cross_validation(d$gauges, d$gauge_rain * 0, d$grid), "No wet")
})

# Guards: the mask follows the polygon, and bad inputs are refused
test_that("catchment_mask and input checks", {
  mask <- catchment_mask(1:4, 1:3, data.frame(x = c(1.5, 3.5, 3.5, 1.5), y = c(1.5, 1.5, 2.5, 2.5)))
  expect_equal(dim(mask), c(4, 3))
  expect_equal(which(mask), c(6, 7))
  d <- merge_case(nt = 20)
  expect_error(merge_rainfall(d$gauges, d$gauge_rain[, -1], d$grid, d$mask), "one column")
  expect_error(merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask * 0), "cell inside")
  expect_error(merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask, method = "conditional"),
               "radar must be")
  expect_error(merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask, c = -1), "positive")
})

# Guards: the one-step field agrees with the catchment series and with the gauges
test_that("rainfall_field maps one step consistently with merge_rainfall", {
  d <- merge_case(nt = 60)
  wet <- which.max(rowSums(d$gauge_rain))
  cm <- merge_rainfall(d$gauges, d$gauge_rain, d$grid, d$mask, radar = d$radar,
                       method = "conditional", c = 3000)
  field <- rainfall_field(d$gauges, d$gauge_rain[wet, ], d$grid, method = "conditional",
                          c = 3000, radar = d$radar[, , wet])
  expect_equal(dim(field), c(length(d$grid$x), length(d$grid$y)))
  expect_equal(mean(field[d$mask]), cm$rain[wet], tolerance = 1e-10)
  mq <- rainfall_field(d$gauges, d$gauge_rain[wet, ], d$grid, method = "multiquadric",
                       c = 3000)
  expect_equal(mq[cbind(d$at$i, d$at$j)], d$gauge_rain[wet, ], tolerance = 0.3)
  expect_true(all(mq >= 0))
  expect_error(rainfall_field(d$gauges, d$gauge_rain[wet, ], d$grid, method = "conditional"),
               "radar must be")
})
