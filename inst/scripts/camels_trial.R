# ============================================================ #
# Tool:         camels_trial
# Description:  The 12-catchment CAMELS-GB v2 trial before the bulk calibration: the protocol
#               the bulk run will use, run twice from different seeds, to see whether it finds
#               the same answer, how well it scores, and how long it takes
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-19
# Modified:     2026-11-19 - First version
#               2026-11-20 - v2: the structure chosen per catchment (recommend_structure()),
#                            the v9 Beggearn Huish stages (DDS, stage 1 hourly, Box-Cox polish,
#                            events), the rainfall factor free within 0.8 to 1.2, Hydro-PE only;
#                            the two surface time constants compared as a sorted pair; each
#                            catchment's water balance beside its scores
# Tier:         1
# Inputs:       The pipeline's gold/camels_gb_v2/ under a store root: hourly tables,
#               descriptors, signatures and screening
# Outputs:      gold/camels_gb_v2/trial/: runs.csv, seed_test.csv, structures.csv,
#               runtime.csv and the calibration projects
# Dependencies: pdmS7 (0.36.0 or later, installed, for parallel workers); data.table; arrow
# ============================================================ #
# Usage: set the store root, then run the whole script, from a shell or an R notebook:
#   CAMELS_STORE=/Volumes/.../hydrometric Rscript camels_trial.R
# or, in a notebook, Sys.setenv(CAMELS_STORE = "...") and source() this file.
#
# Optional environment variables, defaults in brackets:
#   CAMELS_CORES    catchments calibrated at once (12; leave a few of the cluster's cores free)
#   CAMELS_N        catchments in the trial (12)
#   CAMELS_STARTS   random starts per search (3)
#   CAMELS_BUDGET   model runs per start, DDS (300)
#   CAMELS_WORK     local working folder (a folder under tempdir())
#   PDMS7_USER      the name recorded in the calibration logs ("CAMELS-GB trial")
#
# The calibration logs append to files as they go, which a Unity Catalog volume does not
# allow. So the work happens on the cluster's local disk, and the results and the projects are
# copied to the volume, whole, at the end.
#
# The protocol, for each catchment:
#   seed 1   the structure chosen on the record (recharge, soil store, groundwater store), then
#            the stages, each by DDS: volume and baseflow (on the record summed to 6-hour steps,
#            six times quicker), fast response, polish by Box-Cox, and the largest events
#   seed 2   the same structure from fresh starting values, with other random starts: the seed
#            test
# The test windows are not scored: the test is kept for the final protocol.

library(pdmS7)
library(data.table)
stopifnot(utils::packageVersion("pdmS7") >= "0.36.0")
`%||%` <- function(x, y) if (is.null(x)) y else x

store <- Sys.getenv("CAMELS_STORE")
if (!nzchar(store)) stop("Set CAMELS_STORE to the pipeline's store root", call. = FALSE)
cores <- as.integer(Sys.getenv("CAMELS_CORES", "12"))
n_trial <- as.integer(Sys.getenv("CAMELS_N", "12"))
starts <- as.integer(Sys.getenv("CAMELS_STARTS", "3"))
budget <- as.integer(Sys.getenv("CAMELS_BUDGET", "300"))
work <- Sys.getenv("CAMELS_WORK", file.path(tempdir(), "camels-trial"))
user <- Sys.getenv("PDMS7_USER", "CAMELS-GB trial")
options(pdmS7.user = user, pdmS7.role = "custodian")

camels <- file.path(store, "gold", "camels_gb_v2")
target <- file.path(camels, "trial")
dir.create(work, recursive = TRUE, showWarnings = FALSE)

# The rainfall factor free within 0.8 to 1.2: gridded rain can be biased at a catchment, and a
# factor fixed at 1 makes the soil and groundwater stores absorb the bias instead.
overrides <- list(fc = c(0.8, 1.2))

# ---- The catchments ---------------------------------------------------------------------

