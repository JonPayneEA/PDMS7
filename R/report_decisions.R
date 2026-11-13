# report_decisions.R: two report sections rebuilt from the log alone. The structure decisions,
#                     drawn as a flow from the first structure through each component step to
#                     the stages and the candidate, with every option's validation score and the
#                     reason for each choice; and the run totals, model runs and elapsed time for
#                     each step, stage and the project in all.

# ---- The structure decisions -------------------------------------------------------------

# Each step of a structure recommendation, in order: the component, the option it started
# from, every option compared with its validation score and flags, the choice and the reason.
# The choice and the reason come from the step's note; the scores from its comparison.
.structure_decisions <- function(path, entries) {
  prefix <- "Structure recommendation, "
  notes <- Filter(function(e) {
    e$type == "note" && startsWith(e$text %||% "", prefix) && !is.null(e$refers_to)
  }, entries)
  card <- .registration(entries)$scorecard
  tolerance <- card$tie_tolerance %||% 0.02
  direction <- .headline_direction(card$headline)
  base <- .first_structure(entries)
  steps <- list()
  for (n in notes) {
    chosen <- .find_entry(entries, n$refers_to)
    if (is.null(chosen$comparison)) next
    head <- sub(prefix, "", n$text, fixed = TRUE)
    component <- sub(":.*$", "", head)
    reason <- sub("^[^:]*: [^.]*\\. ?", "", head)
    table <- as.data.frame(structure_comparison(path, chosen$comparison))
    table$at_bound <- vapply(table$calibration_entry, function(id) {
      any(!is.na(.bound_flags(entries, .find_entry(entries, id), 0.01)$at_bound))
    }, logical(1))
    table$median_abs_peak_error <- NA_real_
    tie <- .choose_structure(table, "", tolerance, direction)
    table$equally_good <- table$structure %in% tie$equally_good
    incumbent <- if (is.null(base)) {
      NA_character_
    } else {
      tryCatch(.component_type(base, component), error = function(e) NA_character_)
    }
    steps[[length(steps) + 1L]] <- list(
      component = component, incumbent = incumbent, choice = chosen$structure_name,
      reason = reason, table = table, headline = card$headline, entry = chosen$id
    )
    base <- chosen$configuration
  }
  steps
}

# The configuration the recommendation started from: the last structure chosen outside a
# comparison, before the first comparison entry; NULL if there is none.
.first_structure <- function(entries) {
  first <- Position(function(e) !is.null(e$comparison), entries)
  before <- if (is.na(first)) entries else entries[seq_len(first - 1L)]
  picks <- Filter(function(e) e$type == "structure_selected" && is.null(e$comparison), before)
  if (length(picks)) picks[[length(picks)]]$configuration
}

# The section: the flow figure, then one line per step with its reason.
.rpt_decisions <- function(path, entries, candidate) {
  steps <- tryCatch(.structure_decisions(path, entries), error = function(e) list())
  if (!length(steps)) return(NULL)
  stages <- Filter(function(e) {
    e$type == "auto_calibration" && !is.null(e$stage) && is.null(e$comparison)
  }, entries)
  final <- list(stages = vapply(stages, function(e) as.character(e$stage), character(1)),
                candidate = candidate)
  list(
    .blk_h("How the structure was chosen"),
    .blk_p(paste(
      "One component at a time, each chosen by calibrating every option alike and comparing them",
      "on the validation window, which no calibration saw. An option with a parameter at a",
      "bound of its search is set aside; options within the tie tolerance of the best are",
      "equally good, and among those the one the step started from is kept, since the record",
      "cannot justify a change."
    )),
    .blk_fig("decisions", function() .plot_decisions(steps, final),
             paste("The structure decisions, top to bottom. Each row is one step, with every",
                   "option's", steps[[1]]$headline, "on validation. Filled: chosen. Outlined in",
                   "blue: equally good. Grey: set aside with a parameter at a bound. A dot marks",
                   "the option the step started from."),
             width = 10, height = 1.7 * length(steps) + 2.2),
    .blk_list(vapply(steps, function(s) {
      sprintf("%s: %s. %s", .component_label(s$component), s$choice, s$reason)
    }, character(1)))
  )
}

