# ============================================================ #
# Tool:         recommend_structure
# Description:  A stepwise structure recommendation: recharge rule, then soil store
#               distribution, then groundwater store, each chosen by comparison with reasons
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
#               2026-11-09 - overrides and exclude passed to compare_structures(); ties
#                            broken on the median of the absolute peak errors
#               2026-11-10 - Progress: each step announced, with the time left at its pace
# Tier:         1
# Inputs:       A calibration project with registered calibration and validation windows
# Outputs:      The recommended configuration, a table per step, and a note in the log
# Dependencies: none
# ============================================================ #

#' Recommend a model structure
#'
#' Chooses one component at a time, the way a hydrologist would, each by a structure
#' comparison ([compare_structures()]) on the project's own data, and writes down why.
#'
#' **The order** follows what the record can tell apart. On made-up catchments (see the
#' calibration study article) the recharge rule was identified every time, by wide margins; the
#' groundwater store only by margins too small to trust. So the recharge rule comes first, then
#' the soil store distribution, then the groundwater store, each step starting from the
#' calibrated structure the step before chose.
#'
#' **Each choice** follows the same rule:
#' 1. A structure that ended with a parameter at a bound of its search range is set aside: it is
#'    being bent to fit, not describing the catchment. If every structure did, none is set aside.
#' 2. The rest are ranked by their headline score on the validation window, which no
#'    calibration saw. Every structure within `tolerance` of the best counts as equally good.
#' 3. If the structure the step started from is among the equally good, it is kept: the record
#'    cannot justify a change.
#' 4. Otherwise, among the equally good, the one with the smallest median peak error on the
#'    largest validation events wins ([calibration_checks()]), then the one with fewer
#'    parameters.
#'
#' Every comparison is logged in the project as usual, and each step's choice and reason is
#' written as a note, so the recommendation is part of the audit trail.
#'
#' @param project A calibration project with registered calibration and validation windows.
#' @param components Components to choose, in order, among `recharge`, `distribution` and
#'   `groundwater`.
#' @param tolerance Width of the band of equally good scores; by default the project's tie
#'   tolerance (0.02 unless registered otherwise).
#' @param n_events Largest validation events used to break ties.
#' @param starts,seed,control,method,cores Passed to [compare_structures()].
#' @param overrides,exclude Passed to [compare_structures()], and so to [calibration_bounds()]
#'   for every structure compared; an override must name a parameter every structure has.
#' @param reasoning Why the recommendation is being made; recorded with every comparison.
#' @param note Write each step's choice and reason to the log as a note.
#'
#' @return A list of class `pdm_structure_recommendation`: `configuration` (the recommended,
#'   calibrated structure), `entry` (its calibration entry) and `steps`, one per component,
#'   each with the `table` of the comparison (with `at_bound`, `equally_good` and
#'   `median_abs_peak_error`), the `choice` and the `reason`.
#' @examples
#' \dontrun{
#' rec <- recommend_structure("projects/beggearn_huish", reasoning = "First structure choice.")
#' rec
#' rec$steps$recharge$table
#' }
#' @seealso [compare_structures()], [structure_set()], [calibration_checks()]
#' @export
recommend_structure <- function(project,
                                components = c("recharge", "distribution", "groundwater"),
                                tolerance = NULL, n_events = 10L, starts = 2L, seed = 1,
                                control = list(maxit = 100), method = "lbfgsb", cores = 1L,
                                overrides = NULL, exclude = NULL, reasoning, note = TRUE) {
  .check(is.character(components) && length(components) > 0 &&
           all(components %in% names(.component_options())) && !anyDuplicated(components),
         "components must be among recharge, distribution and groundwater")
  reasoning <- .require_text(reasoning, "reasoning")
  path <- .project_path(project)
  entries <- .read_entries(path)
  card <- .registration(entries)$scorecard
  tolerance <- tolerance %||% card$tie_tolerance %||% 0.02
  .check(.scalar(tolerance, 0), "tolerance must be a nonnegative number")
  latest <- .latest(entries, "structure_selected")
  base <- if (is.null(latest)) pdm_presets("standard") else latest$configuration
  steps <- list()
  entry <- NULL
  counts <- vapply(components, function(k) length(.component_options()[[k]]), integer(1))
  .progress_say(sprintf(
    "Structure recommendation: %d steps (%s), %d calibrations in all",
    length(components), toString(components), sum(counts)
  ))
  started <- Sys.time()
  for (k in seq_along(components)) {
    component <- components[[k]]
    options <- .component_variants(base, component)
    label <- sprintf("Structure step %d of %d (%s)", k, length(components), component)
    table <- .with_progress_label(label, compare_structures(
      path, options, overrides = overrides, exclude = exclude, starts = starts, seed = seed,
      control = control, method = method, cores = cores,
      reasoning = paste0(reasoning, " Structure step: ", component, ".")
    ))
    step <- .structure_step(path, table, component, .component_type(base, component), tolerance,
                            n_events, attr(table, "headline"))
    steps[[component]] <- step
    # The time left, at the pace so far: calibrations to go times the time each has taken.
    spent <- .seconds_since(started)
    to_go <- sum(counts[-seq_len(k)])
    .progress_say(sprintf("%s: chose %s.%s", label, step$choice, if (to_go) sprintf(
      " %s so far; about %s for the remaining %d calibrations at this pace",
      .duration_text(spent), .duration_text(spent / sum(counts[seq_len(k)]) * to_go), to_go
    ) else sprintf(" Recommendation done in %s.", .duration_text(spent))))
    chosen <- step$table[step$table$structure == step$choice, ]
    entry <- chosen$calibration_entry
    base <- read_entry(path, entry)$configuration
    if (isTRUE(note)) {
      log_note(path, paste0("Structure recommendation, ", component, ": ", step$choice, ". ",
                            step$reason), refers_to = entry)
    }
  }
  structure(list(configuration = base, entry = entry, steps = steps),
            class = "pdm_structure_recommendation")
}