# Twelve of the screened catchments, evenly spaced through the baseflow index, so the trial
# runs from flashy upland streams to slow, groundwater-fed rivers. The baseflow index comes
# from the gauged flow; it picks the sample and goes into no model.
screen <- fread(file.path(camels, "screening.csv"), colClasses = list(character = "gauge_id"))
signatures <- pdmS7:::.read_parquet(file.path(camels, "signatures.parquet"))
signatures$gauge_id <- as.character(signatures$gauge_id)
descriptors <- pdmS7:::.read_parquet(file.path(camels, "descriptors.parquet"))
descriptors$gauge_id <- as.character(descriptors$gauge_id)
kept <- screen$gauge_id[as.logical(screen$use)]
pool <- signatures[signatures$gauge_id %in% kept & is.finite(signatures$baseflow_index), ]
pool <- pool[order(pool$baseflow_index), ]
pick <- unique(round(seq(1, nrow(pool), length.out = min(n_trial, nrow(pool)))))
gauges <- pool$gauge_id[pick]
sample <- data.frame(gauge = gauges, bfi = round(pool$baseflow_index[pick], 2),
                     name = screen$gauge_name[match(gauges, screen$gauge_id)],
                     area_km2 = as.numeric(descriptors$area[match(gauges, descriptors$gauge_id)]))
cat("Trial catchments (baseflow index):\n")
print(sample, row.names = FALSE)

# The calibrations run in separate R worker processes, which on Databricks cannot read the
# volume: only the notebook's own process can. So this process copies each catchment's hourly
# table to local disk first, and the workers read the copies, as calibrate_batch() did in the
# first trial. A table missing from the volume is reported here.
local_store <- file.path(work, "store")
local_dir <- file.path(local_store, "gold", "camels_gb_v2", "hourly")
dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
copied <- vapply(gauges, function(g) {
  from <- file.path(camels, "hourly", paste0(g, ".parquet"))
  file.exists(from) && file.copy(from, file.path(local_dir, paste0(g, ".parquet")),
                                 overwrite = TRUE)
}, logical(1))
if (!all(copied)) {
  cat("\nNo hourly table on the volume for:", toString(gauges[!copied]),
      "\nRun 01_camels_prepare again; these catchments are left out.\n")
  sample <- sample[copied, ]
  gauges <- gauges[copied]
}
if (!length(gauges)) stop("No hourly tables could be copied from ", camels, call. = FALSE)

# ---- One catchment ----------------------------------------------------------------------

# A structure's components at their default values: seed 2 starts from the structure seed 1
# chose, but not from seed 1's answer. Each component's defaults are the arguments of its
# constructor in the configuration registries.
fresh_structure <- function(cfg) {
  registries <- list(distribution = pdmS7:::.dist_registry(),
                     recharge = pdmS7:::.recharge_registry(),
                     surface = pdmS7:::.route_registry(),
                     groundwater = pdmS7:::.route_registry())
  out <- cfg
  for (part in names(registries)) {
    type <- cfg[[part]]$type
    defaults <- lapply(formals(registries[[part]][[type]]), eval, envir = baseenv())
    out[[part]] <- c(list(type = type), defaults)
  }
  out$fc <- 1
  out$td <- 0
  out
}

stages <- function(config) {
  s <- pdm_stages(config, overrides = overrides, events = TRUE, td_max = 6,
                  event_budget = budget, method = "dds", budget = budget, coarse_dt = 6)
  polish <- which(vapply(s, function(x) identical(x$name, "polish"), logical(1)))
  s[[polish]]$objective <- "boxcox"
  s
}

