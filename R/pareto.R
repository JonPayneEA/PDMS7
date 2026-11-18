# ============================================================ #
# Tool:         pareto
# Description:  Working with a Pareto front from calibrate_pdm_multi(): choosing a point,
#               printing, the standard plots (each pair of objectives, parallel coordinates,
#               flows of the chosen points), and logging a front in a calibration project
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       A pdm_pareto result; forcing and observed flow for the flow plot
# Outputs:      Chosen configurations; plots in the pdmS7 house style; log entries
# Dependencies: graphics; ggplot2 (suggested)
# ============================================================ #

# Plain names for the losses, for plot labels.
.pareto_labels <- c(
  nse_loss = "1 - NSE", rmse = "RMSE (m3/s)", log_rmse = "RMSE of log flow",
  kge_loss = "1 - KGE", abs_bias = "Volume error", peak_relative_error = "Largest-peak error",
  event_nse_loss = "1 - event NSE", event_peak_error = "Event peak error",
  event_timing_error = "Event timing error (response times)",
  threshold_loss = "1 - threshold score"
)

# Short names, for panel titles and the parallel axes.
.pareto_short <- c(
  nse_loss = "1 - NSE", rmse = "RMSE", log_rmse = "Log RMSE", kge_loss = "1 - KGE",
  abs_bias = "Volume", peak_relative_error = "Largest peak", event_nse_loss = "1 - event NSE",
  event_peak_error = "Event peak", event_timing_error = "Event timing",
  threshold_loss = "Thresholds"
)

.pareto_label <- function(o, short = FALSE) {
  names <- if (short) .pareto_short else .pareto_labels
  unname(ifelse(o %in% names(names), names[o], o))
}

# Colours for the best set on each objective: the house palette without black (observed) and
# vermilion (the compromise).
.corner_colours <- function(n) {
  pal <- setdiff(unname(pdm_palette(8)), c("#000000", .pdm_roles[["alternative"]]))
  rep(pal, length.out = n)
}

#' Choose a configuration from a Pareto front
#'
#' Picks one point of the front from [calibrate_pdm_multi()]: the best on one objective
#' (a corner of the front), the best under a weighting of the scaled losses, or, with neither,
#' the result's compromise.
#'
#' @param x A `pdm_pareto` result.
#' @param objective One objective's name: the front point with its lowest loss (ties go to
#'   the lowest equally weighted, scaled sum).
#' @param weights Nonnegative weights named by objective (missing ones count 0), applied to
#'   the scaled losses.
#' @return A list: `config`, `scores` (the point's row of the front) and `row` (its row in
#'   `x$pareto`).
#' @examples
#' # See calibrate_pdm_multi().
#' @seealso [calibrate_pdm_multi()], [plot.pdm_pareto()]
#' @export
pareto_choose <- function(x, objective = NULL, weights = NULL) {
  .check(inherits(x, "pdm_pareto"), "x must come from calibrate_pdm_multi()")
  .check(is.null(objective) || is.null(weights), "Give objective or weights, not both")
  if (is.null(objective) && is.null(weights)) {
    row <- .pareto_row_of(x, x$compromise$scores)
    return(list(config = x$compromise$config, scores = x$compromise$scores, row = row))
  }
  scaled <- as.matrix(x$pareto[, paste0("scaled_", x$objectives), with = FALSE])
  row <- if (is.null(objective)) {
    .pareto_weighted_row(scaled, x$objectives, weights)
  } else {
    .pareto_corner_row(x, scaled, objective)
  }
  list(config = x$configs[[row]], scores = x$pareto[row], row = row)
}

# The front row lowest on one objective; ties go to the lowest equally weighted, scaled sum.
.pareto_corner_row <- function(x, scaled, objective) {
  .check(is.character(objective) && length(objective) == 1L && objective %in% x$objectives,
         paste("objective must be one of:", toString(x$objectives)))
  loss <- x$pareto[[paste0("loss_", objective)]]
  best <- which(loss == min(loss))
  best[which.min(rowSums(scaled[best, , drop = FALSE]))]
}

# The front row lowest under weights named by objective, missing ones counting 0.
.pareto_weighted_row <- function(scaled, objectives, weights) {
  .check(.all_of(is.numeric(weights), !is.null(names(weights)), all(names(weights) %in% objectives),
                 all(is.finite(weights) & weights >= 0), sum(weights) > 0),
         "weights must be nonnegative numbers named by objective, not all zero")
  w <- stats::setNames(numeric(length(objectives)), objectives)
  w[names(weights)] <- weights
  which.min(as.vector(scaled %*% (w / sum(w))))
}

