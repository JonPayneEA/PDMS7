# ============================================================ #
# Tool:         project_entries
# Description:  Calibration log: the eleven entry types
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration log
# Tier:         3
# Inputs:       A calibration project folder; declared user and role
# Outputs:      Append-only YAML entries; invisible entry lists
# Dependencies: yaml; data.table
# ============================================================ #

#' Calibration log
#'
#' A calibration project is a folder holding an append-only, tamper-evident record of a
#' calibration: who did what, when, with which data and parameters, and why. Each function
#' below writes one entry; none edits or deletes an earlier one.
#'
#' | Function | Entry | Role |
#' |---|---|---|
#' | `start_calibration_project()` | `project_start` | Custodian |
#' | `register_data()` | `data_registered` | Custodian |
#' | `select_structure()` | `structure_selected` | Custodian |
#' | `log_trial()` | `trial` | Custodian |
#' | `log_auto_calibration()` | `auto_calibration` | Custodian |
#' | `log_note()` | `note` | Any |
#' | `propose_candidate()` | `candidate` | Custodian |
#' | `validate_candidate()` | `validation` | Custodian |
#' | `test_candidate()` | `test` | Custodian |
#' | `sign_off_project()` | `sign_off` | Steward or Delegated Steward |
#' | `reopen_project()` | `reopen` | Steward or Delegated Steward |
#'
#' Declare who you are once per session, with
#' `options(pdmS7.user = "Your Name", pdmS7.role = "custodian")`, or with the environment
#' variables `PDMS7_USER` and `PDMS7_ROLE`. Every entry records the name, the role and the
#' operating-system login. A Steward cannot sign off a project in which they wrote a trial,
#' automatic calibration, candidate or validation.
#'
#' Every run simulates the whole registered record, starting in steady state at the first
#' observed flow (`start = "flow"`, the default), or from `initial_state(model, soil_fraction)`
#' with `start = "soil"`. Projects registered before version 0.4.1 keep the soil start.
#' Trials and automatic calibrations are scored on the calibration window only; the
#' validation window is scored once, by `validate_candidate()`, and an optional test window
#' once more, by `test_candidate()`, after every choice is made. See
#' [pdm_scorecard()] for the scores and [verify_project()] for the integrity checks.
#'
#' **Extrapolation.** By default the two wettest water years in the calibration and
#' validation windows (see [wettest_years()]) are held back: no calibration, trial or
#' validation scores them, and `test_candidate()` scores them once, with the test window,
#' as a check on floods larger than those the model was fitted to. Each automatic calibration
#' keeps the parameter sets it tried that score within `tie_tolerance` of its best, up to 50
#' spread-out sets, and the test reports the range of their peaks in each held year. Where
#' `highest_gauged_m3s` is given, flows above it are counted window by window at
#' registration and flagged in the test: above that flow the rating is extrapolated, so the
#' observed peak is uncertain. Projects registered before version 0.5.0 hold nothing back.
#'
#' @param project Path of the project folder.
#' @param path Folder to create for a new project; it must not exist or must be empty.
#' @param catchment,gauge,purpose Catchment name, gauge identifier (for example an NRFA
#'   station number) and the purpose of the calibration.
#' @param area_km2 Catchment area, km2. Every configuration must use it.
#' @param owner,steward Names of the accountable Owner and the Steward expected to sign off.
#' @param description Optional free text.
#' @param id Project identifier; defaults to the folder name.
#' @param forcing Path of a CSV file, or a data frame, with `rain` and `pet` in mm per
#'   interval and an optional `time` column.
#' @param observed Path of a CSV file with a `q_m3s` column, a data frame, or a numeric
#'   vector of observed flow, m3/s, aligned with `forcing`. Missing values are allowed.
#' @param calibration,validation,test Scoring windows as `c(start, end)`: row numbers, or
#'   times when the forcing has a time column. Rows before the calibration window are
#'   warm-up. `validation` may be `NULL` until it is needed. `test` is an optional final
#'   window, scored once by `test_candidate()` after every choice is made, and by nothing
#'   else; the three windows must not overlap.
#' @param headline Score used to rank runs: one of `nse`, `log_nse`, `kge`, `rmse`,
#'   `log_rmse`, `abs_volume_error`, or a threshold score written as `metric:name`, such as
#'   `csi:Flood Warning`, where metric is `pod`, `far`, `csi`, `pod_step`, `far_step`,
#'   `csi_step`, `ets_step` or `pss_step`.
#' @param thresholds Optional data frame of thresholds with columns `name`, `value` and
#'   `unit`: `flow` (m3/s) or `level` (m, converted to flow through `rating`). Every run is
#'   then also scored with [pdm_threshold_scores()], under names such as `csi:Flood Warning`.
#' @param rating Rating table for level thresholds: a CSV path or data frame with `stage_m`
#'   and `q_m3s`. Levels outside it are refused, not extrapolated. Stored like the data.
#' @param event_tolerance_h,event_gap_h,event_min_duration_h Event matching settings in
#'   hours; see [pdm_threshold_scores()].
#' @param log_offset Offset added before logarithms, m3/s.
#' @param soil_fraction Initial soil store as a fraction of capacity, used with
#'   `start = "soil"` and with split recharge.
#' @param start,baseflow_fraction How every run in the project starts; see [calibrate_pdm()].
#' @param highest_gauged_m3s Optional highest flow ever gauged at the station, m3/s: the top
#'   of the reliable rating. Flows above it are flagged, not changed.
#' @param wettest_years Number of the wettest water years to hold back, by default 2. Needs a
#'   `time` column in `forcing` and enough record to leave three years; 0 holds none back.
#' @param tie_tolerance Parameter sets whose calibration headline score lies within this of
#'   the best count as equally good, in the headline's own units (0.02 for NSE).
#' @param copy If `TRUE`, files are copied into the project; if `FALSE` they are referenced
#'   by path and MD5. Data frames and vectors are always written into the project.
#' @param reasoning,statement,reason,text Free text explaining the entry.
#' @param configuration A configuration list or the path of a YAML configuration file.
#' @param parent Id of the structure, trial or automatic calibration entry to start from.
#' @param changes Named numeric vector of new values, named by configuration path such as
#'   `surface.k1` or `fc`.
#' @param verdict Your judgement of the trial: `better`, `worse` or `inconclusive`.
#' @param lower,upper,objective,starts,seed,control,method,log_scale,volume_weight Passed to
#'   [calibrate_pdm()].
#' @param event_weights,event_share,event_screen Passed to [calibrate_pdm()] with
#'   `objective = "events"`. In a project, the screen takes the registered highest gauged flow
#'   unless it names its own.
#' @param stage Optional label recorded with an automatic calibration, such as
#'   `1 of 3: volume and baseflow`; [log_staged_calibration()] sets it.
#' @param threshold_objective Optional names of registered thresholds to include in the
#'   objective of an automatic calibration, with `method = "nelder_mead"` or `"dds"`. Their
#'   flows and the registered event settings are used, so the calibration and the scorecard
#'   agree.
#' @param threshold_weight,threshold_score Weight and score of the threshold term; see
#'   [calibrate_pdm()].
#' @param refers_to Optional id of the entry a note concerns.
#' @param entry Id of the structure, trial or automatic calibration proposed as candidate.
#' @param checklist Named logical vector confirming the Steward reviewed `integrity`,
#'   `data`, `calibration_path` and `validation`; all must be `TRUE`.
#' @return The new entry as a list, invisibly. `preview_trial()` writes nothing and returns
#'   the configuration, scores and series of the proposed trial.
#' @examples
#' folder <- file.path(tempdir(), "example-project")
#' old <- options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
#' start_calibration_project(folder, catchment = "Example", gauge = "00000",
#'   purpose = "Illustration", area_km2 = 50, owner = "Deputy Director",
#'   steward = "A Steward")
#' set.seed(1)
#' forcing <- data.frame(rain = ifelse(runif(500) < 0.1, rexp(500, 0.3), 0), pet = 0.1)
#' truth <- pdm_presets("standard")
#' truth$area_km2 <- 50
#' observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s
#' register_data(folder, forcing, observed, calibration = c(101, 350),
#'   validation = c(351, 500), wettest_years = 0)
#' select_structure(folder, truth, reasoning = "Standard structure as a starting point")
#' log_trial(folder, parent = 3, changes = c(surface.k1 = 3), verdict = "worse",
#'   reasoning = "Testing a slower first store")
#' project_trials(folder)
#' options(old)
#' unlink(folder, recursive = TRUE)
#' @name calibration_log
NULL

