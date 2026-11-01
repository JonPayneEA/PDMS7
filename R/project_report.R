# ============================================================ #
# Tool:         project_report
# Description:  Calibration log report: integrity, data, path, candidate, sign-off
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration report
# Tier:         3
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
#' with hydrographs, flow-duration curves and a scatter for both windows; parameter
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

`%||%` <- function(a, b) if (is.null(a)) b else a

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

.rpt_data <- function(path, entries) {
  regs <- Filter(function(e) e$type == "data_registered", entries)
  out <- list(.blk_h("Data"))
  for (r in regs) {
    s <- r$summary
    card <- r$scorecard
    files <- data.frame(
      series = c("forcing", "observed"),
      stored = c(r$data$forcing$stored, r$data$observed$stored),
      copied = c(r$data$forcing$copied, r$data$observed$copied),
      md5 = c(r$data$forcing$md5, r$data$observed$md5)
    )
    windows <- data.frame(
      window = c("warm-up", "calibration", "validation"),
      rows = c(if (card$warmup_rows) paste0("1-", card$warmup_rows) else "none",
               .window_text(card$calibration, FALSE), .window_text(card$validation, FALSE)),
      period = c("", .window_text(card$calibration, TRUE), .window_text(card$validation, TRUE))
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
    if (nzchar(r$reasoning %||% "")) out <- c(out, list(.blk_p(r$reasoning)))
  }
  latest <- .latest(entries, "data_registered")
  if (!is.null(latest)) {
    data <- tryCatch(.load_registration(path, latest), error = function(e) NULL)
    if (!is.null(data)) {
      caption <- "Observed flow, with the calibration (blue) and validation (orange) windows"
      draw <- function() .plot_record(data, latest$scorecard)
      out <- c(out, list(.blk_fig("observed", draw, caption, height = 3.2)))
    }
  }
  out
}

.window_text <- function(w, times) {
  if (is.null(w)) return("not set")
  if (times) paste(w$start %||% "", "to", w$end %||% "") else paste0(w$first_row, "-", w$last_row)
}

.rpt_structure <- function(entries) {
  structures <- Filter(function(e) e$type == "structure_selected", entries)
  out <- list(.blk_h("Model structure"))
  for (s in structures) {
    cfg <- s$configuration
    table <- data.frame(
      component = c("Soil store", "Recharge", "Surface routing", "Groundwater routing"),
      choice = c(cfg$distribution$type %||% "pareto", cfg$recharge$type %||% "standard",
                 cfg$surface$type %||% "cascade",
                 paste(cfg$groundwater$type %||% "cubic", cfg$groundwater$solver %||% ""))
    )
    out <- c(out, list(
      .blk_h(paste("Entry", s$id, "by", s$author$name, "on", substr(s$timestamp, 1, 10)), 3L),
      .blk_table(table), .blk_p(s$reasoning)
    ))
  }
  out
}

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
    out <- c(out, list(.blk_table(starts, paste("Automatic calibration", a$id, ":",
                                                a$objective, "with", a$starts, "start(s)"))))
  }
  if (length(notes)) {
    out <- c(out, list(.blk_h("Notes", 3L), .blk_list(vapply(notes, function(n) {
      paste0(n$id, " (", n$author$name, ", ", substr(n$timestamp, 1, 10), "): ", n$text,
             if (!is.null(n$refers_to)) paste0(" [about entry ", n$refers_to, "]") else "")
    }, character(1)))))
  }
  out
}

.bounds_text <- function(e) {
  paste(vapply(names(e$bounds$lower), function(n) {
    sprintf("%s in [%s, %s]", n, format(e$bounds$lower[[n]]), format(e$bounds$upper[[n]]))
  }, character(1)), collapse = "; ")
}

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
  scores <- data.frame(score = names(candidate$scores),
                       calibration = vapply(candidate$scores, .num_or_na, numeric(1)))
  if (validated) {
    scores$validation <- vapply(validation$validation_scores, .num_or_na, numeric(1))
    out <- c(out, list(.blk_p(paste0("Validated in entry ", validation$id, " (",
                                     validation$author$name, "): ", validation$reasoning))))
  } else {
    out <- c(out, list(.blk_alert("The candidate has not been validated.", FALSE)))
  }
  out <- c(out, list(.blk_table(scores, "Scorecard")))
  for (w in c("calibration", if (validated) "validation")) {
    rows <- .window_rows(card[[w]])
    obs <- series$observed_m3s[rows]
    sim <- series$simulated_m3s[rows]
    time <- if ("time" %in% names(series)) .parse_time(series$time[rows]) else rows
    out <- c(out, list(
      .blk_h(paste(tools::toTitleCase(w), "window"), 3L),
      .blk_fig(paste0("hydrograph-", w), function() .plot_hydrograph(time, obs, sim),
               paste("Observed and simulated flow over the", w, "window, linear and log scale"),
               height = 6),
      .blk_fig(paste0("fdc-", w), function() .plot_fdc_scatter(obs, sim),
               paste("Flow-duration curves and simulated against observed flow,", w, "window"),
               height = 3.8)
    ))
  }
  out
}

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
  graphics::lines(th$x, th$y, col = .pal[["grey"]], lwd = 0.8)
}

.verdict_colour <- function(e) {
  if (e$type == "auto_calibration") return(.pal[["blue"]])
  if (e$type == "structure_selected") return(.pal[["grey"]])
  switch(e$verdict %||% "inconclusive", better = .pal[["green"]], worse = .pal[["red"]],
         .pal[["light"]])
}

.plot_path <- function(nodes, headline, candidate) {
  ids <- vapply(nodes, function(e) e$id, character(1))
  y <- vapply(nodes, function(e) .num_or_na(e$scores[[headline]]), numeric(1))
  x <- seq_along(nodes)
  graphics::par(mar = c(4, 4.2, 0.6, 0.6))
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

# One shared vertical scale, so a parameter that barely moves the score looks flat. Points
# below the floor (the 20th percentile of all values) are drawn at the floor as triangles.
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
