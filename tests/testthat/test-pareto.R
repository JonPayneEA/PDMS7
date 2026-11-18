# ============================================================ #
# Tool:         test_pareto
# Description:  Event and threshold losses in calibrate_pdm_multi(), DDS, choosing from the
#               front, the front plots and the logged front
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Hand-built fronts; the synthetic record of helper-calibration.R
# Outputs:      testthat expectations
# Dependencies: testthat; data.table
# ============================================================ #

# A front built by hand: three sets on two losses, a and b, scales 1.
#   set 1: a 0.1, b 0.5    set 2: a 0.2, b 0.2    set 3: a 0.6, b 0.05
# and one evaluated set off the front, a 0.7, b 0.6. The compromise is set 2.
fake_front <- function() {
  arch <- data.table::data.table(p = c(1, 2, 3, 4), loss_a = c(0.1, 0.2, 0.6, 0.7),
                                 loss_b = c(0.5, 0.2, 0.05, 0.6))
  arch$pareto <- c(TRUE, TRUE, TRUE, FALSE)
  arch$scaled_a <- arch$loss_a
  arch$scaled_b <- arch$loss_b
  front <- arch[arch$pareto]
  structure(list(archive = arch, pareto = front,
                 configs = lapply(1:3, function(i) list(p = i)),
                 compromise = list(config = list(p = 2), scores = front[2]),
                 objectives = c("a", "b"), parameters = "p", scales = c(a = 1, b = 1),
                 method = "dds", failed_evaluations = 0L),
            class = c("pdm_pareto", "list"))
}

# Guards: the quicker front test gives the same answer as the definition, ties included
test_that("the Pareto front by the definition, ties kept", {
  # (1,2) twice: equal rows do not dominate each other. (2,2) is beaten by (1,2). (2,1) and
  # (3,0) trade off against (1,2).
  x <- rbind(c(1, 2), c(1, 2), c(2, 1), c(2, 2), c(3, 0))
  expect_identical(pareto_front(x), c(TRUE, TRUE, TRUE, FALSE, TRUE))
  # The trade-off line of a pair: by a, each point lower in b than all before it
  expect_identical(.front_2d(x[, 1], x[, 2]), c(1L, 3L, 5L))
})

# Guards: a corner is the best set on one loss; weights pick the lowest weighted sum
test_that("choosing from the front", {
  f <- fake_front()
  expect_equal(pareto_choose(f, objective = "a")$row, 1L)
  expect_equal(pareto_choose(f, objective = "b")$row, 3L)
  # Equal weights: sums 0.6, 0.4 and 0.65, so set 2
  expect_equal(pareto_choose(f, weights = c(a = 1, b = 1))$row, 2L)
  # b alone (a counts 0): set 3
  expect_equal(pareto_choose(f, weights = c(b = 2))$row, 3L)
  expect_equal(pareto_choose(f)$row, 2L)
  expect_equal(pareto_choose(f)$config$p, 2)
  expect_error(pareto_choose(f, objective = "c"), "one of")
  expect_error(pareto_choose(f, objective = "a", weights = c(a = 1)), "not both")
})

# Guards: the plots draw what the front holds
test_that("the pairs and parallel plots of a front", {
  f <- fake_front()
  pairs <- .spec_pareto_pairs(f, c("a", "b"))
  s <- pairs$series
  expect_equal(sum(s$label == "On the front"), 3L)
  expect_equal(s$y[s$label == "Compromise"], 0.2)
  # The view is cut at the front's worst plus half its distance from the best evaluated: a at
  # 0.6 + 0.5 x (0.6 - 0.1) = 0.85, b at 0.5 + 0.5 x (0.5 - 0.05) = 0.725. The off-front set
  # (0.7, 0.6) is inside both: nothing cut.
  expect_equal(sum(s$label == "Evaluated"), 4L)
  expect_match(pairs$subtitle, "3 of 4 evaluated sets on the front$")
  # Parallel axes run from the front's best (0) to its worst (1): set 2 sits at
  # (0.2 - 0.1) / 0.5 = 0.2 on a and (0.2 - 0.05) / 0.45 = 1/3 on b
  par <- .spec_pareto_parallel(f, c("a", "b"))$series
  comp <- par[par$label == "Compromise", ]
  expect_equal(comp$y, c(0.2, 1 / 3))
  expect_equal(par$y[par$label == "Best on a"], c(0, 1))
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_invisible(plot(f))
  expect_invisible(plot(f, "parallel"))
  expect_error(plot(f, "pairs", objectives = "a"), "at least two")
})

