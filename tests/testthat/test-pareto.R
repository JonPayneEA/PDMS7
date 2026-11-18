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
  expect_error(pareto_choose(f, objective = "a", weights = c(a = 1)), "one of objective")
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
  obs <- .multi_simulator(truth, d$forcing, list(start = "soil"))(truth)
  front <- calibrate_pdm_multi(
    truth, d$forcing, obs, lower = c(fc = 0.6, surface.k1 = 1),
    upper = c(fc = 1.4, surface.k1 = truth$surface$k1 * 3),
    objectives = c("nse_loss", "event_nse_loss", "event_peak_error", "event_timing_error"),
    method = "dds", n_samples = 6, starts = 1, control = list(maxit = 8), warmup = 120,
    event_share = 1, start = "soil"
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
  expect_error(run(objectives = c("nse_loss", "event_timing_error"), method = "lbfgsb"),
               "use method = \"padds\"")
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

# Guards: PA-DDS draws sets from sparse parts of the front more often
test_that("crowding distance weights", {
  # Four sets on a straight front, (0,3) (1,2) (2,1) (3,0). On each objective the inner two
  # have neighbours 2 apart on a range of 3: 2/3 each, 4/3 over both. The ends are infinite and
  # get twice the largest finite distance, 8/3.
  f <- rbind(c(0, 3), c(1, 2), c(2, 1), c(3, 0))
  expect_equal(.crowding_weights(f), c(8, 4, 4, 8) / 3)
})

# Guards: PA-DDS fills in a front that weighted sums cannot reach
test_that("PA-DDS finds the middle of a non-convex front", {
  # Two losses of a point (z1, z2) in the unit square: f1 = z1 and f2 = 1 - z1^2 + z2. The
  # front is z2 = 0, the curve f2 = 1 - f1^2, which bows out above the line from (0, 1) to
  # (1, 0). Any weighted sum w1 f1 + w2 f2 is concave in z1, so its minimum lies at z1 = 0 or
  # z1 = 1: a weighted search can only find the two ends.
  evaluate <- function(z) c(z[1], 1 - z[1]^2 + z[2])
  set.seed(5)
  z <- matrix(stats::runif(20), ncol = 2)
  f <- t(apply(z, 1, evaluate))
  store <- new.env()
  store$f <- NULL
  logged <- function(z) {
    v <- evaluate(z)
    store$f <- rbind(store$f, v)
    v
  }
  set.seed(6)
  .padds(logged, z, f, list(maxit = 400))
  front <- store$f[pareto_front(store$f), , drop = FALSE]
  # Sets well inside the curve are found, close to it (f2 - (1 - f1^2) = z2, small)
  inner <- front[front[, 1] > 0.3 & front[, 1] < 0.7, , drop = FALSE]
  expect_gt(nrow(inner), 3L)
  expect_lt(max(inner[, 2] - (1 - inner[, 1]^2)), 0.1)
  # A weighted DDS refinement of the same losses, equal weights, ends at one end
  set.seed(6)
  fit <- .dds_box(c(0.5, 0.5), function(z) sum(evaluate(z)) / 2, list(maxit = 400))
  expect_lt(min(fit$par[1], 1 - fit$par[1]), 0.1)
})

# Guards: PA-DDS chains on several cores give the answer they give one by one
test_that("PA-DDS is the default and repeatable", {
  d <- log_data(24 * 30)
  run <- function(cores) {
    calibrate_pdm_multi(d$truth, d$forcing, d$observed, lower = c(fc = 0.6, surface.k1 = 1),
                        upper = c(fc = 1.4, surface.k1 = 20),
                        objectives = c("nse_loss", "abs_bias"), n_samples = 4, starts = 2,
                        control = list(maxit = 6), warmup = 48, seed = 3, cores = cores)
  }
  a <- run(1)
  expect_equal(a$method, "padds")
  expect_length(a$optimization, 2L)
  expect_match(a$optimization[[1]]$message, "PA-DDS: 6 model runs")
  # 1 configured + 4 samples + 2 chains x 6 runs, less exact repeats
  expect_lte(nrow(a$archive), 17L)
  expect_identical(a$pareto, run(1)$pareto)
  skip_on_cran()
  expect_identical(run(2)$pareto, a$pareto)
})

# Guards: the knee is the lowest total on the front's own 0-to-1 scales
test_that("the knee of a front", {
  # On the hand-built front, a runs 0.1 to 0.6 and b 0.05 to 0.5. On those scales the sets sit
  # at (0, 1), (0.2, 1/3) and (1, 0): totals 1, 0.533 and 1, so the knee is set 2, the one
  # furthest below the line from (0, 1) to (1, 0).
  f <- fake_front()
  expect_equal(pareto_choose(f, knee = TRUE)$row, 2L)
  expect_equal(.pareto_pick(f, "knee")$row, 2L)
  expect_equal(.pareto_pick(f, "b")$row, 3L)
  expect_error(pareto_choose(f, objective = "a", knee = TRUE), "one of")
})

# Guards: a front scored on new rows, and the band of its flows
test_that("scoring the front on a check period, and its band", {
  d <- log_data(24 * 60)
  truth <- d$truth
  obs <- .multi_simulator(truth, d$forcing, list(start = "soil"))(truth)
  front <- calibrate_pdm_multi(
    truth, d$forcing, obs, lower = c(fc = 0.6), upper = c(fc = 1.4),
    objectives = c("nse_loss", "abs_bias"), n_samples = 4, starts = 1,
    control = list(maxit = 6), warmup = 120, start = "soil"
  )
  # The truth is the whole front, and it is perfect on any rows: both check losses 0
  checked <- pareto_validate(front, d$forcing, obs, 1000:1400)
  expect_equal(checked$validation_rows, c(1000, 1400))
  expect_equal(unlist(checked$validation[, -1]), c(0, 0), ignore_attr = TRUE)
  # One set on the front: its band has no width, and is the truth's flow
  band <- pareto_band(front, d$forcing)
  expect_equal(band$lower, band$upper)
  expect_equal(band$compromise, obs)
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_invisible(plot(checked, "validation"))
  expect_invisible(plot(front, "band", forcing = d$forcing, observed = obs))
  expect_error(plot(front, "validation"), "pareto_validate")
})

# Guards: a project's front keeps a check period cut from the calibration window, never the
# validation window
test_that("a logged front with a check period", {
  p <- new_project()
  e <- log_pareto_calibration(p$folder, 3, lower = c(fc = 0.5), upper = c(fc = 1.5),
                              objectives = c("nse_loss", "abs_bias"), choose = "knee",
                              n_samples = 4, starts = 1, control = list(maxit = 6),
                              check_share = 0.3, reasoning = "Check the trade-off")
  # Calibration rows 121 to 700, 580 rows; 0.3 of them is 174, so rows 527 to 700 are checked
  expect_equal(unlist(e$pareto$check_rows), c(527L, 700L))
  expect_true(all(c("check_loss_nse_loss", "check_loss_abs_bias") %in% names(e$pareto$front)))
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
  blocks <- .rpt_pareto(e)
  expect_equal(vapply(blocks, function(b) b$kind, character(1)),
               c("figure", "figure", "table"))
  expect_match(blocks[[1]]$caption, "the knee")
})

# Guards: a trade-off stage fits a front over the fast response and keeps its knee
test_that("a trade-off stage in staged calibration", {
  d <- log_data(24 * 40)
  stages <- pdm_stages(d$truth, polish = FALSE, pareto = c("nse_loss", "event_peak_error"),
                       pareto_budget = 6L, td_max = NULL)
  last <- stages[[length(stages)]]
  expect_equal(last$name, "trade-off")
  expect_equal(last$objective, "pareto")
  expect_equal(last$pareto$choose, "knee")
  stages <- lapply(stages, function(s) {
    s$control <- list(maxit = 6)
    if (identical(s$objective, "pareto")) s$pareto$n_samples <- 3L
    s
  })
  fit <- calibrate_staged(d$truth, d$forcing, d$observed, stages = stages, warmup = 48,
                          control = list(maxit = 6))
  trade <- fit$stages[[length(fit$stages)]]
  expect_s3_class(trade$front, "pdm_pareto")
  # The kept set is the knee of the stage's front
  expect_equal(trade$chosen, pareto_choose(trade$front, knee = TRUE)$row)
  expect_identical(fit$config, trade$config)
  # In a project, the stage is logged with its front
  p <- new_project()
  stages <- pdm_stages(p$data$truth, polish = FALSE, pareto = c("nse_loss", "abs_bias"),
                       td_max = NULL)
  stages <- lapply(stages, function(s) {
    s$control <- list(maxit = 4)
    if (identical(s$objective, "pareto")) s$pareto$n_samples <- 3L
    s
  })
  written <- log_staged_calibration(p$folder, 3, "Staged with a trade-off", stages = stages)
  e <- written[[length(written)]]
  expect_equal(e$objective, "pareto")
  expect_match(e$stage, "trade-off")
  expect_true(all(verify_project(p$folder, rerun = TRUE)$ok))
})

# Guards: a band of some sets only
test_that("the band of chosen sets", {
  f <- fake_front()
  expect_error(pareto_band(f, data.frame(rain = 1, pet = 0)), "calibrate_pdm_multi")
  f$settings <- list(start = "soil")
  expect_error(pareto_band(f, data.frame(rain = 1, pet = 0), sets = 9), "rows of the front")
})
