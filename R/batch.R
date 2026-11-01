# ============================================================ #
# Tool:         batch
# Description:  Batch calibration of many basins: resumable, logged, parallel
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add batch calibration
# Tier:         3
# Inputs:       A folder of basin folders (forcing.csv, flow.csv, basin.yml)
# Outputs:      One calibration project per basin; batch-status.csv
# Dependencies: parallel (base R); data.table; yaml
# ============================================================ #

.batch_steps <- c("start", "register", "structure", "calibrate", "candidate", "validate", "test")

#' Calibrate many basins in one batch
#'
#' Runs the same calibration protocol on every basin in a folder, giving each basin its own
#' calibration-log project, so every calibration is recorded, can be reviewed, and is done
#' exactly the same way. The batch can be stopped at any time, by a crash, a power cut or on
#' purpose, and started again with the same call: each basin carries on from the last step it
#' completed. Steps already in a basin's log are never repeated, so a finished basin passes
#' through in moments; a step newly asked for, such as the test, is added. Changing the
#' protocol does not recalibrate a basin that already has a calibration: its log keeps the
#' calibration it had.
#'
#' **Input folder.** One subfolder per basin, named by its identifier, holding:
#'
#' - `forcing.csv`: columns `time` (ISO 8601, UTC), `rain` and `pet` in mm per interval;
#' - `flow.csv`: column `q_m3s` (and optionally `time`), aligned with the forcing;
#' - `basin.yml`: `area_km2` and `calibration` (start and end) are required; `catchment`,
#'   `gauge`, `validation`, `test`, `config` (a YAML configuration file in the folder),
#'   `headline`, `thresholds` (a list of `name`, `value`, `unit`), `rating` (a CSV in the
#'   folder) and `snow` are optional.
#'
#' **Snow.** For a basin with `snow: true` in `basin.yml`, `forcing.csv` also needs a
#' `temperature` column (deg C), and `rain` holds all precipitation. The PACK snow model turns
#' them into the rain and melt reaching the ground, with fixed parameters: the default preset,
#' or a preset named by `snow`, or a PACK YAML file in the basin folder named by `snow`. PACK
#' is not calibrated; only the PDM is. The series PACK produces is registered as the rain, and a
#' note in the log records the PACK parameters and the checksum of the original forcing.
#'
#' **Steps for each basin**, each written to its project as it completes: start the project,
#' register the data, select the structure, run the automatic calibration, propose the best
#' result as candidate, validate it, and, with `test = TRUE`, test it once on the test window.
#'
#' **Progress.** `batch-status.csv` in the output folder gets a row whenever a basin starts,
#' finishes or fails; `batch_status()` summarises it while the batch runs. A failure is
#' recorded with its reason and the batch moves on; fix the cause and run the same call again.
#'
#' **Seeds.** Each basin's random starts are seeded from `seed` and the basin's name, so a
#' basin's result does not change when others are added or removed.
#'
#' @param basins Folder holding one subfolder per basin.
#' @param output Folder for the projects and the status file; created if needed.
#' @param structure Default configuration (a list or YAML path) for basins whose `basin.yml`
#'   names none; the standard PDM if `NULL`. The basin's area is always applied.
#' @param overrides,exclude Passed to [calibration_bounds()].
#' @param objective,starts,seed,control,method Passed to [calibrate_pdm()]. Search scales
#'   come from the bounds table.
#' @param staged If `TRUE`, calibrate in stages, as [calibrate_staged()] does, with stages from
#'   [pdm_stages()]: one `auto_calibration` entry per stage. An interrupted basin resumes
#'   from its last finished stage. `objective` then applies to no stage; each stage has its own.
#' @param test If `TRUE`, score each validated candidate once on its test window, if it has
#'   one. Use it when the protocol is final; the test window is scored only once.
#' @param cores Number of basins to run at once, in parallel worker processes.
#' @param only Optional basin identifiers to run, for example to retry failures.
#' @param owner,steward,purpose Recorded in each new project.
#' @return `calibrate_batch()`: the batch status, invisibly, as from `batch_status()`.
#'   `batch_status()`: a data.table with one row per basin: `basin`, `state` (`queued`,
#'   `running`, `done` or `failed`), `step` reached, `seconds` and `message`.
#'   `batch_results()`: [read_projects()] for every project, with the batch state.
#' @seealso [calibration_log], [compare_structures()], [calibration_bounds()]
#' @export
calibrate_batch <- function(basins, output, structure = NULL, overrides = NULL, exclude = NULL,
                            objective = c("nse", "rmse", "log_rmse"), starts = 10L, seed = 1,
                            control = list(maxit = 200), method = c("lbfgsb", "nelder_mead"),
                            staged = FALSE, test = FALSE, cores = 1L, only = NULL,
                            owner = "Not recorded", steward = "Not recorded",
                            purpose = "Batch calibration") {
  author <- .identity("custodian")
  objective <- match.arg(objective)
  method <- match.arg(method)
  .check(is.character(basins) && length(basins) == 1L && dir.exists(basins),
         "basins must be a folder of basin folders")
  .check(.scalar(cores, 1) && cores == floor(cores), "cores must be a whole number of at least 1")
  ids <- .batch_ids(basins, only)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  status_file <- file.path(normalizePath(output, winslash = "/"), "batch-status.csv")
  if (is.list(structure) || is.null(structure)) {
    default <- structure %||% pdm_presets("standard")
  } else {
    default <- read_pdm_config(structure)
  }
  spec <- list(
    basins = normalizePath(basins, winslash = "/"), output = normalizePath(output, winslash = "/"),
    status = status_file, default = default, overrides = overrides, exclude = exclude,
    objective = objective, starts = as.integer(starts), seed = seed, control = control,
    method = method, staged = isTRUE(staged), test = isTRUE(test), owner = owner,
    steward = steward, purpose = purpose,
    author = author
  )
  # Every basin walks the steps; completed steps are read from its log and skipped, so a
  # finished basin passes quickly and a newly requested step, such as the test, is added.
  .batch_record(status_file, ids, "queued", NA_character_, NA_real_, "")
  .run_jobs(as.list(ids), .batch_basin, cores, spec = spec)
  invisible(batch_status(output))
}

