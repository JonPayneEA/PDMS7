# ============================================================ #
# Tool:         camels_trial
# Description:  The CAMELS-GB v2 trial before the bulk calibration: the protocol the bulk run
#               will use, run twice from different seeds on twelve catchments, and a
#               groundwater arm testing the groundwater extension on aquifer-dominated ones
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-19
# Modified:     2026-11-19 - First version
#               2026-11-20 - v2: the structure chosen per catchment (recommend_structure()),
#                            the v9 Beggearn Huish stages (DDS, stage 1 on 6-hour steps, Box-Cox
#                            polish, events), the rainfall factor free within 0.8 to 1.2,
#                            Hydro-PE only; the two surface time constants compared as a sorted
#                            pair; each catchment's water balance beside its scores
#               2026-11-20 - v3: 600 model runs a start; the seed test lists every parameter the
#                            seeds leave apart; the groundwater arm (the chosen structure, with
#                            underflow, with constant abstraction; two seeds each)
#               2026-11-23 - v4: both seeds run the whole protocol, structure choice included;
#                            the rainfall factor fixed at 1, with rain bias read from the water
#                            balance; extension arms on the nearest structure that takes the
#                            extension, plus an import arm; a snow arm with PACK
# Tier:         1
# Inputs:       The pipeline's gold/camels_gb_v2/ under a store root: hourly tables,
#               descriptors, signatures and screening
# Outputs:      gold/camels_gb_v2/trial/: runs.csv, seed_test.csv, structures.csv,
#               groundwater.csv, snow.csv, runtime.csv and the calibration projects
# Dependencies: pdmS7 (0.37.0 or later, installed, for parallel workers); data.table; arrow
# ============================================================ #
# Usage: set the store root, then run the whole script, from a shell or an R notebook:
#   CAMELS_STORE=/Volumes/.../hydrometric Rscript camels_trial.R
# or, in a notebook, Sys.setenv(CAMELS_STORE = "...") and source() this file.
#
# Optional environment variables, defaults in brackets:
#   CAMELS_CORES    calibrations run at once (12; leave a few of the cluster's cores free)
#   CAMELS_N        catchments in the main trial (12)
#   CAMELS_GW_N     catchments in the groundwater arm (6; 0 to skip it)
#   CAMELS_SNOW_MIN snow share of precipitation from which a main-trial catchment also gets a
#                   snow arm, with PACK (0.05)
#   CAMELS_STARTS   random starts per search (3)
#   CAMELS_BUDGET   model runs per start, DDS (600)
#   CAMELS_WORK     local working folder (a folder under tempdir())
#   PDMS7_USER      the name recorded in the calibration logs ("CAMELS-GB trial")
#
# The calibration logs append to files as they go, which a Unity Catalog volume does not
# allow, and the worker processes cannot read the volume at all. So the hourly tables are
# copied to the cluster's local disk first, the work happens there, and the results and the
# projects are copied to the volume, whole, at the end.
#
# The main trial, for each of twelve screened catchments, the whole protocol twice, with seeds 1
# and 2: the structure chosen on the record (recharge, soil store, groundwater store), then the
# stages, each by DDS: volume and baseflow (on the record summed to 6-hour steps), fast
# response, polish by Box-Cox, and the largest events. The seed test asks whether the protocol
# gives the same model twice, and the same structure. The rainfall factor is fixed at 1: freed,
# it traded off against the soil store and recharge; rain bias is read from each catchment's
# water balance instead (loss_over_pet: well above 1, too much rain or water lost; well below,
# too little rain or water gained).
# A snow arm, for main-trial catchments with a snow share of at least CAMELS_SNOW_MIN: the same
# protocol on PACK rain plus melt, from the precipitation and the day's temperature, at PACK's
# default parameters.
# The groundwater arm, for aquifer-dominated catchments (those screened out for highly
# productive aquifers, groundwater losses or water from outside the catchment, and any kept with
# a baseflow index above 0.85), each with two seeds:
#   chosen        the protocol, as in the main trial
#   compatible    the nearest structure that takes the extension (a cubic store for an
#                 exponential one, standard recharge for demand), where the chosen one does not
#   underflow     that structure with the extension's underflow (ku, Dbu) searched
#   abstraction   that structure with a constant abstraction (ca) searched
#   import        that structure with springs free to bring water in (alpha_b below 0), for
#                 catchments whose runoff ratio is above 0.9
# The test windows are not scored: the test is kept for the final protocol.

