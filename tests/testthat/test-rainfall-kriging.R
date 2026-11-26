# ============================================================ #
# Tool:         test-rainfall-kriging
# Description:  Block kriging and kriging with external drift give the averages and errors
#               worked out from their definitions; the fast path for the linear methods gives
#               the same averages as the field made step by step; the variogram tells pure
#               noise from rain that is related across the gauges
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-26
# Tier:         1
# Inputs:       Small synthetic gauges and grids
# Outputs:      None
# Dependencies: testthat
# ============================================================ #

fixed_variogram <- function(nugget, partial_sill, range) {
  structure(list(model = "exponential", nugget = nugget, partial_sill = partial_sill,
                 range = range, empirical = data.frame()),
            class = "pdm_variogram")
}

# Guards: two gauges placed alike about a block take half each, by symmetry, and the kriging
# variance follows from the kriging equations by hand. With weights 1/2, the first equation,
# 0 x 1/2 + gamma(2000) x 1/2 + mu = mean gamma(gauge 1, block), gives mu; the variance is
# sum(lambda x mean gamma(gauge, block)) + mu - mean gamma(block, block)
# = 2 x g1 - gamma(2000) / 2 - g_bb, where g1 is the mean variogram from gauge 1 to the cells
# (the same from gauge 2, by symmetry) and g_bb the mean over every pair of cells.
test_that("block kriging of two gauges placed alike gives half each and the hand variance", {
  v <- fixed_variogram(0.1, 0.9, 2000)
  gauges <- data.frame(id = c("A", "B"), x = c(-1000, 1000), y = c(0, 0))
  grid <- list(x = c(-500, 0, 500), y = c(-500, 0, 500))
  mask <- matrix(TRUE, 3, 3)
  out <- merge_rainfall(gauges, rbind(c(2, 4), c(0, 0)), grid, mask, method = "kriging",
                        variogram = v)
  expect_equal(out$rain, c(3, 0))
  gam <- function(h) ifelse(h > 0, 0.1 + 0.9 * (1 - exp(-h / 2000)), 0)
  cx <- rep(grid$x, 3)
  cy <- rep(grid$y, each = 3)
  g1 <- mean(gam(sqrt((cx + 1000)^2 + cy^2)))
  g_bb <- mean(gam(sqrt(outer(cx, cx, "-")^2 + outer(cy, cy, "-")^2)))
  variance <- 2 * g1 - gam(2000) / 2 - g_bb
  # The error is of relative rain, times the step's mean over the gauges (3 mm; 0 when dry).
  expect_equal(out$se, c(sqrt(variance) * 3, 0))
  expect_s3_class(out$variogram, "pdm_variogram")
})

# Guards: kriging with an external drift reproduces data that follow the drift exactly. With
# rain at each gauge 2 + 0.01 x drift there, the weights' constraints (summing to 1, and to the
# block's mean drift when weighted by the gauges' drift) give exactly 2 + 0.01 x the block's
# mean drift, whatever the variogram.
test_that("kriging with an external drift reproduces rain that follows the drift", {
  v <- fixed_variogram(0.05, 1, 3000)
  grid <- list(x = seq(500, 9500, by = 1000), y = seq(500, 9500, by = 1000))
  drift <- outer(600 + grid$x / 100, rep(1, 10))
  mask <- catchment_mask(grid$x, grid$y,
                         data.frame(x = c(2000, 8000, 8000, 2000), y = c(2000, 2000, 8000, 8000)))
  # Gauges on cell centres, so the drift at each is exactly that cell's.
  gauges <- data.frame(id = 1:4, x = c(1500, 8500, 4500, 6500), y = c(1500, 2500, 8500, 5500))
  at <- drift[cbind(match(gauges$x, grid$x), match(gauges$y, grid$y))]
  rain <- matrix(2 + 0.01 * at, nrow = 1)
  out <- merge_rainfall(gauges, rain, grid, mask, method = "ked", variogram = v, drift = drift)
  expect_equal(out$rain, 2 + 0.01 * mean(drift[mask]))
  # Ordinary kriging cannot follow the drift: its average is the gauges' weighting alone.
  ok <- merge_rainfall(gauges, rain, grid, mask, method = "kriging", variogram = v)
  expect_false(isTRUE(all.equal(ok$rain, out$rain)))
  expect_error(merge_rainfall(gauges, rain, grid, mask, method = "ked", variogram = v),
               "drift must be a matrix")
})

# Guards: the fast path (weights once per set of gauges reporting) gives the same averages as
# making the field at every step, for each linear method, with gauges missing in different
# patterns and a step whose multiquadric surface dips below zero (set to zero cell by cell).
test_that("the fast path matches the field made step by step", {
  grid <- list(x = seq(500, 9500, by = 1000), y = seq(500, 9500, by = 1000))
  mask <- catchment_mask(grid$x, grid$y,
                         data.frame(x = c(1000, 9000, 9000, 1000), y = c(1000, 1000, 9000, 9000)))
  gauges <- data.frame(id = 1:5, x = c(1500, 8500, 5000, 1500, 8500),
                       y = c(1500, 1500, 5200, 8500, 8500))
  rain <- rbind(c(1, 2, 4, 1, 2), c(0, 0, 0, 0, 0), c(3, NA, 2, 2, 1), c(NA, NA, 5, NA, NA),
                c(0, 0, 9, 0, 0), c(2, 1, NA, NA, 3), c(NA, NA, NA, NA, NA))
  for (method in c("thiessen", "idw", "multiquadric")) {
    fast <- merge_rainfall(gauges, rain, grid, mask, method = method, c = 3000)$rain
    slow <- vapply(seq_len(nrow(rain)), function(t) {
      if (all(is.na(rain[t, ]))) return(NA_real_)
      field <- rainfall_field(gauges, rain[t, ], grid, method = method, c = 3000)
      mean(field[mask])
    }, 0)
    expect_equal(fast, slow, tolerance = 1e-10, info = method)
  }
  # The fifth step's surface, one wet gauge among dry ones, dips below zero between them: the
  # clamp is what keeps the average from coming out below the field's true rain.
  field <- rainfall_field(gauges, rain[5, ], grid, method = "multiquadric", c = 3000)
  expect_true(any(field == 0))
})

# Guards: the variogram of noise that is independent at every gauge is flat (all nugget), and
# that of rain shared across the gauges rises with distance. Four gauges give six pairs.
test_that("the variogram tells independent noise from related rain", {
  gauges <- data.frame(id = 1:4, x = c(0, 1000, 10000, 30000), y = 0)
  set.seed(3)
  steps <- 3000
  noise <- matrix(rexp(steps * 4), steps, 4)
  v <- rainfall_variogram(gauges, noise)
  expect_s3_class(v, "pdm_variogram")
  expect_identical(nrow(v$empirical), 6L)
  expect_gt(v$nugget / (v$nugget + v$partial_sill), 0.8)
  # Rain from a field correlated over about 5 km: near gauges alike, far ones not.
  d <- as.matrix(stats::dist(gauges[, c("x", "y")]))
  chol_c <- chol(exp(-d / 5000))
  related <- exp(matrix(rnorm(steps * 4), steps, 4) %*% chol_c)
  w <- rainfall_variogram(gauges, related)
  near <- w$empirical$semivariance[w$empirical$distance == 1000]
  far <- w$empirical$semivariance[w$empirical$distance == 30000]
  expect_lt(near, far)
  expect_gt(w$range, 0)
  expect_error(rainfall_variogram(gauges[1:2, ], noise[, 1:2]), "three gauges")
})
