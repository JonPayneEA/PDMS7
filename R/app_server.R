# ============================================================ #
# Tool:         app_server
# Description:  Server logic for the calibration app
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration app
# Tier:         3
# Inputs:       Shiny inputs
# Outputs:      Calls to the exported calibration log functions
# Dependencies: shiny (suggested)
# ============================================================ #

.app_server <- function(project) {
  force(project)
  function(input, output, session) {
    rv <- shiny::reactiveValues(project = project, version = 0L, preview = NULL,
                                report = NULL, zoom = NULL, validation = NULL)
    refresh <- function() rv$version <- rv$version + 1L
    # Runs a log action; reports success or the error message on screen.
    act <- function(code, success) {
      tryCatch({
        code()
        shiny::showNotification(success, type = "message")
        refresh()
      }, error = function(e) {
        shiny::showNotification(conditionMessage(e), type = "error", duration = NULL)
      })
    }
    shiny::observe({
      options(pdmS7.user = input$user, pdmS7.role = input$role)
    })
    shiny::observeEvent(input$open, act(function() {
      .project_path(input$project_path)
      rv$project <- input$project_path
    }, "Project opened"))

    state <- .app_state(input, rv)
    .app_status(output, state)
    .app_setup(input, rv, act, session)
    .app_trial(input, output, session, rv, act, state)
    .app_history(input, output, session, rv, act, state)
    .app_report(input, output, rv, act, state)
    .app_signoff(input, output, rv, act, state)
  }
}

.app_state <- function(input, rv) {
  entries <- shiny::reactive({
    rv$version
    shiny::req(rv$project)
    .read_entries(.project_path(rv$project))
  })
  list(
    entries = entries,
    path = shiny::reactive({
      shiny::req(rv$project)
      .project_path(rv$project)
    }),
    nodes = shiny::reactive(Filter(function(e) e$type %in% .model_entry_types, entries())),
    registration = shiny::reactive(.latest(entries(), "data_registered")),
    headline = shiny::reactive({
      reg <- .latest(entries(), "data_registered")
      if (is.null(reg)) "nse" else reg$scorecard$headline
    })
  )
}

# Simulates a logged run again, for plotting; the result is not logged.
.app_run <- function(state, node) {
  entries <- state$entries()
  registration <- .find_entry(entries, node$registration)
  .run_registered(state$path(), .project_info(entries), registration, node$configuration)
}

.app_status <- function(output, state) {
  output$status <- shiny::renderUI({
    entries <- tryCatch(state$entries(), error = function(e) NULL)
    if (is.null(entries)) return(shiny::helpText("No project open."))
    info <- .project_info(entries)
    shiny::helpText(sprintf("%s: %s, gauge %s. %d entries; status %s.", info$id,
                            info$catchment, info$gauge, length(entries),
                            gsub("_", " ", .project_status(entries))))
  })
}

.app_setup <- function(input, rv, act, session) {
  shiny::observeEvent(input$start, act(function() {
    start_calibration_project(input$new_path, input$catchment, input$gauge, input$purpose,
                              input$area, input$owner, input$steward, input$description)
    rv$project <- input$new_path
    shiny::updateTextInput(session, "project_path", value = input$new_path)
  }, "Project started"))
  shiny::observeEvent(input$register, act(function() {
    shiny::req(rv$project)
    register_data(rv$project, input$forcing_path, input$observed_path,
                  calibration = .window_input(input$cal_start, input$cal_end),
                  validation = .window_input(input$val_start, input$val_end),
                  test = .window_input(input$test_start %||% "", input$test_end %||% ""),
                  headline = input$headline, log_offset = input$log_offset,
                  soil_fraction = input$soil_fraction, copy = input$copy,
                  reasoning = input$register_reasoning,
                  thresholds = .parse_thresholds(input$thresholds),
                  rating = if (nzchar(trimws(input$rating_path %||% ""))) input$rating_path,
                  event_tolerance_h = input$event_tolerance %||% 6,
                  event_gap_h = input$event_gap %||% 24,
                  event_min_duration_h = input$event_min %||% 0)
  }, "Data registered"))
  shiny::observeEvent(input$structure, act(function() {
    shiny::req(rv$project)
    config <- if (nzchar(trimws(input$config_path))) {
      read_pdm_config(input$config_path)
    } else {
      cfg <- pdm_presets(input$preset)
      cfg$area_km2 <- .project_info(.read_entries(.project_path(rv$project)))$area_km2
      cfg
    }
    select_structure(rv$project, config, input$structure_reasoning)
  }, "Structure selected"))
}