# Guards: the event losses are the three terms of the events objective
test_that("event losses in closed form", {
  d <- log_data()
  dt <- 1
  events <- find_events(d$forcing$rain, d$observed, dt = dt, area_km2 = 20, independent = TRUE)
  t <- .event_terms(events, d$forcing$rain, d$observed, 120, dt, share = 1, screen = NULL)
  # A perfect simulation scores 0 on all three
  obs <- ifelse(is.finite(d$observed), d$observed, 0)
  expect_equal(unname(t$terms(obs)), c(0, 0, 0))
  # Ten per cent high everywhere: every peak 10% high, at the same hour, so peak error 0.1 and
  # timing 0; and 1 - event NSE = sum((0.1 obs)^2) / sum((obs - window mean)^2)
  w <- .event_windows(events, d$forcing$rain, d$observed, 120, dt, 1, NULL, 20)$windows
  o <- d$observed[unlist(w)]
  g <- rep(seq_along(w), lengths(w))
  expected_nse <- sum((0.1 * o)^2) / sum((o - stats::ave(o, g))^2)
  got <- t$terms(1.1 * obs)
  expect_equal(got[["peak"]], 0.1)
  expect_equal(got[["timing"]], 0)
  expect_equal(got[["nse"]], expected_nse)
  # The weighted objective is the weighted sum of the terms
  obj <- .event_objective(events, d$forcing$rain, d$observed, 120, dt,
                          c(nse = 1, peak = 0.5, timing = 0.5), 1, NULL)
  expect_equal(obj$score(1.1 * obs), expected_nse + 0.5 * 0.1)
})

# Guards: a search started at the truth keeps the truth as the whole front
test_that("a perfect start is the whole front, with event and whole-record losses", {
  d <- log_data(24 * 60)
  truth <- d$truth
  # Observed flow from the same simulator, so the truth scores exactly 0 on every loss and
  # nothing can beat it
  obs <- .multi_simulator(truth, d$forcing)(truth)
  front <- calibrate_pdm_multi(
    truth, d$forcing, obs, lower = c(fc = 0.6, surface.k1 = 1),
    upper = c(fc = 1.4, surface.k1 = truth$surface$k1 * 3),
    objectives = c("nse_loss", "event_nse_loss", "event_peak_error", "event_timing_error"),
    method = "dds", n_samples = 6, starts = 1, control = list(maxit = 8), warmup = 120,
    event_share = 1
  )
  expect_s3_class(front, "pdm_pareto")
  expect_equal(nrow(front$pareto), 1L)
  expect_equal(front$pareto$fc, truth$fc)
  expect_equal(unlist(front$pareto[, paste0("loss_", front$objectives), with = FALSE]),
               rep(0, 4), ignore_attr = TRUE)
  expect_gt(front$events$scored, 0)
  # Every refinement ran by DDS: 1 sampled start for each of 4 + 1 weight rows
  expect_length(front$optimization, 5L)
  expect_output(print(front), "Pareto front: 1 of")
})

# Guards: losses that change in steps need DDS; the threshold loss needs thresholds
test_that("objective checks", {
  d <- log_data(24 * 20)
  run <- function(...) {
    calibrate_pdm_multi(d$truth, d$forcing, d$observed, lower = c(fc = 0.6),
                        upper = c(fc = 1.4), n_samples = 1, starts = 1, ...)
  }
  expect_error(run(objectives = c("nse_loss", "event_timing_error")), "method = \"dds\"")
  expect_error(run(objectives = c("nse_loss", "threshold_loss"), method = "dds"),
               "needs thresholds")
  expect_error(run(objectives = c("nse_loss", "nonsense")), "unique names")
  # A threshold the flow reaches gives a loss between 0 and 1
  top <- stats::quantile(d$observed, 0.95, na.rm = TRUE)
  f <- run(objectives = c("nse_loss", "threshold_loss"), method = "dds",
           thresholds = c(high = unname(top)), control = list(maxit = 3))
  expect_true(all(f$archive$loss_threshold_loss >= 0 & f$archive$loss_threshold_loss <= 1))
})

# Guards: a logged front keeps the whole front, logs the chosen set, and still verifies
test_that("a Pareto calibration in the calibration log", {
  p <- new_project()
  e <- log_pareto_calibration(p$folder, 3, lower = c(fc = 0.5), upper = c(fc = 1.5),
                              objectives = c("nse_loss", "abs_bias"), choose = "abs_bias",
                              n_samples = 4, starts = 1, control = list(maxit = 6),
                              reasoning = "See the trade-off")
  expect_equal(e$type, "auto_calibration")
  expect_equal(e$objective, "pareto")
  front <- data.table::as.data.table(lapply(e$pareto$front, unlist))
  # The logged set is the front's best on volume
  expect_equal(e$configuration$fc, front$fc[which.min(front$loss_abs_bias)])
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
  expect_equal(nrow(calibration_path(p$folder)$stages), 1L)
  blocks <- .rpt_pareto(e)
  expect_equal(vapply(blocks, function(b) b$kind, character(1)), c("figure", "table"))
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_no_error(blocks[[1]]$draw())
})
