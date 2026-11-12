# ============================================================ #
# Tool:         project_report
# Description:  Calibration log report: integrity, data, path, candidate, sign-off
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration report
#               2026-11-10 - Each window's figures show that window (they all showed the
#                            last); hydrographs of the held-back wettest years; the ten
#                            largest events
# Tier:         1
# Inputs:       A calibration project folder
# Outputs:      report/report.html (self-contained), report/report.md, report/figures
# Dependencies: graphics; grDevices; data.table
# ============================================================ #

.pal <- c(blue = "#236b83", orange = "#a26421", green = "#5b8c3a", purple = "#8a3b6b",
          grey = "#444444", red = "#b23b3b", light = "#9aa7b0")

#' Build the calibration report
#'
#' Writes a report generated entirely from the log: never edit it by hand, rebuild it. The
#' HTML file is self-contained, with its figures embedded, so it can be emailed or attached
#' to a review. A Markdown copy with separate figure files suits projects kept under version
#' control.
#'
#' Sections, in reading order: project and roles; integrity (any failure is flagged at the
#' top); data and scoring windows; model structure; the calibration path, as a tree of runs
#' and a table of every run with its changes, scores, verdict and reasoning; the candidate,
#' with hydrographs, flow-duration curves and a scatter for each window, a hydrograph for each
#' held-back wettest year once tested, and the ten largest events of the record in any window,
#' tabled and drawn with their rain; parameter
#' sensitivity; sign-off history; and an appendix with the final configuration and the
#' entry checksums.
#'
#' Sensitivity varies each nonzero numeric parameter of the candidate, one at a time, by
#' factors from `1 - sensitivity_range` to `1 + sensitivity_range`, and scores the headline
#' metric on the calibration window. A flat curve means the data do not determine that
#' parameter. It costs `sensitivity_steps` model runs per parameter.
#'
#' @param project Path of a calibration project folder.
#' @param output Folder to write to; created if needed.
#' @param rerun If `TRUE`, the integrity section reruns every logged run.
#' @param sensitivity `TRUE`, `FALSE`, or `NULL` for on when the latest candidate has been
#'   validated, which is when a Steward reviews the project.
#' @param sensitivity_range,sensitivity_steps Range of the multiplicative variation and the
#'   number of points per parameter.
#' @return The path of `report.html`, invisibly.
#' @seealso [calibration_log], [verify_project()]
#' @export
build_report <- function(project, output = file.path(project, "report"), rerun = TRUE,
                         sensitivity = NULL, sensitivity_range = 0.5, sensitivity_steps = 9L) {
  # The report follows the order of the work: integrity, data, structure, comparison, the
  # calibration path, the candidate with its validation and test, optional sensitivity, the
  # sign-off and an appendix of every entry. Integrity is checked first, with reruns by default.
  path <- .project_path(project)
  .check(.scalar(sensitivity_range, 0, 0.95, strict = TRUE),
         "sensitivity_range must lie between 0 and 0.95")
  .check(.scalar(sensitivity_steps, 3) && sensitivity_steps == floor(sensitivity_steps),
         "sensitivity_steps must be a whole number of at least 3")
  entries <- .read_entries(path)
  info <- .project_info(entries)
  checks <- verify_project(path, rerun = rerun)
  candidate <- .latest(entries, "candidate")
  validation <- .latest(entries, "validation")
  validated <- !is.null(candidate) && !is.null(validation) &&
    identical(validation$candidate, candidate$id)
  if (is.null(sensitivity)) sensitivity <- validated
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  unlink(file.path(output, "figures"), recursive = TRUE)
  blocks <- c(
    .rpt_header(info, entries),
    .rpt_integrity(checks, rerun),
    .rpt_data(path, entries),
    .rpt_structure(entries),
    .rpt_comparison(path, entries),
    .rpt_path(entries, candidate),
    .rpt_candidate(path, entries, candidate, validation, validated),
    if (isTRUE(sensitivity) && !is.null(candidate)) {
      .rpt_sensitivity(path, entries, candidate, sensitivity_range, sensitivity_steps)
    },
    .rpt_signoff(entries),
    .rpt_appendix(entries, candidate)
  )
  file <- .render_report(blocks, output, paste("Calibration report:", info$id))
  logger::log_info("Report written to {file}")
  invisible(file)
}

# ---- Sections ----------------------------------------------------------------------------

# Title, project details, status, and who did what: the people and roles that appear in the log.
.rpt_header <- function(info, entries) {
  status <- .project_status(entries)
  custodians <- unique(unlist(lapply(entries, function(e) {
    if (e$author$role == "custodian") e$author$name
  })))
  table <- data.frame(
    item = c("Project", "Catchment", "Gauge", "Area", "Purpose", "Status", "Owner",
             "Steward", "Custodians", "Started", "Last entry"),
    value = c(info$id, info$catchment, info$gauge, paste(info$area_km2, "km2"), info$purpose,
              gsub("_", " ", status), info$owner, info$steward,
              paste(custodians, collapse = ", "), entries[[1L]]$timestamp,
              entries[[length(entries)]]$timestamp)
  )
  c(list(.blk_h(paste("Calibration report:", info$id), 1L),
         .blk_p(paste("Generated from the calibration log on", .timestamp(),
                      "by pdmS7", as.character(utils::packageVersion("pdmS7")),
                      "- rebuild it rather than editing it."))),
    if (nzchar(info$description %||% "")) list(.blk_p(info$description)),
    list(.blk_table(table)))
}

# a unless it is NULL, then b. Used throughout the package for optional fields and defaults.
`%||%` <- function(a, b) if (is.null(a)) b else a

