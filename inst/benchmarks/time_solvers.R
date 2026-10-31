# ============================================================ #
# Tool:         time_solvers
# Description:  Time the cubic groundwater solvers and the R and compiled engines
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-31
# Modified:     2026-10-31 - Add compiled engine and 15-minute series
# Tier:         3
# Inputs:       None; synthetic daily and 15-minute forcing from fixed seeds
# Outputs:      Console report in markdown; figures apply to the machine used
# Dependencies: pdmS7; data.table
# ============================================================ #
# Usage, from the package root:
#   Rscript inst/benchmarks/time_solvers.R
# Optional environment variables: PDM_BENCH_REPEATS (default 3), PDM_BENCH_STEPS (daily steps,
# default 10600), PDM_BENCH_YEARS (15-minute series length in years, default 29),
# PDM_BENCH_R_ENGINE (time the R reference loop on the daily series, default 1).

if (requireNamespace("pkgload", quietly = TRUE) && file.exists("DESCRIPTION")) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  library(pdmS7)
}

n_steps <- as.integer(Sys.getenv("PDM_BENCH_STEPS", "10600"))
repeats <- as.integer(Sys.getenv("PDM_BENCH_REPEATS", "3"))
years <- as.numeric(Sys.getenv("PDM_BENCH_YEARS", "29"))
time_r_engine <- Sys.getenv("PDM_BENCH_R_ENGINE", "1") == "1"
n_quarter <- as.integer(round(years * 365.25 * 96))

# Synthetic forcing: intermittent gamma rainfall and a seasonal PET curve, in mm per interval.
make_forcing <- function(n, per_day, seed) {
  set.seed(seed)
  day <- seq_len(n) / per_day
  wet <- stats::runif(n) < 0.4
  data.frame(
    rain = ifelse(wet, stats::rgamma(n, shape = 0.6, scale = 12 / per_day), 0),
    pet = pmax(0, 2 + 1.5 * sin(2 * pi * day / 365.25)) / per_day
  )
}
daily <- make_forcing(n_steps, 1, 20261031)
quarter <- make_forcing(n_quarter, 96, 20261101)

config <- pdm_presets("standard")
config$area_km2 <- 100
with_solver <- function(cfg, solver) {
  cfg$groundwater <- list(type = "cubic", kb = cfg$groundwater$kb, solver = solver)
  cfg
}

timed <- function(expr_fun) {
  invisible(expr_fun())  # untimed warm-up
  vapply(
    seq_len(repeats),
    function(i) unname(system.time(expr_fun())[["elapsed"]]),
    numeric(1)
  )
}
run_sim <- function(forcing, solver, minutes) {
  sim_pdm(forcing$rain, forcing$pet, with_solver(config, solver), minutes)
}
row <- function(label, elapsed, steps) {
  cat(sprintf("| %s | %s | %.4g | %.3g |\n", label,
              paste(sprintf("%.4g", elapsed), collapse = ", "),
              stats::median(elapsed), stats::median(elapsed) / steps * 1e6))
}

cat("# Solver and engine timing\n\n")
cat(sprintf("Machine: %s, %d logical cores, R %s, %s\n", Sys.info()[["machine"]],
            parallel::detectCores(), getRversion(), format(Sys.time(), "%Y-%m-%d", tz = "UTC")))
cat(sprintf("Daily: %d steps. 15-minute: %d steps (%g years). Standard preset, cubic groundwater.\n\n",
            n_steps, n_quarter, years))
cat("| Run | Repeats (s) | Median s per simulation | Microseconds per step |\n|---|---|---|---|\n")

t_daily <- list()
for (solver in c("adaptive", "smith")) {
  t_daily[[solver]] <- timed(function() run_sim(daily, solver, 1440L))
  row(paste("daily, compiled,", solver), t_daily[[solver]], n_steps)
}
if (time_r_engine) {
  options(pdmS7.engine = "r")
  t_r <- timed(function() run_sim(daily, "adaptive", 1440L))
  options(pdmS7.engine = "auto")
  row("daily, R loop, adaptive", t_r, n_steps)
}
t_quarter <- list()
for (solver in c("adaptive", "smith")) {
  t_quarter[[solver]] <- timed(function() run_sim(quarter, solver, 15L))
  row(paste("15-minute, compiled,", solver), t_quarter[[solver]], n_quarter)
}

# Calibration evaluations use the lean flow path, which skips the full flux table.
lean_cfg <- with_solver(config, "adaptive")
lean_cfg$dt <- 0.25
lean_model <- pdm_from_config(lean_cfg)
lean_state <- initial_state(lean_model)
t_lean <- timed(function() pdmS7:::.run_flow(lean_model, quarter, lean_state, "q_m3s"))
row("15-minute, compiled, adaptive, flow only", t_lean, n_quarter)

diff_of <- function(forcing, minutes) {
  max(abs(run_sim(forcing, "adaptive", minutes)$qsim_cms -
            run_sim(forcing, "smith", minutes)$qsim_cms))
}
peak_daily <- max(run_sim(daily, "adaptive", 1440L)$qsim_cms)
peak_quarter <- max(run_sim(quarter, "adaptive", 15L)$qsim_cms)
cat(sprintf("\nMaximum absolute flow difference, adaptive vs smith: daily %.6g m3/s (peak %.6g); ",
            diff_of(daily, 1440L), peak_daily))
cat(sprintf("15-minute %.6g m3/s (peak %.6g)\n\n", diff_of(quarter, 15L), peak_quarter))

# One real calibration on the full daily series: three parameters, default optimiser control.
truth <- with_solver(config, "adaptive")
truth$dt <- 24
truth$fc <- 1.2
truth$recharge$kg <- 30
truth$groundwater$kb <- 12000
observed <- run_pdm(pdm_from_config(truth), daily)$output$q_m3s
start <- with_solver(config, "adaptive")
start$dt <- 24
cal_seconds <- unname(system.time(
  fit <- calibrate_pdm(
    start, daily, observed,
    lower = c(fc = 0.5, recharge.kg = 5, groundwater.kb = 5000),
    upper = c(fc = 2, recharge.kg = 60, groundwater.kb = 20000)
  )
)[["elapsed"]])
evals <- fit$start_results$evaluations[fit$start_results$best]
cat(sprintf(
  paste0("Calibration (daily, %d steps, 3 parameters, L-BFGS-B, maxit 200): %d objective ",
         "evaluations including gradient calls (optim reports %d), %.1f s, objective %.6g, ",
         "convergence %d\n\n"),
  n_steps, evals, fit$optim$counts[["function"]], cal_seconds, fit$objective, fit$convergence
))

# Extrapolation: basins x starts x evaluations x seconds per evaluation.
basins <- 60L
starts <- 20L
total_evals <- basins * starts * evals
cores <- c(1L, 4L, 16L, 64L)
per_eval_daily <- cal_seconds / evals
per_eval_quarter <- stats::median(t_lean)
cat(sprintf("Extrapolation: %d basins x %d starts x %d evaluations = %s evaluations\n\n",
            basins, starts, evals, format(total_evals, big.mark = ",")))
cat("| Cores | Daily (hours) | 15-minute (hours) |\n|---|---|---|\n")
for (k in cores) {
  cat(sprintf("| %d | %.3g | %.3g |\n", k, total_evals * per_eval_daily / k / 3600,
              total_evals * per_eval_quarter / k / 3600))
}
