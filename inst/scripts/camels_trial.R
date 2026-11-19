# ============================================================ #
# Tool:         camels_trial
# Description:  The 12-catchment CAMELS-GB v2 trial before the bulk calibration: does the
#               search find the same answer from different seeds, how much does the
#               evaporation product matter, and how long will the bulk run take
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-19
# Modified:     2026-11-19 - First version
# Tier:         1
# Inputs:       The pipeline's gold/camels_gb_v2/ under a store root: hourly tables (with every
#               evaporation product), descriptors, signatures and screening
# Outputs:      gold/camels_gb_v2/trial/: runs.csv, seed_test.csv, pet_test.csv, runtime.csv
#               and the calibration projects
# Dependencies: pdmS7 (installed, for parallel workers); data.table; arrow or nanoparquet
# ============================================================ #
# Usage: set the store root, then run the whole script, from a shell or an R notebook:
#   CAMELS_STORE=/Volumes/.../hydrometric Rscript camels_trial.R
# or, in a notebook, Sys.setenv(CAMELS_STORE = "...") and source() this file.
#
# Optional environment variables, defaults in brackets:
#   CAMELS_CORES    basins calibrated at once (12; leave a few of the cluster's cores free)
#   CAMELS_N        catchments in the trial (12)
#   CAMELS_STARTS   random starts per stage (4)
#   CAMELS_BUDGET   model runs per start and stage, DDS (300)
#   CAMELS_WORK     local working folder (a folder under tempdir())
#   PDMS7_USER      the name recorded in the calibration logs ("CAMELS-GB trial")
#
# The calibration logs append to files as they go, which a Unity Catalog volume does not
# allow. So the work happens on the cluster's local disk, and the results and the projects are
# copied to the volume, whole, at the end.
#
# Three batches over the same catchments, each the staged search with DDS:
#   hydrope, seed 1   Hydro-PE evaporation (the pipeline's default)
#   hydrope, seed 2   the same, other random starts: the seed test
#   chess, seed 1     CHESS-PE evaporation: the evaporation test
# The test windows are not scored: the test is kept for the final protocol.

library(pdmS7)
library(data.table)

store <- Sys.getenv("CAMELS_STORE")
if (!nzchar(store)) stop("Set CAMELS_STORE to the pipeline's store root", call. = FALSE)
cores <- as.integer(Sys.getenv("CAMELS_CORES", "12"))
n_trial <- as.integer(Sys.getenv("CAMELS_N", "12"))
starts <- as.integer(Sys.getenv("CAMELS_STARTS", "4"))
budget <- as.integer(Sys.getenv("CAMELS_BUDGET", "300"))
work <- Sys.getenv("CAMELS_WORK", file.path(tempdir(), "camels-trial"))
options(pdmS7.user = Sys.getenv("PDMS7_USER", "CAMELS-GB trial"), pdmS7.role = "custodian")

camels <- file.path(store, "gold", "camels_gb_v2")
target <- file.path(camels, "trial")
dir.create(work, recursive = TRUE, showWarnings = FALSE)

# ---- The catchments ---------------------------------------------------------------------

# Twelve of the screened catchments, evenly spaced through the baseflow index, so the trial
# runs from flashy upland streams to slow, groundwater-fed rivers. The baseflow index comes
# from the gauged flow; it picks the sample and goes into no model.
screen <- fread(file.path(camels, "screening.csv"), colClasses = list(character = "gauge_id"))
signatures <- pdmS7:::.read_parquet(file.path(camels, "signatures.parquet"))
signatures$gauge_id <- as.character(signatures$gauge_id)
kept <- screen$gauge_id[as.logical(screen$use)]
pool <- signatures[signatures$gauge_id %in% kept & is.finite(signatures$baseflow_index), ]
pool <- pool[order(pool$baseflow_index), ]
pick <- unique(round(seq(1, nrow(pool), length.out = min(n_trial, nrow(pool)))))
gauges <- pool$gauge_id[pick]
cat("Trial catchments (baseflow index):\n")
print(data.frame(gauge = gauges, bfi = round(pool$baseflow_index[pick], 2),
                 name = screen$gauge_name[match(gauges, screen$gauge_id)]), row.names = FALSE)

folders <- list(
  hydrope = camels_batch_folders(store, file.path(work, "basins", "hydrope"), gauges,
                                 pet = "pet_hydrope_mm"),
  chess = camels_batch_folders(store, file.path(work, "basins", "chess"), gauges,
                               pet = "pet_chess_mm")
)
for (name in names(folders)) {
  bad <- folders[[name]][folders[[name]]$state == "failed", ]
  if (nrow(bad)) {
    cat("\nFolders not written,", name, "\n")
    print(bad[, c("gauge", "message")], row.names = FALSE)
  }
}
gauges <- intersect(folders$hydrope$gauge[folders$hydrope$state != "failed"],
                    folders$chess$gauge[folders$chess$state != "failed"])
if (!length(gauges)) stop("No catchments could be prepared", call. = FALSE)

# ---- The batches ------------------------------------------------------------------------

bounds <- calibration_bounds(pdm_presets("standard"))
paths <- bounds$path

