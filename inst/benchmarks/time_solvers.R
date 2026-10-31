# ============================================================ #
# Tool:         time_solvers
# Description:  Time the cubic groundwater solvers (adaptive RK4 and Smith)
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-31
# Modified:     2026-10-31 - Add solver timing benchmark
# Tier:         3
# Inputs:       None; synthetic daily forcing from a fixed seed
# Outputs:      Console report in markdown; figures apply to the machine used
# Dependencies: pdmS7; data.table
# ============================================================ #
# Usage, from the package root:
#   Rscript inst/benchmarks/time_solvers.R
# Optional environment variables: PDM_BENCH_REPEATS (default 3), PDM_BENCH_STEPS (default 10600),
# PDM_BENCH_CAL_STEPS (default 1000).
# The calibration uses the default control (maxit = 200) on the first PDM_BENCH_CAL_STEPS steps.
# It needs hundreds of simulations, so running it on the full series takes hours. The number of
# objective evaluations is what the extrapolation uses; set PDM_BENCH_CAL_STEPS to
# PDM_BENCH_STEPS to calibrate on the full series.

if (requireNamespace("pkgload", quietly = TRUE) && file.exists("DESCRIPTION")) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  library(pdmS7)
}

n_steps <- as.integer(Sys.getenv("PDM_BENCH_STEPS", "10600"))
repeats <- as.integer(Sys.getenv("PDM_BENCH_REPEATS", "3"))
cal_steps <- min(n_steps, as.integer(Sys.getenv("PDM_BENCH_CAL_STEPS", "1000")))
timestep_min <- 1440L

# Synthetic daily forcing: intermittent gamma rainfall and a seasonal PET curve.
set.seed(20261031)
wet <- stats::runif(n_steps) < 0.4
rain <- ifelse(wet, stats::rgamma(n_steps, shape = 0.6, scale = 12), 0)
pet <- pmax(0, 2 + 1.5 * sin(2 * pi * seq_len(n_steps) / 365.25))

config <- pdm_presets("standard")
config$area_km2 <- 100
with_solver <- function(cfg, solver) {
  cfg$groundwater <- list(type = "cubic", kb = cfg$groundwater$kb, solver = solver)
  cfg
}

time_one <- function(solver) {
  cfg <- with_solver(config, solver)
  invisible(sim_pdm(rain, pet, cfg, timestep_min))  # untimed warm-up
  elapsed <- vapply(
    seq_len(repeats),
    function(i) unname(system.time(sim_pdm(rain, pet, cfg, timestep_min))[["elapsed"]]),
    numeric(1)
  )
  list(elapsed = elapsed, flow = sim_pdm(rain, pet, cfg, timestep_min)$qsim_cms)
}
adaptive <- time_one("adaptive")
smith <- time_one("smith")
med_adaptive <- stats::median(adaptive$elapsed)
med_smith <- stats::median(smith$elapsed)
max_diff <- max(abs(adaptive$flow - smith$flow))

# One real calibration: three parameters, default optimiser control, first cal_steps steps.
cal_rows <- seq_len(cal_steps)
truth <- with_solver(config, "adaptive")
truth$dt <- 24
truth$fc <- 1.2
truth$recharge$kg <- 30
truth$groundwater$kb <- 12000
cal_forcing <- data.frame(rain = rain[cal_rows], pet = pet[cal_rows])
observed <- run_pdm(pdm_from_config(truth), cal_forcing)$output$q_m3s
start <- with_solver(config, "adaptive")
start$dt <- 24
cal_seconds <- unname(system.time(
  fit <- calibrate_pdm(
    start, cal_forcing, observed,
    lower = c(fc = 0.5, recharge.kg = 5, groundwater.kb = 5000),
    upper = c(fc = 2, recharge.kg = 60, groundwater.kb = 20000)
  )
)[["elapsed"]])
evals <- fit$start_results$evaluations[fit$start_results$best]

# Extrapolation: basins x starts x evaluations x seconds per simulation.
basins <- 60L
starts <- 20L
total_evals <- basins * starts * evals
cores <- c(1L, 4L, 16L, 64L)
hours <- function(sec_per_sim, k) total_evals * sec_per_sim / k / 3600

cat("# Solver timing\n\n")
cat(sprintf("Machine: %s, %d logical cores, R %s, %s\n", Sys.info()[["machine"]],
            parallel::detectCores(), getRversion(), format(Sys.time(), "%Y-%m-%d", tz = "UTC")))
cat(sprintf("Series: %d daily steps, standard preset, cubic groundwater, seed 20261031\n\n",
            n_steps))
cat("| Solver | Repeats (s) | Median s per simulation |\n|---|---|---|\n")
cat(sprintf("| adaptive | %s | %.3f |\n", paste(sprintf("%.3f", adaptive$elapsed), collapse = ", "),
            med_adaptive))
cat(sprintf("| smith | %s | %.3f |\n\n", paste(sprintf("%.3f", smith$elapsed), collapse = ", "),
            med_smith))
cat(sprintf("Speed-up (adaptive / smith): %.1fx\n", med_adaptive / med_smith))
cat(sprintf("Maximum absolute flow difference, adaptive vs smith: %.6g m3/s\n", max_diff))
cat(sprintf("Maximum simulated flow (adaptive): %.6g m3/s\n\n", max(adaptive$flow)))
cat(sprintf(
  paste0("Calibration (3 parameters, L-BFGS-B, maxit 200, first %d steps): %d objective ",
         "evaluations, %.1f s, objective %.6g, convergence %d\n\n"),
  cal_steps, evals, cal_seconds, fit$objective, fit$convergence
))
cat(sprintf("Extrapolation: %d basins x %d starts x %d evaluations = %s simulations\n\n",
            basins, starts, evals, format(total_evals, big.mark = ",")))
cat("| Cores | adaptive (hours) | smith (hours) |\n|---|---|---|\n")
for (k in cores) {
  cat(sprintf("| %d | %.2f | %.2f |\n", k, hours(med_adaptive, k), hours(med_smith, k)))
}