# The row of the front holding the same parameters and losses as `scores`, or NA.
.pareto_row_of <- function(x, scores) {
  cols <- c(x$parameters, paste0("loss_", x$objectives))
  a <- as.matrix(x$pareto[, cols, with = FALSE])
  b <- unlist(scores[, cols, with = FALSE])
  hit <- which(apply(a, 1, function(r) isTRUE(all.equal(unname(r), unname(b)))))
  if (length(hit)) hit[1L] else NA_integer_
}

#' @export
print.pdm_pareto <- function(x, ...) {
  cat(sprintf("Pareto front: %d of %d evaluated parameter sets, %s, %d failed\n",
              nrow(x$pareto), nrow(x$archive), toupper(x$method), x$failed_evaluations))
  if (!is.null(x$events)) {
    cat(sprintf("Event losses over %s\n", x$events$which))
  }
  for (o in x$objectives) {
    v <- x$pareto[[paste0("loss_", o)]]
    cat(sprintf("  %-22s %.4g to %.4g on the front\n", o, min(v), max(v)))
  }
  invisible(x)
}

#' Plot a Pareto front
#'
#' Three standard views of a front from [calibrate_pdm_multi()]:
#'
#' | `type` | Shows |
#' |---|---|
#' | `pairs` | each pair of objectives: every set tried, the front, the pair's trade-off |
#' | `parallel` | each front set as a line across all the objectives, 0 best to 1 worst |
#' | `flows` | observed flow, the best set on each objective and the compromise, on a storm |
#'
#' **Reading the pairs.** The front's points run from the best on one objective to the best on
#' the other. A steep stretch means a large gain on one costs little on the other; a corner
#' marks the sets where the trade-off turns. Points far up and right are poor on both. The
#' view of each pair is cut at half the front's range beyond its worst point, so the random
#' first samples do not squash it; the subtitle counts those left out.
#'
#' **Reading the parallel plot.** Lines that cross between two axes mark a trade-off between
#' those objectives; lines that run side by side mark objectives that agree.
#'
#' **The flows** show what the numbers mean: the same storm as the best sets for different
#' objectives see it.
#'
#' @param x,object A `pdm_pareto` result.
#' @param type One of the views above.
#' @param objectives For `pairs` and `parallel`, the objectives to show; by default all.
#' @param forcing,observed For `flows`, the forcing and observed flow of the calibration.
#' @param window For `flows`, the rows to draw; by default ten days round the highest
#'   observed flow.
#' @param ... Not used.
#' @return `plot()`: `x`, invisibly. `autoplot()`: a ggplot.
#' @examples
#' # See calibrate_pdm_multi().
#' @seealso [calibrate_pdm_multi()], [pareto_choose()]
#' @export
plot.pdm_pareto <- function(x, type = c("pairs", "parallel", "flows"), objectives = NULL,
                            forcing = NULL, observed = NULL, window = NULL, ...) {
  .draw_base(.pareto_spec(x, match.arg(type), objectives, forcing, observed, window))
  invisible(x)
}

#' @rdname plot.pdm_pareto
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_pareto <- function(object, type = c("pairs", "parallel", "flows"),
                                objectives = NULL, forcing = NULL, observed = NULL,
                                window = NULL, ...) {
  .draw_gg(.pareto_spec(object, match.arg(type), objectives, forcing, observed, window))
}

.pareto_spec <- function(x, type, objectives, forcing, observed, window) {
  .check(inherits(x, "pdm_pareto"), "x must come from calibrate_pdm_multi()")
  objectives <- objectives %||% x$objectives
  .check(is.character(objectives) && all(objectives %in% x$objectives),
         paste("objectives must be among:", toString(x$objectives)))
  switch(type,
    pairs = .spec_pareto_pairs(x, objectives),
    parallel = .spec_pareto_parallel(x, objectives),
    flows = .spec_pareto_flows(x, forcing, observed, window)
  )
}

# The points no other point in (a, b) beats on both, in order of a: the trade-off line.
.front_2d <- function(a, b) {
  best <- Inf
  keep <- integer(0)
  for (i in order(a, b)) {
    if (b[i] < best) {
      keep <- c(keep, i)
      best <- b[i]
    }
  }
  keep
}

