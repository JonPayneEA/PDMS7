# ============================================================ #
# Tool:         search_methods
# Description:  Compare calibration searches on a large synthetic sample against the truth
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-05
# Modified:     2026-11-05 - Add the search comparison
# Tier:         3
# Inputs:       None; 30 synthetic catchments from a fixed seed
# Outputs:      Console report in markdown; timings apply to the machine used
# Dependencies: pdmS7 (installed, for parallel workers)
# ============================================================ #
# Usage, from anywhere:
#   Rscript inst/benchmarks/search_methods.R
# Optional environment variables: PDM_BENCH_CORES (default 4), PDM_BENCH_BASINS (default 30).
#
# Each search is run as one calibrate_batch() over the same sample as the article "A large
# sample: what automatic calibration recovers". Every calibration is then scored against the
# true parameters on the same window: a search that scores at least as well as the truth found
# the best fit the record allows, whatever its parameters. The DDS budget matches the median
# number of model runs of the staged L-BFGS-B search.

library(pdmS7)
options(pdmS7.user = "Benchmark", pdmS7.role = "custodian")
cores <- as.integer(Sys.getenv("PDM_BENCH_CORES", "4"))
n <- as.integer(Sys.getenv("PDM_BENCH_BASINS", "30"))
root <- file.path(tempdir(), "search-methods")
unlink(root, recursive = TRUE)
basins <- file.path(root, "basins")
sample <- synthetic_basins(basins, n = n, years = 10, dt = 24, seed = 7)
paths <- calibration_bounds(pdm_presets("standard"))$path

# One search over the whole sample: elapsed minutes, model runs per basin, and each basin's
# calibration score set against the score of its true parameters.
search <- function(tag, ...) {
  output <- file.path(root, tag)
  minutes <- system.time(calibrate_batch(basins, output, cores = cores, ...))[["elapsed"]] / 60
  rows <- lapply(sample$basin, function(id) {
    project <- file.path(output, id)
    entries <- read_project(project)$entries
    fits <- entries$id[entries$type == "auto_calibration"]
    truth <- read_pdm_config(file.path(basins, id, "truth.yml"))
    changes <- vapply(paths, function(p) pdmS7:::.path_get(truth, p), numeric(1))
    true_score <- suppressWarnings(preview_trial(project, utils::tail(fits, 1), changes))
    data.frame(
      basin = id,
      runs = sum(vapply(fits, function(i) read_entry(project, i)$evaluations, numeric(1))),
      fitted = read_entry(project, read_projects(project)$candidate)$scores$nse,
      truth = true_score$scores$nse
    )
  })
  out <- do.call(rbind, rows)
  out$search <- tag
  attr(out, "minutes") <- minutes
  out
}

runs <- list(
  search("all at once, L-BFGS-B", starts = 4, control = list(maxit = 40)),
  search("staged, L-BFGS-B", staged = TRUE, starts = 2, control = list(maxit = 40))
)
budget <- round(stats::median(runs[[2]]$runs) / (2 * 3))
runs[[3]] <- search("staged, DDS", staged = TRUE, starts = 2, method = "dds",
                    control = list(maxit = budget))

cat("\n| Search | Model runs per basin (median) | Minutes | At least the truth's NSE |",
    "Short by over 0.001 | Largest shortfall |\n|---|---|---|---|---|---|\n")
for (r in runs) {
  gap <- r$fitted - r$truth
  cat(sprintf("| %s | %.0f | %.1f | %d of %d | %d | %.4f |\n", r$search[1], stats::median(r$runs),
              attr(r, "minutes"), sum(gap >= -1e-6), nrow(r), sum(gap < -0.001),
              max(0, -min(gap))))
}
cat("\nDDS budget:", budget, "model runs per start;", cores, "cores.\n")
unlink(root, recursive = TRUE)