# Green or red: whether every integrity check passed, with the failing rows if not.
.rpt_integrity <- function(checks, rerun) {
  failed <- checks[!checks$ok]
  message <- if (nrow(failed)) {
    sprintf("%d of %d integrity checks FAILED. Do not rely on this calibration until resolved.",
            nrow(failed), nrow(checks))
  } else {
    sprintf("All %d integrity checks passed%s.", nrow(checks),
            if (rerun) ", including reruns of every logged run" else " (runs not repeated)")
  }
  c(list(.blk_h("Integrity"), .blk_alert(message, !nrow(failed))),
    if (nrow(failed)) list(.blk_table(failed, "Failed checks")),
    list(.blk_p(paste(
      "Each entry holds the checksum of the one before it, every data file is checked",
      "against the checksum taken when it was registered, and every run records a checksum",
      "of its output. An edit, deletion or insertion, a changed file, or a run that no",
      "longer reproduces is reported here."
    ))))
}

# Each data registration: files and checksums, the data summary, the windows, and a plot of the
# whole record with the windows shaded.
.rpt_data <- function(path, entries) {
  regs <- Filter(function(e) e$type == "data_registered", entries)
  out <- list(.blk_h("Data"))
  for (r in regs) {
    s <- r$summary
    card <- r$scorecard
    files <- data.frame(
      series = names(r$data),
      stored = vapply(r$data, function(d) d$stored, character(1)),
      copied = vapply(r$data, function(d) isTRUE(d$copied), logical(1)),
      md5 = vapply(r$data, function(d) d$md5, character(1)), row.names = NULL
    )
    windows <- data.frame(
      window = c("warm-up", "calibration", "validation", "test"),
      rows = c(if (card$warmup_rows) paste0("1-", card$warmup_rows) else "none",
               .window_text(card$calibration, FALSE), .window_text(card$validation, FALSE),
               .window_text(card$test, FALSE)),
      period = c("", .window_text(card$calibration, TRUE), .window_text(card$validation, TRUE),
                 .window_text(card$test, TRUE))
    )
    quality <- data.frame(
      item = c("Rows", "Period", "Time step", "Observed missing", "Longest gap",
               "Mean observed flow", "Highest observed flow"),
      value = c(s$rows, paste(s$start %||% "", "to", s$end %||% ""),
                if (is.null(s$step_hours)) "not given" else paste(s$step_hours, "h"),
                s$observed_missing, paste(s$observed_longest_gap, "steps"),
                sprintf("%.3g m3/s", s$observed_mean_m3s), sprintf("%.3g m3/s", s$observed_max_m3s))
    )
    out <- c(out, list(
      .blk_h(paste("Registration", r$id, "by", r$author$name, "on",
                   substr(r$timestamp, 1, 10)), 3L),
      .blk_table(files, "Files"), .blk_table(quality, "Quality"),
      .blk_table(windows, paste0("Scoring windows. Headline metric: ", card$headline,
                                 ". The soil store starts at ", card$soil_fraction,
                                 " of capacity."))
    ))
    if (length(r$preparation)) {
      prep <- do.call(rbind, lapply(r$preparation, as.data.frame))
      out <- c(out, list(.blk_table(prep, paste(
        "Preparation: what was done to the series before registration, as noted by the",
        "preparation functions."
      ))))
    }
    out <- c(out, .rpt_held(r))
    if (length(card$thresholds)) {
      out <- c(out, list(.blk_table(.threshold_definitions(card), paste0(
        "Thresholds. Events matched within ", card$events$tolerance_h, " h; exceedances less ",
        "than ", card$events$gap_h, " h apart are one event."
      ))))
    }
    if (nzchar(r$reasoning %||% "")) out <- c(out, list(.blk_p(r$reasoning)))
  }
  latest <- .latest(entries, "data_registered")
  if (!is.null(latest)) {
    data <- tryCatch(.load_registration(path, latest), error = function(e) NULL)
    if (!is.null(data)) {
      caption <- paste("Observed flow, with the calibration (blue) and validation (orange)",
                       "windows; held-back wettest years in grey")
      draw <- function() .plot_record(data, latest$scorecard)
      out <- c(out, list(.blk_fig("observed", draw, caption, height = 3.2)))
    }
  }
  out
}

# The latest structure comparison, if one was run: its ranking table and a chart.
.rpt_comparison <- function(path, entries) {
  has <- any(vapply(entries, function(e) !is.null(e$comparison), logical(1)))
  if (!has) return(NULL)
  table <- structure_comparison(path)
  headline <- attr(table, "headline")
  list(
    .blk_h("Structure comparison"),
    .blk_p(paste0(
      "Comparison ", attr(table, "comparison"), ": each structure was calibrated alike and is ",
      "ranked by its ", headline, " on the validation window, which no calibration saw. ",
      "The change from calibration to validation shows whether extra parameters earned ",
      "their place."
    )),
    .blk_table(as.data.frame(table), "Structures, best first"),
    .blk_fig("structures", function() .plot_structures(table, headline),
             paste("Calibration (open) and validation (filled)", headline, "for each structure"),
             height = 0.45 * nrow(table) + 1.2)
  )
}

# Calibration against validation headline score for each compared structure.
.plot_structures <- function(table, headline) {
  n <- nrow(table)
  graphics::par(mar = c(4, 11, 0.6, 0.6))
  values <- c(table$calibration, table$validation)
  graphics::plot(NA, xlim = range(values, na.rm = TRUE), ylim = c(0.5, n + 0.5), yaxt = "n",
                 xlab = headline, ylab = "")
  graphics::axis(2, at = n:1, labels = table$structure, las = 1, cex.axis = 0.85)
  graphics::segments(table$calibration, n:1, table$validation, n:1, col = .pal[["light"]])
  graphics::points(table$calibration, n:1, pch = 1, col = .pal[["blue"]], cex = 1.3)
  graphics::points(table$validation, n:1, pch = 16, col = .pal[["blue"]], cex = 1.3)
}

