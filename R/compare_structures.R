# ============================================================ #
# Tool:         compare_structures
# Description:  Calibrate several model structures alike and rank them on held-out data
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add structure comparison
# Tier:         3
# Inputs:       A calibration project with a validation window; named configurations
# Outputs:      structure_selected and auto_calibration entries; a ranking table
# Dependencies: parallel (base R); data.table
# ============================================================ #

#' Compare model structures
#'
#' Calibrates several model structures in exactly the same way and ranks them by their
#' headline score on the validation window, which no calibration saw. Each structure is
#' logged as an ordinary `structure_selected` entry and an `auto_calibration` entry, linked
#' by a shared comparison id, so the comparison is part of the audit trail and
#' `structure_comparison()` can rebuild the ranking from the log at any time.
#'
#' Every structure gets the bounds from [calibration_bounds()] for its components, with
#' log-scale search where the table says so, and the same objective, starts, seed and
#' iteration limit. A structure with more parameters nearly always fits the calibration
#' window better; the ranking uses the validation window instead, and the table shows how
#' much each structure's score changes between the two. A large drop is the mark of a
#' structure buying its fit with parameters.
#'
#' With `cross_validate = TRUE`, each structure is also calibrated on the validation window
#' and scored on the calibration window, and ranked on the mean of the two held-out scores.
#' This is more robust for short records, and doubles the cost.
#'
#' Choosing a structure on the validation window uses that window; the optional test window
#' of [register_data()], scored once by [test_candidate()], then gives an untouched final
#' check.
#'
#' @param project Path of a calibration project with registered data and a validation window.
#' @param structures Named list of configurations; by default [structure_set()], built on the
#'   project's latest structure if there is one. Each is given the project's area.
#' @param overrides,exclude Passed to [calibration_bounds()] for every structure.
#' @param objective,starts,seed,control,method Passed to [calibrate_pdm()].
#' @param cores Number of parallel worker processes; 1 runs in this session.
#' @param cross_validate If `TRUE`, also calibrate on the validation window and score on the
#'   calibration window.
#' @param reasoning Why the comparison is being run.
#' @return `compare_structures()` and `structure_comparison()`: a data.table ranked best
#'   first, with `rank`, `structure`, `parameters`, `calibration` and `validation` (headline
#'   scores), `change` (validation minus calibration), `cross_validated` when requested,
#'   `evaluations`, `starts_agree`, and the two entry ids.
#' @seealso [structure_set()], [calibration_bounds()], [calibration_log]
#' @export
compare_structures <- function(project, structures = NULL, overrides = NULL, exclude = NULL,
                               objective = c("nse", "rmse", "log_rmse"), starts = 3L,
                               seed = 1, control = list(maxit = 200),
                               method = c("lbfgsb", "nelder_mead"), cores = 1L,
                               cross_validate = FALSE, reasoning) {
  author <- .identity("custodian")
  objective <- match.arg(objective)
  method <- match.arg(method)
  reasoning <- .require_text(reasoning, "reasoning")
  .check(.scalar(cores, 1) && cores == floor(cores), "cores must be a whole number of at least 1")
  path <- .project_path(project)
  entries <- .read_entries(path)
  info <- .project_info(entries)
  registration <- .registration(entries)
  card <- registration$scorecard
  .check(!is.null(card$validation), "Structures are ranked on the validation window; register one")
  structures <- .comparison_structures(structures, entries, info$area_km2)
  data <- .load_registration(path, registration)
  settings <- list(objective = objective, starts = as.integer(starts), seed = seed,
                   control = control, method = method, overrides = overrides,
                   exclude = exclude, cross_validate = isTRUE(cross_validate))
  jobs <- lapply(names(structures), function(n) list(name = n, config = structures[[n]]))
  fits <- .run_jobs(jobs, .fit_structure, cores, data = data, card = card, info = info,
                    registration = registration, settings = settings)
  comparison <- paste0("comparison-", format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"))
  for (f in fits) .write_structure_fit(path, author, registration, f, comparison, settings,
                                       reasoning)
  logger::log_info("Compared {length(fits)} structures as {comparison}")
  structure_comparison(path, comparison)
}

# Defaults to the standard set built on the project's latest structure; every structure
# takes the project's area.
.comparison_structures <- function(structures, entries, area) {
  if (is.null(structures)) {
    latest <- .latest(entries, "structure_selected")
    base <- if (is.null(latest)) pdm_presets("standard") else latest$configuration
    structures <- structure_set(base = base)
  }
  .check(is.list(structures) && length(structures) > 0 && !is.null(names(structures)) &&
           all(nzchar(names(structures))) && !anyDuplicated(names(structures)),
         "structures must be a named list of configurations")
  lapply(structures, function(cfg) {
    cfg$area_km2 <- area
    pdm_from_config(cfg)
    cfg
  })
}

.run_jobs <- function(jobs, fun, cores, ...) {
  if (cores <= 1L || length(jobs) < 2L) return(lapply(jobs, fun, ...))
  cl <- parallel::makeCluster(min(cores, length(jobs)))
  on.exit(parallel::stopCluster(cl), add = TRUE)
  parallel::clusterEvalQ(cl, {
    library(pdmS7)
    NULL
  })
  parallel::parLapply(cl, jobs, fun, ...)
}

# Fits one structure; runs in a worker, so it writes nothing.
.fit_structure <- function(job, data, card, info, registration, settings) {
  config <- job$config
  bounds <- calibration_bounds(config, settings$overrides, settings$exclude)
  lower <- stats::setNames(bounds$lower, bounds$path)
  upper <- stats::setNames(bounds$upper, bounds$path)
  for (p in bounds$path) {
    config <- .path_set(config, p, min(max(.path_get(config, p), lower[[p]]), upper[[p]]))
  }
  log_scale <- bounds$path[bounds$scale == "log"]
  fit_on <- function(window) {
    w <- card[[window]]
    observed <- data$observed
    observed[-.window_rows(w)] <- NA
    calibrate_pdm(
      config, data$forcing[seq_len(w$last_row)], observed[seq_len(w$last_row)],
      lower = lower, upper = upper, warmup = w$first_row - 1L, objective = settings$objective,
      log_offset = card$log_offset, control = settings$control,
      soil_fraction = card$soil_fraction, starts = settings$starts, seed = settings$seed,
      method = settings$method, log_scale = log_scale
    )
  }
  initial <- .run_registered(NULL, info, registration, config, data = data)
  fit <- fit_on("calibration")
  calibrated <- .run_registered(NULL, info, registration, fit$config, data = data)
  validated <- .run_registered(NULL, info, registration, fit$config, "validation", data)
  reverse <- NULL
  if (settings$cross_validate) {
    back <- fit_on("validation")
    reverse <- .run_registered(NULL, info, registration, back$config, "calibration",
                               data)$scores
  }
  list(name = job$name, config = config, bounds = bounds, log_scale = log_scale,
       initial = initial[c("scores", "output_md5")], fit = fit,
       calibrated = calibrated[c("scores", "output_md5")],
       validation_scores = validated$scores, reverse_scores = reverse)
}

.write_structure_fit <- function(path, author, registration, f, comparison, settings,
                                 reasoning) {
  structure <- .append_entry(path, "structure_selected", author, function(id, entries) {
    list(registration = registration$id, configuration = f$config, scores = f$initial$scores,
         output_md5 = f$initial$output_md5, comparison = comparison, structure_name = f$name,
         reasoning = paste0("Structure comparison (", f$name, "): ", reasoning))
  })
  .append_entry(path, "auto_calibration", author, function(id, entries) {
    list(registration = registration$id, parent = structure$id,
         bounds = list(lower = as.list(stats::setNames(f$bounds$lower, f$bounds$path)),
                       upper = as.list(stats::setNames(f$bounds$upper, f$bounds$path))),
         objective = settings$objective, objective_name = f$fit$objective_name,
         method = settings$method, evaluations = sum(f$fit$start_results$evaluations),
         log_scale = if (length(f$log_scale)) as.list(f$log_scale),
         starts = settings$starts, seed = settings$seed, control = settings$control,
         start_results = as.list(f$fit$start_results), configuration = f$fit$config,
         scores = f$calibrated$scores, output_md5 = f$calibrated$output_md5,
         comparison = comparison, structure_name = f$name,
         comparison_validation_scores = f$validation_scores,
         cross_validation_scores = f$reverse_scores,
         reasoning = paste0("Structure comparison (", f$name, "): ", reasoning))
  })
}

#' @rdname compare_structures
#' @param comparison A comparison id; by default the latest comparison in the project.
#' @export
structure_comparison <- function(project, comparison = NULL) {
  entries <- .read_entries(.project_path(project))
  fits <- Filter(function(e) e$type == "auto_calibration" && !is.null(e$comparison), entries)
  .check(length(fits) > 0, "This project has no structure comparison")
  ids <- unique(vapply(fits, function(e) e$comparison, character(1)))
  if (is.null(comparison)) comparison <- ids[length(ids)]
  .check(comparison %in% ids, paste("No comparison", comparison))
  fits <- Filter(function(e) identical(e$comparison, comparison), fits)
  headline <- .find_entry(entries, fits[[1L]]$registration)$scorecard$headline
  rows <- lapply(fits, function(e) {
    starts <- unlist(e$start_results$objective)
    cal <- .num_or_na(e$scores[[headline]])
    val <- .num_or_na(e$comparison_validation_scores[[headline]])
    rev <- .num_or_na(e$cross_validation_scores[[headline]])
    data.table::data.table(
      structure = e$structure_name, parameters = length(e$bounds$lower),
      calibration = cal, validation = val, change = val - cal,
      cross_validated = if (is.null(e$cross_validation_scores)) NA_real_ else (val + rev) / 2,
      evaluations = as.integer(e$evaluations),
      starts_agree = (max(starts) - min(starts)) < 1e-3 * max(1, abs(min(starts))),
      structure_entry = e$parent, calibration_entry = e$id
    )
  })
  table <- data.table::rbindlist(rows)
  key <- if (all(is.na(table$cross_validated))) table$validation else table$cross_validated
  better_low <- .headline_direction(headline) == "lower"
  table <- table[order(if (better_low) key else -key, na.last = TRUE)]
  if (all(is.na(table$cross_validated))) data.table::set(table, j = "cross_validated", value = NULL)
  table <- cbind(data.table::data.table(rank = seq_len(nrow(table))), table)
  data.table::setattr(table, "comparison", comparison)
  data.table::setattr(table, "headline", headline)
  table
}