#' @export
print.pdm_structure_recommendation <- function(x, ...) {
  cat("Structure recommendation\n")
  for (component in names(x$steps)) {
    s <- x$steps[[component]]
    cat(sprintf("  %-13s %s. %s\n", paste0(component, ":"), s$choice, s$reason))
  }
  cat(sprintf("Recommended calibration: entry %s\n", x$entry))
  invisible(x)
}

# ---- Helpers -----------------------------------------------------------------------------

# The options for each component, by the names the step reports. Starting values follow
# structure_set(); a base that already uses an option keeps its own values for it.
.component_options <- function() {
  list(
    recharge = list(
      standard = list(type = "standard", kg = 4000, bg = 1, st = 0),
      split = list(type = "split", alpha = 0.7),
      demand = list(type = "demand", alpha = 0.5, beta = 1, qsat = 0.05)
    ),
    distribution = list(
      pareto = list(type = "pareto", cmin = 0, cmax = 300, b = 0.4),
      rectangular = list(type = "rectangular", cmin = 0, cmax = 200),
      triangular = list(type = "triangular", cmin = 0, cmax = 250),
      exponential = list(type = "exponential", mean = 100),
      lognormal = list(type = "lognormal", meanlog = 4.1, sdlog = 0.8)
    ),
    groundwater = list(
      cubic = list(type = "cubic", kb = 10000),
      quadratic = list(type = "quadratic", kb = 30000),
      linear = list(type = "linear", kb = 1500),
      exponential = list(type = "exponential", a = 0.05, gamma = -5)
    )
  )
}

# The type a configuration uses for a component, as the option names spell it.
.component_type <- function(config, component) {
  default <- c(recharge = "standard", distribution = "pareto", groundwater = "cubic")
  config[[component]]$type %||% default[[component]]
}

