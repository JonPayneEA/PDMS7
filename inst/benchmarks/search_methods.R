# ============================================================ #
# Tool:         search_methods
# Description:  Compare calibration searches on a large synthetic sample against the truth
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-05
# Modified:     2026-11-06 - Four searches; writes inst/extdata/search_study.csv
# Tier:         3
# Inputs:       None; 30 synthetic catchments from a fixed seed
# Outputs:      search_study.csv (one row per search and basin); console summary
# Dependencies: pdmS7 (installed, for parallel workers); data.table
# ============================================================ #
# Usage, from the package root:
#   Rscript inst/benchmarks/search_methods.R [output.csv]
# The default output is inst/extdata/search_study.csv, the file the article "What limits
# automatic calibration" reads. Optional environment variable: PDM_BENCH_CORES (default 4).
# Takes about 40 minutes on 4 cores; the confined-polish search runs on one core (see below).
#
# Each search is one calibrate_batch() over the sample of the article "A large sample: what
# automatic calibration recovers". Every calibration is then set against the score of the
# basin's true parameters on the same window: a search that scores at least as well as the
# truth found the best fit the record allows, whatever its parameters.
#
# The four searches:
#   staged, confined polish  the staged search as it was before version 0.8.0, its polish
#                            confined to a quarter of each range around stage 2's values
#   staged                   the staged search now, polishing over the full bounds
#   all at once              every parameter in one search, four starts
#   staged, DDS              the staged search with DDS, its budget matching the median model
#                            runs of the confined-polish search
# Every search is seeded per basin, so a rerun gives the same parameters and scores; only the
# minutes depend on the machine.

library(pdmS7)
options(pdmS7.user = "Benchmark", pdmS7.role = "custodian")
args <- commandArgs(TRUE)
target <- if (length(args)) args[1] else file.path("inst", "extdata", "search_study.csv")
cores <- as.integer(Sys.getenv("PDM_BENCH_CORES", "4"))
root <- file.path(tempdir(), "search-methods")
unlink(root, recursive = TRUE)
basins <- file.path(root, "basins")
sample <- synthetic_basins(basins, n = 30, years = 10, dt = 24, seed = 7)
# The basins' rain is biased by a known factor, so the rainfall factor, locked by default, is
# searched as it was when these results were stored.
unlock <- list(fc = c(0.6, 1.6))
paths <- calibration_bounds(pdm_presets("standard"), overrides = unlock)$path
short <- c("fc", "cmax", "b", "kg", "k1", "k2", "kb")

# One search over the whole sample, as rows of: model runs, minutes, the calibrated score, the
# true parameters' score, and the calibrated parameters.
search <- function(label, ...) {
  output <- file.path(root, gsub("[^a-z]+", "-", label))
  run <- function() calibrate_batch(basins, output, test = TRUE, overrides = unlock, ...)
  minutes <- system.time(run())[["elapsed"]] / 60
  rows <- lapply(sample$basin, function(id) {
    project <- file.path(output, id)
    entries <- read_project(project)$entries
    fits <- entries$id[entries$type == "auto_calibration"]
    candidate <- read_entry(project, read_projects(project)$candidate)
    truth <- read_pdm_config(file.path(basins, id, "truth.yml"))
    changes <- vapply(paths, function(p) pdmS7:::.path_get(truth, p), numeric(1))
    true_run <- suppressWarnings(preview_trial(project, utils::tail(fits, 1), changes))
    fitted <- vapply(paths, function(p) pdmS7:::.path_get(candidate$configuration, p), numeric(1))
    data.frame(
      search = label, basin = id,
      model_runs = sum(vapply(fits, function(i) read_entry(project, i)$evaluations, numeric(1))),
      batch_minutes = round(minutes, 2), nse = signif(candidate$scores$nse, 8),
      true_nse = signif(true_run$scores$nse, 8), t(stats::setNames(signif(fitted, 6), short))
    )
  })
  do.call(rbind, rows)
}

# The confined polish is no longer a batch option, so it is restored by giving pdm_stages() its
# old default for this one search. Parallel workers load the package afresh and would not see
# the change, so this search runs on one core.
current <- pdmS7::pdm_stages
confined <- current
formals(confined)$band <- 0.25
utils::assignInNamespace("pdm_stages", confined, "pdmS7")
old <- search("staged, confined polish", staged = TRUE, starts = 2, control = list(maxit = 40),
              cores = 1L)
utils::assignInNamespace("pdm_stages", current, "pdmS7")

staged <- search("staged", staged = TRUE, starts = 2, control = list(maxit = 40), cores = cores)
at_once <- search("all at once", starts = 4, control = list(maxit = 40), cores = cores)
# Six searches per basin for DDS: three stages, two starts each.
budget <- round(mean(old$model_runs) / 6)
dds <- search("staged, DDS", staged = TRUE, starts = 2, method = "dds",
              control = list(maxit = budget), cores = cores)

study <- rbind(old, staged, at_once, dds)
data.table::fwrite(study, target)
for (s in unique(study$search)) {
  r <- study[study$search == s, ]
  gap <- r$nse - r$true_nse
  cat(sprintf("%-24s median runs %5.0f | at least the truth %2d of %d | short by over 0.001: %d\n",
              s, stats::median(r$model_runs), sum(gap >= -1e-6), nrow(r), sum(gap < -0.001)))
}
cat("DDS budget:", budget, "model runs per start. Written to", target, "\n")
unlink(root, recursive = TRUE)
