# ============================================================ #
# Tool:         calibrate_multi
# Description:  calibrate_pdm_multi(): weighted-sum multi-objective calibration, Pareto front,
#               with whole-record, event and threshold losses, by L-BFGS-B or DDS
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Add bounded multi-objective calibration
#               2026-11-18 - Event and threshold losses, DDS, the pdm_pareto class
# Tier:         1
# Inputs:       PDM or coupled configuration, forcing and observed flow
# Outputs:      Candidate archive, nondominated configurations and optimizer status
# Dependencies: data.table; stats
# ============================================================ #

#' Calibrate PDM or coupled snow-PDM against multiple objectives
#'
#' Searches for the trade-off between several objectives at once, and returns the Pareto
#' front: every parameter set that no other beats on all of them. Instead of one best fit for
#' one blend of objectives, the front shows what each gain costs, such as how much fit to the
#' recessions is lost for better peaks, so the choice between them is made in the open.
#'
#' The search evaluates the configured point and `n_samples` uniform random points, then, for
#' each row of `weights`, refines the `starts` best of them under that weighted, scaled sum:
#' by L-BFGS-B (`method = "lbfgsb"`) or by dynamically dimensioned search (`method = "dds"`,
#' as in [calibrate_pdm()], `control$maxit` model runs a refinement). Every evaluation is kept
#' in an archive, and the front is drawn from the whole archive. This is an approximate,
#' sampled front, not a proof of optimality: weighted sums can miss the hollows of a
#' non-convex front, so use several weight rows, repeated seeds and a validation period.
#'
#' **Objectives**, all losses to be minimised:
#'
#' | Name | Loss |
#' |---|---|
#' | `nse_loss`, `rmse`, `log_rmse`, `kge_loss`, `abs_bias`, `peak_relative_error` | See below |
#' | `event_nse_loss` | 1 - pooled event NSE over the chosen events |
#' | `event_peak_error` | Mean absolute peak error over the chosen events |
#' | `event_timing_error` | Mean absolute timing error of the events, over the response time |
#' | `threshold_loss` | 1 - the threshold score (`threshold_score`), averaged over `thresholds` |
#'
#' The first row's losses are over the whole record after the warm-up: see [pdm_objectives()].
#'
#' The event terms are those of `objective = "events"` in [calibrate_pdm()], kept apart; the
#' events are chosen the same way (`events`, `event_share`, `event_screen`). Timing and
#' threshold scores change in steps, which a gradient cannot follow: they need `method = "dds"`.
#'
#' The result has class `pdm_pareto`: [plot.pdm_pareto()] draws the front, and
#' [pareto_choose()] picks a configuration from it.
#'
#' @param config PDM configuration, or list(pdm=..., snow=...) for coupled calibration.
#' @param forcing Data frame with rain and pet; coupled runs also require temperature_c.
#' Optional time column contains POSIXct timestamps.
#' @param observed Aligned observed discharge, m3/s. Missing observations are excluded.
#' @param lower,upper Named finite bounds with identical names/order. Coupled paths
#' start with pdm. or snow., for example snow.melt_factor_mmh_c.
#' @param objectives Loss names from the table above.
#' @param scales Positive named metric divisors in objective order. NULL uses ones;
#' choose meaningful scales before interpreting weighted compromises.
#' @param weights Nonnegative named vector or matrix with objective column names in
#' order. Rows are normalized to sum one. NULL uses individual objectives and equal weights.
#' @param n_samples Nonnegative number of initial uniform random candidates.
#' @param starts Positive number of sampled starts refined per weight vector.
#' @param seed Nonnegative integer random seed.
#' @param warmup Number of initial intervals excluded from scoring, not simulation.
#' @param log_offset Positive offset for log-RMSE, m3/s.
#' @param control Control list: for L-BFGS-B, forwarded to stats::optim; for DDS, `maxit`
#'   model runs a refinement and `r` the step size.
#' @param method `"lbfgsb"` or `"dds"`.
#' @param events,event_share,event_screen How the events of the event objectives are chosen,
#'   as in [calibrate_pdm()].
#' @param thresholds,threshold_score,event_settings For `threshold_loss`: flows in m3/s, the
#'   score, and how threshold events are matched, as in [calibrate_pdm()].
#' @return A `pdm_pareto` list: `archive` (every evaluation, its raw and scaled losses and a
#'   `pareto` flag), `pareto` (the front's rows), `configs` (their configurations),
#'   `compromise` (the archived point best under the last weight row), `objectives`,
#'   `weights`, `scales`, `method`, `optimization` (each refinement's status), `events` (how
#'   many events the event objectives score, when used) and `failed_evaluations`.
#'   Candidates are not posterior probabilities.
#' @examples
#' rain <- synthetic_rain("2021-01-01", years = 1, dt = 1, seed = 2)
#' truth <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(truth), rain[c("rain", "pet")])$output$q_m3s
#' start <- truth
#' start$distribution$cmax <- 150
#' front <- calibrate_pdm_multi(
#'   start, rain[c("time", "rain", "pet")], flow,
#'   lower = c(distribution.cmax = 80, surface.k1 = 2),
#'   upper = c(distribution.cmax = 400, surface.k1 = 30),
#'   objectives = c("nse_loss", "event_peak_error"), method = "dds", n_samples = 8,
#'   starts = 1, control = list(maxit = 20), warmup = 24 * 30
#' )
#' plot(front)
#' pareto_choose(front, objective = "event_peak_error")$scores
#' @seealso [plot.pdm_pareto()], [pareto_choose()], [log_pareto_calibration()]
#' @export
# Multi-objective calibration by weighted sums. Outline: build one scorer for all the losses;
# sample random parameter sets; for each row of weights, refine the best few samples on the
# weighted, scaled losses; keep every evaluated point in an archive; and return the archive's
# Pareto front (the points no other point beats on every objective) and the best compromise
# under the last weight row.
calibrate_pdm_multi <- function(config, forcing, observed, lower, upper,
                                objectives = c("nse_loss", "log_rmse", "abs_bias"),
                                scales = NULL, weights = NULL, n_samples = 64L,
                                starts = 2L, seed = 1L, warmup = 0L, log_offset = 0.01,
                                control = list(maxit = 100), method = c("lbfgsb", "dds"),
                                events = NULL, event_share = 0.5, event_screen = list(),
                                thresholds = NULL, threshold_score = "csi",
                                event_settings = list(tolerance_h = 6, gap_h = 24,
                                                      min_duration_h = 0)) {
  method <- match.arg(method)
  .multi_check_inputs(forcing, observed, lower, upper, n_samples, starts, seed)
  .multi_check_objectives(objectives, method, thresholds)
  metrics <- .multi_metrics(config, forcing, observed, objectives, warmup, log_offset, events,
                            event_share, event_screen, thresholds, threshold_score,
                            event_settings)
  scales <- .multi_scales(scales, objectives)
  weights <- .multi_weights(weights, objectives)
  initial <- vapply(names(lower), function(p) .path_get(config, p), numeric(1))
  .check(all(initial >= lower & initial <= upper), "Initial parameters outside bounds")
  .check(!any(names(lower) %in% c("dt", "pdm.dt")), "Do not calibrate the forcing timestep")
  simulate <- .multi_simulator(config, forcing)
  build <- function(par) {
    out <- config
    for (i in seq_along(par)) out <- .path_set(out, names(lower)[i], unname(par[i]))
    out
  }
  # Fail early on invalid forcing/configuration rather than hiding it as bad trials.
  first <- metrics$score(simulate(config))
  .check(all(is.finite(first)), "The configured model's losses are not finite")
  evaluations <- new.env(parent = emptyenv())
  evaluations$archive <- list()
  evaluations$failures <- 0L
  # Runs one point of the unit box: archives its raw losses and returns them divided by the
  # scales, so that objectives in different units can be weighted together. A failed trial is
  # counted and given huge losses rather than stopping the search.
  evaluate <- function(z) {
    par <- lower + z * (upper - lower)
    values <- tryCatch(metrics$score(simulate(build(par))), error = function(e) {
      logger::log_debug("Rejected multi-objective trial: {conditionMessage(e)}")
      NULL
    })
    if (is.null(values) || !all(is.finite(values))) {
      evaluations$failures <- evaluations$failures + 1L
      return(rep(1e30, length(objectives)))
    }
    evaluations$archive[[length(evaluations$archive) + 1L]] <- c(par, stats::setNames(
      values,
      paste0("loss_", objectives)
    ))
    values / scales
  }
  status <- .with_seed(seed, .multi_search(
    evaluate, (initial - lower) / (upper - lower), n_samples, weights, starts, control, method
  ))
  out <- .multi_results(evaluations, objectives, scales, weights, lower, build, status)
  out$objectives <- objectives
  out$method <- method
  out$events <- metrics$events
  out$parameters <- names(lower)
  structure(out, class = c("pdm_pareto", "list"))
}

