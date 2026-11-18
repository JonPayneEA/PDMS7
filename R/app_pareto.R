# ============================================================ #
# Tool:         app_pareto
# Description:  The calibration app's Trade-offs tab: search a Pareto front and log it, draw a
#               logged front for any pair of objectives, click a set to see its flow and
#               scores, and keep it as a trial
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Shiny inputs; the open project's Pareto entries
# Outputs:      Calls to log_pareto_calibration() and log_trial()
# Dependencies: shiny (suggested); graphics
# ============================================================ #

# The losses offered in the tab: all of calibrate_pdm_multi()'s but the threshold loss, which
# needs registered thresholds and is added when the project has them.
.app_pareto_losses <- function(thresholds = FALSE) {
  out <- c("nse_loss", "log_rmse", "abs_bias", "kge_loss", "event_nse_loss",
           "event_peak_error", "event_timing_error")
  if (thresholds) out <- c(out, "threshold_loss")
  stats::setNames(out, .pareto_label(out))
}

.ui_pareto <- function() {
  search <- shiny::column(
    4,
    shiny::h3("Search a front"),
    shiny::selectInput("front_parent", "Start from", character(0), width = "100%"),
    shiny::checkboxGroupInput("front_objectives", "Objectives", .app_pareto_losses(),
                              c("nse_loss", "event_nse_loss", "abs_bias")),
    shiny::splitLayout(
      shiny::numericInput("front_budget", "Runs a chain", 200, 10),
      shiny::numericInput("front_chains", "Chains", 2, 1),
      shiny::numericInput("front_cores", "Cores", 1, 1)
    ),
    shiny::numericInput("front_check", "Check period (share of calibration)", 0, 0, 0.8, 0.05),
    shiny::selectInput("front_choose", "Log which set", c("knee", "compromise")),
    .text_area("front_reasoning", "Why search a front?"),
    shiny::actionButton("front_search", "Search and log", class = "btn-primary"),
    shiny::helpText(paste("Every parameter in the structure's calibration_bounds() is searched;",
                          "the registered validation window is never used."))
  )
  view <- shiny::column(
    8,
    shiny::selectInput("front_entry", "Front", character(0)),
    shiny::splitLayout(
      shiny::selectInput("front_x", "Across", character(0)),
      shiny::selectInput("front_y", "Up", character(0))
    ),
    shiny::plotOutput("front_plot", height = "360px", click = "front_click"),
    shiny::helpText("Click a set to see its flow and scores."),
    shiny::plotOutput("front_flow", height = "280px"),
    shiny::tableOutput("front_set"),
    .text_area("front_keep_reasoning", "Why keep this set?"),
    shiny::actionButton("front_keep", "Keep this set as a trial")
  )
  shiny::fluidRow(search, view)
}

