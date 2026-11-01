# ============================================================ #
# Tool:         app
# Description:  Shiny app over the calibration log: setup, trials, history, report, sign-off
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration app
# Tier:         3
# Inputs:       A calibration project folder; the user's declared name and role
# Outputs:      Log entries written through the exported calibration log functions
# Dependencies: shiny (suggested); graphics
# ============================================================ #

#' Calibration app
#'
#' A Shiny app over the calibration log, for staff who prefer not to script. Every button
#' calls the same exported function a script would ([start_calibration_project()],
#' [log_trial()], [sign_off_project()] and the rest), so a project started in the app can be
#' continued in R and the other way round, and the same rules apply: roles, reasoning,
#' scoring windows, integrity checks and the bar on signing off your own work.
#'
#' Tabs:
#' - **Setup**: start a project, register data, select a model structure.
#' - **Trial**: choose a parent run, adjust parameters, preview the hydrograph and scorecard
#'   against the parent (drag to zoom, double-click to reset), then save with a verdict and
#'   reasoning. Notes and automatic calibration are here too. Nothing is logged until saved.
#' - **History**: the calibration path, every run, a side-by-side comparison of any two
#'   runs, and proposing and validating a candidate.
#' - **Report**: integrity checks, and building and downloading the report.
#' - **Sign-off**: for a Steward or Delegated Steward, with the review checklist; and
#'   reopening.
#'
#' The app runs on your own machine and reads data files from local or shared-drive paths.
#' Enter your name and role at the top; they are recorded in every entry, with your login.
#'
#' @param project Optional path of a calibration project to open.
#' @return A Shiny app object; printing it, as at the console, runs it.
#' @examples
#' if (interactive() && requireNamespace("shiny", quietly = TRUE)) {
#'   calibration_app()
#' }
#' @export
calibration_app <- function(project = NULL) {
  .check(requireNamespace("shiny", quietly = TRUE),
         "The calibration app needs the shiny package: install.packages(\"shiny\")")
  shiny::shinyApp(.app_ui(project), .app_server(project))
}

# ---- Helpers -----------------------------------------------------------------------------

# Every numeric parameter a calibrator may adjust, zeros included.
.editable <- function(key, v) {
  is.numeric(v) && length(v) == 1L && !key %in% c("area_km2", "dt") &&
    !grepl("(rtol|atol)$", key)
}

.editable_paths <- function(config, prefix = NULL) {
  out <- character(0)
  for (n in names(config)) {
    key <- paste(c(prefix, n), collapse = ".")
    v <- config[[n]]
    if (is.list(v)) out <- c(out, .editable_paths(v, key)) else if (.editable(key, v)) {
      out <- c(out, key)
    }
  }
  out
}

.input_id <- function(path) paste0("p_", gsub(".", "__", path, fixed = TRUE))

.node_choices <- function(nodes, headline) {
  if (!length(nodes)) return(character(0))
  labels <- vapply(nodes, function(e) {
    score <- .num_or_na(e$scores[[headline]])
    sprintf("%s  %s  %s %.4g", e$id, gsub("_", " ", e$type), headline, score)
  }, character(1))
  stats::setNames(vapply(nodes, function(e) e$id, character(1)), labels)
}

# Window bounds typed as text: whole numbers are rows, anything else a time.
.window_input <- function(start, end) {
  values <- trimws(c(start, end))
  if (!all(nzchar(values))) return(NULL)
  if (all(grepl("^[0-9]+$", values))) as.numeric(values) else values
}

# Thresholds typed as lines of "name, value, unit".
.parse_thresholds <- function(text) {
  lines <- trimws(strsplit(text %||% "", "\n", fixed = TRUE)[[1L]])
  lines <- lines[nzchar(lines)]
  if (!length(lines)) return(NULL)
  parts <- lapply(strsplit(lines, ",", fixed = TRUE), trimws)
  .check(all(lengths(parts) == 3L), "Write each threshold as: name, value, flow or level")
  data.frame(name = vapply(parts, `[`, "", 1L), value = as.numeric(vapply(parts, `[`, "", 2L)),
             unit = vapply(parts, `[`, "", 3L))
}