# The losses calibrate_pdm_multi() accepts: the whole-record ones of pdm_objectives(), the
# three event terms, and the threshold loss.
.multi_whole <- c("rmse", "log_rmse", "nse_loss", "kge_loss", "abs_bias",
                  "peak_relative_error")
.multi_event <- c(event_nse_loss = "nse", event_peak_error = "peak",
                  event_timing_error = "timing")
.multi_allowed <- c(.multi_whole, names(.multi_event), "threshold_loss")

# Objective names must be known and unique; losses that change in steps need DDS; the threshold
# loss needs thresholds.
.multi_check_objectives <- function(objectives, method, thresholds) {
  .check(is.character(objectives) && length(objectives) > 0 && !anyDuplicated(objectives) &&
           all(objectives %in% .multi_allowed),
         paste("objectives must be unique names from:", toString(.multi_allowed)))
  steps <- intersect(objectives, c("event_timing_error", "threshold_loss"))
  .check(!length(steps) || method == "dds", paste0(
    toString(steps), " changes in steps, which a gradient optimiser cannot follow; ",
    "use method = \"dds\""
  ))
  .check(!"threshold_loss" %in% objectives || length(thresholds) > 0,
         "threshold_loss needs thresholds")
  invisible(TRUE)
}

# Thresholds for the threshold loss: positive flows, a known score, and reached at least once.
.multi_check_thresholds <- function(thresholds, score, observed) {
  .check(is.numeric(thresholds) && all(is.finite(thresholds) & thresholds > 0),
         "thresholds must be positive flows in m3/s")
  .check(score %in% names(.threshold_headlines),
         paste("threshold_score must be one of:", toString(names(.threshold_headlines))))
  .check(any(observed >= min(thresholds), na.rm = TRUE),
         "No threshold is reached by the observed flow after the warm-up")
}