# One batch; one row per catchment: state, seconds, model runs, scores and parameters.
batch <- function(label, pet, seed) {
  output <- file.path(work, "runs", label)
  minutes <- system.time(calibrate_batch(
    file.path(work, "basins", pet), output, staged = TRUE, method = "dds", starts = starts,
    seed = seed, control = list(maxit = budget), cores = cores, only = gauges,
    purpose = paste("CAMELS-GB trial,", label)
  ))[["elapsed"]] / 60
  status <- batch_status(output)
  rows <- lapply(gauges, function(g) {
    s <- status[status$basin == g]
    row <- data.frame(run = label, pet = pet, seed = seed, gauge = g, state = s$state,
                      seconds = s$seconds, message = s$message, batch_minutes = round(minutes, 1),
                      model_runs = NA_real_, nse_calibration = NA_real_,
                      nse_validation = NA_real_)
    values <- stats::setNames(rep(NA_real_, length(paths)), paths)
    if (identical(s$state, "done")) {
      project <- file.path(output, g)
      summary <- read_projects(project)
      entries <- read_project(project)$entries
      fits <- entries$id[entries$type == "auto_calibration"]
      row$model_runs <- sum(vapply(fits, function(i) {
        e <- read_entry(project, i)$evaluations
        if (is.null(e)) NA_real_ else as.numeric(e)
      }, numeric(1)))
      row$nse_calibration <- summary$candidate_score
      row$nse_validation <- summary$validation_score
      config <- read_entry(project, summary$candidate)$configuration
      values <- vapply(paths, function(p) as.numeric(pdmS7:::.path_get(config, p)), numeric(1))
    }
    cbind(row, as.data.frame(as.list(values), check.names = FALSE))
  })
  out <- do.call(rbind, rows)
  cat(sprintf("\n%s: %d of %d done in %.1f minutes\n", label, sum(out$state == "done"),
              nrow(out), minutes))
  out
}

runs <- rbind(batch("hydrope, seed 1", "hydrope", 1),
              batch("hydrope, seed 2", "hydrope", 2),
              batch("chess, seed 1", "chess", 1))

# ---- The seed test ----------------------------------------------------------------------

# How far apart two seeds put each parameter, as a share of its search range (on the log scale
# for parameters searched on it). Within 5% of every range and 0.01 NSE: the search finds the
# same answer, and one seed will do for the bulk run.
spread <- function(a, b) {
  vapply(seq_len(nrow(bounds)), function(k) {
    p <- bounds$path[k]
    lo <- bounds$lower[k]
    hi <- bounds$upper[k]
    if (bounds$scale[k] == "log") abs(log(a[[p]]) - log(b[[p]])) / log(hi / lo) else
      abs(a[[p]] - b[[p]]) / (hi - lo)
  }, numeric(1))
}
pair <- function(x, y) {
  x <- runs[runs$run == x, ]
  y <- runs[runs$run == y, ]
  do.call(rbind, lapply(gauges, function(g) {
    a <- x[x$gauge == g, ]
    b <- y[y$gauge == g, ]
    if (a$state != "done" || b$state != "done") return(NULL)
    d <- spread(a, b)
    data.frame(gauge = g, nse_validation_a = a$nse_validation,
               nse_validation_b = b$nse_validation,
               nse_difference = b$nse_validation - a$nse_validation,
               widest_share = max(d), widest_parameter = paths[which.max(d)])
  }))
}
seed_test <- pair("hydrope, seed 1", "hydrope, seed 2")
if (!is.null(seed_test)) {
  seed_test$consistent <- seed_test$widest_share <= 0.05 & abs(seed_test$nse_difference) <= 0.01
  cat("\nSeed test: same answer from both seeds in", sum(seed_test$consistent), "of",
      nrow(seed_test), "catchments\n")
  print(seed_test, row.names = FALSE, digits = 3)
}

# ---- The evaporation test ---------------------------------------------------------------

# CHESS-PE against Hydro-PE: the change in validation NSE, and the parameter that moves most.
# A small change in score with a large one in a parameter means the parameter absorbs the
# difference, as the soil store does for evaporation; the bulk run should then use one product
# throughout, and the descriptor model learns parameters for that product only.
pet_test <- pair("hydrope, seed 1", "chess, seed 1")
pet_total <- function(pet) {
  vapply(gauges, function(g) {
    f <- fread(file.path(work, "basins", pet, g, "forcing.csv"), select = "pet")
    sum(f$pet) / (nrow(f) / 8766)
  }, numeric(1))
}
if (!is.null(pet_test)) {
  names(pet_test)[2:3] <- c("nse_validation_hydrope", "nse_validation_chess")
  totals <- data.frame(gauge = gauges, pet_hydrope_mm_yr = pet_total("hydrope"),
                       pet_chess_mm_yr = pet_total("chess"))
  pet_test <- merge(totals, pet_test, by = "gauge")
  cat("\nEvaporation test: CHESS-PE minus Hydro-PE, validation NSE\n")
  print(pet_test, row.names = FALSE, digits = 3)
}

# ---- Runtime ----------------------------------------------------------------------------

# A basin runs on one core, so the bulk run takes about the mean basin time, times the
# screened catchments, over the cores in use.
done <- runs[runs$run == "hydrope, seed 1" & runs$state == "done", ]
n_bulk <- sum(as.logical(screen$use))
runtime <- data.frame(
  catchments = nrow(done), mean_minutes = mean(done$seconds) / 60,
  slowest_minutes = max(done$seconds) / 60, mean_model_runs = mean(done$model_runs),
  cores = cores, bulk_catchments = n_bulk,
  bulk_hours = mean(done$seconds) * n_bulk / cores / 3600
)
cat("\nRuntime\n")
print(runtime, row.names = FALSE, digits = 3)

# ---- Results to the volume --------------------------------------------------------------

dir.create(target, recursive = TRUE, showWarnings = FALSE)
fwrite(runs, file.path(target, "runs.csv"))
if (!is.null(seed_test)) fwrite(seed_test, file.path(target, "seed_test.csv"))
if (!is.null(pet_test)) fwrite(pet_test, file.path(target, "pet_test.csv"))
fwrite(runtime, file.path(target, "runtime.csv"))
file.copy(file.path(work, "runs"), target, recursive = TRUE)
cat("\nWritten to", target, "\n")