# "rows 121 to 700 (2021-01-06 to 2021-01-30)" for a window.
.window_text <- function(w, times) {
  if (is.null(w)) return("not set")
  if (times) paste(w$start %||% "", "to", w$end %||% "") else paste0(w$first_row, "-", w$last_row)
}

# The components of a configuration, one row each; for a multi-zone configuration, one set of
# rows per zone, with its share of the area.
.structure_table <- function(cfg) {
  one <- function(c) {
    data.frame(
      component = c("Soil store", "Recharge", "Surface routing", "Groundwater routing"),
      choice = c(c$distribution$type %||% "pareto", c$recharge$type %||% "standard",
                 c$surface$type %||% "cascade",
                 paste(c$groundwater$type %||% "cubic", c$groundwater$solver %||% ""))
    )
  }
  if (!.is_multizone_config(cfg)) return(one(cfg))
  shares <- vapply(cfg$zones[-1], function(z) z$share, numeric(1))
  shares <- c(1 - sum(shares), shares)
  do.call(rbind, lapply(seq_along(cfg$zones), function(i) {
    t <- one(cfg$zones[[i]])
    t$component <- paste0(names(cfg$zones)[i], " zone (", format(signif(shares[i], 3)),
                          " of area): ", t$component)
    t
  }))
}

# Every structure selection, with its configuration and reasoning.
.rpt_structure <- function(entries) {
  structures <- Filter(function(e) e$type == "structure_selected", entries)
  out <- list(.blk_h("Model structure"))
  for (s in structures) {
    table <- .structure_table(s$configuration)
    out <- c(out, list(
      .blk_h(paste("Entry", s$id, "by", s$author$name, "on", substr(s$timestamp, 1, 10)), 3L),
      .blk_table(table), .blk_p(s$reasoning)
    ))
  }
  out
}

# The calibration path: every structure, trial and automatic calibration with its parent, its
# changes or bounds, its headline score and its verdict, as a chart and a table, then the start
# results of each automatic calibration and the notes.
.rpt_path <- function(entries, candidate) {
  nodes <- Filter(function(e) e$type %in% .model_entry_types, entries)
  if (!length(nodes)) return(list(.blk_h("Calibration path"), .blk_p("No runs logged yet.")))
  headline <- .latest(entries, "data_registered")$scorecard$headline
  run_row <- function(e) {
    changes <- if (e$type == "auto_calibration") .bounds_text(e) else .changes_text(e$changes)
    data.table::data.table(
      entry = e$id, type = gsub("_", " ", e$type), parent = .text_or_na(e$parent),
      by = e$author$name, date = substr(e$timestamp, 1, 10), changes = .text_or_na(changes),
      headline = .num_or_na(e$scores[[headline]]),
      volume_error = .num_or_na(e$scores$volume_error),
      verdict = .text_or_na(e$verdict), reasoning = .text_or_na(e$reasoning)
    )
  }
  runs <- data.table::rbindlist(lapply(nodes, run_row))
  data.table::setnames(runs, "headline", headline)
  notes <- Filter(function(e) e$type == "note", entries)
  out <- list(
    .blk_h("Calibration path"),
    .blk_fig("path", function() .plot_path(nodes, headline, candidate),
             paste("Every run by its", headline, "on the calibration window. Lines join each",
                   "run to its parent; colour shows the verdict; the ring marks the candidate.")),
    .blk_table(runs, "Every run, in order")
  )
  for (a in Filter(function(e) e$type == "auto_calibration", nodes)) {
    starts <- as.data.frame(lapply(a$start_results, unlist))
    stage <- if (is.null(a$stage)) "" else paste0(" (stage ", a$stage, ")")
    out <- c(out, list(.blk_table(starts, paste0("Automatic calibration ", a$id, stage, ": ",
                                                 a$objective_name %||% a$objective, " with ",
                                                 a$starts, " start(s)"))))
  }
  if (length(notes)) {
    out <- c(out, list(.blk_h("Notes", 3L), .blk_list(vapply(notes, function(n) {
      paste0(n$id, " (", n$author$name, ", ", substr(n$timestamp, 1, 10), "): ", n$text,
             if (!is.null(n$refers_to)) paste0(" [about entry ", n$refers_to, "]") else "")
    }, character(1)))))
  }
  out
}

# "fc in [0.6, 1.6]; surface.k1 in [0.5, 72]" for an automatic calibration entry.
.bounds_text <- function(e) {
  paste(vapply(names(e$bounds$lower), function(n) {
    sprintf("%s in [%s, %s]", n, format(e$bounds$lower[[n]]), format(e$bounds$upper[[n]]))
  }, character(1)), collapse = "; ")
}