# One scorer for every loss: a function of the simulated flow returning the named losses in
# objective order. The events and threshold settings are worked out once, here.
.multi_metrics <- function(config, forcing, observed, objectives, warmup, log_offset, events,
                           event_share, event_screen, thresholds, threshold_score,
                           event_settings) {
  whole <- intersect(objectives, .multi_whole)
  if (length(whole)) pdm_objectives(observed, observed, whole, warmup, log_offset)
  pdm_cfg <- if (is.list(config) && "pdm" %in% names(config)) config$pdm else config
  model <- pdm_from_config(pdm_cfg)
  terms <- if (any(objectives %in% names(.multi_event))) {
    .event_terms(events, forcing$rain, observed, warmup, model@dt, event_share, event_screen,
                 model@area_km2, if ("time" %in% names(forcing)) forcing$time)
  }
  scored <- seq_along(observed) > warmup
  if ("threshold_loss" %in% objectives) {
    .multi_check_thresholds(thresholds, threshold_score, observed[scored])
  }
  score <- function(sim) {
    out <- stats::setNames(numeric(length(objectives)), objectives)
    if (length(whole)) out[whole] <- pdm_objectives(sim, observed, whole, warmup, log_offset)
    if (!is.null(terms)) {
      t <- terms$terms(sim)
      if (is.null(t)) return(rep(NA_real_, length(objectives)))
      for (o in intersect(objectives, names(.multi_event))) out[[o]] <- t[[.multi_event[[o]]]]
    }
    if ("threshold_loss" %in% objectives) {
      out[["threshold_loss"]] <- .threshold_loss(sim[scored], observed[scored], thresholds,
                                                 threshold_score, event_settings, model@dt)
    }
    out
  }
  list(score = score, events = .multi_event_summary(terms))
}