library(pdmS7)
library(data.table)
stopifnot(utils::packageVersion("pdmS7") >= "0.37.0")
`%||%` <- function(x, y) if (is.null(x)) y else x

store <- Sys.getenv("CAMELS_STORE")
if (!nzchar(store)) stop("Set CAMELS_STORE to the pipeline's store root", call. = FALSE)
cores <- as.integer(Sys.getenv("CAMELS_CORES", "12"))
n_trial <- as.integer(Sys.getenv("CAMELS_N", "12"))
n_groundwater <- as.integer(Sys.getenv("CAMELS_GW_N", "6"))
snow_min <- as.numeric(Sys.getenv("CAMELS_SNOW_MIN", "0.05"))
starts <- as.integer(Sys.getenv("CAMELS_STARTS", "3"))
budget <- as.integer(Sys.getenv("CAMELS_BUDGET", "600"))
work <- Sys.getenv("CAMELS_WORK", file.path(tempdir(), "camels-trial"))
user <- Sys.getenv("PDMS7_USER", "CAMELS-GB trial")
options(pdmS7.user = user, pdmS7.role = "custodian")

camels <- file.path(store, "gold", "camels_gb_v2")
target <- file.path(camels, "trial")
dir.create(work, recursive = TRUE, showWarnings = FALSE)

# The rainfall factor is fixed at 1 in every arm: freed within 0.8 to 1.2 in trial 3, it traded
# off against the soil store and recharge at seven of twelve catchments.
fixed_fc <- NULL
# The groundwater extension's starting values: a slow underflow, a small constant abstraction,
# or springs bringing water in. Only the parameters named are searched (calibration_bounds()).
extensions <- list(underflow = list(ku = 1e4, dbu = 0), abstraction = list(ca = 0.001),
                   import = list(alpha_b = -0.2))

# ---- The catchments ---------------------------------------------------------------------

# Twelve of the screened catchments, evenly spaced through the baseflow index, so the trial
# runs from flashy upland streams to slow, groundwater-fed rivers. The baseflow index comes
# from the gauged flow; it picks the sample and goes into no model.
screen <- fread(file.path(camels, "screening.csv"), colClasses = list(character = "gauge_id"))
signatures <- pdmS7:::.read_parquet(file.path(camels, "signatures.parquet"))
signatures$gauge_id <- as.character(signatures$gauge_id)
descriptors <- pdmS7:::.read_parquet(file.path(camels, "descriptors.parquet"))
descriptors$gauge_id <- as.character(descriptors$gauge_id)
bfi_of <- function(g) signatures$baseflow_index[match(g, signatures$gauge_id)]
spread_pick <- function(ids, n) {
  ids <- ids[is.finite(bfi_of(ids))]
  ids <- ids[order(bfi_of(ids))]
  if (n <= 0 || !length(ids)) return(character(0))
  ids[unique(round(seq(1, length(ids), length.out = min(n, length(ids)))))]
}
ratio_of <- function(g) {
  if (!"runoff_ratio" %in% names(signatures)) return(rep(NA_real_, length(g)))
  signatures$runoff_ratio[match(g, signatures$gauge_id)]
}
snow_of <- function(g) {
  if (!"frac_snow" %in% names(descriptors)) return(rep(NA_real_, length(g)))
  as.numeric(descriptors$frac_snow[match(g, descriptors$gauge_id)])
}
describe <- function(ids) {
  data.frame(gauge = ids, bfi = round(bfi_of(ids), 2),
             name = screen$gauge_name[match(ids, screen$gauge_id)],
             area_km2 = as.numeric(descriptors$area[match(ids, descriptors$gauge_id)]),
             frac_snow = round(snow_of(ids), 3))
}
kept <- screen$gauge_id[as.logical(screen$use)]
sample <- describe(spread_pick(kept, n_trial))
cat("Main trial catchments (baseflow index):\n")
print(sample, row.names = FALSE)

# The groundwater arm: catchments left out only for their aquifers, groundwater losses or water
# from outside the catchment, and kept catchments with a baseflow index above 0.85.
groundwater_reasons <- c("highly productive aquifer", "groundwater losses",
                         "water from outside the catchment")
