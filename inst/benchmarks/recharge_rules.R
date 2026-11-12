# ============================================================ #
# Tool:         recharge_rules benchmark
# Description:  Can the recharge rule be identified from the record? Made-up catchments with
#               standard, split and demand recharge, each fitted with all three
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         1
# Inputs:       None: synthetic rain and known truths
# Outputs:      inst/extdata/recharge_rules.csv, one row per truth and candidate rule
# Dependencies: pdmS7; parallel
# ============================================================ #
#
# Usage, from the package root: Rscript inst/benchmarks/recharge_rules.R
# 27 staged calibrations of seven years of hourly data; about 15 minutes on four cores.
#
# Besides the validation scores, one diagnostic needs no model: across each event found by
# find_events(), how far the baseflow line rises, and how closely that follows the event's quick
# flow. Split recharge sends a fixed share of each event's runoff to groundwater, so the rise
# should follow the quick flow; standard and demand recharge fill groundwater from the soil
# store, between events as well as during them.

library(pdmS7)

recharges <- list(
  standard = list(type = "standard", kg = 3000, bg = 1, st = 0),
  split = list(type = "split", alpha = 0.6),
  demand = list(type = "demand", alpha = 0.5, beta = 1, qsat = 0.03)
)
seeds <- c(5, 11, 17)
years <- 10
fit_rows <- seq_len(7 * 8760)
check_rows <- seq(7 * 8760 + 1, years * 8760)

base <- pdm_presets("standard")
base$area_km2 <- 50

nse <- function(s, o) 1 - sum((s - o)^2) / sum((o - mean(o))^2)

# Correlation across events between the rise of the baseflow line and the event's quick flow.
rise_follows_quick <- function(rain, flow) {
  ev <- find_events(rain, flow, dt = 1, area_km2 = base$area_km2)
  baseflow <- attr(ev, "baseflow")
  rise <- baseflow[ev$flow_end] - baseflow[ev$flow_start]
  ok <- is.finite(rise) & is.finite(ev$quickflow_mm)
  stats::cor(rise[ok], ev$quickflow_mm[ok])
}

one_truth <- function(job) {
  r <- synthetic_rain("2000-10-01", years = years, dt = 1, seed = job$seed)
  forcing <- data.frame(rain = r$rain, pet = r$pet)
  truth <- base
  truth$recharge <- recharges[[job$recharge]]
  model <- pdm_from_config(truth)
  set.seed(job$seed)
  observed <- suppressWarnings(
    run_pdm(model, forcing, initial_state_from_flow(model, 0.3, 0.7))$output$q_m3s
  ) * exp(stats::rnorm(nrow(forcing), 0, 0.03))
  observed_rise <- rise_follows_quick(forcing$rain, observed)
  do.call(rbind, lapply(names(recharges), function(candidate) {
    start <- base
    start$recharge <- recharges[[candidate]]
    fit <- tryCatch(
      suppressWarnings(calibrate_staged(start, forcing[fit_rows, ], observed[fit_rows],
                                        warmup = 8760, control = list(maxit = 30), seed = 1)),
      error = function(e) NULL
    )
    row <- data.frame(truth = job$recharge, seed = job$seed, candidate = candidate,
                      val_nse = NA_real_, val_log_nse = NA_real_,
                      observed_rise_cor = observed_rise, simulated_rise_cor = NA_real_)
    if (is.null(fit)) return(row)
    sim <- suppressWarnings(run_pdm(fit$model, forcing,
                                    initial_state_from_flow(fit$model, observed[1],
                                                            0.7))$output$q_m3s)
    row$val_nse <- nse(sim[check_rows], observed[check_rows])
    row$val_log_nse <- nse(log(sim[check_rows] + 0.01), log(observed[check_rows] + 0.01))
    row$simulated_rise_cor <- rise_follows_quick(forcing$rain, sim)
    row
  }))
}

jobs <- expand.grid(recharge = names(recharges), seed = seeds, stringsAsFactors = FALSE)
jobs <- split(jobs, seq_len(nrow(jobs)))
cores <- min(4L, parallel::detectCores())
results <- do.call(rbind, parallel::mclapply(jobs, one_truth, mc.cores = cores))
rownames(results) <- NULL
utils::write.csv(results, file.path("inst", "extdata", "recharge_rules.csv"), row.names = FALSE)
print(results)