# The scores worth showing in a table: the scorecard and the main threshold scores.
.shown_scores <- function(names) {
  main <- c("pod", "far", "csi", "crossing_error_h")
  keep <- !grepl(":", names, fixed = TRUE) | sub(":.*$", "", names) %in% main
  names[keep]
}

.score_table <- function(parent, trial) {
  names <- .shown_scores(names(trial))
  p <- vapply(names, function(n) .num_or_na(parent[[n]]), numeric(1))
  t <- vapply(names, function(n) .num_or_na(trial[[n]]), numeric(1))
  data.frame(score = names, parent = signif(p, 5), trial = signif(t, 5),
             change = signif(t - p, 3), row.names = NULL)
}

.plot_compare <- function(time, observed, runs, xlim = NULL) {
  graphics::par(mar = c(3, 4.2, 0.6, 0.6))
  cols <- c(.pal[["blue"]], .pal[["orange"]])[seq_along(runs)]
  top <- max(c(observed, unlist(runs)), na.rm = TRUE)
  graphics::plot(time, observed, type = "n", ylim = c(0, top), xlim = xlim, xlab = "",
                 ylab = "Flow (m3/s)")
  graphics::points(time, observed, pch = 16, cex = 0.25, col = .pal[["grey"]])
  for (i in seq_along(runs)) {
    graphics::lines(time, runs[[i]], col = cols[[i]], lwd = 1.4)
  }
  graphics::legend("topright", c("observed", names(runs)), bty = "n", cex = 0.85,
                   col = c(.pal[["grey"]], cols),
                   pch = c(16, rep(NA, length(runs))), lty = c(NA, rep(1, length(runs))))
}

# ---- UI ----------------------------------------------------------------------------------

.text_area <- function(id, label, placeholder = "") {
  shiny::textAreaInput(id, label, rows = 3, width = "100%", placeholder = placeholder)
}

.app_ui <- function(project) {
  roles <- c(Custodian = "custodian", Steward = "steward",
             "Delegated Steward" = "delegated_steward")
  role <- .setting("pdmS7.role", "PDMS7_ROLE")
  identity <- shiny::fluidRow(
    shiny::column(3, shiny::textInput("user", "Your name", .setting("pdmS7.user", "PDMS7_USER"))),
    shiny::column(2, shiny::selectInput("role", "Role", roles,
                                        if (role %in% roles) role else "custodian")),
    shiny::column(5, shiny::textInput("project_path", "Project folder", project %||% "",
                                      width = "100%")),
    shiny::column(2, shiny::br(), shiny::actionButton("open", "Open project")),
    shiny::column(12, shiny::uiOutput("status"))
  )
  shiny::navbarPage(
    "pdmS7 calibration", id = "tabs", header = shiny::div(class = "container-fluid", identity),
    shiny::tabPanel("Setup", .ui_setup()),
    shiny::tabPanel("Trial", .ui_trial()),
    shiny::tabPanel("History", .ui_history()),
    shiny::tabPanel("Report", .ui_report()),
    shiny::tabPanel("Sign-off", .ui_signoff())
  )
}