only_groundwater <- vapply(strsplit(screen$reasons, "; ", fixed = TRUE), function(r) {
  length(r) > 0 && all(r %in% groundwater_reasons)
}, logical(1))
gw_pool <- unique(c(screen$gauge_id[!as.logical(screen$use) & only_groundwater],
                    kept[is.finite(bfi_of(kept)) & bfi_of(kept) > 0.85]))
gw_sample <- describe(spread_pick(gw_pool, n_groundwater))
if (nrow(gw_sample)) {
  cat("\nGroundwater arm catchments (baseflow index):\n")
  print(gw_sample, row.names = FALSE)
}
snow_sample <- sample[is.finite(sample$frac_snow) & sample$frac_snow >= snow_min, ]
if (nrow(snow_sample)) {
  cat("\nSnow arm catchments (snow share of precipitation):\n")
  print(snow_sample[, c("gauge", "name", "frac_snow")], row.names = FALSE)
}

# The calibrations run in separate R worker processes, which on Databricks cannot read the
# volume: only the notebook's own process can. So this process copies each catchment's hourly
# table to local disk first, and the workers read the copies. A table missing from the volume
# is reported here, and its catchment left out.
local_store <- file.path(work, "store")
local_dir <- file.path(local_store, "gold", "camels_gb_v2", "hourly")
dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
all_gauges <- unique(c(sample$gauge, gw_sample$gauge))
copied <- vapply(all_gauges, function(g) {
  from <- file.path(camels, "hourly", paste0(g, ".parquet"))
  file.exists(from) && file.copy(from, file.path(local_dir, paste0(g, ".parquet")),
                                 overwrite = TRUE)
}, logical(1))
if (!all(copied)) {
  cat("\nNo hourly table on the volume for:", toString(all_gauges[!copied]),
      "\nRun 01_camels_prepare again; these catchments are left out.\n")
}
sample <- sample[sample$gauge %in% all_gauges[copied], ]
gw_sample <- gw_sample[gw_sample$gauge %in% all_gauges[copied], ]
snow_sample <- snow_sample[snow_sample$gauge %in% all_gauges[copied], ]
if (!nrow(sample) && !nrow(gw_sample)) {
  stop("No hourly tables could be copied from ", camels, call. = FALSE)
}

# ---- One calibration --------------------------------------------------------------------

# A structure's components at their default values: seed 2 starts from the structure seed 1
# chose, but not from seed 1's answer. Each component's defaults are the arguments of its
# constructor in the configuration registries. Any extension is dropped; the job adds its own.
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

# The nearest structure that takes the groundwater extension: a cubic store for an exponential
# one, and standard recharge for demand (pdmS7 allows neither with the extension).
compatible_structure <- function(cfg) {
  out <- cfg
  if (identical(cfg$groundwater$type, "exponential")) {
    out$groundwater <- c(list(type = "cubic"),
                         lapply(formals(pdmS7:::.route_registry()$cubic), eval, envir = baseenv()))
  }
  if (identical(cfg$recharge$type, "demand")) {
    out$recharge <- c(list(type = "standard"),
                      lapply(formals(pdmS7:::.recharge_registry()$standard), eval,
                             envir = baseenv()))
  }
  out
}
types_of <- function(cfg) {
  paste(cfg$recharge$type, cfg$distribution$type, cfg$groundwater$type, sep = " / ")
}

make_stages <- function(overrides) {
  function(config) {
    s <- pdm_stages(config, overrides = overrides, events = TRUE, td_max = 6,
                    event_budget = budget, method = "dds", budget = budget, coarse_dt = 6)
    polish <- which(vapply(s, function(x) identical(x$name, "polish"), logical(1)))
    s[[polish]]$objective <- "boxcox"
    s
  }
}