.app_trial <- function(input, output, session, rv, act, state) {
  shiny::observe({
    choices <- .node_choices(state$nodes(), state$headline())
    selected <- if (length(choices)) choices[[length(choices)]] else character(0)
    shiny::updateSelectInput(session, "parent", choices = choices, selected = selected)
  })
  parent <- shiny::reactive({
    shiny::req(input$parent)
    .find_entry(state$entries(), input$parent)
  })
  parent_run <- shiny::reactive(.app_run(state, parent()))
  shiny::observe({
    paths <- .editable_paths(parent()$configuration)
    shiny::updateSelectizeInput(session, "calib_params", choices = paths, selected = character(0))
  })
  shiny::observe({
    reg <- state$registration()
    names <- if (is.null(reg)) character(0) else
      vapply(reg$scorecard$thresholds, function(t) t$name, character(1))
    shiny::updateSelectizeInput(session, "calib_thresholds", choices = names,
                                selected = character(0))
  })
  output$params <- shiny::renderUI({
    config <- parent()$configuration
    boxes <- lapply(.editable_paths(config), function(p) {
      shiny::column(6, shiny::numericInput(.input_id(p), p, .path_get(config, p),
                                           width = "100%"))
    })
    shiny::fluidRow(boxes)
  })
  changes <- function() {
    config <- parent()$configuration
    paths <- .editable_paths(config)
    values <- vapply(paths, function(p) as.numeric(input[[.input_id(p)]] %||% NA), numeric(1))
    old <- vapply(paths, function(p) .path_get(config, p), numeric(1))
    keep <- is.finite(values) & values != old
    .check(any(keep), "Change at least one parameter first")
    values[keep]
  }
  shiny::observeEvent(input$preview, act(function() {
    rv$preview <- preview_trial(rv$project, input$parent, changes())
  }, "Preview ready; nothing is logged until you save"))
  shiny::observeEvent(input$parent, rv$preview <- NULL)
  shiny::observeEvent(input$hydro_brush, {
    rv$zoom <- c(input$hydro_brush$xmin, input$hydro_brush$xmax)
  })
  shiny::observeEvent(input$hydro_reset, rv$zoom <- NULL)
  output$hydrograph <- shiny::renderPlot({
    base <- parent_run()
    rows <- base$rows
    time <- if (is.null(base$time)) rows else base$time[rows]
    runs <- list(parent = base$simulated[rows])
    if (!is.null(rv$preview) && identical(rv$preview$parent, input$parent)) {
      runs$trial <- rv$preview$simulated[rows]
    }
    xlim <- if (is.null(rv$zoom)) NULL else rv$zoom
    if (inherits(time, "POSIXct") && !is.null(xlim)) {
      xlim <- as.POSIXct(xlim, origin = "1970-01-01", tz = "UTC")
    }
    .plot_compare(time, base$observed[rows], runs, xlim)
  })
  output$scores <- shiny::renderTable({
    trial <- if (is.null(rv$preview)) parent()$scores else rv$preview$scores
    .score_table(parent()$scores, trial)
  }, digits = 4)
  shiny::observeEvent(input$save_trial, act(function() {
    log_trial(rv$project, input$parent, changes(), input$verdict, input$trial_reasoning)
    rv$preview <- NULL
    shiny::updateTextAreaInput(session, "trial_reasoning", value = "")
  }, "Trial saved"))
  shiny::observeEvent(input$save_note, act(function() {
    log_note(rv$project, input$note)
    shiny::updateTextAreaInput(session, "note", value = "")
  }, "Note saved"))
  shiny::observeEvent(input$run_calib, act(function() {
    .check(length(input$calib_params) > 0, "Choose parameters to calibrate")
    config <- parent()$configuration
    value <- vapply(input$calib_params, function(p) .path_get(config, p), numeric(1))
    .check(all(value != 0), "Bounds are relative to the value; a zero parameter cannot be used")
    chosen <- input$calib_thresholds
    log_auto_calibration(rv$project, input$parent, lower = value * (1 - input$calib_range),
                         upper = value * (1 + input$calib_range), starts = input$calib_starts,
                         seed = input$calib_seed, control = list(maxit = input$calib_maxit),
                         reasoning = input$calib_reasoning,
                         method = input$calib_method %||% "lbfgsb",
                         threshold_objective = if (length(chosen)) chosen,
                         threshold_weight = input$calib_weight %||% 1,
                         threshold_score = input$calib_score %||% "csi")
  }, "Calibration logged"))
}