# Reasoning, statements and reasons must be real text: the log exists to record why.
.require_text <- function(x, name) {
  .check(is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x)),
         paste(name, "must be a non-empty explanation"))
  trimws(x)
}

# The project's fixed details (catchment, area, Owner, Steward) from its first entry.
.project_info <- function(entries) .latest(entries, "project_start")$project

# The data registration in force: the latest data_registered entry.
.registration <- function(entries) {
  out <- .latest(entries, "data_registered")
  .check(!is.null(out), "Register data first with register_data()")
  out
}

# An entry that carries a configuration (structure, trial or automatic calibration), the only
# kinds a trial may start from or a candidate may name.
.model_node <- function(entries, id) {
  node <- .find_entry(entries, id)
  .check(node$type %in% .model_entry_types,
         paste("Entry", node$id, "is a", node$type, "; choose a structure, trial or calibration"))
  node
}

# A configuration given as a list or a YAML path, checked by building it once.
.read_configuration <- function(configuration) {
  if (is.character(configuration)) configuration <- read_pdm_config(configuration)
  .check(is.list(configuration), "configuration must be a list or a YAML file path")
  pdm_from_config(configuration)
  configuration
}

.valid_changes <- function(changes) {
  if (!is.numeric(changes) || !length(changes) || is.null(names(changes))) return(FALSE)
  all(is.finite(changes), nzchar(names(changes)), !duplicated(names(changes)))
}

