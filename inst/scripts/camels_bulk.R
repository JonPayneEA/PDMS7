# ============================================================ #
# Tool:         camels_bulk
# Description:  The bulk PDM calibration of CAMELS-GB v2: every screened catchment through the
#               protocol settled in the trials, with PACK for snow, the groundwater extension
#               where the water balance calls for it, and a free rainfall factor where the
#               rain is likely too low. Resumable; results reach the volume as each chunk ends
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-23
# Modified:     2026-11-23 - First version, from CAMELS-GB trials 1 to 4
# Tier:         1
# Inputs:       The pipeline's gold/camels_gb_v2/ under a store root: hourly tables,
#               descriptors and screening.csv (with its treatment and pack columns)
# Outputs:      gold/camels_gb_v2/bulk/: results/<gauge>.csv (one row per catchment, written
#               as it finishes), projects/<gauge>/ (its calibration logs), results.csv
# Dependencies: pdmS7 (0.37.0 or later, installed, for parallel workers); data.table; arrow
# ============================================================ #
# Usage: set the store root, then run the whole script, from a shell or an R notebook:
#   CAMELS_STORE=/Volumes/.../hydrometric Rscript camels_bulk.R
# or, in a notebook, Sys.setenv(CAMELS_STORE = "...") and source() this file. Run it again
# after any stop: catchments whose results are on the volume are skipped.
#
# Optional environment variables, defaults in brackets:
#   CAMELS_CORES    catchments calibrated at once, one chunk (12)
#   CAMELS_STARTS   random starts per search (3)
#   CAMELS_BUDGET   model runs per start, DDS (600)
#   CAMELS_LIMIT    at most this many catchments this run, for a first look (all)
#   CAMELS_ONLY     a comma-separated list of gauges to run (all screened in)
#   CAMELS_WORK     local working folder (a folder under tempdir())
#   PDMS7_USER      the name recorded in the calibration logs ("CAMELS-GB bulk")
#
# The protocol, for each catchment screened in (screening.csv, use = TRUE):
#   1. Rain: CEH-GEAR hourly; where pack is TRUE (a snow share of 5% or more), PACK at its
#      default parameters turns precipitation and the day's temperature into rain and melt.
#   2. The structure chosen on the record (recharge, soil store, groundwater store), then the
#      stages, each by DDS: volume and baseflow (on 6-hour steps), fast response, a Box-Cox
#      polish, and the largest events. The rainfall factor is fixed at 1, except where the
#      treatment is free_fc (rain likely too low): there it is searched from 0.9 to 1.5.
#   3. Where the treatment is abstraction (groundwater-fed and losing water) or import
#      (groundwater-fed and gaining), the nearest structure that takes the groundwater
#      extension is calibrated again with an abstraction term, or with springs free to bring
#      water in. It is kept only if it beats step 2 on validation by more than 0.02 NSE.
#   4. One row of results: the structures equally good at each step of the choice (within
#      0.02 NSE of the best, so the descriptor model can tell a firm choice from a tie), the
#      kept model's scores and parameters (the surface time constants as a sorted pair), and
#      the water balance.
# The test windows are not scored: the test is kept for the final protocol.
#
# Calibration logs append to files, which a Unity Catalog volume does not allow, and the
# worker processes cannot read the volume. So each chunk's hourly tables are copied to local
# disk, calibrated there, and its results and projects copied to the volume, whole, when the
# chunk ends. A stop loses only the chunk in hand.

library(pdmS7)
library(data.table)
stopifnot(utils::packageVersion("pdmS7") >= "0.37.0")
`%||%` <- function(x, y) if (is.null(x)) y else x

store <- Sys.getenv("CAMELS_STORE")
if (!nzchar(store)) stop("Set CAMELS_STORE to the pipeline's store root", call. = FALSE)
cores <- as.integer(Sys.getenv("CAMELS_CORES", "12"))
starts <- as.integer(Sys.getenv("CAMELS_STARTS", "3"))
budget <- as.integer(Sys.getenv("CAMELS_BUDGET", "600"))
limit <- as.integer(Sys.getenv("CAMELS_LIMIT", "0"))
only <- strsplit(Sys.getenv("CAMELS_ONLY"), ",", fixed = TRUE)[[1]]
work <- Sys.getenv("CAMELS_WORK", file.path(tempdir(), "camels-bulk"))
user <- Sys.getenv("PDMS7_USER", "CAMELS-GB bulk")
options(pdmS7.user = user, pdmS7.role = "custodian")