# The base configuration with each option of one component in turn, named by the option. The
# option the base already uses keeps the base's values, and its solver settings carry over.
.component_variants <- function(base, component) {
  current <- .component_type(base, component)
  options <- .component_options()[[component]]
  lapply(stats::setNames(names(options), names(options)), function(name) {
    config <- base
    if (name == current) return(config)
    config[[component]] <- options[[name]]
    if (component == "groundwater" && name == "cubic" && !is.null(base$groundwater$solver)) {
      config$groundwater$solver <- base$groundwater$solver
    }
    config
  })
}

# One step: flags each compared structure, finds the equally good, and chooses.
.structure_step <- function(path, table, component, incumbent, tolerance, n_events, headline) {
  entries <- .read_entries(path)
  table <- as.data.frame(table)
  table$at_bound <- vapply(table$calibration_entry, function(id) {
    flags <- .bound_flags(entries, .find_entry(entries, id), 0.01)
    any(!is.na(flags$at_bound))
  }, logical(1))
  table$median_abs_peak_error <- vapply(table$calibration_entry, function(id) {
    s <- tryCatch(calibration_checks(path, id, top = n_events)$summary, error = function(e) NULL)
    row <- if (is.null(s)) NULL else s[s$period == "validation", ]
    # The median size of the errors: -50% and +50% must not cancel to a perfect zero.
    if (is.null(row) || !nrow(row)) NA_real_ else row$median_abs_peak_error
  }, numeric(1))
  choice <- .choose_structure(table, incumbent, tolerance, .headline_direction(headline))
  table$equally_good <- table$structure %in% choice$equally_good
  list(component = component, table = table, choice = choice$choice, reason = choice$reason)
}

# The choice rule, on a table with structure, parameters, validation, at_bound and
# median_abs_peak_error: set aside structures at a bound (unless all are), call those within
# tolerance of the best validation score equally good, keep the incumbent if it is among them,
# else take the smallest event peak error, then the fewest parameters.
.choose_structure <- function(table, incumbent, tolerance, direction) {
  scored <- table[is.finite(table$validation), ]
  .check(nrow(scored) > 0, "No compared structure has a validation score")
  usable <- scored[!scored$at_bound, ]
  set_aside <- setdiff(scored$structure, usable$structure)
  if (!nrow(usable)) usable <- scored
  sign <- if (direction == "lower") -1 else 1
  best <- max(sign * usable$validation)
  tied <- usable[sign * usable$validation >= best - tolerance, ]
  aside <- if (length(set_aside) && nrow(usable) < nrow(scored)) {
    paste0(" Set aside with a parameter at a bound: ", toString(set_aside), ".")
  } else {
    ""
  }
  if (incumbent %in% tied$structure) {
    others <- setdiff(tied$structure, incumbent)
    reason <- if (length(others)) {
      sprintf(paste0("Within %g of the best validation score, so equally good: %s. The record ",
                     "cannot justify a change from %s."), tolerance,
              toString(tied$structure), incumbent)
    } else {
      sprintf("Best validation score, by more than %g.", tolerance)
    }
    return(list(choice = incumbent, equally_good = tied$structure, reason = paste0(reason, aside)))
  }
  peak <- ifelse(is.finite(tied$median_abs_peak_error), tied$median_abs_peak_error, Inf)
  pick <- tied[order(peak, tied$parameters, -sign * tied$validation), ][1, ]
  reason <- if (nrow(tied) > 1) {
    sprintf(paste0("Equally good within %g: %s; chosen for the smallest median peak error on ",
                   "the largest validation events, then fewer parameters."), tolerance,
            toString(tied$structure))
  } else {
    sprintf("Best validation score, by more than %g over %s.", tolerance, incumbent)
  }
  list(choice = pick$structure, equally_good = tied$structure, reason = paste0(reason, aside))
}