# Applies a trial's parameter changes and records each as from and to, for the report.
.apply_changes <- function(config, changes) {
  .check(.valid_changes(changes), "changes must be a named finite numeric vector")
  record <- list()
  for (name in names(changes)) {
    old <- .path_get(config, name)
    .check(is.numeric(old) && length(old) == 1L, paste(name, "is not a numeric parameter"))
    config <- .path_set(config, name, unname(changes[[name]]))
    record[[name]] <- list(from = as.numeric(old), to = unname(changes[[name]]))
  }
  list(config = config, record = record)
}

# Flows of the named registered thresholds, for a threshold objective.
.registered_flows <- function(card, names) {
  if (is.null(names)) return(NULL)
  known <- vapply(card$thresholds, function(t) t$name, character(1))
  .check(length(known) > 0, "No thresholds are registered; add them with register_data()")
  .check(is.character(names) && all(names %in% known),
         paste("Unknown threshold; registered thresholds are", paste(known, collapse = ", ")))
  stats::setNames(vapply(card$thresholds[match(names, known)], function(t) t$flow_m3s,
                         numeric(1)), names)
}

# A short "nse 0.8712" text for log messages.
.headline_text <- function(registration, scores) {
  name <- registration$scorecard$headline
  sprintf("%s %.4g", name, scores[[name]])
}

#' @rdname calibration_log
#' @export
start_calibration_project <- function(path, catchment, gauge, purpose, area_km2, owner,
                                      steward, description = "", id = basename(path)) {
  author <- .identity("custodian")
  .check(is.character(path) && length(path) == 1L && !is.na(path), "path must be a folder")
  .check(!file.exists(path) || length(list.files(path, all.files = TRUE, no.. = TRUE)) == 0L,
         paste("Folder exists and is not empty:", path))
  .check(.scalar(area_km2, 0, strict = TRUE), "area_km2 must be positive")
  fields <- list(
    id = .require_text(id, "id"), catchment = .require_text(catchment, "catchment"),
    gauge = .require_text(as.character(gauge), "gauge"),
    purpose = .require_text(purpose, "purpose"), area_km2 = as.numeric(area_km2),
    owner = .require_text(owner, "owner"), steward = .require_text(steward, "steward"),
    description = as.character(description)
  )
  # The marker file identifies the folder as a project; entries then go under entries/.
  dir.create(file.path(path, "entries"), recursive = TRUE, showWarnings = FALSE)
  marker <- yaml::as.yaml(list(format = .log_format, project = fields$id, created = .timestamp()))
  writeBin(charToRaw(enc2utf8(paste0("# pdmS7 calibration project\n", marker))),
           file.path(path, .marker))
  entry <- .append_entry(.project_path(path), "project_start", author,
                         function(id, entries) list(project = fields))
  logger::log_info("Started calibration project {fields$id} in {path}")
  invisible(entry)
}