# The candidate: its scores on every window side by side, hydrographs and flow-duration curves
# for each window scored, and the threshold section if thresholds are registered.
.rpt_candidate <- function(path, entries, candidate, validation, validated) {
  out <- list(.blk_h("Candidate"))
  if (is.null(candidate)) return(c(out, list(.blk_p("No candidate proposed yet."))))
  out <- c(out, list(.blk_p(paste0(
    "Entry ", candidate$id, " proposes the parameters of entry ", candidate$entry, " (",
    candidate$author$name, ", ", substr(candidate$timestamp, 1, 10), "): ", candidate$reasoning
  ))))
  series <- data.table::fread(file.path(path, candidate$series$file))
  registration <- .find_entry(entries, candidate$registration)
  card <- registration$scorecard
  core <- !grepl(":", names(candidate$scores), fixed = TRUE)
  scores <- data.frame(score = names(candidate$scores)[core],
                       calibration = vapply(candidate$scores[core], .num_or_na, numeric(1)))
  if (validated) {
    scores$validation <- vapply(validation$validation_scores[core], .num_or_na, numeric(1))
    out <- c(out, list(.blk_p(paste0("Validated in entry ", validation$id, " (",
                                     validation$author$name, "): ", validation$reasoning))))
  } else {
    out <- c(out, list(.blk_alert("The candidate has not been validated.", FALSE)))
  }
  test <- .candidate_test(entries, candidate)
  if (!is.null(test)) {
    scores <- .test_columns(scores, test)
    out <- c(out, list(.blk_p(paste0(
      "Tested once, after every choice was made, in entry ", test$id, " (", test$author$name,
      "): ", test$reasoning
    ))))
  } else if (.has_test(card)) {
    out <- c(out, list(.blk_p(paste(
      "A test window or held-back years are registered but have not been scored. They are",
      "scored once, by test_candidate(), after the structure and parameters are final."
    ))))
  }
  out <- c(out, list(.blk_table(scores, "Scorecard")))
  if (!is.null(test$wettest)) out <- c(out, .rpt_wettest(test$wettest, card))
  if (length(card$thresholds)) {
    out <- c(out, .rpt_thresholds(card, candidate$scores,
                                  if (validated) validation$validation_scores,
                                  if (!is.null(test)) test$test_scores))
  }
  c(out, .rpt_candidate_figures(path, series, card, validated, test, registration, candidate))
}

# The candidate's figures: each window, each held-back wettest year once tested, and the largest
# events. Each window's figures are built in a function of their own: figures are drawn after
# the report is assembled, and closures made in a loop would all see the loop's last window.
.rpt_candidate_figures <- function(path, series, card, validated, test, registration,
                                   candidate) {
  windows <- c("calibration", if (validated) "validation")
  out <- unlist(lapply(windows, function(w) .rpt_window(series, card, w)), recursive = FALSE)
  if (!is.null(test$wettest) && !is.null(test$series)) {
    out <- c(out, .rpt_wettest_figures(path, test, card))
  }
  c(out, .rpt_top_events(path, registration, candidate, series))
}

# A window's hydrograph, flow-duration curves and scatter.
.rpt_window <- function(series, card, w) {
  rows <- .window_rows(card[[w]])
  obs <- series$observed_m3s[rows]
  sim <- series$simulated_m3s[rows]
  time <- if ("time" %in% names(series)) .parse_time(series$time[rows]) else rows
  list(
    .blk_h(paste(tools::toTitleCase(w), "window"), 3L),
    .blk_fig(paste0("hydrograph-", w), function() .plot_hydrograph(time, obs, sim),
             paste("Observed and simulated flow over the", w, "window, linear and log scale"),
             height = 6),
    .blk_fig(paste0("fdc-", w), function() .plot_fdc_scatter(obs, sim),
             paste("Flow-duration curves and simulated against observed flow,", w, "window"),
             height = 3.8)
  )
}

# One hydrograph per held-back wettest year, from the run the test saved: the floods the model
# was never fitted to, beside the peaks table above.
.rpt_wettest_figures <- function(path, test, card) {
  series <- data.table::fread(file.path(path, test$series$file))
  figure <- function(y) {
    rows <- seq.int(y$first_row, y$last_row)
    obs <- series$observed_m3s[rows]
    sim <- series$simulated_m3s[rows]
    time <- if ("time" %in% names(series)) .parse_time(series$time[rows]) else rows
    .blk_fig(paste0("hydrograph-wettest-", y$water_year),
             function() .plot_hydrograph(time, obs, sim),
             paste("Observed and simulated flow in held-back water year", y$water_year,
                   "(scored once, by the test), linear and log scale"), height = 6)
  }
  c(list(.blk_h("Held-back wettest years", 3L)), lapply(.held_years(card), figure))
}

# The ten largest usable events of the record, whichever window they fall in, each with its rain,
# the observed flow and the candidate's: the floods that matter most, side by side.
.rpt_top_events <- function(path, registration, candidate, series, n = 10L) {
  checks <- tryCatch(calibration_checks(path, candidate$id, top = n),
                     error = function(e) NULL)
  if (is.null(checks)) return(list())
  ev <- as.data.frame(checks$events)
  use <- if ("use" %in% names(ev)) ev$use else rep(TRUE, nrow(ev))
  ev <- ev[use & is.finite(ev$peak_error), ]
  if (!nrow(ev)) return(list())
  ev <- ev[order(-ev$observed_peak), ][seq_len(min(n, nrow(ev))), ]
  rain <- .load_registration(path, registration)$forcing$rain
  dt <- candidate$configuration$dt %||% 1
  spec <- .top_events_spec(ev, series, rain, dt)
  table <- data.frame(window = ev$period, peak_m3s = signif(ev$observed_peak, 3),
                      simulated_m3s = signif(ev$simulated_peak, 3),
                      peak_error = sprintf("%+.0f%%", 100 * ev$peak_error),
                      timing_h = sprintf("%+.1f", ev$timing_error_h),
                      event_nse = round(ev$nse, 2))
  if ("time" %in% names(series)) {
    table <- cbind(peak = format(.parse_time(series$time[ev$peak_row]), "%d %b %Y %H:%M"),
                   table)
  }
  list(
    .blk_h("Largest events", 3L),
    .blk_table(table, paste(
      "The", nrow(ev), "largest events of the record by observed peak, in any window. A",
      "negative peak error is a peak too low; a negative timing error, a peak too early."
    )),
    .blk_fig("top-events", function() .draw_base(spec),
             paste("The", nrow(ev), "largest events: observed flow (dots), the candidate (line)",
                   "and rain (bars)"), height = 2.3 * ceiling(nrow(ev) / 2) + 0.8)
  )
}

