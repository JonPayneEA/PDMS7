# ============================================================ #
# Tool:         smith_step_error
# Description:  Error of the Smith cubic solver against adaptive RK4 by time step
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-31
# Modified:     2026-10-31 - Add Smith step error sweep
# Tier:         3
# Inputs:       None; three years of synthetic 15-minute forcing, aggregated to each step
# Outputs:      Console table; supports the 1-hour threshold in pdm_model()
# Dependencies: pdmS7
# ============================================================ #
# Usage, from the package root:
#   Rscript inst/benchmarks/smith_step_error.R

if (requireNamespace("pkgload", quietly = TRUE) && file.exists("DESCRIPTION")) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  library(pdmS7)
}

set.seed(20261101)
n <- round(3 * 365.25 * 96)
day <- seq_len(n) / 96
rain <- ifelse(stats::runif(n) < 0.4, stats::rgamma(n, 0.6, scale = 12 / 96), 0)
pet <- pmax(0, 2 + 1.5 * sin(2 * pi * day / 365.25)) / 96
aggregate_steps <- function(x, k) {
  colSums(matrix(x[seq_len(floor(length(x) / k) * k)], nrow = k))
}

cat("| kb | dt (hours) | Smith max error (% of peak) | Adaptive max error (% of peak) |\n")
cat("|---|---|---|---|\n")
for (kb in c(1000, 10000, 50000)) {
  for (dt in c(0.25, 0.5, 1, 2, 3, 6, 12, 24)) {
    k <- dt / 0.25
    forcing <- data.frame(rain = aggregate_steps(rain, k), pet = aggregate_steps(pet, k))
    build <- function(solver, rtol = 1e-8) {
      suppressWarnings(pdm_model(
        area_km2 = 100, dt = dt,
        groundwater = power_routing(k = 1 / kb, m = 3, solver = solver, rtol = rtol, atol = 1e-12)
      ))
    }
    reference <- run_pdm(build("adaptive", 1e-12), forcing)$output$q_m3s
    smith <- run_pdm(build("smith"), forcing)$output$q_m3s
    adaptive <- run_pdm(build("adaptive"), forcing)$output$q_m3s
    peak <- max(reference)
    cat(sprintf("| %d | %g | %.3g | %.2g |\n", kb, dt,
                100 * max(abs(smith - reference)) / peak,
                100 * max(abs(adaptive - reference)) / peak))
  }
}