#' @rdname calibration_log
#' @export
register_data <- function(project, forcing, observed, calibration, validation = NULL,
                          headline = "nse", log_offset = 0.01, soil_fraction = 0.5,
                          start = c("flow", "soil"), baseflow_fraction = 0.7,
                          copy = TRUE, reasoning = "", thresholds = NULL, rating = NULL,
                          event_tolerance_h = 6, event_gap_h = 24, event_min_duration_h = 0,
                          test = NULL, highest_gauged_m3s = NULL, wettest_years = 2,
                          tie_tolerance = 0.02) {
  author <- .identity("custodian")
  path <- .project_path(project)
  forcing_data <- .as_forcing(forcing)
  observed_data <- .as_observed(observed)
  .check(length(observed_data) == nrow(forcing_data), "observed must align with forcing rows")
  rating_data <- if (is.null(rating)) NULL else .as_rating(rating)
  levels <- .resolve_thresholds(thresholds, rating_data)
  for (v in list(event_tolerance_h, event_gap_h, event_min_duration_h)) {
    .check(.scalar(v, 0), "Event settings must be nonnegative hours")
  }
  .check(.valid_headline(headline, levels), paste(
    "headline must be one of", paste(names(.headline_scores()), collapse = ", "),
    "or a threshold score such as csi:<threshold name>"
  ))
  .check(.scalar(log_offset, 0, strict = TRUE), "log_offset must be positive")
  .check(.scalar(soil_fraction, 0, 1), "soil_fraction must lie between 0 and 1")
  start <- match.arg(start)
  .check(.scalar(baseflow_fraction, 0, 1), "baseflow_fraction must lie between 0 and 1")
  .check(isTRUE(copy) || isFALSE(copy), "copy must be TRUE or FALSE")
  .check(is.null(highest_gauged_m3s) || .scalar(highest_gauged_m3s, 0, strict = TRUE),
         "highest_gauged_m3s must be a positive flow, or NULL")
  .check(.scalar(wettest_years, 0) && wettest_years == floor(wettest_years),
         "wettest_years must be a whole number, 0 or more")
  .check(.scalar(tie_tolerance, 0), "tie_tolerance must be a nonnegative number")
  if (!is.null(highest_gauged_m3s)) highest_gauged_m3s <- as.numeric(highest_gauged_m3s)
  # Windows may be given as rows or times; they must not overlap, and each needs observed flow.
  cal <- .resolve_window(calibration, forcing_data, "calibration")
  val <- .resolve_window(validation, forcing_data, "validation")
  tst <- .resolve_window(test, forcing_data, "test")
  .check_no_overlap(list(calibration = cal, validation = val, test = tst))
  for (w in list(cal, val, tst)) {
    if (!is.null(w)) {
      .check(sum(is.finite(observed_data[.window_rows(w)])) >= 2,
             "Each window needs at least two observed values")
    }
  }
  # The held years are chosen once, here, from the observed flow, and recorded; later runs
  # read them from the scorecard rather than choosing again.
  wettest <- .choose_wettest(wettest_years, forcing_data, observed_data, cal, val)
  summary <- .data_summary(forcing_data, observed_data)
  # What preparation functions noted on the series (units, gaps, negatives), for the log.
  preparation <- .registration_notes(forcing, observed)
  # Files are stored under the lock, in a folder named by the entry id, and the scorecard (windows,
  # headline, thresholds, event settings) is fixed here for every later run in the project.
  entry <- .append_entry(path, "data_registered", author, function(id, entries) {
    .check(!is.null(.project_info(entries)), "This project has no project_start entry")
    data <- list(
      forcing = .store_series(forcing, forcing_data, path, id, "forcing", copy, .write_forcing),
      observed = .store_series(observed, observed_data, path, id, "observed", copy,
                               .write_observed)
    )
    if (!is.null(rating_data)) {
      data$rating <- .store_series(rating, rating_data, path, id, "rating", copy,
                                   function(x, target) data.table::fwrite(x, target))
    }
    body <- list(
      data = data, summary = summary,
      scorecard = list(
        warmup_rows = cal$first_row - 1L, calibration = cal, validation = val, test = tst,
        metrics = names(pdm_scorecard(c(1, 2), c(1, 2))), headline = headline,
        log_offset = log_offset, soil_fraction = soil_fraction, start = start,
        baseflow_fraction = baseflow_fraction, thresholds = levels,
        events = list(tolerance_h = event_tolerance_h, gap_h = event_gap_h,
                      min_duration_h = event_min_duration_h),
        wettest = wettest, highest_gauged_m3s = highest_gauged_m3s,
        tie_tolerance = tie_tolerance
      ),
      rating_check = .rating_check(highest_gauged_m3s, observed_data,
                                   list(calibration = cal, validation = val, test = tst,
                                        wettest = wettest)),
      reasoning = as.character(reasoning)
    )
    if (length(preparation)) body$preparation <- preparation
    body
  })
  logger::log_info("Registered data {entry$id}: {summary$rows} rows")
  invisible(entry)
}