# The panels of the largest events, in the house style of the event plots.
.top_events_spec <- function(ev, series, rain, dt) {
  has_time <- "time" %in% names(series)
  lead <- round(12 / dt)
  parts <- lapply(seq_len(nrow(ev)), function(e) {
    rows <- seq.int(max(1L, min(ev$rain_start[e], ev$flow_start[e]) - lead), ev$flow_end[e])
    x <- if (has_time) .parse_time(series$time[rows]) else rows
    obs <- series$observed_m3s[rows]
    sim <- series$simulated_m3s[rows]
    layers <- rbind(
      .layer(x, obs, "Observed", .pdm_roles[["observed"]], geom = "point", lwd = 1.1,
             panel = e),
      .layer(x, sim, "Candidate", .pdm_roles[["simulated"]], panel = e)
    )
    step <- if (has_time) dt * 3600 else 1
    when <- if (has_time) format(x[rows == ev$peak_row[e]][1], "%d %b %Y") else
      paste("row", ev$peak_row[e])
    list(series = layers,
         title = sprintf("%s (%s)  peak %+.0f%%, %+.1f h", when, ev$period[e],
                         100 * ev$peak_error[e], ev$timing_error_h[e]),
         rain = .rain_layer(x - step, x, rain[rows], max(c(obs, sim), na.rm = TRUE),
                            panel = e))
  })
  list(
    series = do.call(rbind, lapply(parts, `[[`, "series")),
    rain = do.call(rbind, lapply(parts, `[[`, "rain")), rain_axis = FALSE,
    panels = data.frame(panel = seq_along(parts), title = vapply(parts, `[[`, "", "title")),
    ncol = 2L, xlab = "", ylab = "Flow (m3/s)", log = "", title = "Largest events"
  )
}

# Adds the test window's and the held-back years' scores to the scorecard table, where scored.
.test_columns <- function(scores, test) {
  if (!is.null(test$test_scores)) {
    scores$test <- vapply(test$test_scores[scores$score], .num_or_na, numeric(1))
  }
  if (!is.null(test$wettest)) {
    scores$wettest_years <- vapply(test$wettest$scores[scores$score], .num_or_na, numeric(1))
  }
  scores
}

# A registration's held-back years and, when the highest gauged flow is given, how much of each
# window lies above it.
.rpt_held <- function(r) {
  card <- r$scorecard
  out <- list()
  years <- .held_years(card)
  if (length(years)) {
    table <- data.frame(
      water_year = vapply(years, function(y) y$water_year, ""),
      period = vapply(years, function(y) paste(y$start, "to", y$end), ""),
      peak_m3s = vapply(years, function(y) y$peak_m3s, 0)
    )
    out <- c(out, list(.blk_table(table, paste(
      "Held-back wettest years. No calibration, trial or validation scores them; the test",
      "scores them once, as a check on floods larger than those the model was fitted to."
    ))))
  }
  check <- r$rating_check
  if (!is.null(check)) {
    windows <- check$windows
    table <- data.frame(
      window = names(windows),
      steps_above = vapply(windows, function(w) w$steps_above, 0),
      share_above = sprintf("%.2f%%", 100 * vapply(windows, function(w) w$share_above, 0)),
      highest_m3s = vapply(windows, function(w) w$highest_m3s, 0), row.names = NULL
    )
    out <- c(out, list(.blk_table(table, sprintf(paste(
      "Observed flow above the highest gauged flow, %.4g m3/s. Above it the rating is",
      "extrapolated, so those flows are uncertain in size, though not in order."
    ), check$highest_gauged_m3s))))
  }
  out
}

# The test's held-back years: observed peak, the candidate's peak, and the range across the
# equally good parameter sets.
.rpt_wettest <- function(w, card) {
  years <- w$years
  table <- data.frame(
    water_year = vapply(years, function(y) y$water_year, ""),
    observed_peak = vapply(years, function(y) y$observed_peak_m3s, 0),
    candidate_peak = vapply(years, function(y) y$simulated_peak_m3s, 0),
    equally_good_low = vapply(years, function(y) y$spread_low_m3s, 0),
    equally_good_high = vapply(years, function(y) y$spread_high_m3s, 0)
  )
  if (!is.null(card$highest_gauged_m3s)) {
    table$observed_above_gauged <- vapply(years, function(y) isTRUE(y$above_gauged), TRUE)
  }
  spread <- if (w$sets > 0) {
    sprintf(paste("The range covers the candidate and %d parameter sets that scored within",
                  "%.3g of the best calibration %s."), w$sets, w$tolerance, card$headline)
  } else {
    paste("No equally good sets were recorded with the candidate's calibration (a manual",
          "trial or a structure comparison keeps none), so the range is the candidate alone.")
  }
  list(.blk_table(table, paste(
    "Peaks in the held-back wettest years, m3/s.", spread,
    "A wide range means the calibration cannot pin down floods of this size."
  )))
}

