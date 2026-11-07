# ============================================================ #
# Tool:         app_events
# Description:  Server code for the Events tab of the calibration app: the events workbench
#               on sliders, saved as a logged trial
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         3
# Inputs:       Shiny inputs; the open project
# Outputs:      Event plots, scores, recession check; trial entries
# Dependencies: shiny
# ============================================================ #

# The sliders of the Events tab: the surface stores, the time delay and the store shape b where
# the structure has one, each over its calibration bounds (the time delay from 0 to 12 hours,
# or further if the run already uses more).
.wb_slider_specs <- function(config) {
  b <- calibration_bounds(config)
  rows <- b[grepl("^surface\\.", b$path) | b$path == "distribution.b", ]
  specs <- data.frame(path = rows$path, min = rows$lower, max = rows$upper)
  specs <- rbind(specs, data.frame(path = "td", min = 0, max = max(12, config$td %||% 0)))
  specs$value <- vapply(specs$path, function(p) .path_get(config, p), numeric(1))
  specs$step <- ifelse(specs$path == "distribution.b", 0.01, ifelse(specs$path == "td", 0.25, 0.1))
  # A run may already sit outside the default bounds; widen the slider rather than move it.
  specs$min <- pmin(specs$min, specs$value)
  specs$max <- pmax(specs$max, specs$value)
  rownames(specs) <- NULL
  specs
}

# The slider values that differ from the run's, as changes for workbench_try() and log_trial().
.wb_changes <- function(specs, values) {
  values <- unlist(values[specs$path])
  if (is.null(values) || length(values) != nrow(specs)) return(NULL)
  moved <- abs(values - specs$value) > 1e-12
  if (!any(moved)) return(NULL)
  stats::setNames(values[moved], specs$path[moved])
}

# Medians over the events, for the run and the trial side by side.
.wb_summary_table <- function(wb, trial) {
  summarise <- function(s) {
    c(median_peak_error_pct = 100 * stats::median(s$peak_error),
      median_abs_timing_h = stats::median(abs(s$timing_error_h)),
      median_event_nse = stats::median(s$nse),
      peaks_within_20pct = sum(abs(s$peak_error) <= 0.2))
  }
  out <- data.frame(measure = c("median peak error (%)", "median |timing error| (h)",
                                "median event NSE", "peaks within 20%"),
                    run = signif(summarise(wb$scores), 3), row.names = NULL)
  if (!is.null(trial)) out$trial <- signif(summarise(trial$scores), 3)
  out
}

.app_events <- function(input, output, session, rv, act, state) {
  shiny::observe({
    choices <- .node_choices(state$nodes(), state$headline())
    selected <- if (length(choices)) choices[[length(choices)]] else character(0)
    shiny::updateSelectInput(session, "wb_parent", choices = choices, selected = selected)
  })
  shiny::observeEvent(input$wb_load, act(function() {
    rv$wb <- NULL
    rv$wb_recession <- NULL
    rv$wb <- event_workbench(rv$project, input$wb_parent, n = input$wb_n,
                             window = input$wb_window)
  }, "Events loaded"))
  specs <- shiny::reactive({
    shiny::req(rv$wb)
    .wb_slider_specs(rv$wb$configuration)
  })
  output$wb_sliders <- shiny::renderUI({
    s <- specs()
    lapply(seq_len(nrow(s)), function(i) {
      shiny::sliderInput(.input_id(paste0("wb.", s$path[i])), s$path[i], min = s$min[i],
                         max = s$max[i], value = s$value[i], step = s$step[i])
    })
  })
  values <- shiny::debounce(shiny::reactive({
    s <- specs()
    stats::setNames(lapply(s$path, function(p) input[[.input_id(paste0("wb.", p))]]), s$path)
  }), 400)
  trial <- shiny::reactive({
    changes <- .wb_changes(specs(), values())
    if (is.null(changes)) return(NULL)
    tryCatch(workbench_try(rv$wb, changes), error = function(e) {
      shiny::showNotification(conditionMessage(e), type = "error")
      NULL
    })
  })
  # The trial on screen, kept where the rest of the app (and its tests) can see it.
  shiny::observe(rv$wb_trial <- trial())
  shiny::observeEvent(input$wb_reset, {
    s <- specs()
    for (i in seq_len(nrow(s))) {
      shiny::updateSliderInput(session, .input_id(paste0("wb.", s$path[i])), value = s$value[i])
    }
  })
  output$wb_summary <- shiny::renderUI({
    shiny::req(rv$wb)
    t <- trial()
    shiny::helpText(sprintf(
      "%d largest events in the %s window, from entry %s.%s", nrow(rv$wb$events),
      rv$wb$window, rv$wb$parent,
      if (is.null(t)) " Move a slider to compare." else if (t$full_run)
        " The change reaches the soil store, so the whole record was rerun." else ""
    ))
  })
  output$wb_plot_box <- shiny::renderUI({
    shiny::req(rv$wb)
    shiny::plotOutput("wb_plot", height = paste0(260 * ceiling(nrow(rv$wb$events) / 2), "px"))
  })
  output$wb_plot <- shiny::renderPlot({
    shiny::req(rv$wb)
    plot_workbench(rv$wb, trial())
  })
  output$wb_table <- shiny::renderTable({
    shiny::req(rv$wb)
    .wb_summary_table(rv$wb, trial())
  })
  shiny::observeEvent(input$wb_save, act(function() {
    shiny::req(rv$wb)
    changes <- .wb_changes(specs(), values())
    .check(!is.null(changes), "Move a slider first; there is nothing to save")
    log_trial(rv$project, rv$wb$parent, changes, input$wb_verdict, input$wb_reasoning)
    shiny::updateTextAreaInput(session, "wb_reasoning", value = "")
  }, "Trial saved"))
  shiny::observeEvent(input$wb_recession, act(function() {
    shiny::req(rv$wb)
    wb <- rv$wb
    config <- if (is.null(trial())) wb$configuration else trial()$configuration
    simulated <- .workbench_full_run(wb, config)
    rv$wb_recession <- list(
      observed = recession_analysis(wb$observed, wb$forcing$rain, wb$model@dt, boot = 100),
      simulated = recession_analysis(simulated, wb$forcing$rain, wb$model@dt, boot = 100)
    )
  }, "Recessions checked"))
  output$wb_recession_plot <- shiny::renderPlot({
    shiny::req(rv$wb_recession)
    plot_recession(rv$wb_recession$observed, rv$wb_recession$simulated,
                   main = "Recessions: observed (blue) and the model (orange)")
  })
}
