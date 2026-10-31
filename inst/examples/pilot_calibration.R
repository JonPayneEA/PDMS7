# ============================================================ #
# Tool:         pilot_calibration
# Description:  Multi-start calibration pilot on a few basins, with a compute budget
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-31
# Modified:     2026-10-31 - Initial pilot script
# Tier:         3
# Inputs:       Per-basin CSV files of rain, PET and flow; a basin table with areas
# Outputs:      Per-basin and per-start CSV tables, an RDS of all fits, a console report
# Dependencies: pdmS7; parallel; utils
# ============================================================ #
#
# Purpose: before calibrating many basins, run a few with many starts and measure
#   1. how many starts it takes to reach the best objective, and
#   2. how much the full run will cost on your hardware.
#
# Usage, from the package root or anywhere once pdmS7 is installed:
#   Rscript inst/examples/pilot_calibration.R
# Dry run on synthetic basins written in the expected format:
#   PILOT_SYNTHETIC=1 Rscript inst/examples/pilot_calibration.R
#
# Default data format (edit read_basin() below if yours differs):
#   <data_dir>/basins.csv      columns: basin_id, area_km2
#   <data_dir>/<basin_id>.csv  columns: time (UTC, e.g. 2001-01-01 00:15:00), rain_mm,
#                              pet_mm, flow_cms. Rain and PET are depths per interval.
#                              Missing flow is allowed and is not scored; missing rain or
#                              PET is not, so infill it first.
# Supply the calibration period only. Keep the validation period out of these files.

# ---- Configuration: edit this block ------------------------------------------------------

settings <- list(
  data_dir = "pilot_data",           # folder holding basins.csv and one CSV per basin
  output_dir = "pilot_results",      # created if missing
  basin_ids = NULL,                  # NULL runs every basin in basins.csv
  timestep_min = 15L,                # model interval in minutes; must match the files
  warmup_days = 365,                 # simulated but not scored
  objective = "nse",                 # rmse, nse (minimises 1 - NSE) or log_rmse
  starts = 20L,                      # starts per basin in the pilot
  seed_base = 1000L,                 # basin i uses seed_base + i
  maxit = 200L,                      # L-BFGS-B iteration limit per start
  cores = max(1L, parallel::detectCores() - 1L),
  best_tolerance = 1e-4,             # a start "reaches the best" within this objective gap
  bound_margin = 0.01,               # flag parameters within 1% of the range of a bound
  full_run_basins = 60L,             # size of the full run to budget for
  full_run_starts = c(5L, 10L, 20L),
  full_run_cores = c(16L, 64L)
)

# Calibrated parameters and bounds. These are illustrative only: set them from catchment
# knowledge. Time constants are in hours and capacities in mm. Every name is a path into
# pdm_presets("standard"); add or remove rows as needed.
bounds <- data.frame(
  parameter = c("fc", "distribution.cmax", "distribution.b", "recharge.kg",
                "surface.k1", "surface.k2", "groundwater.kb"),
  lower = c(0.7, 50, 0.1, 10, 1, 1, 100),
  upper = c(1.3, 400, 2, 5000, 50, 50, 100000)
)

