# ============================================================ #
# Tool:         project_entries
# Description:  Calibration log: the ten entry types
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
#' Every run simulates the whole registered record from `initial_state(model,
#' soil_fraction)`. Trials and automatic calibrations are scored on the calibration window
#' only; the validation window is scored once, by `validate_candidate()`, and an optional
#' test window once more, by `test_candidate()`, after every choice is made. See
#' [pdm_scorecard()] for the scores and [verify_project()] for the integrity checks.
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
#' @param soil_fraction Initial soil store as a fraction of capacity for every run.
#' @param copy If `TRUE`, files are copied into the project; if `FALSE` they are referenced
#'   by path and MD5. Data frames and vectors are always written into the project.
#' @param reasoning,statement,reason,text Free text explaining the entry.
#' @param configuration A configuration list or the path of a YAML configuration file.
#' @param parent Id of the structure, trial or automatic calibration entry to start from.
#' @param changes Named numeric vector of new values, named by configuration path such as
#'   `surface.k1` or `fc`.
#' @param verdict Your judgement of the trial: `better`, `worse` or `inconclusive`.
#' @param lower,upper,objective,starts,seed,control,method,log_scale Passed to
#'   [calibrate_pdm()].
#' @param threshold_objective Optional names of registered thresholds to include in the
#'   objective of an automatic calibration, with `method = "nelder_mead"`. Their flows and
#'   the registered event settings are used, so the calibration and the scorecard agree.
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
#'   validation = c(351, 500))
#' select_structure(folder, truth, reasoning = "Standard structure as a starting point")
#' log_trial(folder, parent = 3, changes = c(surface.k1 = 3), verdict = "worse",
#'   reasoning = "Testing a slower first store")
#' project_trials(folder)
#' options(old)
#' unlink(folder, recursive = TRUE)
#' @name calibration_log
NULL

.require_text <- function(x, name) {
  .check(is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x)),
         paste(name, "must be a non-empty explanation"))
  trimws(x)
}

.project_info <- function(entries) .latest(entries, "project_start")$project

.registration <- function(entries) {
  out <- .latest(entries, "data_registered")
  .check(!is.null(out), "Register data first with register_data()")
  out
}

.model_node <- function(entries, id) {
  node <- .find_entry(entries, id)
  .check(node$type %in% .model_entry_types,
         paste("Entry", node$id, "is a", node$type, "; choose a structure, trial or calibration"))
  node
}

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
                          copy = TRUE, reasoning = "", thresholds = NULL, rating = NULL,
                          event_tolerance_h = 6, event_gap_h = 24, event_min_duration_h = 0,
                          test = NULL) {
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
  .check(isTRUE(copy) || isFALSE(copy), "copy must be TRUE or FALSE")
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
  summary <- .data_summary(forcing_data, observed_data)
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
    list(
      data = data, summary = summary,
      scorecard = list(
        warmup_rows = cal$first_row - 1L, calibration = cal, validation = val, test = tst,
        metrics = names(pdm_scorecard(c(1, 2), c(1, 2))), headline = headline,
        log_offset = log_offset, soil_fraction = soil_fraction, thresholds = levels,
        events = list(tolerance_h = event_tolerance_h, gap_h = event_gap_h,
                      min_duration_h = event_min_duration_h)
      ),
      reasoning = as.character(reasoning)
    )
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
                                 objective = c("nse", "rmse", "log_rmse", "threshold"),
                                 starts = 1L, seed = NULL, control = list(maxit = 200),
                                 reasoning, method = c("lbfgsb", "nelder_mead"),
                                 threshold_objective = NULL, threshold_weight = 1,
                                 threshold_score = "csi", log_scale = character(0)) {
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
  fit <- calibrate_pdm(
    node$configuration, data$forcing[seq_len(last)], data$observed[seq_len(last)],
    lower = lower, upper = upper, warmup = card$calibration$first_row - 1L,
    objective = objective, log_offset = card$log_offset, control = control,
    soil_fraction = card$soil_fraction, starts = starts, seed = seed, method = method,
    thresholds = flows, threshold_weight = threshold_weight, threshold_score = threshold_score,
    event_settings = card$events, log_scale = log_scale
  )
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
         starts = as.integer(starts), seed = seed,
         control = control, start_results = as.list(fit$start_results),
         configuration = fit$config, scores = run$scores, output_md5 = run$output_md5,
         reasoning = reasoning)
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
  .check(!is.null(registration$scorecard$test),
         "The registration has no test window; register data with one")
  .check(is.null(.candidate_test(entries, candidate)),
         "This candidate has already been tested; the test window is scored once")
  run <- .run_registered(path, .project_info(entries), registration, candidate$configuration,
                         "test")
  out <- .append_entry(path, "test", author, function(id, entries) {
    .check(is.null(.candidate_test(entries, candidate)),
           "This candidate has already been tested; the test window is scored once")
    list(candidate = candidate$id, validation = validation$id, registration = registration$id,
         test_scores = run$scores, validation_scores = validation$validation_scores,
         calibration_scores = candidate$scores, output_md5 = run$output_md5,
         series = .save_series(path, id, run), reasoning = reasoning)
  })
  logger::log_info("Test {out$id}: {.headline_text(registration, run$scores)}")
  invisible(out)
}

.candidate_test <- function(entries, candidate) {
  if (is.null(candidate)) return(NULL)
  hits <- Filter(function(e) e$type == "test" && identical(e$candidate, candidate$id), entries)
  if (length(hits)) hits[[length(hits)]] else NULL
}

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
    .check(is.null(registration$scorecard$test) || !is.null(test),
           "A test window is registered; run test_candidate() before signing off")
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