#' @rdname calibration_log
#' @export
select_structure <- function(project, configuration, reasoning) {
  author <- .identity("custodian")
  path <- .project_path(project)
  config <- .read_configuration(configuration)
  reasoning <- .require_text(reasoning, "reasoning")
  entries <- .read_entries(path)
  registration <- .registration(entries)
  run <- .run_registered(path, .project_info(entries), registration, config)
  entry <- .append_entry(path, "structure_selected", author, function(id, entries) {
    list(registration = registration$id, configuration = config, scores = run$scores,
         output_md5 = run$output_md5, reasoning = reasoning)
  })
  logger::log_info("Structure {entry$id}: {.headline_text(registration, run$scores)}")
  invisible(entry)
}

#' @rdname calibration_log
#' @export
preview_trial <- function(project, parent, changes) {
  path <- .project_path(project)
  entries <- .read_entries(path)
  node <- .model_node(entries, parent)
  registration <- .registration(entries)
  changed <- .apply_changes(node$configuration, changes)
  run <- .run_registered(path, .project_info(entries), registration, changed$config)
  c(list(parent = node$id, parent_scores = node$scores, configuration = changed$config,
         changes = changed$record, registration = registration$id), run)
}

#' @rdname calibration_log
#' @export
log_trial <- function(project, parent, changes, verdict, reasoning) {
  author <- .identity("custodian")
  verdict <- match.arg(verdict, c("better", "worse", "inconclusive"))
  reasoning <- .require_text(reasoning, "reasoning")
  run <- preview_trial(project, parent, changes)
  entry <- .append_entry(.project_path(project), "trial", author, function(id, entries) {
    list(registration = run$registration, parent = run$parent, changes = run$changes,
         configuration = run$configuration, scores = run$scores, output_md5 = run$output_md5,
         verdict = verdict, reasoning = reasoning)
  })
  headline <- .headline_text(.registration(.read_entries(.project_path(project))), run$scores)
  logger::log_info(paste0("Trial ", entry$id, " from ", run$parent, ": ", headline))
  invisible(entry)
}