.spec_pareto_pairs <- function(x, objectives) {
  .check(length(objectives) >= 2L, "A pairs plot needs at least two objectives")
  pairs <- utils::combn(objectives, 2L, simplify = FALSE)
  arch <- x$archive
  comp <- x$compromise$scores
  cut <- 0L
  series <- NULL
  titles <- character(0)
  for (p in seq_along(pairs)) {
    ox <- pairs[[p]][1L]
    oy <- pairs[[p]][2L]
    ax <- arch[[paste0("loss_", ox)]]
    ay <- arch[[paste0("loss_", oy)]]
    fx <- x$pareto[[paste0("loss_", ox)]]
    fy <- x$pareto[[paste0("loss_", oy)]]
    limit <- function(f, a) {
      top <- max(f)
      top + 0.5 * max(top - min(a), abs(top) * 0.1, 1e-12)
    }
    show <- ax <= limit(fx, ax) & ay <= limit(fy, ay)
    cut <- max(cut, sum(!show))
    line <- .front_2d(ax, ay)
    tried <- .layer(ax[show], ay[show], "Evaluated", .pdm_roles[["reference"]],
                    geom = "point", lwd = 1.6, panel = p)
    trade <- .layer(ax[line], ay[line], "Trade-off of the pair", .pdm_roles[["simulated"]],
                    lwd = 1.2, panel = p)
    on <- .layer(fx, fy, "On the front", .pdm_roles[["simulated"]], geom = "point", lwd = 2.4,
                 panel = p)
    mid <- .layer(comp[[paste0("loss_", ox)]], comp[[paste0("loss_", oy)]], "Compromise",
                  .pdm_roles[["alternative"]], geom = "point", lwd = 4, panel = p)
    series <- rbind(series, tried, trade, on, mid)
    titles[p] <- sprintf("%s (up) against %s", .pareto_label(oy, TRUE),
                         .pareto_label(ox, TRUE))
  }
  sub <- sprintf("%d of %d evaluated sets on the front%s", nrow(x$pareto), nrow(arch),
                 if (cut) sprintf("; up to %d far from it left out of view", cut) else "")
  single <- length(pairs) == 1L
  list(series = series, zero = FALSE, ncol = if (length(pairs) > 4L) 3L else 2L,
       panels = data.frame(panel = seq_along(pairs), title = titles),
       xlab = if (single) .pareto_label(pairs[[1L]][1L]) else "",
       ylab = if (single) .pareto_label(pairs[[1L]][2L]) else "Loss",
       title = if (single) "Pareto front" else paste("Pareto front:", sub),
       subtitle = if (single) sub, legend = c("Evaluated", "On the front",
                                              "Trade-off of the pair", "Compromise"))
}

# The front points best on each objective, as rows of x$pareto, named by objective.
.pareto_corners <- function(x, objectives) {
  stats::setNames(vapply(objectives, function(o) pareto_choose(x, objective = o)$row,
                         integer(1)), objectives)
}

.spec_pareto_parallel <- function(x, objectives) {
  .check(length(objectives) >= 2L, "A parallel plot needs at least two objectives")
  k <- length(objectives)
  raw <- as.matrix(x$pareto[, paste0("loss_", objectives), with = FALSE])
  lo <- apply(raw, 2, min)
  hi <- apply(raw, 2, max)
  pos <- sweep(sweep(raw, 2, lo, "-"), 2, ifelse(hi > lo, hi - lo, 1), "/")
  # Every front set as one line across the axes, sets apart by a gap
  all_x <- unlist(lapply(seq_len(nrow(pos)), function(i) c(seq_len(k), NA)))
  all_y <- unname(unlist(lapply(seq_len(nrow(pos)), function(i) c(pos[i, ], NA))))
  series <- .layer(all_x, all_y, "Front", .pdm_roles[["reference"]], lwd = 0.8)
  corners <- .pareto_corners(x, objectives)
  colours <- .corner_colours(length(corners))
  for (j in seq_along(corners)) {
    series <- rbind(series, .layer(seq_len(k), unname(pos[corners[[j]], ]),
                                   paste("Best on", .pareto_label(names(corners)[j])),
                                   colours[j], lwd = 1.6))
  }
  comp <- .pareto_row_of(x, x$compromise$scores)
  if (!is.na(comp)) {
    series <- rbind(series, .layer(seq_len(k), unname(pos[comp, ]), "Compromise",
                                   .pdm_roles[["alternative"]], lwd = 2.6, lty = 2))
  }
  ranges <- paste(sprintf("%s %.3g to %.3g", .pareto_label(objectives, TRUE), lo, hi),
                  collapse = "; ")
  list(series = series, ylim = c(0, 1), zero = FALSE,
       xticks = list(at = seq_len(k), labels = .pareto_label(objectives, TRUE)),
       xlab = "", ylab = "Within the front (0 best, 1 worst)",
       title = sprintf("Pareto front: %d sets across %d objectives", nrow(pos), k),
       subtitle = paste("Ranges on the front:", ranges))
}

