# ============================================================ #
# Tool:         calibrate_project
# Description:  One call from prepared data to a validated, tested candidate; the candidate's
#               model; a readout of the acceptance checks; and a run of a separate event file
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-08
# Modified:     2026-11-08 - First version, from the Beggearn Huish calibration script
#               2026-11-09 - recommend: choose the structure with recommend_structure() first;
#                            stages and bounds may be functions of the chosen structure;
#                            held-back years without a validation window refused before the
#                            search; a rerun finishes the validation, test and report
#               2026-11-10 - Progress: the plan at the start, each step as it begins, the
#                            total time at the end
# Tier:         3
# Inputs:       Forcing and observed flow; a calibration project
# Outputs:      A logged calibration project; models, check readouts and event runs
# Dependencies: none beyond pdmS7
# ============================================================ #

#' Calibrate a catchment from start to finish in one call
#'
#' Runs the whole logged calibration of [Automatic calibration from start to
#' finish](https://jonpayneea.github.io/PDMS7/articles/calibration-journey.html) for one set of
#' prepared data: [start_calibration_project()], [register_data()], [select_structure()],
#' [recommend_structure()] when `recommend = TRUE`, [log_staged_calibration()],
#' [propose_candidate()] (the last stage), [validate_candidate()] when a validation window is
#' registered, and [test_candidate()] when a test window or wettest years are. Each step is an
#' entry in the project's log, as if made by hand.
#'
#' **Choosing the structure.** With `recommend = TRUE`, `structure` is only the starting
#' point. [recommend_structure()] then chooses the recharge rule, the soil store distribution
#' and the groundwater store in turn, each by a structure comparison on this record, and the
#' stages start from the calibration of the structure it recommends. Each comparison and each
#' choice, with its reason, is in the log. It needs a validation window, since the choice is
#' made on validation scores, and it costs one calibration per option compared: twelve in all.
#' The stages then need to suit whichever structure is chosen, so give `stages` and `bounds`
#' as functions of a configuration, such as
#' `function(config) pdm_stages(config, events = TRUE)`, or leave them `NULL`.
#'
#' **Test years need a validation window.** The test scores a validated candidate, so a record
#' with test years, or long enough for the wettest years to be held back (the default), needs a
#' validation window. Without one the call stops after registering the data and before the
#' search; give `validation`, or `wettest_years = 0`.
#'
#' **Progress.** A calibration of a long record takes hours, so it reports as it goes: the plan
#' at the start, each structure step and calibration stage as it begins, each structure's
#' scores and time when its comparison ends, with the time left for the rest at that pace, and,
#' every minute or so during a search, the model runs made so far and the time each takes.
#' Comparisons run on several cores (`cores > 1`) cannot write to this console, so each
#' structure's progress goes to `progress.log` in the project folder; open it to follow them.
#' `options(pdmS7.progress_every = 0)` turns the minute-by-minute lines off, and any number sets
#' their interval in seconds.
#'
#' **Existing projects.** A project that already has a candidate keeps it: a rerun only does
#' whichever of the validation, the test and (with `report = TRUE`) the report are still
#' missing, so a run that stopped after proposing the candidate can be finished, and a report
#' added later. Delete the folder to calibrate again. A project without a candidate, from a run
#' that stopped earlier, is renamed `<project>_unfinished_<time>` (its log kept) and the
#' calibration starts afresh.
#'
#' Declare who you are first (`options(pdmS7.user = ..., pdmS7.role = "custodian")`).
#'
#' @param project Folder for the project; its name is the project id.
#' @param forcing Data frame of `time`, `rain` and `pet` (mm per step), prepared with
#'   [align_series()], [convert_units()] and [fill_gaps()] or otherwise.
#' @param observed Observed flow, m3/s, aligned with `forcing`.
#' @param area_km2 Catchment area.
#' @param calibration,validation Windows, as for [register_data()].
#' @param structure Model configuration; by default the standard preset at the step of
#'   `forcing`. With `recommend = TRUE`, the structure the recommendation starts from.
#' @param stages Stages from [pdm_stages()], or a function of the configuration that returns
#'   them; by default `pdm_stages(structure, overrides, exclude)`.
#' @param bounds Search ranges from [calibration_bounds()], or a function of the configuration
#'   that returns them; by default `calibration_bounds(structure, overrides, exclude)`.
#' @param recommend Choose the recharge rule, soil store distribution and groundwater store
#'   with [recommend_structure()] before the stages.
#' @param overrides,exclude Passed to [calibration_bounds()] for the default stages and bounds
#'   and, with `recommend = TRUE`, for every structure compared.
#' @param cores Cores for the structure comparisons, with `recommend = TRUE`.
#' @param starts,seed,control,method Passed to [log_staged_calibration()] and, with
#'   `recommend = TRUE`, to [recommend_structure()].
#' @param catchment,gauge,purpose,owner,steward Passed to [start_calibration_project()]; the
#'   owner and steward default to the user declared.
#' @param report If `TRUE`, build the report with [build_report()] at the end.
#' @param ... Passed to [register_data()], such as `wettest_years`, `thresholds`,
#'   `highest_gauged_m3s` or `reasoning`.
#' @return The project's row of [read_projects()], invisibly.
#' @examples
#' \dontrun{
#' options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
#' calibrate_project("projects/beggearn_huish", forcing, flow, area_km2 = 36.7,
#'                   calibration = c("2010-10-01", "2019-09-30 23:45"),
#'                   validation = c("2019-10-01", "2025-06-30 23:45"),
#'                   stages = pdm_stages(structure, events = TRUE))
#' # Choose the structure on this record first, then run the stages on it
#' calibrate_project("projects/beggearn_huish", forcing, flow, area_km2 = 36.7,
#'                   calibration = c("2010-10-01", "2019-09-30 23:45"),
#'                   validation = c("2019-10-01", "2025-06-30 23:45"), recommend = TRUE,
#'                   stages = function(config) pdm_stages(config, events = TRUE))
#' }
#' @seealso [calibrate_batch()] for many catchments laid out in folders.
#' @export
calibrate_project <- function(project, forcing, observed, area_km2, calibration,
                              validation = NULL, structure = NULL, stages = NULL, bounds = NULL,
                              recommend = FALSE, overrides = NULL, exclude = NULL, cores = 1L,
                              starts = 2L, seed = 1L, control = list(maxit = 40L),
                              method = "lbfgsb", catchment = basename(project),
                              gauge = catchment, purpose = "PDM calibration", owner = NULL,
                              steward = NULL, report = FALSE, ...) {
  user <- .identity("custodian")$name
  .check(is.character(project) && length(project) == 1L, "project must be a folder path")
  .check(isTRUE(recommend) || isFALSE(recommend), "recommend must be TRUE or FALSE")
  .check(!recommend || !is.null(validation),
         "recommend = TRUE needs a validation window: structures are chosen on it")
  existing <- .existing_project(project)
  if (!is.null(existing)) return(invisible(.finish_project(project, report)))
  structure <- structure %||% .default_structure(forcing, area_km2)
  started <- Sys.time()
  .progress_say(.calibration_plan(recommend, validation, report))
  start_calibration_project(project, catchment, gauge, purpose, area_km2, owner %||% user,
                            steward %||% user)
  register_data(project, forcing, observed, calibration = calibration, validation = validation,
                ...)
  # The test scores a validated candidate: refuse now, not after the search.
  card <- .registration(.read_entries(.project_path(project)))$scorecard
  .check(!.has_test(card) || !is.null(card$validation),
         paste("Test years are registered (test, or the wettest years held back) but no",
               "validation window; the test needs a validated candidate. Give validation,",
               "or wettest_years = 0"))
  if (recommend) {
    select_structure(project, structure, "Starting structure for the structure recommendation.")
    chosen <- recommend_structure(
      project, starts = starts, seed = seed, control = control, method = method, cores = cores,
      overrides = overrides, exclude = exclude,
      reasoning = "Automatic calibration: structure chosen on this record."
    )
    parent <- chosen$entry
    structure <- chosen$configuration
  } else {
    parent <- select_structure(project, structure, "Structure for the automatic calibration.")$id
  }
  # Stages and bounds suit the structure the stages start from, chosen or given.
  for_structure <- function(x, default) {
    if (is.function(x)) x(structure) else x %||% default(structure, overrides, exclude)
  }
  fits <- log_staged_calibration(project, parent, "Staged automatic calibration.",
                                 stages = for_structure(stages, pdm_stages),
                                 bounds = for_structure(bounds, calibration_bounds),
                                 starts = starts, seed = seed, control = control,
                                 method = method)
  propose_candidate(project, fits[[length(fits)]]$id, "Final stage of the staged calibration.")
  out <- .finish_project(project, report)
  .progress_say(sprintf("Calibration of %s finished in %s", basename(project),
                        .duration_text(.seconds_since(started))))
  invisible(out)
}