#' @rdname calibration_log
#' @export
log_auto_calibration <- function(project, parent, lower, upper,
                                 objective = c("nse", "rmse", "log_rmse", "log_nse", "threshold",
                                               "events"),
                                 starts = 1L, seed = NULL, control = list(maxit = 200),
                                 reasoning, method = c("lbfgsb", "nelder_mead", "dds"),
                                 threshold_objective = NULL, threshold_weight = 1,
                                 threshold_score = "csi", log_scale = character(0),
                                 volume_weight = 0, stage = NULL,
                                 event_weights = c(nse = 1, peak = 0.5, timing = 0.5),
                                 event_share = 0.5, event_screen = list()) {
  author <- .identity("custodian")
  objective <- match.arg(objective)
  method <- match.arg(method)
  reasoning <- .require_text(reasoning, "reasoning")
  path <- .project_path(project)
  entries <- .read_entries(path)
  node <- .model_node(entries, parent)
  registration <- .registration(entries)
  card <- registration$scorecard
  data <- .load_registration(path, registration)
  last <- card$calibration$last_row
  flows <- .registered_flows(card, threshold_objective)
  # Held-back years are blanked, so the search never sees them. When years are held back, every
  # trial's headline score is archived, and the equally good sets are drawn from that archive.
  observed <- .scoring_observed(data$observed, card, "calibration")
  rows <- .scored_rows(card, "calibration")
  dt <- pdm_from_config(node$configuration)@dt
  archive <- if (length(.held_years(card))) {
    function(sim) .headline_score(sim[rows], data$observed[rows], card, dt)
  }
  fit <- calibrate_pdm(
    node$configuration, data$forcing[seq_len(last)], observed[seq_len(last)],
    lower = lower, upper = upper, warmup = card$calibration$first_row - 1L,
    objective = objective, log_offset = card$log_offset, control = control,
    soil_fraction = card$soil_fraction, start = card$start %||% "soil",
    baseflow_fraction = card$baseflow_fraction %||% 0.7,
    start_flow = .first_observed(data$observed), starts = starts, seed = seed, method = method,
    thresholds = flows, threshold_weight = threshold_weight, threshold_score = threshold_score,
    event_settings = card$events, log_scale = log_scale, volume_weight = volume_weight,
    archive = archive, event_weights = event_weights, event_share = event_share,
    event_screen = .project_screen(event_screen, card)
  )
  good <- if (!is.null(archive)) {
    .equally_good(fit$trials, attr(fit$trials, "unit"), .headline_direction(card$headline),
                  card$tie_tolerance %||% 0.02)
  }
  run <- .run_registered(path, .project_info(entries), registration, fit$config, data = data)
  entry <- .append_entry(path, "auto_calibration", author, function(id, entries) {
    list(registration = registration$id, parent = node$id,
         bounds = list(lower = as.list(lower), upper = as.list(upper)),
         objective = objective, objective_name = fit$objective_name, method = method,
         threshold_objective = threshold_objective,
         threshold_weight = if (is.null(flows)) NULL else threshold_weight,
         threshold_score = if (is.null(flows)) NULL else threshold_score,
         evaluations = sum(fit$start_results$evaluations),
         log_scale = if (length(log_scale)) as.list(log_scale),
         volume_weight = if (volume_weight > 0) volume_weight, stage = stage,
         event_weights = if (objective == "events") as.list(event_weights),
         event_share = if (objective == "events") event_share,
         event_screen = if (objective == "events") .project_screen(event_screen, card),
         starts = as.integer(starts), seed = seed,
         control = control, start_results = as.list(fit$start_results),
         configuration = fit$config, scores = run$scores, output_md5 = run$output_md5,
         equally_good = good, reasoning = reasoning)
  })
  logger::log_info("Calibration {entry$id}: {.headline_text(registration, run$scores)}")
  invisible(entry)
}

#' @rdname calibration_log
#' @export
log_note <- function(project, text, refers_to = NULL) {
  author <- .identity()
  text <- .require_text(text, "text")
  entry <- .append_entry(.project_path(project), "note", author, function(id, entries) {
    if (!is.null(refers_to)) refers_to <- .find_entry(entries, refers_to)$id
    list(text = text, refers_to = refers_to)
  })
  invisible(entry)
}

#' @rdname calibration_log
#' @export
propose_candidate <- function(project, entry, reasoning) {
  author <- .identity("custodian")
  reasoning <- .require_text(reasoning, "reasoning")
  path <- .project_path(project)
  entries <- .read_entries(path)
  node <- .model_node(entries, entry)
  registration <- .find_entry(entries, node$registration)
  run <- .run_registered(path, .project_info(entries), registration, node$configuration)
  .check(identical(run$output_md5, node$output_md5), paste(
    "Entry", node$id, "no longer reproduces its recorded output; run verify_project(rerun =",
    "TRUE) to see what changed"
  ))
  out <- .append_entry(path, "candidate", author, function(id, entries) {
    list(entry = node$id, registration = registration$id, configuration = node$configuration,
         scores = run$scores, series = .save_series(path, id, run), reasoning = reasoning)
  })
  invisible(out)
}