# How many events the event losses score, of how many found, for the result.
.multi_event_summary <- function(terms) {
  if (is.null(terms)) return(NULL)
  list(scored = terms$events, found = terms$found, which = terms$which,
       response_h = terms$response_h)
}

# Argument checks for calibrate_pdm_multi().
.multi_check_inputs <- function(forcing, observed, lower, upper, n_samples, starts, seed) {
  .check(is.data.frame(forcing) && all(c("rain", "pet") %in% names(forcing)) &&
           nrow(forcing) == length(observed), "Forcing needs aligned rain, pet and observations")
  .check(.named_bounds(lower, upper), "Supply finite, uniquely named ordered bounds")
  .check(.whole(n_samples, 0, 100000) && .whole(starts, 1, 1000) &&
           .whole(seed, 0, .Machine$integer.max), "Invalid search controls")
}

# TRUE if every argument is TRUE. Arguments are evaluated in order and only until one fails,
# as with &&, so later checks may assume earlier ones.
.all_of <- function(...) {
  for (i in seq_len(...length())) {
    if (!isTRUE(...elt(i))) return(FALSE)
  }
  TRUE
}

# Finite, uniquely named lower and upper bounds in the same order, lower below upper.
.named_bounds <- function(lower, upper) {
  .all_of(
    is.numeric(lower), is.numeric(upper), length(lower) > 0, !is.null(names(lower)),
    identical(names(lower), names(upper)), !anyDuplicated(names(lower)),
    all(is.finite(c(lower, upper))), all(lower < upper)
  )
}

# A whole number within [lo, hi].
.whole <- function(x, lo, hi) .scalar(x, lo, hi) && x == floor(x)

# Divisors that bring each objective to a comparable size before weighting; one by default.
.multi_scales <- function(scales, objectives) {
  if (is.null(scales)) scales <- stats::setNames(rep(1, length(objectives)), objectives)
  .check(is.numeric(scales) && identical(names(scales), objectives) &&
           all(is.finite(scales)) && all(scales > 0),
         "scales must be positive and named in metric order")
  scales
}

# Weight rows, each normalised to sum to one. By default: each objective alone, then all equally,
# which traces the corners of the trade-off and one balanced compromise.
.multi_weights <- function(weights, objectives) {
  k <- length(objectives)
  if (is.null(weights)) {
    weights <- rbind(diag(k), rep(1 / k, k))
    colnames(weights) <- objectives
  } else if (is.numeric(weights) && is.null(dim(weights))) {
    weights <- matrix(weights, nrow = 1, dimnames = list(NULL, names(weights)))
  }
  .check(.all_of(
    is.matrix(weights), is.numeric(weights), nrow(weights) > 0,
    identical(colnames(weights), objectives), all(is.finite(weights)), all(weights >= 0),
    all(rowSums(weights) > 0)
  ), "Invalid objective weights")
  weights / rowSums(weights)
}