# Calibrates one catchment with one seed. Seed 1 chooses the structure; seed 2 is given it.
run_one <- function(job) {
  started <- proc.time()[["elapsed"]]
  out <- tryCatch({
    x <- camels_forcing(camels_read(local_store, job$gauge))
    w <- camels_windows(x$forcing$time)
    area <- job$area_km2
    project <- file.path(work, "runs", paste0("seed", job$seed), job$gauge)
    structure <- if (is.null(job$structure)) {
      cfg <- pdm_presets("standard")
      cfg$dt <- 1
      cfg$area_km2 <- area
      cfg
    } else {
      job$structure
    }
    calibrate_project(project, x$forcing[c("time", "rain", "pet")], x$observed, area,
                      w$calibration, w$validation, structure = structure, stages = stages,
                      recommend = is.null(job$structure), overrides = overrides,
                      starts = starts, seed = job$seed, control = list(maxit = budget),
                      method = "dds", catchment = job$name, gauge = job$gauge,
                      purpose = "CAMELS-GB trial", test = w$test, wettest_years = 0,
                      reasoning = "CAMELS-GB v2: CEH-GEAR hourly rain, Hydro-PE, hourly flow.")
    s <- read_projects(project)
    list(state = "done", message = "", project = project,
         nse_calibration = s$candidate_score, nse_validation = s$validation_score,
         config = read_entry(project, s$candidate)$configuration,
         flow_missing_pct = x$summary$flow_missing_pct,
         runoff_ratio = tryCatch(
           water_balance(x$forcing, x$observed, area)$record$runoff_ratio,
           error = function(e) NA_real_))
  }, error = function(e) list(state = "failed", message = conditionMessage(e)))
  out$gauge <- job$gauge
  out$seed <- job$seed
  out$seconds <- round(proc.time()[["elapsed"]] - started)
  out
}

run_all <- function(jobs) {
  if (cores <= 1L || length(jobs) < 2L) return(lapply(jobs, run_one))
  cl <- parallel::makeCluster(min(cores, length(jobs)))
  on.exit(parallel::stopCluster(cl), add = TRUE)
  parallel::clusterCall(cl, function(p, u) {
    .libPaths(p)
    library(pdmS7)
    options(pdmS7.user = u, pdmS7.role = "custodian")
    NULL
  }, unique(c(dirname(system.file(package = "pdmS7")), .libPaths())), user)
  parallel::clusterExport(cl, c("local_store", "work", "starts", "budget", "overrides",
                                "stages"),
                          envir = environment(run_one))
  parallel::parLapply(cl, jobs, run_one)
}

# ---- The two seeds ----------------------------------------------------------------------

jobs <- lapply(seq_len(nrow(sample)), function(i) {
  list(gauge = sample$gauge[i], name = sample$name[i], area_km2 = sample$area_km2[i], seed = 1)
})
cat("\nSeed 1: choosing the structure and calibrating", length(jobs), "catchments\n")
first <- run_all(jobs)
names(first) <- vapply(first, `[[`, "", "gauge")
# Any failure is shown at once, with its reason; if every catchment failed, the trial stops
# here rather than in the tables.
failures <- Filter(function(r) !identical(r$state, "done"), first)
if (length(failures)) {
  cat("\nSeed 1 failed for", length(failures), "of", length(first), "catchments:\n")
  for (r in failures) cat(" ", r$gauge, ":", r$message, "\n")
}
if (length(failures) == length(first)) {
  stop("Every catchment failed in seed 1; the reasons are above", call. = FALSE)
}
second_jobs <- Filter(Negate(is.null), lapply(jobs, function(j) {
  r <- first[[j$gauge]]
  if (!identical(r$state, "done")) return(NULL)
  j$seed <- 2
  j$structure <- fresh_structure(r$config)
  j
}))
cat("Seed 2: the same structures from fresh starts,", length(second_jobs), "catchments\n")
second <- run_all(second_jobs)
names(second) <- vapply(second, `[[`, "", "gauge")
for (r in Filter(function(r) !identical(r$state, "done"), second)) {
  cat("  Seed 2 failed for", r$gauge, ":", r$message, "\n")
}

# ---- Tables -----------------------------------------------------------------------------