# The steps a calibrate_project() call will take, said before it starts.
.calibration_plan <- function(recommend, validation, report) {
  n <- sum(lengths(.component_options()))
  steps <- c(
    "register the data",
    if (recommend) sprintf("choose the structure (%d calibrations)", n) else "select the structure",
    "run the calibration stages", "propose the candidate",
    if (!is.null(validation)) c("validate it", "test it, if test years are held back"),
    if (isTRUE(report)) "build the report"
  )
  paste0("Calibration plan: ", paste(steps, collapse = "; "), ". Long searches report every ",
         "minute or so; options(pdmS7.progress_every = 0) quietens them.")
}

# The steps after the candidate, each done only if still missing: validation when a window is
# registered, the test when test years are, and the report when asked for. Returns the
# project's summary.
.finish_project <- function(project, report) {
  path <- .project_path(project)
  state <- function() {
    entries <- .read_entries(path)
    list(entries = entries, card = .registration(entries)$scorecard,
         candidate = .latest(entries, "candidate"))
  }
  s <- state()
  validation <- .latest(s$entries, "validation")
  if (!is.null(s$card$validation) &&
        (is.null(validation) || !identical(validation$candidate, s$candidate$id))) {
    validate_candidate(project, "Validation window.")
    s <- state()
  }
  if (.has_test(s$card) && !is.null(s$card$validation) &&
        is.null(.candidate_test(s$entries, s$candidate))) {
    test_candidate(project, "Held-back test years.")
  }
  if (isTRUE(report) && !file.exists(file.path(project, "report", "report.html"))) {
    build_report(project)
  }
  read_projects(project)
}