# The registered thresholds and event settings, as a table.
.threshold_definitions <- function(card) {
  data.frame(
    threshold = vapply(card$thresholds, function(t) t$name, character(1)),
    given = vapply(card$thresholds, function(t) {
      if (identical(t$source, "flow marker")) return("from the record")
      paste(format(t$value), if (t$unit == "level") "m" else "m3/s")
    }, character(1)),
    flow_m3s = vapply(card$thresholds, function(t) t$flow_m3s, numeric(1))
  )
}

# One row per threshold and window, from flattened "metric:name" scores.
.threshold_table <- function(card, scores, window) {
  metrics <- c("observed_events", "hits", "misses", "false_alarms", "pod", "far", "csi",
               "bias", "crossing_error_h", "peak_error", "duration_error_h", "csi_step", "ets_step")
  rows <- lapply(card$thresholds, function(t) {
    values <- lapply(metrics, function(m) .num_or_na(scores[[paste0(m, ":", t$name)]]))
    data.frame(threshold = t$name, window = window, stats::setNames(values, metrics),
               check.names = FALSE)
  })
  do.call(rbind, rows)
}

# Threshold scores for the candidate on each window, with the performance diagram.
.rpt_thresholds <- function(card, calibration, validation, test = NULL) {
  table <- rbind(.threshold_table(card, calibration, "calibration"),
                 if (!is.null(validation)) .threshold_table(card, validation, "validation"),
                 if (!is.null(test)) .threshold_table(card, test, "test"))
  table <- table[order(match(table$threshold, table$threshold)), ]
  list(
    .blk_h("Threshold crossings", 3L),
    .blk_p(paste(
      "Event scores count each episode above a threshold once, and match a simulated",
      "crossing to an observed one within the tolerance. Crossing and peak timing errors are",
      "simulated minus observed, so positive means late. Step scores (csi_step, ets_step)",
      "count every time step and penalise small timing errors twice."
    )),
    .blk_table(table, "Threshold scores"),
    .blk_fig("performance", function() .plot_performance(table),
             paste("Performance diagram: probability of detection against success ratio",
                   "(1 - false alarm ratio). Curves are critical success index; dashed lines",
                   "are frequency bias. Best is top right."),
             width = 5.5, height = 5.5)
  )
}

# One-at-a-time sensitivity: each tunable parameter scaled from 1 - range to 1 + range times its
# value, the others held, and the headline scored on the calibration window. Costs one model run
# per parameter per step, so it is on by default only once a candidate is validated.
.rpt_sensitivity <- function(path, entries, candidate, range, steps) {
  registration <- .find_entry(entries, candidate$registration)
  data <- .load_registration(path, registration)
  info <- .project_info(entries)
  headline <- registration$scorecard$headline
  params <- .numeric_paths(candidate$configuration)
  factors <- seq(1 - range, 1 + range, length.out = steps)
  curves <- lapply(params, function(p) {
    base <- .path_get(candidate$configuration, p)
    vapply(factors, function(f) {
      cfg <- .path_set(candidate$configuration, p, base * f)
      tryCatch(.run_registered(path, info, registration, cfg, data = data)$scores[[headline]],
               error = function(e) NA_real_)
    }, numeric(1))
  })
  names(curves) <- params
  list(
    .blk_h("Parameter sensitivity"),
    .blk_p(paste(
      "Each parameter of the candidate is varied alone, from", 1 - range, "to", 1 + range,
      "times its value, and the", headline, "is scored on the calibration window. A sharp",
      "peak at 1 means the data determine the parameter well; a flat line means they do not,",
      "and its value rests on judgement or prior knowledge. All panels share one scale;",
      "triangles mark values below it, and gaps are invalid parameter values."
    )),
    .blk_fig("sensitivity", function() .plot_sensitivity(curves, factors, headline),
             paste("Sensitivity of the", headline, "to each parameter"),
             height = 2.2 * ceiling(length(curves) / 4))
  )
}

# Nonzero numeric parameters, excluding area, time step and solver tolerances.
.tunable <- function(key, v) {
  is.numeric(v) && length(v) == 1L && v != 0 && !key %in% c("area_km2", "dt") &&
    !grepl("(rtol|atol)$", key)
}

# Every tunable numeric parameter of a configuration, as dotted paths.
.numeric_paths <- function(config, prefix = NULL) {
  out <- character(0)
  for (n in names(config)) {
    key <- paste(c(prefix, n), collapse = ".")
    v <- config[[n]]
    if (is.list(v)) {
      out <- c(out, .numeric_paths(v, key))
    } else if (.tunable(key, v)) {
      out <- c(out, key)
    }
  }
  out
}

# Every sign-off and reopen, with the checklist, statement or reason.
.rpt_signoff <- function(entries) {
  decisions <- Filter(function(e) e$type %in% c("sign_off", "reopen"), entries)
  out <- list(.blk_h("Sign-off"))
  if (!length(decisions)) return(c(out, list(.blk_p("Not yet signed off."))))
  decision_row <- function(e) {
    data.table::data.table(
      entry = e$id, action = gsub("_", " ", e$type), by = e$author$name,
      capacity = gsub("_", " ", e$author$role), login = .text_or_na(e$author$login),
      date = e$timestamp, candidate = .text_or_na(e$candidate),
      statement = .text_or_na(if (e$type == "sign_off") e$statement else e$reason)
    )
  }
  table <- data.table::rbindlist(lapply(decisions, decision_row))
  c(out, list(.blk_table(table)))
}