.ui_setup <- function() {
  start <- shiny::column(
    4,
    shiny::h3("1. Start a project"),
    shiny::textInput("new_path", "New project folder", width = "100%"),
    shiny::textInput("catchment", "Catchment"),
    shiny::textInput("gauge", "Gauge"),
    shiny::textInput("purpose", "Purpose", width = "100%"),
    shiny::numericInput("area", "Area (km2)", NA, min = 0),
    shiny::textInput("owner", "Owner"),
    shiny::textInput("steward", "Steward"),
    .text_area("description", "Description"),
    shiny::actionButton("start", "Start project", class = "btn-primary")
  )
  register <- shiny::column(
    4,
    shiny::h3("2. Register data"),
    shiny::textInput("forcing_path", "Forcing CSV (time, rain, pet)", width = "100%"),
    shiny::textInput("observed_path", "Observed flow CSV (q_m3s)", width = "100%"),
    shiny::p("Windows as row numbers, or times such as 2010-01-01."),
    shiny::splitLayout(
      shiny::textInput("cal_start", "Calibration from"),
      shiny::textInput("cal_end", "to")
    ),
    shiny::splitLayout(
      shiny::textInput("val_start", "Validation from"),
      shiny::textInput("val_end", "to")
    ),
    shiny::splitLayout(
      shiny::textInput("test_start", "Final test from (optional)"),
      shiny::textInput("test_end", "to")
    ),
    .text_area("thresholds", "Thresholds, one per line: name, value, flow or level",
               "Flood Alert, 12.5, flow\nFlood Warning, 1.85, level"),
    shiny::textInput("rating_path", "Rating CSV (stage_m, q_m3s), for level thresholds",
                     width = "100%"),
    shiny::splitLayout(
      shiny::numericInput("event_tolerance", "Timing tolerance (h)", 6, 0),
      shiny::numericInput("event_gap", "Merge gap (h)", 24, 0),
      shiny::numericInput("event_min", "Minimum duration (h)", 0, 0)
    ),
    shiny::selectizeInput("headline", "Headline score", names(.headline_scores()),
                          options = list(create = TRUE)),
    shiny::helpText("Or type a threshold score such as csi:Flood Warning."),
    shiny::splitLayout(
      shiny::numericInput("log_offset", "Log offset (m3/s)", 0.01),
      shiny::numericInput("soil_fraction", "Initial soil fraction", 0.5)
    ),
    shiny::checkboxInput("copy", "Copy data into the project", TRUE),
    .text_area("register_reasoning", "Notes on the data"),
    shiny::actionButton("register", "Register data", class = "btn-primary")
  )
  structure <- shiny::column(
    4,
    shiny::h3("3. Select the structure"),
    shiny::selectInput("preset", "Start from preset", pdm_presets()),
    shiny::textInput("config_path", "or a YAML configuration file", width = "100%"),
    shiny::p("The project's area is applied to the preset."),
    .text_area("structure_reasoning", "Why this structure?"),
    shiny::actionButton("structure", "Select structure", class = "btn-primary")
  )
  shiny::fluidRow(start, register, structure)
}

.ui_trial <- function() {
  calibration <- shiny::tagList(
    shiny::h4("Automatic calibration"),
    shiny::selectizeInput("calib_params", "Parameters", character(0), multiple = TRUE),
    shiny::radioButtons("calib_method", "Optimiser",
                        c("Gradient (L-BFGS-B)" = "lbfgsb", "Nelder-Mead" = "nelder_mead"),
                        inline = TRUE),
    shiny::selectizeInput("calib_thresholds", "Threshold objective (Nelder-Mead only)",
                          character(0), multiple = TRUE),
    shiny::splitLayout(
      shiny::numericInput("calib_weight", "Threshold weight", 1, 0),
      shiny::selectInput("calib_score", "Threshold score", names(.threshold_headlines), "csi")
    ),
    shiny::sliderInput("calib_range", "Bounds: value times 1 +/-", 0.05, 0.9, 0.5, 0.05),
    shiny::splitLayout(
      shiny::numericInput("calib_starts", "Starts", 3, 1),
      shiny::numericInput("calib_seed", "Seed", 1),
      shiny::numericInput("calib_maxit", "Iterations", 100, 1)
    ),
    .text_area("calib_reasoning", "Reasoning"),
    shiny::actionButton("run_calib", "Run and log calibration")
  )
  side <- shiny::sidebarPanel(
    width = 4,
    shiny::selectInput("parent", "Start from run", character(0), width = "100%"),
    shiny::uiOutput("params"),
    shiny::actionButton("preview", "Preview", class = "btn-primary"),
    shiny::hr(),
    shiny::radioButtons("verdict", "Verdict", c("better", "worse", "inconclusive"),
                        "inconclusive", inline = TRUE),
    .text_area("trial_reasoning", "Reasoning", "What did you change, and why?"),
    shiny::actionButton("save_trial", "Save trial", class = "btn-success"),
    shiny::hr(),
    shiny::h4("Note"),
    .text_area("note", "Note"),
    shiny::actionButton("save_note", "Save note"),
    shiny::hr(),
    calibration
  )
  brush <- shiny::brushOpts("hydro_brush", direction = "x", resetOnNew = TRUE)
  main <- shiny::mainPanel(
    width = 8,
    shiny::plotOutput("hydrograph", height = "380px", dblclick = "hydro_reset", brush = brush),
    shiny::helpText("Calibration window. Drag to zoom; double-click to reset."),
    shiny::tableOutput("scores")
  )
  shiny::sidebarLayout(side, main)
}