# A finished project's summary, or NULL after moving an unfinished one aside.
.existing_project <- function(project) {
  if (!dir.exists(project) || !length(list.files(project))) return(NULL)
  summary <- tryCatch(read_projects(project), error = function(e) NULL)
  if (!is.null(summary) && !is.na(summary$candidate)) {
    message("Project ", project, " already has a candidate; finishing any missing steps")
    return(summary)
  }
  moved <- paste0(project, "_unfinished_", format(Sys.time(), "%Y%m%dT%H%M%S"))
  .check(file.rename(project, moved), paste("Cannot move the unfinished project", project))
  warning("Moved the unfinished project to ", moved, call. = FALSE)
  NULL
}

# The standard preset at the step of the forcing.
.default_structure <- function(forcing, area_km2) {
  config <- pdm_presets("standard")
  config$area_km2 <- area_km2
  if (is.data.frame(forcing) && "time" %in% names(forcing) && nrow(forcing) > 1L) {
    config$dt <- as.numeric(stats::median(diff(forcing$time)), units = "hours")
  }
  config
}

#' The model of a project's candidate
#'
#' @param project A calibration project folder.
#' @param entry Model entry; by default the current candidate.
#' @return A PDM model, as [pdm_from_config()] builds it.
#' @examples
#' \dontrun{
#' model <- candidate_model("projects/beggearn_huish")
#' }
#' @seealso [read_entry()], [project_series()]
#' @export
candidate_model <- function(project, entry = NULL) {
  entries <- .read_entries(.project_path(project))
  if (is.null(entry)) {
    candidate <- .latest(entries, "candidate")
    .check(!is.null(candidate), "The project has no candidate yet")
    entry <- candidate$entry
  }
  node <- .find_entry(entries, entry)
  .check(!is.null(node$configuration), paste("Entry", entry, "holds no model"))
  pdm_from_config(node$configuration)
}