# One calibration: a catchment, an arm and a seed. Without a structure the structure is chosen
# on the record; with one, that structure is calibrated, plus the job's extension if any.
run_one <- function(job) {
  started <- proc.time()[["elapsed"]]
  out <- tryCatch({
    x <- camels_forcing(camels_read(local_store, job$gauge))
    w <- camels_windows(x$forcing$time)
    reasoning <- "CAMELS-GB v2: CEH-GEAR hourly rain, Hydro-PE, hourly flow."
    if (isTRUE(job$snow)) {
      # PACK at its default parameters turns precipitation and the day's temperature into the
      # rain and melt reaching the ground; that is what the PDM is calibrated on.
      if (anyNA(x$forcing$temperature)) stop("Temperature missing inside the rain years")
      x$forcing$rain <- sim_pack(x$forcing$rain, x$forcing$temperature, pack_presets(),
                                 timestep_min = 60L)$effective_rain_mm
      reasoning <- paste(reasoning, "Rain is PACK rain plus melt, at PACK's default parameters.")
    }
    area <- job$area_km2
    project <- file.path(work, "runs", job$arm, paste0("seed", job$seed), job$gauge)
    structure <- job$structure
    if (is.null(structure)) {
      structure <- pdm_presets("standard")
      structure$dt <- 1
      structure$area_km2 <- area
    }
    if (!is.null(job$extension)) structure$groundwater$extension <- job$extension
    calibrate_project(project, x$forcing[c("time", "rain", "pet")], x$observed, area,
                      w$calibration, w$validation, structure = structure,
                      stages = make_stages(job$overrides),
                      recommend = is.null(job$structure), overrides = job$overrides,
                      starts = starts, seed = job$seed, control = list(maxit = budget),
                      method = "dds", catchment = job$name, gauge = job$gauge,
                      purpose = paste("CAMELS-GB trial,", job$arm), test = w$test,
                      wettest_years = 0, reasoning = reasoning)
    s <- read_projects(project)
    wb <- tryCatch(water_balance(x$forcing, x$observed, area)$record, error = function(e) NULL)
    list(state = "done", message = "", project = project,
         nse_calibration = s$candidate_score, nse_validation = s$validation_score,
         config = read_entry(project, s$candidate)$configuration,
         flow_missing_pct = x$summary$flow_missing_pct,
         runoff_ratio = if (is.null(wb)) NA_real_ else wb$runoff_ratio,
         loss_over_pet = if (is.null(wb)) NA_real_ else wb$loss_over_pet,
         balance_flags = if (is.null(wb)) "" else wb$flags)
  }, error = function(e) list(state = "failed", message = conditionMessage(e)))
  out$gauge <- job$gauge
  out$arm <- job$arm
  out$seed <- job$seed
  out$overrides <- job$overrides
  out$seconds <- round(proc.time()[["elapsed"]] - started)
  out
}

run_all <- function(jobs) {
  if (!length(jobs)) return(list())
  results <- if (cores <= 1L || length(jobs) < 2L) {
    lapply(jobs, run_one)
  } else {
    cl <- parallel::makeCluster(min(cores, length(jobs)))
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, function(p, u) {
      .libPaths(p)
      library(pdmS7)
      options(pdmS7.user = u, pdmS7.role = "custodian")
      NULL
    }, unique(c(dirname(system.file(package = "pdmS7")), .libPaths())), user)
    parallel::clusterExport(cl, c("local_store", "work", "starts", "budget", "make_stages"),
                            envir = environment(run_one))
    parallel::parLapply(cl, jobs, run_one)
  }
  names(results) <- vapply(results, function(r) paste(r$arm, r$gauge, r$seed), "")
  for (r in Filter(function(r) !identical(r$state, "done"), results)) {
    cat("  Failed:", r$arm, r$gauge, "seed", r$seed, ":", r$message, "\n")
  }
  results
}

job <- function(row, arm, seed, overrides, structure = NULL, extension = NULL, snow = FALSE) {
  list(gauge = row$gauge, name = row$name, area_km2 = row$area_km2, arm = arm, seed = seed,
       overrides = overrides, structure = structure, extension = extension, snow = snow)
}
rows <- function(d) lapply(seq_len(nrow(d)), function(i) d[i, ])

# ---- Round 1: every run of the whole protocol ------------------------------------------

# Both seeds run the whole protocol, structure choice included: the seed test then asks what
# the bulk run relies on, whether the protocol gives the same model twice.
round1 <- list()
for (seed in 1:2) {
  round1 <- c(round1,
              lapply(rows(sample), job, arm = "main", seed = seed, overrides = fixed_fc),
              lapply(rows(snow_sample), job, arm = "snow", seed = seed, overrides = fixed_fc,
                     snow = TRUE),
              lapply(rows(gw_sample), job, arm = "chosen", seed = seed, overrides = fixed_fc))
}
cat("\nRound 1: the whole protocol, two seeds,", length(round1), "calibrations\n")
first <- run_all(round1)
if (!any(vapply(first, function(r) identical(r$state, "done"), logical(1)))) {
  stop("Every calibration failed in round 1; the reasons are above", call. = FALSE)
}