# The signed-off (or candidate) configuration as YAML, and a table of every entry.
.rpt_appendix <- function(entries, candidate) {
  final <- .latest(entries, "sign_off")
  config <- if (!is.null(final)) final$configuration else candidate$configuration
  entry_row <- function(e) {
    data.table::data.table(
      entry = e$id, type = e$type, by = e$author$name, role = e$author$role,
      login = .text_or_na(e$author$login), time = e$timestamp,
      pdmS7 = e$software$pdmS7, R = e$software$r, engine = e$software$engine, md5 = e$.md5
    )
  }
  table <- data.table::rbindlist(lapply(entries, entry_row))
  c(list(.blk_h("Appendix")),
    if (!is.null(config)) list(
      .blk_h(if (!is.null(final)) "Signed-off configuration" else "Candidate configuration", 3L),
      .blk_code(yaml::as.yaml(.yaml_ready(config)))
    ),
    list(.blk_h("Entries", 3L), .blk_table(table)))
}

# ---- Plots -------------------------------------------------------------------------------

# Keeps peaks visible when a long record is drawn: block maxima of about 4000 points.
# Plotting every 15-minute value of a decade would be slow and would hide nothing a block
# maximum does not show; a block mean would flatten the floods a reviewer is looking for.
.thin <- function(x, y) {
  n <- length(y)
  if (n <= 8000L) return(list(x = x, y = y))
  k <- ceiling(n / 4000)
  block <- (seq_len(n) - 1L) %/% k
  keep <- vapply(split(seq_len(n), block), function(i) {
    i[which.max(replace(y[i], !is.finite(y[i]), -Inf))]
  }, integer(1))
  list(x = x[keep], y = y[keep])
}

# The whole observed record, thinned for plotting, with calibration, validation and test windows
# shaded in different colours.
.plot_record <- function(data, card) {
  graphics::par(mar = c(3, 4.2, 0.6, 0.6))
  t <- if ("time" %in% names(data$forcing)) data$forcing$time else seq_along(data$observed)
  th <- .thin(t, data$observed)
  graphics::plot(th$x, th$y, type = "n", xlab = "", ylab = "Observed flow (m3/s)")
  shade <- function(w, col) {
    if (is.null(w)) return()
    graphics::rect(t[w$first_row], graphics::par("usr")[3], t[w$last_row],
                   graphics::par("usr")[4], col = col, border = NA)
  }
  shade(card$calibration, grDevices::adjustcolor(.pal[["blue"]], 0.15))
  shade(card$validation, grDevices::adjustcolor(.pal[["orange"]], 0.2))
  for (y in .held_years(card)) shade(y, grDevices::adjustcolor(.pal[["grey"]], 0.35))
  graphics::lines(th$x, th$y, col = .pal[["grey"]], lwd = 0.8)
  if (!is.null(card$highest_gauged_m3s)) {
    graphics::abline(h = card$highest_gauged_m3s, lty = 2, col = .pal[["grey"]])
  }
}

.verdict_colour <- function(e) {
  if (e$type == "auto_calibration") return(.pal[["blue"]])
  if (e$type == "structure_selected") return(.pal[["grey"]])
  switch(e$verdict %||% "inconclusive", better = .pal[["green"]], worse = .pal[["red"]],
         .pal[["light"]])
}

# Each run plotted by its order in the log against its headline score, joined to its parent;
# colour shows the verdict and a ring marks the candidate.
.plot_path <- function(nodes, headline, candidate) {
  ids <- vapply(nodes, function(e) e$id, character(1))
  y <- vapply(nodes, function(e) .num_or_na(e$scores[[headline]]), numeric(1))
  x <- seq_along(nodes)
  graphics::par(mar = c(4, 4.2, 0.6, 0.6))
  if (!any(is.finite(y))) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, paste("No run has a defined", headline))
    return(invisible())
  }
  span <- range(y, na.rm = TRUE)
  pad <- max(diff(span), 1e-6)
  graphics::plot(x, y, type = "n", xlab = "Run, in the order logged", ylab = headline,
                 xaxt = "n", ylim = span + c(-0.3, 0.1) * pad)
  graphics::axis(1, at = x, labels = ids, cex.axis = 0.75, las = 2)
  for (i in x) {
    parent <- nodes[[i]]$parent
    if (!is.null(parent) && parent %in% ids) {
      j <- match(parent, ids)
      graphics::segments(x[j], y[j], x[i], y[i], col = .pal[["light"]])
    }
  }
  shapes <- c(structure_selected = 15, trial = 16, auto_calibration = 17)
  graphics::points(x, y, pch = shapes[vapply(nodes, function(e) e$type, character(1))],
                   col = vapply(nodes, .verdict_colour, character(1)), cex = 1.4)
  if (!is.null(candidate)) {
    k <- match(candidate$entry, ids)
    graphics::points(x[k], y[k], pch = 1, cex = 2.6, lwd = 2, col = .pal[["purple"]])
  }
  graphics::legend("bottomright", c("structure", "better", "worse", "inconclusive",
                                    "automatic", "candidate"),
                   pch = c(15, 16, 16, 16, 17, 1),
                   col = c(.pal[["grey"]], .pal[["green"]], .pal[["red"]], .pal[["light"]],
                           .pal[["blue"]], .pal[["purple"]]), bty = "n", cex = 0.75)
}