.batch_ids <- function(basins, only) {
  dirs <- list.dirs(basins, full.names = FALSE, recursive = FALSE)
  ids <- sort(dirs[file.exists(file.path(basins, dirs, "basin.yml"))])
  .check(length(ids) > 0, "No basin folders with a basin.yml found")
  if (!is.null(only)) {
    .check(all(only %in% ids), paste("Unknown basins:", toString(setdiff(only, ids))))
    ids <- intersect(ids, only)
  }
  ids
}

.batch_record <- function(path, basin, state, step, seconds, message) {
  .append_csv(path, data.table::data.table(
    basin = basin, state = state, step = step, time = .timestamp(), seconds = seconds,
    message = message
  ), "Batch status")
}

.basin_seed <- function(id, seed) {
  (strtoi(substr(.md5_text(id), 1L, 7L), 16L) + as.integer(seed)) %% 2147483647L
}

# Runs one basin from wherever it got to. Runs in a worker, so it sets the identity itself.
.batch_basin <- function(id, spec) {
  old <- options(pdmS7.user = spec$author$name, pdmS7.role = spec$author$role)
  on.exit(options(old), add = TRUE)
  started <- proc.time()[["elapsed"]]
  .batch_record(spec$status, id, "running", NA_character_, NA_real_, "")
  step <- "start"
  outcome <- tryCatch({
    for (step in .batch_steps) .batch_step(step, id, spec)
    step <- "complete"
    list(state = "done", message = "")
  }, error = function(e) list(state = "failed", message = conditionMessage(e)))
  seconds <- round(proc.time()[["elapsed"]] - started, 1)
  .batch_record(spec$status, id, outcome$state, step, seconds, outcome$message)
  invisible(outcome$state)
}

.basin_meta <- function(id, spec) {
  folder <- file.path(spec$basins, id)
  meta <- .read_yaml_file(file.path(folder, "basin.yml"))
  .check(.scalar(meta$area_km2, 0, strict = TRUE), "basin.yml needs a positive area_km2")
  .check(length(meta$calibration) == 2L, "basin.yml needs calibration: [start, end]")
  meta$folder <- folder
  meta
}

.basin_config <- function(meta, spec) {
  config <- if (is.null(meta$config)) spec$default else
    read_pdm_config(file.path(meta$folder, meta$config))
  config$area_km2 <- as.numeric(meta$area_km2)
  config
}