paths <- function(cfg) calibration_bounds(cfg, overrides = overrides)$path
# The parameters of a configuration, with the two surface time constants as a sorted pair:
# two linear stores in series give the same flow whichever way round they are, so k_fast and
# k_slow are what the record determines, not k1 and k2.
parameters <- function(cfg) {
  p <- paths(cfg)
  v <- vapply(p, function(x) as.numeric(pdmS7:::.path_get(cfg, x)), numeric(1))
  if (all(c("surface.k1", "surface.k2") %in% p)) {
    k <- sort(v[c("surface.k1", "surface.k2")])
    v["surface.k1"] <- k[1]
    v["surface.k2"] <- k[2]
    names(v)[names(v) == "surface.k1"] <- "surface.k_fast"
    names(v)[names(v) == "surface.k2"] <- "surface.k_slow"
  }
  v
}
row_of <- function(r) {
  base <- data.frame(seed = r$seed, gauge = r$gauge, state = r$state,
                     seconds = r$seconds, message = r$message %||% "",
                     nse_calibration = r$nse_calibration %||% NA_real_,
                     nse_validation = r$nse_validation %||% NA_real_,
                     runoff_ratio = r$runoff_ratio %||% NA_real_,
                     flow_missing_pct = r$flow_missing_pct %||% NA_real_)
  if (!identical(r$state, "done")) return(base)
  cfg <- r$config
  v <- parameters(cfg)
  cbind(base, recharge = cfg$recharge$type, distribution = cfg$distribution$type,
        groundwater = cfg$groundwater$type, as.data.frame(as.list(v), check.names = FALSE))
}
runs <- rbindlist(lapply(c(first, second), row_of), fill = TRUE)
runs <- merge(sample, runs, by = "gauge", all.y = TRUE, sort = FALSE)
runs <- runs[order(runs$bfi, runs$seed), ]

# How far apart the seeds put each parameter, as a share of its search range (on the log scale
# for parameters searched on it), and the parameter furthest apart. Within 5% of every range
# and 0.01 NSE: one seed will do for the bulk run. A wide share with the same score means the
# record does not determine that parameter.
seed_test <- rbindlist(lapply(names(second), function(g) {
  a <- first[[g]]
  b <- second[[g]]
  if (!identical(b$state, "done")) return(NULL)
  bounds <- calibration_bounds(a$config, overrides = overrides)
  va <- parameters(a$config)
  vb <- parameters(b$config)
  share <- vapply(seq_along(va), function(k) {
    i <- match(sub("k_fast", "k1", sub("k_slow", "k2", names(va)[k])), bounds$path)
    lo <- bounds$lower[i]
    hi <- bounds$upper[i]
    if (bounds$scale[i] == "log") abs(log(va[k]) - log(vb[k])) / log(hi / lo) else
      abs(va[k] - vb[k]) / (hi - lo)
  }, numeric(1))
  names(share) <- names(va)
  others <- share[names(share) != "groundwater.kb"]
  data.frame(gauge = g, nse_validation_1 = a$nse_validation, nse_validation_2 = b$nse_validation,
             nse_difference = b$nse_validation - a$nse_validation,
             widest_share = max(share), widest_parameter = names(share)[which.max(share)],
             kb_share = if ("groundwater.kb" %in% names(share)) share[["groundwater.kb"]] else NA,
             widest_without_kb = if (length(others)) max(others) else NA,
             consistent = max(share) <= 0.05 &&
               abs(b$nse_validation - a$nse_validation) <= 0.01)
}))
structures <- runs[runs$seed == 1 & runs$state == "done",
                   c("gauge", "name", "bfi", "recharge", "distribution", "groundwater",
                     "nse_validation", "runoff_ratio")]
done <- runs[runs$seed == 1 & runs$state == "done", ]
n_bulk <- sum(as.logical(screen$use))
runtime <- data.frame(
  catchments = nrow(done), mean_minutes = mean(done$seconds) / 60,
  slowest_minutes = max(done$seconds) / 60, cores = cores, bulk_catchments = n_bulk,
  bulk_hours = mean(done$seconds) * n_bulk / cores / 3600
)

cat("\nStructures chosen\n")
print(structures, row.names = FALSE, digits = 3)
cat("\nSeed test\n")
print(seed_test, row.names = FALSE, digits = 3)
cat("\nRuntime (seed 1: structure choice and calibration)\n")
print(runtime, row.names = FALSE, digits = 3)

# ---- Results to the volume --------------------------------------------------------------

dir.create(target, recursive = TRUE, showWarnings = FALSE)
fwrite(runs, file.path(target, "runs.csv"))
fwrite(seed_test, file.path(target, "seed_test.csv"))
fwrite(structures, file.path(target, "structures.csv"))
fwrite(runtime, file.path(target, "runtime.csv"))
file.copy(file.path(work, "runs"), target, recursive = TRUE)
cat("\nWritten to", target, "\n")