# Observed (points) and simulated (line) flow over one window.
.plot_hydrograph <- function(time, obs, sim) {
  graphics::par(mfrow = c(2, 1), mar = c(2.5, 4.2, 0.6, 0.6))
  o <- .thin(time, obs)
  s <- .thin(time, sim)
  top <- max(c(o$y, s$y), na.rm = TRUE)
  graphics::plot(o$x, o$y, type = "l", col = .pal[["grey"]], ylim = c(0, top), xlab = "",
                 ylab = "Flow (m3/s)")
  graphics::lines(s$x, s$y, col = .pal[["blue"]])
  graphics::legend("topright", c("observed", "simulated"),
                   col = c(.pal[["grey"]], .pal[["blue"]]), lwd = 1.5, bty = "n", cex = 0.8)
  low <- max(min(c(obs, sim)[c(obs, sim) > 0], na.rm = TRUE), 1e-4)
  graphics::plot(time, pmax(obs, low), type = "l", log = "y", col = .pal[["grey"]],
                 xlab = "", ylab = "Flow (m3/s, log)")
  graphics::lines(time, pmax(sim, low), col = .pal[["blue"]])
}

# Left: flow-duration curves, observed and simulated, with the 2, 20 and 70 per cent exceedance
# marks used by the signatures. Right: simulated against observed on log axes.
.plot_fdc_scatter <- function(obs, sim) {
  keep <- is.finite(obs)
  obs <- obs[keep]
  sim <- sim[keep]
  graphics::par(mfrow = c(1, 2), mar = c(4, 4.2, 0.6, 0.6))
  p <- seq_along(obs) / (length(obs) + 1) * 100
  low <- max(min(c(obs, sim)[c(obs, sim) > 0]), 1e-4)
  graphics::plot(p, pmax(sort(obs, decreasing = TRUE), low), type = "l", log = "y",
                 col = .pal[["grey"]], lwd = 2, xlab = "Exceedance (%)",
                 ylab = "Flow (m3/s, log)")
  graphics::lines(p, pmax(sort(sim, decreasing = TRUE), low), col = .pal[["blue"]], lwd = 1.5)
  graphics::abline(v = c(2, 20, 70), lty = 3, col = .pal[["light"]])
  pick <- unique(round(seq(1, length(obs), length.out = min(length(obs), 20000L))))
  graphics::plot(pmax(obs[pick], low), pmax(sim[pick], low), log = "xy", pch = 16, cex = 0.3,
                 col = grDevices::adjustcolor(.pal[["blue"]], 0.4), xlab = "Observed (m3/s)",
                 ylab = "Simulated (m3/s)")
  graphics::abline(0, 1, col = .pal[["grey"]])
}

# Roebber (2009) performance diagram: success ratio (1 - FAR) across, POD up, with curved lines
# of equal CSI and dashed lines of equal bias. One colour per threshold, one symbol per window.
.plot_performance <- function(table) {
  graphics::par(mar = c(4, 4, 0.6, 0.6))
  graphics::plot(NA, xlim = c(0, 1), ylim = c(0, 1), xaxs = "i", yaxs = "i",
                 xlab = "Success ratio (1 - FAR)", ylab = "Probability of detection")
  grid <- seq(0.01, 1, length.out = 200)
  for (csi in seq(0.1, 0.9, 0.1)) {
    pod <- 1 / (1 / csi + 1 - 1 / grid)
    pod[pod <= 0 | pod > 1] <- NA
    graphics::lines(grid, pod, col = .pal[["light"]])
    k <- which(!is.na(pod))[1L]
    if (!is.na(k)) graphics::text(grid[k], pod[k], csi, cex = 0.6, pos = 4, col = .pal[["light"]])
  }
  for (b in c(0.5, 0.8, 1, 1.25, 2)) {
    graphics::lines(c(0, 1), c(0, b), lty = 2, col = .pal[["light"]])
    at <- if (b <= 1) c(1, b) else c(1 / b, 1)
    graphics::text(at[1], at[2], paste("bias", b), cex = 0.6, col = .pal[["grey"]],
                   adj = c(1.1, if (b <= 1) -0.3 else 1.3))
  }
  thresholds <- unique(table$threshold)
  cols <- rep(c(.pal[["blue"]], .pal[["orange"]], .pal[["green"]], .pal[["purple"]],
                .pal[["red"]]), length.out = length(thresholds))
  for (i in seq_along(thresholds)) {
    rows <- table[table$threshold == thresholds[i], ]
    graphics::points(1 - rows$far, rows$pod, col = cols[i], cex = 1.6, lwd = 2,
                     pch = c(calibration = 16, validation = 2, test = 5)[rows$window])
  }
  windows <- unique(table$window)
  graphics::legend("bottomright", c(thresholds, windows),
                   col = c(cols, rep(.pal[["grey"]], length(windows))),
                   pch = c(rep(15, length(thresholds)),
                           c(calibration = 16, validation = 2, test = 5)[windows]),
                   bty = "n", cex = 0.8)
}

# One small panel per parameter. One shared vertical scale, so a parameter that barely moves the
# score looks flat. Points below the floor (the 20th percentile of all values) are drawn at the
# floor as triangles.
.plot_sensitivity <- function(curves, factors, headline) {
  n <- length(curves)
  values <- unlist(curves)
  values <- values[is.finite(values)]
  floor <- if (length(values)) stats::quantile(values, 0.2, names = FALSE) else 0
  top <- if (length(values)) max(values) else 1
  if (top <= floor) top <- floor + 1
  graphics::par(mfrow = c(ceiling(n / 4), min(n, 4)), mar = c(3, 3.2, 1.6, 0.4),
                mgp = c(1.8, 0.5, 0))
  for (p in names(curves)) {
    y <- curves[[p]]
    clipped <- is.finite(y) & y < floor
    graphics::plot(factors, pmax(y, floor), type = "o", pch = ifelse(clipped, 6, 16),
                   cex = 0.6, col = .pal[["blue"]], ylim = c(floor, top), main = p,
                   cex.main = 0.9, xlab = "Factor", ylab = headline)
    graphics::abline(v = 1, lty = 3, col = .pal[["light"]])
  }
}