.basin_thresholds <- function(meta) {
  if (is.null(meta$thresholds)) return(NULL)
  data.frame(name = vapply(meta$thresholds, function(t) as.character(t$name), ""),
             value = vapply(meta$thresholds, function(t) as.numeric(t$value), 0),
             unit = vapply(meta$thresholds, function(t) as.character(t$unit), ""))
}

.batch_step <- function(step, id, spec) {
  ctx <- list(id = id, spec = spec, project = file.path(spec$output, id),
              meta = .basin_meta(id, spec),
              reasoning = paste0("Batch protocol (", spec$purpose, ")."))
  .batch_actions[[step]](ctx)
  invisible(TRUE)
}

.batch_has <- function(project, type) {
  file.exists(file.path(project, .marker)) &&
    any(vapply(.read_entries(.project_path(project)), function(e) e$type == type, logical(1)))
}

# One function per step; each does nothing if its entry is already in the log.
.batch_start <- function(ctx) {
  if (file.exists(file.path(ctx$project, .marker))) return(invisible())
  m <- ctx$meta
  start_calibration_project(ctx$project, catchment = m$catchment %||% ctx$id,
                            gauge = as.character(m$gauge %||% ctx$id),
                            purpose = ctx$spec$purpose, area_km2 = as.numeric(m$area_km2),
                            owner = ctx$spec$owner, steward = ctx$spec$steward, id = ctx$id)
}

.batch_register <- function(ctx) {
  if (.batch_has(ctx$project, "data_registered")) return(invisible())
  m <- ctx$meta
  forcing <- file.path(m$folder, "forcing.csv")
  if (!is.null(m$snow) && !isFALSE(m$snow)) {
    forcing <- .batch_snow(ctx, forcing)
    on.exit(unlink(forcing), add = TRUE)
  }
  register_data(ctx$project, forcing,
                file.path(m$folder, "flow.csv"), calibration = unlist(m$calibration),
                validation = unlist(m$validation), test = unlist(m$test),
                headline = m$headline %||% "nse", thresholds = .basin_thresholds(m),
                rating = if (!is.null(m$rating)) file.path(m$folder, m$rating))
}

# Snow basins: PACK, at fixed parameters, turns precipitation and temperature into the rain
# and melt reaching the ground. That series is registered as the rain, so only the PDM is
# calibrated; a note records the PACK settings and the raw forcing's checksum.
.batch_snow <- function(ctx, path) {
  m <- ctx$meta
  raw <- data.table::fread(path)
  .check(all(c("time", "rain", "pet", "temperature") %in% names(raw)),
         "A snow basin's forcing.csv needs time, rain (all precipitation), pet and temperature")
  config <- .basin_pack(m)
  formats <- c("%Y-%m-%dT%H:%M:%OSZ", "%Y-%m-%d %H:%M:%OS")
  times <- as.POSIXct(raw$time[1:2], tz = "UTC", tryFormats = formats)
  step <- as.numeric(difftime(times[2], times[1], units = "mins"))
  snow <- sim_pack(raw$rain, raw$temperature, config, timestep_min = as.integer(round(step)))
  out <- tempfile("forcing-", fileext = ".csv")
  data.table::fwrite(data.frame(time = raw$time, rain = snow$effective_rain_mm, pet = raw$pet),
                     out)
  entries <- .read_entries(.project_path(ctx$project))
  noted <- any(vapply(entries, function(e) e$type == "note" && startsWith(e$text, "Snow:"),
                      logical(1)))
  if (!noted) {
    log_note(ctx$project, paste0(
      "Snow: the registered rain is PACK rain plus melt, from forcing.csv (MD5 ", .md5_file(path),
      ") at fixed PACK parameters, not calibrated: ",
      paste(names(config), vapply(config, function(v) paste(format(v), collapse = " "), ""),
            sep = " = ", collapse = "; "), "."
    ))
  }
  out
}

.basin_pack <- function(m) {
  if (isTRUE(m$snow)) return(pack_presets())
  .check(is.character(m$snow) && length(m$snow) == 1L,
         "snow in basin.yml must be true, a PACK preset name or a PACK YAML file")
  file <- file.path(m$folder, m$snow)
  if (file.exists(file)) .read_yaml_file(file) else pack_presets(m$snow)
}

.batch_structure <- function(ctx) {
  if (.batch_has(ctx$project, "structure_selected")) return(invisible())
  select_structure(ctx$project, .basin_config(ctx$meta, ctx$spec), ctx$reasoning)
}