.ui_history <- function() {
  compare <- shiny::column(
    3,
    shiny::selectInput("compare_a", "Compare", character(0), width = "100%"),
    shiny::selectInput("compare_b", "with", character(0), width = "100%")
  )
  compared <- shiny::column(
    9,
    shiny::plotOutput("compare_plot", height = "320px"),
    shiny::tableOutput("compare_scores")
  )
  propose <- shiny::column(
    6,
    shiny::h4("Propose a candidate"),
    shiny::selectInput("candidate_entry", "Run", character(0), width = "100%"),
    .text_area("candidate_reasoning", "Why this run?"),
    shiny::actionButton("propose", "Propose candidate", class = "btn-primary")
  )
  validate <- shiny::column(
    6,
    shiny::h4("Validate the latest candidate"),
    .text_area("validation_reasoning", "Your reading of the validation"),
    shiny::actionButton("validate", "Run validation", class = "btn-primary"),
    shiny::tableOutput("validation_scores"),
    shiny::h4("Final test"),
    shiny::helpText("Scored once, after the structure and parameters are final."),
    .text_area("test_reasoning", "Your reading of the test"),
    shiny::actionButton("final_test", "Run final test", class = "btn-warning")
  )
  shiny::fluidRow(
    shiny::column(12, shiny::plotOutput("path", height = "320px")),
    shiny::column(12, shiny::tableOutput("trials")),
    compare, compared, propose, validate
  )
}

.ui_report <- function() {
  shiny::fluidRow(shiny::column(
    12,
    shiny::checkboxInput("report_rerun", "Rerun every logged run", TRUE),
    shiny::checkboxInput("report_sensitivity", "Include parameter sensitivity", TRUE),
    shiny::actionButton("build", "Build report", class = "btn-primary"),
    shiny::downloadButton("download", "Download report"),
    shiny::actionButton("verify", "Check integrity"),
    shiny::tableOutput("integrity")
  ))
}

.ui_signoff <- function() {
  reviewed <- c("Integrity checks" = "integrity", "Data and scoring windows" = "data",
                "The calibration path and reasoning" = "calibration_path",
                "The validation" = "validation")
  review <- shiny::column(
    6,
    shiny::h3("Review"),
    shiny::uiOutput("signoff_summary"),
    shiny::checkboxGroupInput("checklist", "I have reviewed", reviewed),
    .text_area("statement", "Sign-off statement"),
    shiny::actionButton("sign", "Sign off", class = "btn-success")
  )
  reopen <- shiny::column(
    6,
    shiny::h3("Reopen"),
    .text_area("reopen_reason", "Why reopen?"),
    shiny::actionButton("reopen", "Reopen project", class = "btn-warning")
  )
  shiny::fluidRow(review, reopen)
}