camels <- file.path(store, "gold", "camels_gb_v2")
target <- file.path(camels, "bulk")
dir.create(file.path(target, "results"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(target, "projects"), recursive = TRUE, showWarnings = FALSE)
dir.create(work, recursive = TRUE, showWarnings = FALSE)

tie <- 0.02                                   # NSE: equally good, and the extension's margin
free_fc <- list(fc = c(0.9, 1.5))            # where the rain is likely too low
extensions <- list(abstraction = list(ca = 0.001), import = list(alpha_b = -0.2))

# ---- The catchments ---------------------------------------------------------------------

screen <- fread(file.path(camels, "screening.csv"), colClasses = list(character = "gauge_id"))
need <- c("use", "treatment", "pack")
if (!all(need %in% names(screen))) {
  stop("screening.csv has no treatment and pack columns: rerun 01_camels_prepare with the ",
       "current pipeline", call. = FALSE)
}
descriptors <- pdmS7:::.read_parquet(file.path(camels, "descriptors.parquet"))
descriptors$gauge_id <- as.character(descriptors$gauge_id)
todo <- screen[as.logical(screen$use)]
if (length(only) && any(nzchar(only))) todo <- todo[todo$gauge_id %in% trimws(only)]
done_already <- sub("\\.csv$", "", list.files(file.path(target, "results"), "\\.csv$"))
todo <- todo[!todo$gauge_id %in% done_already]
if (limit > 0) todo <- head(todo, limit)
todo$area_km2 <- as.numeric(descriptors$area[match(todo$gauge_id, descriptors$gauge_id)])
cat(nrow(todo), "catchments to calibrate;", length(done_already), "already on the volume\n")
print(table(treatment = todo$treatment, pack = as.logical(todo$pack)))
if (!nrow(todo)) {
  cat("Nothing to do.\n")
}

# ---- One catchment ----------------------------------------------------------------------

registry <- function(part) {
  switch(part, distribution = pdmS7:::.dist_registry(), recharge = pdmS7:::.recharge_registry(),
         pdmS7:::.route_registry())
}
component <- function(part, type) {
  c(list(type = type), lapply(formals(registry(part)[[type]]), eval, envir = baseenv()))
}
# The chosen structure's components at their default values, without any extension.
fresh_structure <- function(cfg) {
  out <- cfg
  for (part in c("distribution", "recharge", "surface", "groundwater")) {
    out[[part]] <- component(part, cfg[[part]]$type)
  }
  out$fc <- 1
  out$td <- 0
  out
}
# The nearest structure that takes the groundwater extension: a cubic store for an exponential
# one, standard recharge for demand.
compatible_structure <- function(cfg) {
  out <- cfg
  if (identical(cfg$groundwater$type, "exponential")) out$groundwater <- component("route", "cubic")
  if (identical(cfg$recharge$type, "demand")) out$recharge <- component("recharge", "standard")
  out
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
# Parameters, the two surface time constants as a sorted pair (k_fast, k_slow): two linear
# stores in series give the same flow whichever way round they are.
parameters <- function(cfg, overrides) {
  p <- calibration_bounds(cfg, overrides = overrides)$path
  v <- vapply(p, function(x) as.numeric(pdmS7:::.path_get(cfg, x)), numeric(1))
  if (all(c("surface.k1", "surface.k2") %in% p)) {
    k <- sort(v[c("surface.k1", "surface.k2")])
    v[c("surface.k1", "surface.k2")] <- k
    names(v)[names(v) == "surface.k1"] <- "surface.k_fast"
    names(v)[names(v) == "surface.k2"] <- "surface.k_slow"
  }
  v
}
# The structures within `tie` NSE of the best at each step of the choice, in step order.
equally_good <- function(project) {
  entries <- pdmS7:::.read_entries(pdmS7:::.project_path(project))
  ids <- unique(unlist(lapply(entries, function(e) {
    if (identical(e$type, "auto_calibration")) e$comparison
  })))
  steps <- c("recharge", "distribution", "groundwater")
  vapply(seq_along(ids), function(i) {
    tab <- structure_comparison(project, ids[i])
    best <- max(tab$validation, na.rm = TRUE)
    paste0(steps[i] %||% paste("step", i), ": ",
           paste(tab$structure[tab$validation >= best - tie], collapse = " | "))
  }, character(1))
}

run_one <- function(job) {
  started <- proc.time()[["elapsed"]]
  g <- job$gauge
  out <- tryCatch({
    x <- camels_forcing(camels_read(local_store, g))
    w <- camels_windows(x$forcing$time)
    reasoning <- "CAMELS-GB v2 bulk: CEH-GEAR hourly rain, Hydro-PE, hourly flow."
    if (isTRUE(job$pack)) {
      if (anyNA(x$forcing$temperature)) stop("Temperature missing inside the rain years")
      x$forcing$rain <- sim_pack(x$forcing$rain, x$forcing$temperature, pack_presets(),
                                 timestep_min = 60L)$effective_rain_mm
      reasoning <- paste(reasoning, "Rain is PACK rain plus melt, at PACK's default parameters.")
    }
    overrides <- if (identical(job$treatment, "free_fc")) free_fc else NULL
    if (!is.null(overrides)) reasoning <- paste(reasoning, "Rain likely too low: fc searched.")
    calibrate <- function(name, structure, recommend) {
      project <- file.path(work, "runs", g, name)
      calibrate_project(project, x$forcing[c("time", "rain", "pet")], x$observed, job$area_km2,
                        w$calibration, w$validation, structure = structure,
                        stages = make_stages(overrides), recommend = recommend,
                        overrides = overrides, starts = starts, seed = 1L,
                        control = list(maxit = budget), method = "dds", catchment = job$name,
                        gauge = g, purpose = paste("CAMELS-GB bulk,", name), test = w$test,
                        wettest_years = 0, reasoning = reasoning)
      s <- read_projects(project)
      list(project = project, nse_calibration = s$candidate_score,
           nse_validation = s$validation_score,
           config = read_entry(project, s$candidate)$configuration)
    }
    start <- pdm_presets("standard")
    start$dt <- 1
    start$area_km2 <- job$area_km2
    protocol <- calibrate("protocol", start, TRUE)
    kept <- protocol
    kept$name <- "protocol"
    extension <- NULL
    if (job$treatment %in% names(extensions)) {
      base <- compatible_structure(fresh_structure(protocol$config))
      base$groundwater$extension <- extensions[[job$treatment]]
      extension <- tryCatch(calibrate(job$treatment, base, FALSE),
                            error = function(e) list(error = conditionMessage(e)))
      if (!is.null(extension$nse_validation) &&
          extension$nse_validation > protocol$nse_validation + tie) {
        kept <- extension
        kept$name <- job$treatment
      }
    }
    wb <- tryCatch(water_balance(x$forcing, x$observed, job$area_km2)$record,
                   error = function(e) NULL)
    cfg <- kept$config
    v <- parameters(cfg, overrides)
    eq <- equally_good(protocol$project)
    row <- data.frame(
      gauge = g, name = job$name, state = "done", message = "", treatment = job$treatment,
      pack = isTRUE(job$pack), kept = kept$name,
      recharge = cfg$recharge$type, distribution = cfg$distribution$type,
      groundwater = cfg$groundwater$type,
      structure_tied = any(grepl("|", eq, fixed = TRUE)),
      equally_good = paste(eq, collapse = "; "),
      nse_calibration = kept$nse_calibration, nse_validation = kept$nse_validation,
      nse_validation_protocol = protocol$nse_validation,
      nse_validation_extension = extension$nse_validation %||% NA_real_,
      extension_message = extension$error %||% "",
      runoff_ratio = if (is.null(wb)) NA_real_ else wb$runoff_ratio,
      loss_over_pet = if (is.null(wb)) NA_real_ else wb$loss_over_pet,
      balance_flags = if (is.null(wb)) "" else wb$flags,
      flow_missing_pct = x$summary$flow_missing_pct,
      check.names = FALSE)
    cbind(row, as.data.frame(as.list(v), check.names = FALSE))
  }, error = function(e) {
    data.frame(gauge = g, name = job$name, state = "failed", message = conditionMessage(e),
               treatment = job$treatment, pack = isTRUE(job$pack))
  })
  out$seconds <- round(proc.time()[["elapsed"]] - started)
  out
}

run_chunk <- function(jobs) {
  if (cores <= 1L || length(jobs) < 2L) return(lapply(jobs, run_one))
  cl <- parallel::makeCluster(min(cores, length(jobs)))
  on.exit(parallel::stopCluster(cl), add = TRUE)
  parallel::clusterCall(cl, function(p, u) {
    .libPaths(p)
    library(pdmS7)
    options(pdmS7.user = u, pdmS7.role = "custodian")
    NULL
  }, unique(c(dirname(system.file(package = "pdmS7")), .libPaths())), user)
  parallel::clusterExport(cl, c("local_store", "work", "starts", "budget", "tie", "free_fc",
                                "extensions", "registry", "component", "fresh_structure",
                                "compatible_structure", "make_stages", "parameters",
                                "equally_good", "%||%"),
                          envir = environment(run_one))
  parallel::parLapply(cl, jobs, run_one)
}

# ---- Chunks -----------------------------------------------------------------------------

local_store <- file.path(work, "store")
local_dir <- file.path(local_store, "gold", "camels_gb_v2", "hourly")
dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
# A file reaches the volume whole: written locally, then copied.
to_volume <- function(df, path) {
  tmp <- tempfile(fileext = ".csv")
  fwrite(df, tmp)
  file.copy(tmp, path, overwrite = TRUE)
  unlink(tmp)
}

chunks <- split(seq_len(nrow(todo)), ceiling(seq_len(nrow(todo)) / max(1L, cores)))
started <- proc.time()[["elapsed"]]
for (k in seq_along(chunks)) {
  rows <- todo[chunks[[k]]]
  for (g in rows$gauge_id) {
    file.copy(file.path(camels, "hourly", paste0(g, ".parquet")),
              file.path(local_dir, paste0(g, ".parquet")), overwrite = TRUE)
  }
  jobs <- lapply(seq_len(nrow(rows)), function(i) {
    list(gauge = rows$gauge_id[i], name = rows$gauge_name[i], area_km2 = rows$area_km2[i],
         treatment = rows$treatment[i], pack = as.logical(rows$pack[i]))
  })
  results <- run_chunk(jobs)
  for (r in results) {
    g <- r$gauge[1]
    to_volume(r, file.path(target, "results", paste0(g, ".csv")))
    if (dir.exists(file.path(work, "runs", g))) {
      file.copy(file.path(work, "runs", g), file.path(target, "projects"), recursive = TRUE)
      unlink(file.path(work, "runs", g), recursive = TRUE)
    }
    unlink(file.path(local_dir, paste0(g, ".parquet")))
    if (!identical(r$state[1], "done")) cat("  Failed:", g, ":", r$message[1], "\n")
  }
  spent <- (proc.time()[["elapsed"]] - started) / 3600
  cat(sprintf("Chunk %d of %d done: %d catchments, %.1f h so far, about %.1f h to go\n", k,
              length(chunks), sum(lengths(chunks[seq_len(k)])), spent,
              spent / k * (length(chunks) - k)))
}

# ---- All results ------------------------------------------------------------------------

files <- list.files(file.path(target, "results"), "\\.csv$", full.names = TRUE)
if (!length(files)) stop("No results on the volume yet", call. = FALSE)
results <- rbindlist(lapply(files, fread, colClasses = list(character = "gauge")), fill = TRUE)
to_volume(results, file.path(target, "results.csv"))
done <- results[results$state == "done"]
cat("\n", nrow(done), "of", nrow(results), "catchments calibrated\n")
if (nrow(done)) {
  cat("Validation NSE, quartiles:", round(stats::quantile(done$nse_validation,
                                                           c(0.25, 0.5, 0.75), na.rm = TRUE), 2),
      "\n")
  print(table(kept = done$kept, treatment = done$treatment))
  cat("Structure tied at some step:", sum(done$structure_tied), "of", nrow(done), "\n")
}
cat("Written to", target, "\n")
