# ============================================================ #
# Tool:         test_forecast_compare
# Description:  Candidates ranked as forecasters by hindcast skill and threshold scores
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       A synthetic record whose true model is known
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

forecast_case <- function() {
  set.seed(1)
  n <- 24 * 40
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.06, stats::rgamma(n, 0.7, scale = 4),
                                      0), pet = 0.05)
  truth <- pdm_model(area_km2 = 40, fc = 1.1)
  start <- initial_state(truth, 0.5)
  list(forcing = forcing, observed = run_pdm(truth, forcing, start)$output$q_m3s,
       truth = truth, wrong = pdm_model(area_km2 = 40, fc = 0.7), start = start)
}

# Guards: the true model ranks first; the ranking is the mean of the rows it is judged on
test_that("the true model is the better forecaster", {
  d <- forecast_case()
  # Both start from the state that made the record, so the true model's open loop is exact
  cmp <- compare_forecasts(list(wrong = d$wrong, truth = d$truth), d$forcing, d$observed,
                           horizon_h = 12, every_h = 12, method = "none", state = d$start,
                           ar = list())
  expect_s3_class(cmp, "pdm_forecast_comparison")
  expect_equal(cmp$ranking$candidate, c("truth", "wrong"))
  expect_equal(cmp$ranking$rank, 1:2)
  # Open loop, the true model's forecasts are exact: skill 1 at every lead
  t <- cmp$chosen[cmp$chosen$candidate == "truth"]
  expect_equal(t$skill, rep(1, nrow(t)))
  w <- cmp$chosen[cmp$chosen$candidate == "wrong"]
  expect_equal(cmp$ranking$mean_skill[2], mean(w$skill))
  expect_output(print(cmp), "2 candidates")
})

# Guards: the best method at each lead, threshold ranking, and the checks
test_that("best methods, thresholds and checks", {
  d <- forecast_case()
  top <- c(high = unname(stats::quantile(d$observed, 0.95)))
  cmp <- compare_forecasts(list(truth = d$truth, wrong = d$wrong), d$forcing, d$observed,
                           horizon_h = 6, every_h = 12, thresholds = top,
                           ar = list(ea = ar_ea_default()), rank_on = "threshold",
                           leads_h = c(1, 3))
  # Each candidate is judged once a lead, on its best method by skill
  expect_equal(nrow(cmp$chosen), 2L * 2L)
  for (nm in c("truth", "wrong")) {
    for (l in c(1, 3)) {
      all <- cmp$scores[cmp$scores$candidate == nm & cmp$scores$lead_h == l &
                          cmp$scores$method != "persistence"]
      got <- cmp$chosen[cmp$chosen$candidate == nm & cmp$chosen$lead_h == l]
      expect_equal(got$skill, max(all$skill))
    }
  }
  expect_true(all(is.finite(cmp$ranking$mean_threshold)))
  expect_error(compare_forecasts(list(d$truth), d$forcing, d$observed), "unique names")
  expect_error(compare_forecasts(list(a = d$truth), d$forcing, d$observed,
                                 rank_on = "threshold"), "needs thresholds")
  pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_invisible(plot(cmp))
})