#' @rdname calibration_log
#' @export
validate_candidate <- function(project, reasoning) {
  author <- .identity("custodian")
  reasoning <- .require_text(reasoning, "reasoning")
  path <- .project_path(project)
  entries <- .read_entries(path)
  candidate <- .latest(entries, "candidate")
  .check(!is.null(candidate), "Propose a candidate first with propose_candidate()")
  registration <- .find_entry(entries, candidate$registration)
  .check(!is.null(registration$scorecard$validation),
         "The registration has no validation window; register data with one")
  data <- .load_registration(path, registration)
  info <- .project_info(entries)
  run <- .run_registered(path, info, registration, candidate$configuration, "validation", data)
  out <- .append_entry(path, "validation", author, function(id, entries) {
    # Checked again under the lock: a candidate proposed by another session while this one was
    # running would otherwise be skipped, and this validation recorded against the older one.
    .check(identical(.latest(entries, "candidate")$id, candidate$id),
           "A newer candidate was proposed while validating; run validate_candidate() again")
    list(candidate = candidate$id, registration = registration$id,
         validation_scores = run$scores, calibration_scores = candidate$scores,
         output_md5 = run$output_md5, series = .save_series(path, id, run),
         reasoning = reasoning)
  })
  logger::log_info("Validation {out$id}: {.headline_text(registration, run$scores)}")
  invisible(out)
}

#' @rdname calibration_log
#' @export
test_candidate <- function(project, reasoning) {
  author <- .identity("custodian")
  reasoning <- .require_text(reasoning, "reasoning")
  path <- .project_path(project)
  entries <- .read_entries(path)
  candidate <- .latest(entries, "candidate")
  validation <- .latest(entries, "validation")
  .check(!is.null(candidate) && !is.null(validation) &&
           identical(validation$candidate, candidate$id),
         "Validate the latest candidate before testing it")
  registration <- .find_entry(entries, candidate$registration)
  card <- registration$scorecard
  .check(.has_test(card),
         "The registration has no test window or held-back years; nothing to test")
  .check(is.null(.candidate_test(entries, candidate)),
         "This candidate has already been tested; the test window is scored once")
  # Checked again under the lock below, so two sessions cannot both score the test window.
  # The held-back wettest years are revealed here too, with the spread of the equally good
  # parameter sets across their peaks.
  info <- .project_info(entries)
  data <- .load_registration(path, registration)
  run <- if (!is.null(card$test)) {
    .run_registered(path, info, registration, candidate$configuration, "test", data)
  }
  wettest <- if (length(.held_years(card))) {
    .score_wettest(info, registration, candidate, entries, data)
  }
  series_run <- run %||% wettest$run
  out <- .append_entry(path, "test", author, function(id, entries) {
    .check(is.null(.candidate_test(entries, candidate)),
           "This candidate has already been tested; the test window is scored once")
    list(candidate = candidate$id, validation = validation$id, registration = registration$id,
         test_scores = run$scores, validation_scores = validation$validation_scores,
         calibration_scores = candidate$scores,
         wettest = if (!is.null(wettest)) wettest[c("scores", "sets", "tolerance", "years")],
         output_md5 = series_run$output_md5, series = .save_series(path, id, series_run),
         reasoning = reasoning)
  })
  if (!is.null(run)) {
    logger::log_info("Test {out$id}: {.headline_text(registration, run$scores)}")
  }
  if (!is.null(wettest)) {
    logger::log_info("Wettest years {out$id}: {.headline_text(registration, wettest$scores)}")
  }
  invisible(out)
}

# Whether a registration has anything for test_candidate() to score.
.has_test <- function(card) !is.null(card$test) || length(.held_years(card)) > 0L

# The test entry for a candidate, if it has been tested.
.candidate_test <- function(entries, candidate) {
  if (is.null(candidate)) return(NULL)
  hits <- Filter(function(e) e$type == "test" && identical(e$candidate, candidate$id), entries)
  if (length(hits)) hits[[length(hits)]] else NULL
}

# Calibration, validation and test windows must be disjoint, pairwise.
.check_no_overlap <- function(windows) {
  windows <- Filter(Negate(is.null), windows)
  if (length(windows) < 2L) return(invisible(TRUE))
  pairs <- utils::combn(names(windows), 2L)
  for (k in seq_len(ncol(pairs))) {
    a <- windows[[pairs[1L, k]]]
    b <- windows[[pairs[2L, k]]]
    .check(a$last_row < b$first_row || b$last_row < a$first_row,
           paste(pairs[2L, k], "must not overlap", pairs[1L, k]))
  }
  invisible(TRUE)
}