# The kind of decision, in a few words, from the step's reason.
.decision_tag <- function(reason) {
  if (startsWith(reason, "Best validation score")) return("best on validation")
  if (startsWith(reason, "Within")) return("kept: no clear winner")
  if (startsWith(reason, "Equally good")) return("smallest peak error")
  ""
}

.component_label <- function(component) {
  c(recharge = "Recharge", distribution = "Soil store", groundwater = "Groundwater store",
    zones = "Zones")[[component]] %||% component
}

# The flow: a box for the start, a row of option boxes for each step, an arrow from each
# choice down to the next step, then the stages and the candidate.
.plot_decisions <- function(steps, final) {
  n <- length(steps)
  rows <- n + 2
  graphics::par(mar = c(0.2, 0.2, 0.2, 0.2))
  graphics::plot(NA, xlim = c(0, 1), ylim = c(0.2, rows + 0.4), axes = FALSE, xlab = "",
                 ylab = "")
  box <- function(x, y, w, h, label, border, fill = NA, lwd = 1.2, text_col = .pal[["grey"]],
                  cex = 0.72) {
    graphics::rect(x - w / 2, y - h / 2, x + w / 2, y + h / 2, border = border, col = fill,
                   lwd = lwd)
    graphics::text(x, y, label, cex = cex, col = text_col)
  }
  arrow <- function(x0, y0, x1, y1) {
    graphics::arrows(x0, y0, x1, y1, length = 0.06, col = .pal[["light"]], lwd = 1.2)
  }
  label_x <- 0.075
  y_top <- rows
  box(0.55, y_top, 0.34, 0.42, "First structure", .pal[["grey"]])
  from_x <- 0.55
  from_y <- y_top - 0.21
  for (k in seq_len(n)) {
    s <- steps[[k]]
    t <- s$table
    y <- rows - k
    graphics::text(label_x, y + 0.08, .component_label(s$component), font = 2, cex = 0.78,
                   col = .pal[["grey"]])
    graphics::text(label_x, y - 0.12, .decision_tag(s$reason), font = 3, cex = 0.66,
                   col = .pal[["grey"]])
    m <- nrow(t)
    xs <- 0.17 + (seq_len(m) - 0.5) * (0.83 / m)
    w <- min(0.16, 0.83 / m - 0.012)
    pick <- which(t$structure == s$choice)
    for (i in seq_len(m)) {
      chosen <- i %in% pick
      aside <- isTRUE(t$at_bound[i])
      tied <- isTRUE(t$equally_good[i])
      border <- if (chosen) .pal[["green"]] else if (aside) .pal[["light"]] else if (tied) {
        .pal[["blue"]]
      } else {
        .pal[["grey"]]
      }
      fill <- if (chosen) grDevices::adjustcolor(.pal[["green"]], 0.25) else if (aside) {
        grDevices::adjustcolor(.pal[["light"]], 0.25)
      } else {
        NA
      }
      score <- if (is.finite(t$validation[i])) sprintf("%.3f", t$validation[i]) else "no score"
      flag <- if (aside) "\nat a bound" else ""
      box(xs[i], y, w, 0.5, paste0(t$structure[i], "\n", score, flag), border, fill,
          lwd = if (chosen || tied) 2 else 1,
          text_col = if (aside) .pal[["light"]] else .pal[["grey"]])
      if (identical(t$structure[i], s$incumbent)) {
        graphics::points(xs[i] - w / 2 + 0.012, y + 0.25 - 0.06, pch = 19, cex = 0.7,
                         col = .pal[["orange"]])
      }
    }
    arrow(from_x, from_y, xs[pick[1]], y + 0.25)
    from_x <- xs[pick[1]]
    from_y <- y - 0.25
  }
  stages <- final$stages
  label <- if (length(stages)) {
    paste(c(sprintf("Staged calibration, %d stages:", length(stages)), stages), collapse = "\n")
  } else {
    "Calibration"
  }
  cand <- final$candidate
  if (!is.null(cand)) label <- paste0(label, "\nCandidate: entry ", cand$entry)
  lines <- length(strsplit(label, "\n", fixed = TRUE)[[1]])
  box(0.55, 1, 0.5, 0.12 * lines + 0.1, label, .pal[["green"]], lwd = 1.6)
  arrow(from_x, from_y, 0.55, 1 + (0.12 * lines + 0.1) / 2)
}