# Reads one basin. Returns forcing (data.frame of rain, pet and POSIXct time), observed flow
# in m3/s and the area in km2. Replace the body if your data are stored differently.
read_basin <- function(basin_id, data_dir, basin_table) {
  path <- file.path(data_dir, paste0(basin_id, ".csv"))
  raw <- utils::read.csv(path, stringsAsFactors = FALSE)
  needed <- c("time", "rain_mm", "pet_mm", "flow_cms")
  missing_cols <- setdiff(needed, names(raw))
  if (length(missing_cols) > 0L) {
    stop(sprintf("%s lacks column(s): %s", path, paste(missing_cols, collapse = ", ")))
  }
  time <- as.POSIXct(raw$time, tz = "UTC", tryFormats = c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"))
  forcing <- data.frame(rain = raw$rain_mm, pet = raw$pet_mm, time = time)
  if (anyNA(forcing$rain) || anyNA(forcing$pet) || anyNA(forcing$time)) {
    stop(sprintf("%s has missing rain, PET or time values; infill them first", path))
  }
  list(
    forcing = forcing,
    observed = as.numeric(raw$flow_cms),
    area_km2 = basin_table$area_km2[basin_table$basin_id == basin_id]
  )
}

# ---- Setup -------------------------------------------------------------------------------

source_root <- if (file.exists("DESCRIPTION") && dir.exists("src")) normalizePath(".") else ""
load_pdm <- function(root) {
  if (nzchar(root) && requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all(root, quiet = TRUE)
  } else {
    library(pdmS7)
  }
  invisible(TRUE)
}
load_pdm(source_root)

# Writes synthetic basins in the default format, from known parameters, for a dry run.
write_synthetic_basins <- function(data_dir, timestep_min) {
  dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
  per_day <- 1440 / timestep_min
  n <- as.integer(2 * 365 * per_day)
  basins <- data.frame(basin_id = c("synthetic_a", "synthetic_b", "synthetic_c"),
                       area_km2 = c(45, 120, 300))
  truths <- list(
    list(fc = 1.1, cmax = 180, kg = 400, kb = 20000),
    list(fc = 0.9, cmax = 250, kg = 1500, kb = 5000),
    list(fc = 1.0, cmax = 120, kg = 200, kb = 60000)
  )
  for (i in seq_len(nrow(basins))) {
    set.seed(100 + i)
    day <- seq_len(n) / per_day
    rain <- ifelse(stats::runif(n) < 0.08, stats::rgamma(n, shape = 0.7, scale = 1), 0)
    pet <- pmax(0, 2 + 1.5 * sin(2 * pi * day / 365.25)) / per_day
    cfg <- pdm_presets("standard")
    cfg$dt <- timestep_min / 60
    cfg$area_km2 <- basins$area_km2[i]
    cfg$fc <- truths[[i]]$fc
    cfg$distribution$cmax <- truths[[i]]$cmax
    cfg$recharge$kg <- truths[[i]]$kg
    cfg$groundwater$kb <- truths[[i]]$kb
    flow <- run_pdm(pdm_from_config(cfg), data.frame(rain = rain, pet = pet))$output$q_m3s
    flow <- flow * exp(stats::rnorm(n, sd = 0.05))  # observation noise
    flow[sample.int(n, n %/% 100)] <- NA            # gaps in the record
    time <- as.POSIXct("2001-01-01", tz = "UTC") + timestep_min * 60 * seq_len(n)
    utils::write.csv(
      data.frame(time = format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                 rain_mm = rain, pet_mm = pet, flow_cms = flow),
      file.path(data_dir, paste0(basins$basin_id[i], ".csv")), row.names = FALSE
    )
  }
  utils::write.csv(basins, file.path(data_dir, "basins.csv"), row.names = FALSE)
  invisible(basins$basin_id)
}

if (Sys.getenv("PILOT_SYNTHETIC") == "1") {
  settings$data_dir <- file.path(tempdir(), "pilot_synthetic")
  settings$warmup_days <- 60
  settings$maxit <- as.integer(Sys.getenv("PILOT_MAXIT", "20"))
  settings$starts <- as.integer(Sys.getenv("PILOT_STARTS", "6"))
  write_synthetic_basins(settings$data_dir, settings$timestep_min)
  cat("Synthetic dry run: basins written to", settings$data_dir, "\n")
}

basin_table <- utils::read.csv(file.path(settings$data_dir, "basins.csv"),
                               stringsAsFactors = FALSE)
basin_ids <- if (is.null(settings$basin_ids)) basin_table$basin_id else settings$basin_ids
lower <- stats::setNames(bounds$lower, bounds$parameter)
upper <- stats::setNames(bounds$upper, bounds$parameter)
dir.create(settings$output_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Calibrate one basin -----------------------------------------------------------------

calibrate_basin <- function(i, basin_ids, settings, lower, upper, basin_table, read_basin) {
  basin_id <- basin_ids[i]
  data <- read_basin(basin_id, settings$data_dir, basin_table)
  config <- pdm_presets("standard")
  config$dt <- settings$timestep_min / 60
  config$area_km2 <- data$area_km2
  # Start 1 is the centre of the bounds, so the pilot does not favour the preset values.
  for (p in names(lower)) {
    config <- pdmS7:::.path_set(config, p, (lower[[p]] + upper[[p]]) / 2)
  }
  warmup <- as.integer(round(settings$warmup_days * 1440 / settings$timestep_min))
  elapsed <- system.time(
    fit <- calibrate_pdm(
      config, data$forcing, data$observed, lower, upper,
      warmup = warmup, objective = settings$objective,
      control = list(maxit = settings$maxit),
      starts = settings$starts, seed = settings$seed_base + i
    )
  )[["elapsed"]]
  list(basin_id = basin_id, n_steps = nrow(data$forcing), seconds = unname(elapsed),
       fit = fit)
}

cat(sprintf("Pilot: %d basin(s), %d starts each, %d worker(s)\n",
            length(basin_ids), settings$starts, min(settings$cores, length(basin_ids))))
workers <- min(settings$cores, length(basin_ids))
run_one <- function(i) {
  calibrate_basin(i, basin_ids, settings, lower, upper, basin_table, read_basin)
}
if (workers > 1L) {
  cl <- parallel::makeCluster(workers)
  results <- tryCatch(
    {
      parallel::clusterExport(cl, c("load_pdm", "source_root"))
      parallel::clusterEvalQ(cl, load_pdm(source_root))
      parallel::parLapply(
        cl, seq_along(basin_ids), calibrate_basin,
        basin_ids = basin_ids, settings = settings, lower = lower, upper = upper,
        basin_table = basin_table, read_basin = read_basin
      )
    },
    finally = parallel::stopCluster(cl)
  )
} else {
  results <- lapply(seq_along(basin_ids), run_one)
}

# ---- Summarise ---------------------------------------------------------------------------

at_bound <- function(values, lower, upper, margin) {
  span <- upper - lower
  hit <- values <= lower + margin * span | values >= upper - margin * span
  if (any(hit)) paste(names(values)[hit], collapse = " ") else ""
}

start_rows <- list()
basin_rows <- list()
for (r in results) {
  tab <- as.data.frame(r$fit$start_results)
  best <- min(tab$objective)
  reached <- tab$objective <= best + settings$best_tolerance
  total_evals <- sum(tab$evaluations)
  tab$basin_id <- r$basin_id
  start_rows[[r$basin_id]] <- tab
  basin_rows[[r$basin_id]] <- data.frame(
    basin_id = r$basin_id,
    n_steps = r$n_steps,
    best_objective = best,
    best_nse = if (settings$objective == "nse") 1 - best else NA_real_,
    first_start_at_best = which(reached)[1L],
    starts_at_best = sum(reached),
    objective_spread = max(tab$objective) - best,
    converged = sum(tab$convergence == 0L),
    median_evaluations = stats::median(tab$evaluations),
    seconds = r$seconds,
    seconds_per_evaluation = r$seconds / total_evals,
    params_at_bound = at_bound(r$fit$parameters, lower, upper, settings$bound_margin),
    stringsAsFactors = FALSE
  )
}
basin_summary <- do.call(rbind, basin_rows)
start_table <- do.call(rbind, start_rows)
rownames(basin_summary) <- NULL
rownames(start_table) <- NULL

utils::write.csv(basin_summary, file.path(settings$output_dir, "basin_summary.csv"),
                 row.names = FALSE)
utils::write.csv(start_table, file.path(settings$output_dir, "start_results.csv"),
                 row.names = FALSE)
saveRDS(results, file.path(settings$output_dir, "pilot_fits.rds"))

# ---- Report ------------------------------------------------------------------------------

cat("\nPer basin\n")
print(basin_summary[, c("basin_id", "n_steps", "best_objective", "best_nse",
                        "first_start_at_best", "starts_at_best", "objective_spread",
                        "converged", "median_evaluations", "seconds", "params_at_bound")],
      row.names = FALSE, digits = 4)

needed <- max(basin_summary$first_start_at_best)
cat(sprintf(
  "\nStarts needed to reach the best in every pilot basin: %d of %d.\n",
  needed, settings$starts
))
cat("The order of random starts is one sample, so treat this as a lower bound and add a",
    "margin.\n")
if (any(nzchar(basin_summary$params_at_bound))) {
  cat("Some best-fit parameters sit on a bound (see params_at_bound): widen those bounds",
      "or fix the parameter before the full run.\n")
}

# Budget: per basin and per start, seconds = median evaluations x seconds per evaluation.
# Seconds per evaluation scale with series length, so they are normalised per million steps.
per_start <- basin_summary$median_evaluations * basin_summary$seconds_per_evaluation /
  basin_summary$n_steps * 1e6
sec_per_start_per_mstep <- stats::median(per_start)
median_steps <- stats::median(basin_summary$n_steps)
cat(sprintf(
  "\nMeasured cost: %.3g s per start per million steps (median over pilot basins).\n",
  sec_per_start_per_mstep
))
cat(sprintf("Budget for %d basins of %s steps each (the pilot median length):\n\n",
            settings$full_run_basins, format(median_steps, big.mark = ",")))
budget <- expand.grid(starts = settings$full_run_starts, cores = settings$full_run_cores)
budget$hours <- settings$full_run_basins * budget$starts * sec_per_start_per_mstep *
  median_steps / 1e6 / budget$cores / 3600
budget$hours <- signif(budget$hours, 3)
print(budget, row.names = FALSE)
cat("\nThis assumes one basin per core and that the full-run basins resemble the pilot.\n")
cat("Results written to", normalizePath(settings$output_dir), "\n")
