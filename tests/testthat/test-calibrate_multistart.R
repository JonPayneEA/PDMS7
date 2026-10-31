# ============================================================ #
# Tool:         test-calibrate_multistart
# Description:  Configurable PDM framework: test-calibrate_multistart
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-31 - Add multi-start calibration tests
# Tier:         3
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
    loss <- function(z) {
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
    expect_equal(fit$start_results$evaluations, ref$counts[["function"]])
  }
)

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