# ---- Round 2: the groundwater variants --------------------------------------------------

round2 <- list()
for (row in rows(gw_sample)) {
  r <- first[[paste("chosen", row$gauge, 1)]]
  if (!identical(r$state, "done")) next
  chosen_fresh <- fresh_structure(r$config)
  base <- compatible_structure(chosen_fresh)
  variants <- names(extensions)
  if (!(is.finite(ratio_of(row$gauge)) && ratio_of(row$gauge) > 0.9)) {
    variants <- setdiff(variants, "import")
  }
  for (seed in 1:2) {
    if (!identical(types_of(base), types_of(chosen_fresh))) {
      round2 <- c(round2, list(job(row, "compatible", seed, fixed_fc, base)))
    }
    for (arm in variants) {
      round2 <- c(round2, list(job(row, arm, seed, fixed_fc, base, extensions[[arm]])))
    }
  }
}
cat("Round 2: groundwater variants,", length(round2), "calibrations\n")
results <- c(first, run_all(round2))

# ---- Tables -----------------------------------------------------------------------------

# The parameters of a configuration, with the two surface time constants as a sorted pair:
# two linear stores in series give the same flow whichever way round they are, so k_fast and
# k_slow are what the record determines, not k1 and k2.
parameters <- function(cfg, overrides) {
  p <- calibration_bounds(cfg, overrides = overrides)$path
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
  base <- data.frame(arm = r$arm, seed = r$seed, gauge = r$gauge, state = r$state,
                     seconds = r$seconds, message = r$message %||% "",
                     nse_calibration = r$nse_calibration %||% NA_real_,
                     nse_validation = r$nse_validation %||% NA_real_,
                     runoff_ratio = r$runoff_ratio %||% NA_real_,
                     loss_over_pet = r$loss_over_pet %||% NA_real_,
                     balance_flags = r$balance_flags %||% "",
                     flow_missing_pct = r$flow_missing_pct %||% NA_real_)
  if (!identical(r$state, "done")) return(base)
  cfg <- r$config
  v <- parameters(cfg, r$overrides)
  cbind(base, recharge = cfg$recharge$type, distribution = cfg$distribution$type,
        groundwater = cfg$groundwater$type, as.data.frame(as.list(v), check.names = FALSE))
}
runs <- rbindlist(lapply(results, row_of), fill = TRUE)
runs <- as.data.table(merge(unique(rbind(sample, gw_sample, snow_sample)), runs, by = "gauge",
                            all.y = TRUE, sort = FALSE))
runs <- runs[order(runs$arm, runs$bfi, runs$seed), ]

# How far apart the seeds put each parameter, as a share of its search range (on the log scale
# for parameters searched on it). Within 5% of every range and 0.01 NSE: one seed will do.
# `apart` lists every parameter more than 5% apart: those the search, or the record, has not
# settled. A wide share with the same score means the record does not determine it. Where the
# two seeds chose different structures, their parameters are not comparable: the row says so.
seed_pair <- function(arm, g) {
  a <- results[[paste(arm, g, 1)]]
  b <- results[[paste(arm, g, 2)]]
  if (is.null(a) || is.null(b) || !identical(a$state, "done") || !identical(b$state, "done")) {
    return(NULL)
  }
  if (!identical(types_of(a$config), types_of(b$config))) {
    return(data.frame(arm = arm, gauge = g, same_structure = FALSE,
                      structure_1 = types_of(a$config), structure_2 = types_of(b$config),
                      nse_validation_1 = a$nse_validation, nse_validation_2 = b$nse_validation,
                      nse_difference = b$nse_validation - a$nse_validation,
                      widest_share = NA_real_, widest_parameter = NA_character_,
                      kb_share = NA_real_, widest_without_kb = NA_real_,
                      apart = "different structures", consistent = FALSE))
  }
  bounds <- calibration_bounds(a$config, overrides = a$overrides)
  va <- parameters(a$config, a$overrides)
  vb <- parameters(b$config, b$overrides)
  share <- vapply(seq_along(va), function(k) {
    i <- match(sub("k_fast", "k1", sub("k_slow", "k2", names(va)[k])), bounds$path)
    lo <- bounds$lower[i]
    hi <- bounds$upper[i]
    if (bounds$scale[i] == "log") abs(log(va[k]) - log(vb[k])) / log(hi / lo) else
      abs(va[k] - vb[k]) / (hi - lo)
  }, numeric(1))
  names(share) <- names(va)
  others <- share[names(share) != "groundwater.kb"]
  data.frame(arm = arm, gauge = g, same_structure = TRUE,
             structure_1 = types_of(a$config), structure_2 = types_of(b$config),
             nse_validation_1 = a$nse_validation, nse_validation_2 = b$nse_validation,
             nse_difference = b$nse_validation - a$nse_validation,
             widest_share = max(share), widest_parameter = names(share)[which.max(share)],
             kb_share = if ("groundwater.kb" %in% names(share)) share[["groundwater.kb"]] else NA,
             widest_without_kb = if (length(others)) max(others) else NA,
             apart = paste(names(share)[share > 0.05], collapse = ", "),
             consistent = max(share) <= 0.05 &&
               abs(b$nse_validation - a$nse_validation) <= 0.01)
}
pairs <- unique(runs[, c("arm", "gauge")])
seed_test <- rbindlist(lapply(seq_len(nrow(pairs)), function(i) {
  seed_pair(pairs$arm[i], pairs$gauge[i])
}))

