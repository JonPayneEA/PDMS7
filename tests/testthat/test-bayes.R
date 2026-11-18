# ============================================================ #
# Tool:         test_bayes
# Description:  The likelihood and priors in closed form, the DREAM(ZS) sampler on a target
#               whose answer is known, and a Bayesian calibration of a model
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Hand-built errors; a known Gaussian target; the synthetic record
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Guards: the AR(1) likelihood with its autocorrelation and variance set to their best values
test_that("the likelihood of autocorrelated errors", {
  # e = 1, -1, 1, 2: rho = (1 x -1 + -1 x 1 + 1 x 2) / (1 + 1 + 1) = 0, so the three
  # innovations are -1, 1, 2 with mean square 2: log L = -(3 / 2) (log(2 pi 2) + 1)
  e <- c(1, -1, 1, 2)
  expect_equal(.boxcox_ar1_loglik(e), -1.5 * (log(4 * pi) + 1))
  # e = 1, 0.5, 0.75: rho = (0.5 + 0.375) / (1 + 0.25) = 0.7; innovations 0.5 - 0.7 = -0.2 and
  # 0.75 - 0.35 = 0.4, mean square 0.1: log L = -(2 / 2) (log(2 pi 0.1) + 1)
  expect_equal(.boxcox_ar1_loglik(c(1, 0.5, 0.75)), -(log(0.2 * pi) + 1))
  # Without the autoregression, the innovations are the errors themselves: 0.25 and 0.5625
  expect_equal(.boxcox_ar1_loglik(c(1, 0.5, 0.75), ar1 = FALSE),
               -(log(2 * pi * (0.25 + 0.5625) / 2) + 1))
  em <- .error_model(c(1, 0.5, 0.75), TRUE)
  expect_equal(c(em$rho, em$s2), c(0.7, 0.1))
})

# Guards: prior densities and the inverse transform
test_that("priors and the inverse Box-Cox", {
  expect_equal(.log_prior(prior_uniform(), 3), 0)
  expect_equal(.log_prior(prior_normal(1, 0.2), 1.2), stats::dnorm(1.2, 1, 0.2, log = TRUE))
  expect_equal(.log_prior(prior_lognormal(250, 0.3), 250),
               stats::dlnorm(250, log(250), 0.3, log = TRUE))
  q <- c(0, 0.5, 3, 40)
  expect_equal(.boxcox_inverse(boxcox_flow(q, 0.5, 0.01), 0.5, 0.01), q)
  expect_equal(.boxcox_inverse(boxcox_flow(q, 0, 0.01), 0, 0.01), q)
  expect_equal(.reflect_unit(c(-0.2, 1.3, 0.5, 2.4)), c(0.2, 0.7, 0.5, 0.4))
  expect_error(prior_normal(1, 0), "sd positive")
})

# Guards: DREAM(ZS) samples a known posterior
test_that("DREAM(ZS) recovers a Gaussian target", {
  # Independent normals at 0.3 and 0.6, sd 0.05, well inside the unit box
  target <- function(z) {
    lp <- sum(stats::dnorm(z, c(0.3, 0.6), 0.05, log = TRUE))
    c(lp, lp)
  }
  run <- .with_seed(7, .dream_zs(target, 2L, 3000L, 3L))
  kept <- run$chains[1501:3000, , , drop = FALSE]
  draws <- matrix(kept, ncol = 2)
  expect_equal(colMeans(draws), c(0.3, 0.6), tolerance = 0.03)
  expect_equal(apply(draws, 2, stats::sd), c(0.05, 0.05), tolerance = 0.3)
  expect_true(all(.gelman_rubin(kept) < 1.1))
  expect_gt(run$acceptance, 0.1)
})

# Guards: a Bayesian calibration finds the rainfall factor, with a band that brackets it
test_that("a Bayesian calibration and its band", {
  d <- log_data()
  start <- d$truth
  start$fc <- 0.8
  fit <- calibrate_bayes(start, d$forcing, d$observed, lower = c(fc = 0.5), upper = c(fc = 1.5),
                         priors = list(fc = prior_normal(1, 0.3)), generations = 200L,
                         warmup = 120, start = "flow", seed = 2)
  expect_s3_class(fit, "pdm_bayes")
  s <- fit$summary
  expect_lt(abs(s$mean - 1), 0.05)
  expect_lte(s$q05, 1.02)
  expect_gte(s$q95, 0.98)
  expect_lt(s$rhat, 1.2)
  expect_equal(nrow(fit$samples), 100L * 3L)
  expect_output(print(fit), "Bayesian calibration")
  band <- posterior_band(fit, d$forcing, draws = 20L, noise = FALSE)
  expect_true(all(band$q05 <= band$q50 + 1e-12 & band$q50 <= band$q95 + 1e-12))
  noisy <- posterior_band(fit, d$forcing, draws = 20L, noise = TRUE)
  expect_gt(mean(noisy$q95 - noisy$q05), mean(band$q95 - band$q05))
  expect_error(calibrate_bayes(start, d$forcing, d$observed, c(fc = 0.5), c(fc = 1.5),
                               priors = list(cmax = prior_uniform())), "named by parameters")
})

# Guards: a table of predicted parameters becomes priors, widened on request
test_that("priors from a table", {
  t <- data.frame(parameter = c("distribution.cmax", "fc"), median = c(250, NA),
                  sdlog = c(0.3, NA), mean = c(NA, 1), sd = c(NA, 0.1))
  p <- priors_from_table(t, widen = 2)
  expect_equal(p$distribution.cmax, prior_lognormal(250, 0.6))
  expect_equal(p$fc, prior_normal(1, 0.2))
  expect_error(priors_from_table(data.frame(parameter = "b", mean = NA)), "neither")
})