#' @export
print.pdm_calibration_checks <- function(x, ...) {
  cat(sprintf("Acceptance checks. Response time %.2f h observed, %.2f h simulated\n",
              x$response_h[["observed"]], x$response_h[["simulated"]]))
  edge <- x$parameters[!is.na(x$parameters$at_bound), ]
  if (nrow(edge)) {
    cat("PARAMETERS AT A BOUND (the structure may be bent to fit; review before use):\n")
    for (i in seq_len(nrow(edge))) {
      cat(sprintf("  %-20s %10.4g at its %s bound (searched %g to %g)\n", edge$path[i],
                  edge$value[i], edge$at_bound[i], edge$lower[i], edge$upper[i]))
      if (!is.na(edge$note[i] %||% NA)) cat("  ", " -> ", edge$note[i], "\n", sep = "")
    }
  } else {
    cat("No parameter at a bound\n")
  }
  cat("Largest events in each window:\n")
  shown <- x$summary
  numeric <- vapply(shown, is.numeric, logical(1))
  shown[numeric] <- lapply(shown[numeric], round, 2)
  print(shown, row.names = FALSE)
  invisible(x)
}

# ---- Separate event files ----------------------------------------------------------------

#' Run a project's model over a separate event
#'
#' Validation events often come as their own files, apart from the registered record.
#' `event_run()` runs a model entry of the project over one, from the best start available:
#'
#' - **Warm start**: when the event begins inside the registered record, the record is run up to
#'   that moment and the model continues from its own state then.
#' - **Steady state**: otherwise the stores start in balance with the event's first observed
#'   flow. That is only approximate, so give the file a few days before the rise and distrust
#'   the first hours.
#'
#' Missing evaporation is taken from the registered record at the same times, or, outside it,
#' from the record's mean for that month and time of day.
#'
#' @param project A calibration project folder.
#' @param forcing Data frame of the event's `time`, `rain` and, optionally, `pet`, on the
#'   project's time step.
#' @param observed Observed flow over the event, m3/s; optional.
#' @param entry Model entry; by default the candidate.
#' @param x A `pdm_event_run`.
#' @param ... For `plot()`: passed to [plot.pdm_series()].
#' @return A `pdm_event_run` list: `series` (time, rain, pet, observed, simulated), `start`
#'   (`"warm"` or `"steady"`) and `scores` (NSE, observed and simulated peak, peak error and
#'   timing error in hours) when flow is given. `plot()` draws its hydrograph.
#' @examples
#' \dontrun{
#' ev <- event_run("projects/beggearn_huish", event_forcing, event_flow)
#' ev
#' plot(ev)
#' }
#' @seealso [candidate_model()], [pdm_series()]
#' @export
event_run <- function(project, forcing, observed = NULL, entry = NULL) {
  .check(is.data.frame(forcing) && all(c("time", "rain") %in% names(forcing)),
         "forcing needs time and rain columns")
  .check(is.null(observed) || length(observed) == nrow(forcing),
         "observed must be as long as forcing")
  path <- .project_path(project)
  entries <- .read_entries(path)
  registration <- .registration(entries)
  data <- .load_registration(path, registration)
  model <- candidate_model(project, entry)
  time <- as.POSIXct(forcing$time, tz = "UTC")
  pet <- .event_pet(forcing$pet, time, data$forcing)
  start <- .event_start(model, registration$scorecard, data, time[1], observed)
  sim <- .quietly(run_pdm(model, data.frame(rain = forcing$rain, pet = pet),
                          start$state))$output$q_m3s
  series <- data.frame(time = time, rain = forcing$rain, pet = pet,
                       observed = observed %||% NA_real_, simulated = sim)
  structure(list(series = series, start = start$kind, dt = model@dt,
                 scores = if (!is.null(observed)) .event_run_scores(series, model@dt)),
            class = "pdm_event_run")
}