# Simulated flow for a configuration, coupled to PACK when the configuration has a pdm part.
.multi_simulator <- function(config, forcing) {
  coupled <- is.list(config) && "pdm" %in% names(config)
  dt <- (if (coupled) config$pdm$dt else config$dt) %||% 1
  .check(
    .scalar(dt, 0, strict = TRUE) && abs(dt * 60 - round(dt * 60)) < 1e-8,
    "Calibration timestep must be a whole number of minutes"
  )
  time <- if ("time" %in% names(forcing)) forcing$time else NULL
  if (coupled) {
    function(cfg) {
      .check("temperature_c" %in% names(forcing), "Coupled forcing needs temperature_c")
      sim_snow_pdm(forcing$rain, forcing$temperature_c, forcing$pet, cfg,
        timestep_min = round(dt * 60), datetime = time
      )$qsim_cms
    }
  } else {
    function(cfg) {
      .quietly(sim_pdm(forcing$rain, forcing$pet, cfg, round(dt * 60), datetime = time))$qsim_cms
    }
  }
}

# Runs code with the random seed set, restoring the caller's random number state after.
.with_seed <- function(seed, code) {
  name <- ".Random.seed"
  had <- exists(name, envir = .GlobalEnv, inherits = FALSE)
  if (had) old <- get(name, envir = .GlobalEnv)
  on.exit(
    if (had) {
      assign(name, old, envir = .GlobalEnv)
    } else if (exists(name, envir = .GlobalEnv, inherits = FALSE)) {
      rm(list = name, envir = .GlobalEnv)
    },
    add = TRUE
  )
  set.seed(seed)
  force(code)
}

# The search: the configured point plus n_samples uniform random points, all evaluated; then, for
# each weight row, the 'starts' best of them under that weighting are refined by L-BFGS-B or DDS.
# Returns each refinement's convergence status. Every evaluation lands in the archive as a side
# effect.
.multi_search <- function(evaluate, z0, n_samples, weights, starts, control, method = "lbfgsb") {
  candidates <- rbind(z0, matrix(stats::runif(n_samples * length(z0)), ncol = length(z0)))
  losses <- do.call(rbind, lapply(seq_len(nrow(candidates)), function(i) evaluate(candidates[i, ])))
  status <- list()
  for (w in seq_len(nrow(weights))) {
    order <- order(as.vector(losses %*% weights[w, ]))
    for (j in order[seq_len(min(length(order), starts))]) {
      loss <- function(z) sum(evaluate(z) * weights[w, ])
      fit <- if (method == "dds") {
        .dds_box(candidates[j, ], loss, control)
      } else {
        stats::optim(candidates[j, ], loss, method = "L-BFGS-B", lower = rep(0, length(z0)),
                     upper = rep(1, length(z0)), control = control)
      }
      status[[length(status) + 1L]] <- list(
        weight_row = w, convergence = fit$convergence,
        message = fit$message, value = fit$value
      )
    }
  }
  status
}

# Builds the result: the archive with scaled losses and a Pareto flag, the configurations on the
# front, and the compromise, the archived point best under the last (by default equal) weights.
.multi_results <- function(evaluations, objectives, scales, weights, lower, build, status) {
  table <- unique(data.table::rbindlist(lapply(evaluations$archive, as.list)))
  loss_names <- paste0("loss_", objectives)
  raw <- as.matrix(table[, loss_names, with = FALSE])
  normalized <- sweep(raw, 2, scales, "/")
  front <- pareto_front(raw)
  data.table::set(table, j = "pareto", value = front)
  for (i in seq_along(objectives)) {
    data.table::set(table, j = paste0("scaled_", objectives[i]), value = normalized[, i])
  }
  configs <- lapply(seq_len(nrow(table)), function(i) {
    build(unlist(table[i, names(lower), with = FALSE]))
  })
  best <- which.min(as.vector(normalized %*% weights[nrow(weights), ]))
  list(
    archive = table, pareto = table[which(front)], configs = configs[which(front)],
    compromise = list(config = configs[[best]], scores = table[best]),
    weights = weights, scales = scales, optimization = status,
    failed_evaluations = evaluations$failures
  )
}