.app_history <- function(input, output, session, rv, act, state) {
  shiny::observe({
    choices <- .node_choices(state$nodes(), state$headline())
    n <- length(choices)
    shiny::updateSelectInput(session, "compare_a", choices = choices,
                             selected = if (n > 1) choices[[n - 1L]] else choices)
    shiny::updateSelectInput(session, "compare_b", choices = choices,
                             selected = if (n) choices[[n]] else character(0))
    shiny::updateSelectInput(session, "candidate_entry", choices = choices,
                             selected = if (n) choices[[n]] else character(0))
  })
  output$path <- shiny::renderPlot({
    shiny::req(length(state$nodes()) > 0)
    .plot_path(state$nodes(), state$headline(), .latest(state$entries(), "candidate"))
  })
  output$trials <- shiny::renderTable({
    shiny::req(length(state$nodes()) > 0)
    table <- project_trials(state$path())
    keep <- intersect(c("id", "type", "parent", "author", "changes", state$headline(),
                        "volume_error", "verdict", "reasoning"), names(table))
    as.data.frame(table)[, keep, drop = FALSE]
  }, digits = 4)
  compared <- shiny::reactive({
    shiny::req(input$compare_a, input$compare_b)
    entries <- state$entries()
    list(a = .find_entry(entries, input$compare_a), b = .find_entry(entries, input$compare_b))
  })
  output$compare_plot <- shiny::renderPlot({
    pair <- compared()
    a <- .app_run(state, pair$a)
    b <- .app_run(state, pair$b)
    rows <- a$rows
    time <- if (is.null(a$time)) rows else a$time[rows]
    runs <- stats::setNames(list(a$simulated[rows], b$simulated[rows]), c(pair$a$id, pair$b$id))
    .plot_compare(time, a$observed[rows], runs)
  })
  output$compare_scores <- shiny::renderTable({
    pair <- compared()
    out <- .score_table(pair$a$scores, pair$b$scores)
    names(out)[2:3] <- c(pair$a$id, pair$b$id)
    out
  }, digits = 4)
  shiny::observeEvent(input$propose, act(function() {
    propose_candidate(rv$project, input$candidate_entry, input$candidate_reasoning)
  }, "Candidate proposed"))
  shiny::observeEvent(input$validate, act(function() {
    entry <- validate_candidate(rv$project, input$validation_reasoning)
    rv$validation <- .score_table(entry$calibration_scores, entry$validation_scores)
  }, "Validation logged"))
  shiny::observeEvent(input$final_test, act(function() {
    test_candidate(rv$project, input$test_reasoning)
  }, "Final test logged"))
  output$validation_scores <- shiny::renderTable({
    shiny::req(rv$validation)
    out <- rv$validation
    names(out)[2:3] <- c("calibration", "validation")
    out[, 1:3]
  }, digits = 4)
}

.app_report <- function(input, output, rv, act, state) {
  shiny::observeEvent(input$build, act(function() {
    rv$report <- build_report(state$path(), rerun = input$report_rerun,
                              sensitivity = input$report_sensitivity)
  }, "Report built"))
  output$download <- shiny::downloadHandler(
    filename = function() paste0(basename(state$path()), "-report.html"),
    content = function(file) {
      report <- rv$report %||% build_report(state$path())
      file.copy(report, file, overwrite = TRUE)
    }
  )
  checks <- shiny::eventReactive(input$verify, verify_project(state$path(), rerun = TRUE))
  output$integrity <- shiny::renderTable(as.data.frame(checks()))
}

.app_signoff <- function(input, output, rv, act, state) {
  output$signoff_summary <- shiny::renderUI({
    entries <- state$entries()
    candidate <- .latest(entries, "candidate")
    validation <- .latest(entries, "validation")
    checks <- verify_project(state$path())
    lines <- c(
      paste("Status:", gsub("_", " ", .project_status(entries))),
      if (all(checks$ok)) "Integrity: all checks pass." else
        paste("Integrity:", sum(!checks$ok), "checks FAIL. See the Report tab."),
      if (is.null(candidate)) "No candidate proposed." else
        paste0("Candidate: entry ", candidate$id, " (run ", candidate$entry, ")."),
      if (!is.null(validation) && !is.null(candidate) &&
            identical(validation$candidate, candidate$id)) {
        sprintf("Validation %s: %s %.4g.", validation$id, state$headline(),
                .num_or_na(validation$validation_scores[[state$headline()]]))
      } else {
        "The latest candidate has not been validated."
      },
      .test_line(entries, candidate, state$headline())
    )
    shiny::tags$ul(lapply(lines, shiny::tags$li))
  })
  shiny::observeEvent(input$sign, act(function() {
    needed <- c("integrity", "data", "calibration_path", "validation")
    sign_off_project(rv$project, input$statement,
                     stats::setNames(needed %in% input$checklist, needed))
  }, "Signed off"))
  shiny::observeEvent(input$reopen, act(function() {
    reopen_project(rv$project, input$reopen_reason)
  }, "Project reopened"))
}

.test_line <- function(entries, candidate, headline) {
  registration <- .latest(entries, "data_registered")
  if (is.null(registration$scorecard$test)) return(NULL)
  test <- .candidate_test(entries, candidate)
  if (is.null(test)) return("Final test: not yet run; required before sign-off.")
  sprintf("Final test %s: %s %.4g.", test$id, headline,
          .num_or_na(test$test_scores[[headline]]))
}
