# ============================================================ #
# Tool:         test-calibrate_multistart
# Description:  Tests for multi-start calibration: starts, seeds and bounds
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-11-05 - Add DDS tests
# Tier:         1
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

ms_setup <- function() {
  forcing <- make_forcing() # nolint: object_usage_linter.
  truth <- pdm_presets("split")
  truth$fc <- 1.3
  truth$recharge$alpha <- 0.6
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s
  config <- pdm_presets("split")
  config$fc <- 0.8
  config$recharge$alpha <- 0.3
  list(
    config = config, forcing = forcing, observed = observed,
    lower = c(fc = 0.5, recharge.alpha = 0.1),
    upper = c(fc = 2, recharge.alpha = 0.9)
  )
}

# Guards: the multi-start wrapper adds nothing when one start is asked for
test_that(
  "starts = 1 matches a direct single L-BFGS-B run",
  {
    s <- ms_setup()
    fit <- calibrate_pdm(
      s$config, s$forcing, s$observed, s$lower, s$upper,
      control = list(maxit = 4)
    )
    explicit <- calibrate_pdm(
      s$config, s$forcing, s$observed, s$lower, s$upper,
      control = list(maxit = 4), starts = 1L, seed = 99
    )
    # Reference: the original algorithm written out without calibrate_pdm.
    counter <- new.env()
    counter$calls <- 0L
    loss <- function(z) {
      counter$calls <- counter$calls + 1L
      par <- s$lower + z * (s$upper - s$lower)
      cfg <- s$config
      cfg$fc <- par[["fc"]]
      cfg$recharge$alpha <- par[["recharge.alpha"]]
      sim <- run_pdm(pdm_from_config(cfg), s$forcing)$output$q_m3s
      sqrt(mean((sim - s$observed)^2))
    }
    z0 <- c(0.3 / 1.5, 0.2 / 0.8)
    ref <- stats::optim(
      z0, loss, method = "L-BFGS-B", lower = c(0, 0), upper = c(1, 1),
      control = list(maxit = 4)
    )
    ref_par <- s$lower + ref$par * (s$upper - s$lower)
    expect_equal(unname(fit$parameters), unname(ref_par), tolerance = 1e-10)
    expect_lt(abs(fit$objective - ref$value), 1e-9)
    expect_identical(explicit$parameters, fit$parameters)
    expect_identical(explicit$objective, fit$objective)
    expect_equal(nrow(fit$start_results), 1L)
    expect_equal(fit$start_results$evaluations, counter$calls)
    expect_gt(counter$calls, ref$counts[["function"]])
  }
)

# Guards: random starts are reproducible and the caller's random state is restored
test_that(
  "a fixed seed reproduces the multi-start result and restores the RNG",
  {
    s <- ms_setup()
    run <- function() {
      calibrate_pdm(
        s$config, s$forcing, s$observed, s$lower, s$upper,
        control = list(maxit = 3), starts = 3L, seed = 42
      )
    }
    set.seed(7)
    before <- .Random.seed
    a <- run()
    expect_identical(.Random.seed, before)
    b <- run()
    expect_identical(a$parameters, b$parameters)
    expect_identical(a$objective, b$objective)
    expect_identical(a$start_results, b$start_results)
    other <- calibrate_pdm(
      s$config, s$forcing, s$observed, s$lower, s$upper,
      control = list(maxit = 3), starts = 3L, seed = 43
    )
    expect_false(identical(a$start_results$recharge.alpha, other$start_results$recharge.alpha))
  }
)

# Guards: no start leaves its bounds and the returned fit is the best of them
test_that(
  "every start respects the bounds and the best start is returned",
  {
    s <- ms_setup()
    single <- calibrate_pdm(
      s$config, s$forcing, s$observed, s$lower, s$upper,
      control = list(maxit = 3)
    )
    multi <- calibrate_pdm(
      s$config, s$forcing, s$observed, s$lower, s$upper,
      control = list(maxit = 3), starts = 3L, seed = 1
    )
    tab <- multi$start_results
    expect_equal(nrow(tab), 3L)
    expect_equal(tab$start, 1:3)
    expect_true(all(tab$fc >= s$lower[["fc"]] & tab$fc <= s$upper[["fc"]]))
    expect_true(
      all(
        tab$recharge.alpha >= s$lower[["recharge.alpha"]] &
          tab$recharge.alpha <= s$upper[["recharge.alpha"]]
      )
    )
    expect_true(all(multi$parameters >= s$lower & multi$parameters <= s$upper))
    expect_equal(sum(tab$best), 1L)
    expect_identical(multi$objective, min(tab$objective))
    expect_identical(tab$objective[tab$best], multi$objective)
    expect_true(all(tab$convergence %in% 0:52))
    # Start 1 is the configured point, so it reproduces the single start exactly.
    expect_identical(tab$objective[1], single$objective)
    expect_lte(multi$objective, single$objective)
  }
)