# Two authors are the same person if either their declared names or their logins match, ignoring
# case and surrounding spaces. Matching on either defeats signing off under a different name.
.same_person <- function(a, b) {
  clean <- function(x) tolower(trimws(as.character(x)))
  identical(clean(a$name), clean(b$name)) || identical(clean(a$login), clean(b$login))
}

#' @rdname calibration_log
#' @export
sign_off_project <- function(project, statement,
                             checklist = c(integrity = FALSE, data = FALSE,
                                           calibration_path = FALSE, validation = FALSE)) {
  author <- .identity(c("steward", "delegated_steward"))
  statement <- .require_text(statement, "statement")
  needed <- c("integrity", "data", "calibration_path", "validation")
  .check(is.logical(checklist) && all(needed %in% names(checklist)) &&
           all(checklist[needed] %in% TRUE),
         paste("Confirm you reviewed", paste(needed, collapse = ", "), "in checklist"))
  # Integrity is checked first, outside the lock (it reads every file); the conditions that
  # depend on the latest entries are checked again inside it.
  path <- .project_path(project)
  checks <- verify_project(path)
  .check(all(checks$ok), "Integrity checks fail; see verify_project() before signing off")
  entry <- .append_entry(path, "sign_off", author, function(id, entries) {
    candidate <- .latest(entries, "candidate")
    validation <- .latest(entries, "validation")
    .check(!is.null(candidate) && !is.null(validation) &&
             identical(validation$candidate, candidate$id),
           "The latest candidate has not been validated")
    test <- .candidate_test(entries, candidate)
    registration <- .find_entry(entries, candidate$registration)
    .check(!.has_test(registration$scorecard) || !is.null(test), paste(
      "A test window or held-back years are registered; run test_candidate() before signing",
      "off"
    ))
    worker_types <- c("trial", "auto_calibration", "candidate", "validation", "test")
    workers <- Filter(function(e) e$type %in% worker_types, entries)
    .check(!any(vapply(workers, function(e) .same_person(e$author, author), logical(1))),
           "You wrote calibration entries in this project; another Steward must sign off")
    list(candidate = candidate$id, validation = validation$id, test = test$id,
         configuration = candidate$configuration, capacity = author$role,
         checklist = as.list(checklist[needed]), statement = statement)
  })
  logger::log_info("Signed off {basename(path)} as entry {entry$id}")
  invisible(entry)
}

#' @rdname calibration_log
#' @export
reopen_project <- function(project, reason) {
  author <- .identity(c("steward", "delegated_steward"))
  reason <- .require_text(reason, "reason")
  entry <- .append_entry(.project_path(project), "reopen", author, function(id, entries) {
    .check(.project_status(entries) == "signed_off", "Only a signed-off project can be reopened")
    list(reason = reason)
  })
  invisible(entry)
}

# Event screening settings in a project: the registered highest gauged flow, unless the settings
# name their own. NULL (no screening) stays NULL.
.project_screen <- function(screen, card) {
  if (is.null(screen)) return(NULL)
  if (is.null(screen$highest_gauged_m3s) && !is.null(card$highest_gauged_m3s)) {
    screen$highest_gauged_m3s <- card$highest_gauged_m3s
  }
  screen
}

# Preparation notes carried by the forcing and observed series, as records for the log; NULL
# when there are none, so registrations of unprepared data are unchanged.
.registration_notes <- function(forcing, observed) {
  notes <- list()
  if (is.data.frame(forcing)) {
    notes$forcing <- preparation_notes(forcing[intersect(c("rain", "pet"), names(forcing))])
  }
  flow <- if (is.data.frame(observed)) {
    observed[[if ("q_m3s" %in% names(observed)) "q_m3s" else setdiff(names(observed), "time")[1]]]
  } else if (is.numeric(observed)) {
    observed
  }
  if (!is.null(flow)) {
    n <- preparation_notes(flow)
    n$series <- rep("flow", nrow(n))
    notes$flow <- n
  }
  all <- do.call(rbind, notes)
  if (is.null(all) || !nrow(all)) return(NULL)
  lapply(seq_len(nrow(all)), function(i) {
    list(series = all$series[i], step = all$step[i], detail = all$detail[i])
  })
}