# The Trade-offs tab: searching and logging a front, viewing a logged one, keeping a set.
.app_pareto <- function(input, output, session, rv, act, state) {
  fronts <- shiny::reactive(Filter(function(e) identical(e$objective, "pareto"),
                                   state$nodes()))
  shiny::observe({
    ids <- vapply(state$nodes(), function(e) e$id, character(1))
    shiny::updateSelectInput(session, "front_parent", choices = rev(ids))
    f <- vapply(fronts(), function(e) e$id, character(1))
    shiny::updateSelectInput(session, "front_entry", choices = rev(f))
    reg <- state$registration()
    has <- !is.null(reg) && length(reg$scorecard$thresholds) > 0
    shiny::updateCheckboxGroupInput(session, "front_objectives",
                                    choices = .app_pareto_losses(has),
                                    selected = input$front_objectives)
  })
  shiny::observeEvent(input$front_objectives, {
    picks <- c("knee", "compromise", input$front_objectives)
    shiny::updateSelectInput(session, "front_choose", choices = picks)
  })
  shiny::observeEvent(input$front_search, act(function() {
    .check(length(input$front_objectives) >= 2L, "Choose at least two objectives")
    parent <- .find_entry(state$entries(), input$front_parent)
    b <- calibration_bounds(parent$configuration)
    reg <- state$registration()
    thresholds <- if ("threshold_loss" %in% input$front_objectives) {
      vapply(reg$scorecard$thresholds, function(t) t$name, character(1))
    }
    log_pareto_calibration(
      rv$project, parent = parent$id, lower = stats::setNames(b$lower, b$path),
      upper = stats::setNames(b$upper, b$path), objectives = input$front_objectives,
      choose = input$front_choose, starts = input$front_chains,
      control = list(maxit = input$front_budget), check_share = input$front_check %||% 0,
      threshold_objective = thresholds, log_scale = b$path[b$scale == "log"],
      cores = input$front_cores, reasoning = input$front_reasoning
    )
  }, "Front searched and logged"))
  entry <- shiny::reactive({
    shiny::req(input$front_entry)
    .find_entry(state$entries(), input$front_entry)
  })
  front <- shiny::reactive(.pareto_from_entry(entry()))
  shiny::observe({
    objectives <- front()$objectives
    shiny::updateSelectInput(session, "front_x", choices = objectives,
                             selected = objectives[1L])
    shiny::updateSelectInput(session, "front_y", choices = objectives,
                             selected = objectives[2L])
  })
  picked <- shiny::reactiveVal(NULL)
  shiny::observeEvent(input$front_entry, picked(NULL))
  shiny::observeEvent(input$front_click, {
    x <- front()
    picked(.app_nearest_set(x, input$front_x, input$front_y, input$front_click$x,
                            input$front_click$y))
  })
  chosen <- shiny::reactive(picked() %||% entry()$pareto$chosen_row %||% 1L)
  output$front_plot <- shiny::renderPlot({
    shiny::req(input$front_x, input$front_y, input$front_x != input$front_y)
    x <- front()
    x$compromise$scores <- x$pareto[chosen()]
    .draw_base(.spec_pareto_pairs(x, c(input$front_x, input$front_y)))
  })
  set_config <- shiny::reactive(.app_set_config(entry(), front(), chosen()))
  output$front_flow <- shiny::renderPlot({
    run <- .app_run(state, list(configuration = set_config(),
                                registration = entry()$registration))
    logged <- .app_run(state, entry())
    rows <- run$rows[.storm_window(list(configs = list(set_config())),
                                   run$observed[run$rows])]
    time <- if (is.null(run$time)) rows else run$time[rows]
    runs <- stats::setNames(list(logged$simulated[rows], run$simulated[rows]),
                            c(paste("Logged", entry()$id), paste("Set", chosen())))
    .plot_compare(time, run$observed[rows], runs)
  })
  output$front_set <- shiny::renderTable({
    x <- front()
    row <- as.data.frame(x$pareto[chosen()])
    data.frame(quantity = names(row), value = unlist(row), row.names = NULL)
  }, digits = 4)
  shiny::observeEvent(input$front_keep, act(function() {
    x <- front()
    changes <- unlist(x$pareto[chosen(), x$parameters, with = FALSE])
    log_trial(rv$project, parent = entry()$id, changes = changes, verdict = "inconclusive",
              reasoning = input$front_keep_reasoning)
  }, "Set kept as a trial"))
}

# The front set nearest a click on the pair (ox, oy), each loss put on the front's 0-1 scale.
.app_nearest_set <- function(x, ox, oy, cx, cy) {
  if (is.null(cx) || is.null(cy)) return(NULL)
  a <- x$pareto[[paste0("loss_", ox)]]
  b <- x$pareto[[paste0("loss_", oy)]]
  scale <- function(v, ref) (v - min(ref)) / max(diff(range(ref)), 1e-12)
  which.min((scale(a, a) - scale(cx, a))^2 + (scale(b, b) - scale(cy, b))^2)
}

# The configuration of front set `row`: the logged configuration with the set's parameters.
.app_set_config <- function(entry, x, row) {
  cfg <- entry$configuration
  values <- unlist(x$pareto[row, x$parameters, with = FALSE])
  for (p in names(values)) cfg <- .path_set(cfg, p, unname(values[[p]]))
  cfg
}