# ---- Run totals --------------------------------------------------------------------------

# Model runs and elapsed time for each part of the work, from the log alone: each structure
# step (all its options together), each calibration stage, any other automatic calibration,
# and the project in all. Elapsed time is the span of the part's entries in the log, from the
# entry before its first to its last, so it is wall-clock time, whatever the cores.
.run_totals <- function(entries) {
  times <- vapply(entries, function(e) {
    as.numeric(as.POSIXct(e$timestamp, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  }, numeric(1))
  autos <- which(vapply(entries, function(e) e$type == "auto_calibration", logical(1)))
  if (!length(autos)) return(NULL)
  group <- vapply(entries[autos], function(e) {
    if (!is.null(e$comparison)) {
      why <- e$reasoning %||% ""
      step <- regmatches(why, regexpr("Structure step: [a-z]+", why))
      if (length(step)) {
        paste("Structure step:", .component_label(sub("Structure step: ", "", step)))
      } else {
        paste("Structure comparison", e$comparison)
      }
    } else if (!is.null(e$stage)) {
      paste("Stage", e$stage)
    } else {
      "Other automatic calibration"
    }
  }, character(1))
  parts <- unique(group)
  # A comparison writes all its entries once its fits are done, so its time runs from the entry
  # before the first of them, the structure entries included.
  comparison_of <- vapply(entries, function(e) e$comparison %||% NA_character_, character(1))
  rows <- lapply(parts, function(p) {
    at <- autos[group == p]
    ids <- unique(stats::na.omit(comparison_of[at]))
    first <- min(c(at, which(comparison_of %in% ids)))
    begun <- times[max(1L, first - 1L)]
    data.frame(part = p, calibrations = length(at),
               model_runs = sum(vapply(entries[at], function(e) {
                 as.numeric(e$evaluations %||% NA)
               }, numeric(1))),
               elapsed = times[max(at)] - begun, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  start <- min(c(autos, which(!is.na(comparison_of))))
  total <- data.frame(part = "Total", calibrations = sum(out$calibrations),
                      model_runs = sum(out$model_runs),
                      elapsed = max(times[autos]) - times[max(1L, start - 1L)])
  out <- rbind(out, total)
  out$per_run_s <- ifelse(out$model_runs > 0, out$elapsed / out$model_runs, NA_real_)
  out
}

# The section: the table, with elapsed time as text and the time a run took.
.rpt_run_totals <- function(entries) {
  totals <- .run_totals(entries)
  if (is.null(totals)) return(NULL)
  shown <- data.frame(
    part = totals$part, calibrations = totals$calibrations,
    model_runs = format(totals$model_runs, big.mark = ","),
    elapsed = vapply(totals$elapsed, .duration_text, character(1)),
    seconds_a_run = signif(totals$per_run_s, 3)
  )
  list(
    .blk_h("Run totals"),
    .blk_p(paste(
      "Model runs and elapsed time for each part of the work. A structure step counts every",
      "option it calibrated; model runs include the finite-difference gradient runs.",
      "Elapsed time is the span of the part's entries in the log, so it is wall-clock time and",
      "shrinks with more cores; the seconds a run divide it by the runs."
    )),
    .blk_table(shown, "Model runs and time")
  )
}