# Guards: invalid starts or seed values are refused with a clear message
test_that(
  "starts and seed are validated",
  {
    s <- ms_setup()
    args <- list(s$config, s$forcing, s$observed, s$lower, s$upper)
    for (bad in list(0, -1, 1.5, NA, "2", c(1, 2))) {
      expect_error(do.call(calibrate_pdm, c(args, list(starts = bad))), "starts")
    }
    for (bad in list(NA, Inf, "1", c(1, 2))) {
      expect_error(do.call(calibrate_pdm, c(args, list(seed = bad))), "seed")
    }
  }
)

# Guards: the start table keeps its shape when only one parameter is calibrated
test_that(
  "multi-start works with a single calibrated parameter",
  {
    s <- ms_setup()
    fit <- calibrate_pdm(
      s$config, s$forcing, s$observed, c(fc = 0.5), c(fc = 2),
      control = list(maxit = 3), starts = 3L, seed = 1
    )
    tab <- fit$start_results
    expect_equal(nrow(tab), 3L)
    expect_true(all(tab$fc >= 0.5 & tab$fc <= 2))
    expect_identical(fit$objective, min(tab$objective))
  }
)

# Guards: DDS spends exactly its budget, stays in bounds, reproduces from a seed, leaves the
# caller's random stream alone, and finds the truth on a smooth two-parameter problem
test_that(
  "dds searches within budget and bounds, reproducibly",
  {
    s <- ms_setup()
    run <- function(seed, starts = 2L) {
      calibrate_pdm(s$config, s$forcing, s$observed, s$lower, s$upper, method = "dds",
                    control = list(maxit = 150), starts = starts, seed = seed)
    }
    set.seed(3)
    before <- stats::runif(1)
    set.seed(3)
    fit <- run(5)
    expect_equal(stats::runif(1), before)
    expect_identical(fit$start_results, run(5)$start_results)
    expect_false(identical(fit$start_results, run(6)$start_results))
    expect_equal(fit$start_results$evaluations, c(150L, 150L))
    expect_equal(fit$method, "dds")
    expect_match(fit$message, "DDS: 150 model runs")
    expect_true(all(fit$start_results$fc >= 0.5 & fit$start_results$fc <= 2))
    expect_equal(unname(fit$parameters), c(1.3, 0.6), tolerance = 0.05)
    expect_error(calibrate_pdm(s$config, s$forcing, s$observed, s$lower, s$upper,
                               method = "dds", control = list(maxit = 0.5)), "model runs")
    expect_error(calibrate_pdm(s$config, s$forcing, s$observed, s$lower, s$upper,
                               method = "dds", control = list(r = -1)), "control\\$r")
  }
)

# Guards: a DDS step past a bound is reflected inside, never left outside the unit box
test_that(
  "dds reflects steps at the bounds",
  {
    seen <- new.env()
    seen$z <- list()
    loss <- function(z) {
      seen$z[[length(seen$z) + 1L]] <- z
      sum((z - c(0, 1))^2)
    }
    set.seed(1)
    fit <- pdmS7:::.dds_box(c(0.01, 0.99), loss, list(maxit = 300, r = 0.5))
    trials <- do.call(rbind, seen$z)
    expect_true(all(trials >= 0 & trials <= 1))
    expect_equal(nrow(trials), 300L)
    expect_lt(fit$value, 1e-3)
  }
)

# Guards: starts run on several cores give exactly the result of running them one by one,
# including every start's row and the archive of trials
test_that("starts on several cores match starts run one by one", {
  skip_on_cran()
  f <- data.frame(rain = rep(c(0, 8, 3, 0, 0, 1), 20), pet = 0.05)
  cfg <- pdm_presets("standard")
  q <- run_pdm(pdm_from_config(cfg), f)$output$q_m3s
  fit <- function(cores, method) {
    calibrate_pdm(cfg, f, q, lower = c(fc = 0.8, "surface.k1" = 1),
                  upper = c(fc = 1.2, "surface.k1" = 6), method = method, starts = 3L, seed = 2,
                  control = list(maxit = 15), archive = function(x) sum(x), cores = cores)
  }
  for (method in c("lbfgsb", "dds")) {
    one <- fit(1L, method)
    two <- fit(2L, method)
    expect_identical(two$parameters, one$parameters)
    expect_identical(two$start_results, one$start_results)
    expect_identical(two$trials, one$trials)
  }
  expect_error(fit(0, "dds"), "cores")
})