main1 <- runs[runs$arm == "main" & runs$seed == 1 & runs$state == "done", ]
structures <- main1[, c("gauge", "name", "bfi", "recharge", "distribution", "groundwater",
                        "nse_validation", "runoff_ratio", "loss_over_pet", "balance_flags")]

# The groundwater arm side by side: for each catchment and arm, both seeds' validation scores
# and whether the seeds agree. The extension earns its place where it scores clearly higher
# than the chosen structure and its seeds agree.
gw_arms <- c("chosen", "compatible", names(extensions))
side_by_side <- function(arms) {
  keep <- intersect(c("gauge", "name", "bfi", "arm", "state", "nse_validation",
                      "runoff_ratio", "recharge", "groundwater"), names(runs))
  g <- runs[runs$arm %in% arms & runs$seed == 1, ..keep]
  if (!nrow(g)) return(NULL)
  st <- if (nrow(seed_test)) {
    seed_test[seed_test$arm %in% arms, c("arm", "gauge", "nse_validation_2", "consistent",
                                         "apart")]
  } else {
    data.table(arm = character(0), gauge = character(0))
  }
  merge(g, st, by = c("arm", "gauge"), all.x = TRUE)[order(bfi, gauge, arm)]
}
groundwater <- if (nrow(gw_sample)) side_by_side(gw_arms)
# The snow arm beside the same catchments' main runs: PACK earns its place where it scores
# clearly higher.
snow <- if (nrow(snow_sample)) {
  out <- side_by_side(c("main", "snow"))
  out <- out[out$gauge %in% snow_sample$gauge]
  out$frac_snow <- snow_sample$frac_snow[match(out$gauge, snow_sample$gauge)]
  out
}

n_bulk <- sum(as.logical(screen$use))
runtime <- data.frame(
  catchments = nrow(main1), mean_minutes = mean(main1$seconds) / 60,
  slowest_minutes = max(main1$seconds) / 60, cores = cores, bulk_catchments = n_bulk,
  bulk_hours = mean(main1$seconds) * n_bulk / cores / 3600
)

cat("\nStructures chosen\n")
print(structures, row.names = FALSE, digits = 3)
cat("\nSeed test\n")
print(seed_test, row.names = FALSE, digits = 3)
if (!is.null(groundwater)) {
  cat("\nGroundwater arm\n")
  print(groundwater, row.names = FALSE, digits = 3)
}
if (!is.null(snow)) {
  cat("\nSnow arm\n")
  print(snow, row.names = FALSE, digits = 3)
}
cat("\nRuntime (main trial, one run of the whole protocol)\n")
print(runtime, row.names = FALSE, digits = 3)

# ---- Results to the volume --------------------------------------------------------------

dir.create(target, recursive = TRUE, showWarnings = FALSE)
fwrite(runs, file.path(target, "runs.csv"))
fwrite(seed_test, file.path(target, "seed_test.csv"))
fwrite(structures, file.path(target, "structures.csv"))
if (!is.null(groundwater)) fwrite(groundwater, file.path(target, "groundwater.csv"))
if (!is.null(snow)) fwrite(snow, file.path(target, "snow.csv"))
fwrite(runtime, file.path(target, "runtime.csv"))
file.copy(file.path(work, "runs"), target, recursive = TRUE)
cat("\nWritten to", target, "\n")