.batch_fit <- function(ctx) {
  entries <- .read_entries(.project_path(ctx$project))
  fits <- Filter(function(e) e$type == "auto_calibration", entries)
  staged_fits <- Filter(function(e) !is.null(e$stage), fits)
  # A basin keeps the kind of calibration it already has; only unfinished stages are run.
  if (length(fits) && (!ctx$spec$staged || length(staged_fits) < length(fits))) {
    return(invisible())
  }
  if (ctx$spec$staged) {
    return(.batch_staged(ctx, entries, staged_fits))
  }
  .batch_calibrate(ctx$project, ctx$id, ctx$spec, ctx$reasoning)
}

.batch_staged <- function(ctx, entries, done) {
  structure <- .latest(entries, "structure_selected")
  config <- structure$configuration
  stages <- pdm_stages(config, ctx$spec$overrides, ctx$spec$exclude)
  bounds <- calibration_bounds(config, ctx$spec$overrides, ctx$spec$exclude)
  labels <- vapply(done, function(e) e$stage, character(1))
  parent <- structure$id
  for (i in seq_along(stages)) {
    hit <- which(labels == .stage_label(i, stages))
    if (length(hit)) {
      parent <- done[[hit[length(hit)]]]$id
      next
    }
    parent <- .log_stage(ctx$project, parent, stages, i, bounds, ctx$reasoning,
                         ctx$spec$starts, .basin_seed(ctx$id, ctx$spec$seed), ctx$spec$control,
                         ctx$spec$method)$id
  }
  invisible()
}

.batch_candidate <- function(ctx) {
  if (.batch_has(ctx$project, "candidate")) return(invisible())
  fit <- .latest(.read_entries(.project_path(ctx$project)), "auto_calibration")
  propose_candidate(ctx$project, fit$id, paste(ctx$reasoning, "Best of the automatic starts."))
}

.batch_validate <- function(ctx) {
  if (.batch_has(ctx$project, "validation") || is.null(ctx$meta$validation)) {
    return(invisible())
  }
  validate_candidate(ctx$project, ctx$reasoning)
}

.batch_test <- function(ctx) {
  if (!ctx$spec$test || .batch_has(ctx$project, "test") || is.null(ctx$meta$test)) {
    return(invisible())
  }
  test_candidate(ctx$project, ctx$reasoning)
}

.batch_actions <- list(
  start = .batch_start,
  register = .batch_register,
  structure = .batch_structure,
  calibrate = .batch_fit,
  candidate = .batch_candidate,
  validate = .batch_validate,
  test = .batch_test
)

.batch_calibrate <- function(project, id, spec, reasoning) {
  entries <- .read_entries(.project_path(project))
  structure <- .latest(entries, "structure_selected")
  bounds <- calibration_bounds(structure$configuration, spec$overrides, spec$exclude)
  log_auto_calibration(
    project, parent = structure$id, lower = stats::setNames(bounds$lower, bounds$path),
    upper = stats::setNames(bounds$upper, bounds$path), objective = spec$objective,
    starts = spec$starts, seed = .basin_seed(id, spec$seed), control = spec$control,
    method = spec$method, log_scale = bounds$path[bounds$scale == "log"], reasoning = reasoning
  )
}

#' @rdname calibrate_batch
#' @export
batch_status <- function(output) {
  path <- file.path(output, "batch-status.csv")
  .check(file.exists(path), paste("No batch status in", output))
  rows <- data.table::fread(path, colClasses = list(character = c("step", "message")))
  rows <- rows[rev(seq_len(nrow(rows)))]
  latest <- rows[!duplicated(rows$basin)]
  latest <- latest[order(latest$basin)]
  out <- latest[, c("basin", "state", "step", "seconds", "message")]
  data.table::setattr(out, "counts", table(factor(out$state,
                                                  c("queued", "running", "done", "failed"))))
  out
}

#' @rdname calibrate_batch
#' @export
batch_results <- function(output) {
  status <- batch_status(output)
  folders <- file.path(output, status$basin)
  folders <- folders[file.exists(file.path(folders, .marker))]
  .check(length(folders) > 0, "No projects have been started yet")
  results <- read_projects(folders)
  out <- merge(results, status[, c("basin", "state", "step", "message")], by.x = "project",
               by.y = "basin", all.x = TRUE, sort = FALSE)
  data.table::setkey(out, NULL)
  out[order(out$project)]
}