# Evaporation for the event: given, or the record's at the same time, or its mean for the month
# and time of day.
.event_pet <- function(pet, time, record) {
  pet <- if (is.null(pet)) rep(NA_real_, length(time)) else as.numeric(pet)
  gap <- !is.finite(pet)
  if (!any(gap)) return(pet)
  .check("time" %in% names(record), "The registered record has no times to take pet from")
  pet[gap] <- record$pet[match(time[gap], record$time)]
  gap <- !is.finite(pet)
  if (any(gap)) {
    key <- function(t) format(t, "%m %H:%M", tz = "UTC")
    climate <- tapply(record$pet, key(record$time), mean, na.rm = TRUE)
    pet[gap] <- climate[key(time[gap])]
  }
  .check(all(is.finite(pet)), "Cannot find pet for every step of the event")
  pet
}

# A warm start from the record's own run when the event begins inside it, else steady state.
.event_start <- function(model, card, data, first, observed) {
  at <- if ("time" %in% names(data$forcing)) match(first, data$forcing$time) else NA
  if (!is.na(at) && at > 1L) {
    state <- .workbench_start(model, card, data$observed)
    lead <- data$forcing[seq_len(at - 1L), c("rain", "pet")]
    return(list(kind = "warm", state = .quietly(run_pdm(model, lead, state))$state))
  }
  flow <- if (is.null(observed)) NA else observed[is.finite(observed)][1]
  .check(is.finite(flow), "An event outside the record needs observed flow to start from")
  list(kind = "steady",
       state = suppressWarnings(initial_state_from_flow(model, flow,
                                                        card$baseflow_fraction %||% 0.7)))
}

.event_run_scores <- function(series, dt) {
  ok <- is.finite(series$observed) & is.finite(series$simulated)
  obs <- series$observed[ok]
  sim <- series$simulated[ok]
  data.frame(
    nse = 1 - sum((sim - obs)^2) / sum((obs - mean(obs))^2),
    observed_peak = max(obs), simulated_peak = max(sim), peak_error = max(sim) / max(obs) - 1,
    timing_error_h = (which(ok)[which.max(sim)] - which(ok)[which.max(obs)]) * dt
  )
}

#' @export
print.pdm_event_run <- function(x, ...) {
  s <- x$series
  cat(sprintf("Event run, %s start, %s to %s\n", x$start,
              format(min(s$time), "%Y-%m-%d %H:%M"), format(max(s$time), "%Y-%m-%d %H:%M")))
  if (!is.null(x$scores)) {
    sc <- x$scores
    cat(sprintf("NSE %.3f; peak %.3g m3/s observed, %.3g simulated (%+.0f%%), timing %+.1f h\n",
                sc$nse, sc$observed_peak, sc$simulated_peak, 100 * sc$peak_error,
                sc$timing_error_h))
  }
  invisible(x)
}

#' @rdname event_run
#' @export
plot.pdm_event_run <- function(x, ...) {
  s <- x$series
  observed <- if (all(is.na(s$observed))) NULL else s$observed
  plot(pdm_series(s$simulated, observed, rain = s$rain, time = s$time, dt = x$dt), ...)
  invisible(x)
}