.spec_pareto_flows <- function(x, forcing, observed, window) {
  .check(is.data.frame(forcing) && is.numeric(observed) && nrow(forcing) == length(observed),
         "A flows plot needs the calibration's forcing and observed flow")
  corners <- .pareto_corners(x, x$objectives)
  if (is.null(window)) {
    dt <- .pareto_dt(x$configs[[1L]])
    peak <- which.max(observed)
    half <- round(5 * 24 / dt)
    window <- seq.int(max(1L, peak - half), min(length(observed), peak + half))
  }
  inside <- all(window >= 1 & window <= length(observed))
  .check(is.numeric(window) && length(window) >= 2L && inside,
         "window must be at least two rows of the forcing")
  simulate <- .multi_simulator(x$configs[[1L]], forcing)
  t <- if ("time" %in% names(forcing)) forcing$time[window] else window
  series <- .layer(t, observed[window], "Observed", .pdm_roles[["observed"]], lwd = 1.6)
  colours <- .corner_colours(length(corners))
  for (j in seq_along(corners)) {
    q <- simulate(x$configs[[corners[[j]]]])
    series <- rbind(series, .layer(t, q[window],
                                   paste("Best on", .pareto_label(names(corners)[j])),
                                   colours[j], lwd = 1.2))
  }
  q <- simulate(x$compromise$config)
  series <- rbind(series, .layer(t, q[window], "Compromise", .pdm_roles[["alternative"]],
                                 lwd = 1.8, lty = 2))
  list(series = series, xlab = if ("time" %in% names(forcing)) "" else "Row",
       ylab = "Flow (m3/s)", title = "The front's corners on one storm",
       subtitle = "The best set on each objective, and the compromise")
}

.pareto_dt <- function(config) {
  cfg <- if (is.list(config) && "pdm" %in% names(config)) config$pdm else config
  cfg$dt %||% 1
}

#' @rdname calibration_log
#' @param objectives For log_pareto_calibration(): the losses of [calibrate_pdm_multi()].
#' @param choose For log_pareto_calibration(): which front point becomes the logged run: the
#'   name of one objective (its best set), weights named by objective, or NULL for the
#'   compromise.
#' @param scales,weights,n_samples For log_pareto_calibration(): as in [calibrate_pdm_multi()].
#' @export
# A Pareto front logged as an automatic calibration whose configuration is the chosen front
# point. The whole front (parameters and losses) is kept in the entry, so the report can draw it
# and another point can be chosen later from the log alone.
log_pareto_calibration <- function(project, parent, lower, upper,
                                   objectives = c("nse_loss", "event_nse_loss", "abs_bias"),
                                   choose = NULL, scales = NULL, weights = NULL,
                                   n_samples = 64L, starts = 2L, seed = 1L,
                                   control = list(maxit = 200), method = c("dds", "lbfgsb"),
                                   reasoning, event_share = 0.5, event_screen = list(),
                                   threshold_objective = NULL, threshold_score = "csi") {
  author <- .identity("custodian")
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
  observed <- .scoring_observed(data$observed, card, "calibration")
  forcing <- as.data.frame(data$forcing)[seq_len(last), , drop = FALSE]
  front <- calibrate_pdm_multi(
    node$configuration, forcing, observed[seq_len(last)], lower, upper,
    objectives = objectives, scales = scales, weights = weights, n_samples = n_samples,
    starts = starts, seed = seed, warmup = card$calibration$first_row - 1L,
    log_offset = card$log_offset, control = control, method = method,
    event_share = .project_event_share(event_share, card),
    event_screen = .project_screen(event_screen, card), thresholds = flows,
    threshold_score = threshold_score,
    event_settings = card$events %||% list(tolerance_h = 6, gap_h = 24, min_duration_h = 0)
  )
  pick <- if (is.null(choose)) {
    pareto_choose(front)
  } else if (is.character(choose)) {
    pareto_choose(front, objective = choose)
  } else {
    pareto_choose(front, weights = choose)
  }
  run <- .run_registered(path, .project_info(entries), registration, pick$config, data = data)
  status <- data.table::rbindlist(lapply(front$optimization, function(s) {
    list(weight_row = s$weight_row, convergence = s$convergence, objective = s$value)
  }))
  status$start <- seq_len(nrow(status))
  status$best <- FALSE
  name <- paste("Pareto front of", toString(objectives))
  entry <- .append_entry(path, "auto_calibration", author, function(id, entries) {
    list(registration = registration$id, parent = node$id,
         bounds = list(lower = as.list(lower), upper = as.list(upper)),
         objective = "pareto", objective_name = name, method = method,
         evaluations = nrow(front$archive), starts = as.integer(starts), seed = seed,
         control = control, start_results = as.list(status),
         threshold_objective = threshold_objective,
         configuration = pick$config, scores = run$scores, output_md5 = run$output_md5,
         pareto = list(objectives = as.list(objectives), parameters = as.list(names(lower)),
                       scales = as.list(front$scales),
                       choice = if (is.null(choose)) "compromise" else as.list(choose),
                       chosen_row = pick$row, events = front$events,
                       front = as.list(front$pareto[, c(names(lower),
                                                        paste0("loss_", objectives)),
                                                    with = FALSE])),
         reasoning = reasoning)
  })
  logger::log_info("Pareto calibration {entry$id}: {nrow(front$pareto)} sets on the front; ",
                   "{.headline_text(registration, run$scores)}")
  invisible(entry)
}
