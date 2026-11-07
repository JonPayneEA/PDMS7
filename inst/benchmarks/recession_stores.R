# ============================================================ #
# Tool:         recession_stores benchmark
# Description:  Can the groundwater store be identified from the record? Made-up catchments
#               with each store and two recharge rules, each fitted with all four stores, and
#               four rules for choosing among them
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         3
# Inputs:       None: synthetic rain and known truths
# Outputs:      inst/extdata/recession_stores.csv, one row per truth and candidate store
# Dependencies: pdmS7; parallel
# ============================================================ #
#
# Usage, from the package root: Rscript inst/benchmarks/recession_stores.R
# About 64 staged calibrations of seven years of hourly data; about 25 minutes on one core.

library(pdmS7)

stores <- list(
  linear = list(type = "linear", kb = 1500),
  quadratic = list(type = "quadratic", kb = 30000),
  cubic = list(type = "cubic", kb = 1e6),
  exponential = list(type = "exponential", a = 0.03, gamma = -6)
)
recharges <- list(standard = list(type = "standard", kg = 1000, bg = 1, st = 0),
                  split = list(type = "split", alpha = 0.6))
seeds <- c(5, 11)
years <- 10
fit_rows <- seq_len(7 * 8760)
check_rows <- seq(7 * 8760 + 1, years * 8760)

base <- pdm_presets("standard")
base$area_km2 <- 50

slope_of <- function(q, rain) {
  out <- tryCatch(recession_analysis(q, rain, dt = 1, boot = 0)$slope, error = function(e) NA)
  out
}
nse <- function(s, o) 1 - sum((s - o)^2) / sum((o - mean(o))^2)

one_truth <- function(job) {
  r <- synthetic_rain("2000-10-01", years = years, dt = 1, seed = job$seed)
  forcing <- data.frame(rain = r$rain, pet = r$pet)
  truth <- base
  truth$groundwater <- stores[[job$store]]
  truth$recharge <- recharges[[job$recharge]]
  # The record starts in steady state at 0.5 m3/s, as a river does; from empty stores its first
  # flow would be zero, at which an exponential store has no state to start from.
  model <- pdm_from_config(truth)
  set.seed(job$seed)
  observed <- run_pdm(model, forcing, initial_state_from_flow(model, 0.5, 0.7))$output$q_m3s *
    exp(stats::rnorm(nrow(forcing), 0, 0.03))
  observed_slope <- slope_of(observed, forcing$rain)
  do.call(rbind, lapply(names(stores), function(candidate) {
    start <- base
    start$groundwater <- stores[[candidate]]
    start$recharge <- recharges[[job$recharge]]
    fit <- tryCatch(
      calibrate_staged(start, forcing[fit_rows, ], observed[fit_rows], warmup = 8760,
                       control = list(maxit = 30), seed = 1),
      error = function(e) NULL
    )
    if (is.null(fit)) {
      return(data.frame(truth = job$store, recharge = job$recharge, seed = job$seed,
                        candidate = candidate, val_nse = NA, val_log_nse = NA,
                        observed_slope = observed_slope, simulated_slope = NA))
    }
    sim <- run_pdm(fit$model, forcing, initial_state_from_flow(fit$model, observed[1],
                                                               0.7))$output$q_m3s
    data.frame(truth = job$store, recharge = job$recharge, seed = job$seed,
               candidate = candidate,
               val_nse = nse(sim[check_rows], observed[check_rows]),
               val_log_nse = nse(log(sim[check_rows] + 0.01), log(observed[check_rows] + 0.01)),
               observed_slope = observed_slope, simulated_slope = slope_of(sim, forcing$rain))
  }))
}

jobs <- expand.grid(store = names(stores), recharge = names(recharges), seed = seeds,
                    stringsAsFactors = FALSE)
jobs <- split(jobs, seq_len(nrow(jobs)))
cores <- min(4L, parallel::detectCores())
results <- do.call(rbind, parallel::mclapply(jobs, one_truth, mc.cores = cores))
rownames(results) <- NULL
utils::write.csv(results, file.path("inst", "extdata", "recession_stores.csv"), row.names = FALSE)
print(results)
