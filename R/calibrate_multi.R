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
#' The search first evaluates the configured point and `n_samples` uniform random points.
#' Then, by default (`method = "padds"`), it grows the front directly by Pareto-archived
#' dynamically dimensioned search (PA-DDS; Asadzadeh and Tolson, 2013): `starts` chains of
#' `control$maxit` model runs each, every chain keeping the sets no other set it has seen beats,
#' perturbing one of them at a time as DDS does and favouring sets in sparse parts of the front,
#' so the search spreads along all of it, hollows included. The other methods minimise weighted
#' sums instead: for each row of `weights`, the `starts` best samples under that weighting are
#' refined by DDS (`"dds"`, `control$maxit` model runs each), L-BFGS-B (`"lbfgsb"`) or
#' Nelder-Mead (`"nelder_mead"`). Weighted sums can miss the hollows of a non-convex front.
#' Every evaluation is kept, and the front is drawn from all of them; it is still a sampled
#' front, not a proof of optimality, so check it with another seed and on a validation period
#' ([pareto_validate()]).
#'
#' Each trial runs as in [calibrate_pdm()]: from the same start (`start`, `start_flow`,
#' `baseflow_fraction`, `soil_fraction`), on the same engine, with parameters searched on a log
#' scale where `log_scale` says. The chains or refinements run side by side on `cores` cores,
#' each with its own seed, so the answer does not depend on the number of cores. A coupled
#' snow-PDM configuration runs through [sim_snow_pdm()] from its default state.
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
#' threshold scores change in steps, which a gradient cannot follow: they need a method other
#' than `"lbfgsb"`.
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
#' @param starts For PA-DDS, the number of chains; otherwise the number of sampled starts
#'   refined per weight vector.
#' @param seed Nonnegative integer random seed.
#' @param warmup Number of initial intervals excluded from scoring, not simulation.
#' @param log_offset Positive offset for log-RMSE, m3/s.
#' @param control Control list: for PA-DDS and DDS, `maxit` model runs a chain or refinement
#'   and `r` the step size; otherwise forwarded to the optimiser.
#' @param method `"padds"`, `"dds"`, `"lbfgsb"` or `"nelder_mead"`.
#' @param log_scale Parameters searched uniformly in log(value), as in [calibrate_pdm()].
#' @param start,baseflow_fraction,soil_fraction,start_flow How each trial starts, as in
#'   [calibrate_pdm()]: in steady state at the first observed flow (`"flow"`) or from a soil
#'   fraction (`"soil"`).
#' @param flow The flow column scored, as in [calibrate_pdm()].
#' @param cores Cores for the chains or refinements.
#' @param events,event_share,event_screen How the events of the event objectives are chosen,
#'   as in [calibrate_pdm()].
#' @param thresholds,threshold_score,event_settings For `threshold_loss`: flows in m3/s, the
#'   score, and how threshold events are matched, as in [calibrate_pdm()].
#' @return A `pdm_pareto` list: `archive` (every evaluation, its raw and scaled losses and a
#'   `pareto` flag), `pareto` (the front's rows), `configs` (their configurations),
#'   `compromise` (the archived point best under the last weight row), `objectives`,
#'   `weights`, `scales`, `method`, `optimization` (each chain's or refinement's status),
#'   `events` (how many events the event objectives score, when used), `settings` (the start
#'   and scoring settings, for [pareto_validate()]) and `failed_evaluations`.
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
#'   objectives = c("nse_loss", "event_peak_error"), n_samples = 8,
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
                                control = list(maxit = 100),
                                method = c("padds", "dds", "lbfgsb", "nelder_mead"),
                                events = NULL, event_share = 0.5, event_screen = list(),
                                thresholds = NULL, threshold_score = "csi",
                                event_settings = list(tolerance_h = 6, gap_h = 24,
                                                      min_duration_h = 0),
                                log_scale = character(0), start = c("flow", "soil"),
                                baseflow_fraction = 0.7, soil_fraction = 0.5,
                                start_flow = NULL, flow = c("q_m3s", "q_end_m3s"),
                                cores = getOption("pdmS7.cores", 1L)) {
  method <- match.arg(method)
  start <- match.arg(start)
  flow <- match.arg(flow)
  .multi_check_inputs(forcing, observed, lower, upper, n_samples, starts, seed)
  .multi_check_objectives(objectives, method, thresholds)
  .check(.whole(cores, 1, Inf), "cores must be a whole number of at least 1")
  settings <- list(
    warmup = warmup, log_offset = log_offset, events = events, event_share = event_share,
    event_screen = event_screen, thresholds = thresholds, threshold_score = threshold_score,
    event_settings = event_settings, start = start, baseflow_fraction = baseflow_fraction,
    soil_fraction = soil_fraction, flow = flow,
    start_flow = start_flow %||% observed[is.finite(observed)][1L]
  )
  metrics <- .multi_metrics(config, forcing, observed, objectives, settings)
  scales <- .multi_scales(scales, objectives)
  weights <- .multi_weights(weights, objectives)
  initial <- vapply(names(lower), function(p) .path_get(config, p), numeric(1))
  .check(all(initial >= lower & initial <= upper), "Initial parameters outside bounds")
  .check(!any(names(lower) %in% c("dt", "pdm.dt")), "Do not calibrate the forcing timestep")
  box <- .search_box(lower, upper, log_scale)
  simulate <- .multi_simulator(config, forcing, settings)
  build <- function(par) {
    out <- config
    for (i in seq_along(par)) out <- .path_set(out, names(lower)[i], unname(par[i]))
    out
  }
  # Fail early on invalid forcing/configuration rather than hiding it as bad trials.
  first <- metrics$score(simulate(config))
  .check(all(is.finite(first)), "The configured model's losses are not finite")
  # An evaluator writing to its own store: the trial's parameters and raw losses are archived,
  # and its losses divided by the scales are returned, so that objectives in different units can
  # be weighted together. A failed trial is counted and given huge losses rather than stopping
  # the search. Each search job has its own store, so jobs can run in other processes.
  make_evaluator <- function(store, beat) {
    function(z) {
      beat$tick()
      par <- box$to_value(z)
      values <- tryCatch(metrics$score(simulate(build(par))), error = function(e) {
        logger::log_debug("Rejected multi-objective trial: {conditionMessage(e)}")
        NULL
      })
      if (is.null(values) || !all(is.finite(values))) {
        store$failures <- store$failures + 1L
        return(rep(1e30, length(objectives)))
      }
      store$archive[[length(store$archive) + 1L]] <- c(par, stats::setNames(
        values, paste0("loss_", objectives)
      ))
      values / scales
    }
  }
  search <- .with_seed(seed, .multi_search(
    make_evaluator, box$to_unit(initial), n_samples, weights, starts, control, method, seed,
    cores
  ))
  out <- .multi_results(search, objectives, scales, weights, names(lower), build)
  out$objectives <- objectives
  out$method <- method
  out$events <- metrics$events
  out$parameters <- names(lower)
  out$log_scale <- log_scale
  out$settings <- settings
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
  .check(!length(steps) || method != "lbfgsb", paste0(
    toString(steps), " changes in steps, which a gradient optimiser cannot follow; ",
    "use method = \"padds\", \"dds\" or \"nelder_mead\""
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
.multi_metrics <- function(config, forcing, observed, objectives, settings) {
  warmup <- settings$warmup
  log_offset <- settings$log_offset
  thresholds <- settings$thresholds
  threshold_score <- settings$threshold_score
  event_settings <- settings$event_settings
  whole <- intersect(objectives, .multi_whole)
  if (length(whole)) pdm_objectives(observed, observed, whole, warmup, log_offset)
  pdm_cfg <- if (is.list(config) && "pdm" %in% names(config)) config$pdm else config
  model <- pdm_from_config(pdm_cfg)
  terms <- if (any(objectives %in% names(.multi_event))) {
    .event_terms(settings$events, forcing$rain, observed, warmup, model@dt,
                 settings$event_share, settings$event_screen, model@area_km2,
                 if ("time" %in% names(forcing)) forcing$time)
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

# Simulated flow for a configuration. A PDM trial starts the way calibrate_pdm() starts it, by
# the start rule of `settings` (steady state at the first observed flow, or a soil fraction),
# and runs on the same engine. A configuration with a pdm part is coupled to PACK and starts
# from PACK's own default state.
.multi_simulator <- function(config, forcing, settings = list(start = "soil")) {
  coupled <- is.list(config) && "pdm" %in% names(config)
  dt <- (if (coupled) config$pdm$dt else config$dt) %||% 1
  .check(
    .scalar(dt, 0, strict = TRUE) && abs(dt * 60 - round(dt * 60)) < 1e-8,
    "Calibration timestep must be a whole number of minutes"
  )
  time <- if ("time" %in% names(forcing)) forcing$time else NULL
  if (coupled) {
    return(function(cfg) {
      .check("temperature_c" %in% names(forcing), "Coupled forcing needs temperature_c")
      sim_snow_pdm(forcing$rain, forcing$temperature_c, forcing$pet, cfg,
        timestep_min = round(dt * 60), datetime = time
      )$qsim_cms
    })
  }
  start <- settings$start %||% "soil"
  function(cfg) {
    mod <- pdm_from_config(cfg)
    state <- suppressWarnings(.start_state(mod, start, settings$start_flow,
                                           settings$baseflow_fraction %||% 0.7,
                                           settings$soil_fraction %||% 0.5))
    .quietly(.run_flow(mod, forcing, state, settings$flow %||% "q_m3s"))
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

# A store for one search job's evaluations.
.eval_store <- function() {
  store <- new.env(parent = emptyenv())
  store$archive <- list()
  store$failures <- 0L
  store
}

# The search. First the configured point and n_samples uniform random points are evaluated.
# Then the jobs: for PA-DDS, `starts` chains, each grown from the front of those samples; for the
# weighted methods, for each weight row, the `starts` best samples under that weighting refined
# by DDS, L-BFGS-B or Nelder-Mead. Each job has its own seed and store, so jobs give the same
# results one by one or side by side on several cores. Returns every archived evaluation, the
# failures and each job's status.
.multi_search <- function(make_evaluator, z0, n_samples, weights, starts, control, method,
                          seed, cores) {
  main <- .eval_store()
  sample_beat <- .heartbeat(1L, n_samples + 1L)
  evaluate <- make_evaluator(main, sample_beat)
  k <- length(z0)
  candidates <- rbind(z0, matrix(stats::runif(n_samples * k), ncol = k))
  losses <- do.call(rbind, lapply(seq_len(nrow(candidates)), function(i) {
    evaluate(candidates[i, ])
  }))
  jobs <- if (method == "padds") {
    lapply(seq_len(starts), function(j) list(id = j, weight_row = NA_integer_))
  } else {
    unlist(lapply(seq_len(nrow(weights)), function(w) {
      order <- order(as.vector(losses %*% weights[w, ]))
      lapply(order[seq_len(min(length(order), starts))], function(j) {
        list(weight_row = w, z = candidates[j, ])
      })
    }), recursive = FALSE)
  }
  for (i in seq_along(jobs)) jobs[[i]]$id <- i
  budget <- control$maxit %||% 100L
  beat <- .heartbeat(length(jobs), if (method %in% c("padds", "dds")) budget)
  run <- function(job) {
    store <- .eval_store()
    beat$start(job$id)
    ev <- make_evaluator(store, beat)
    fit <- .seeded(if (!is.null(seed)) seed + job$id, switch(method,
      padds = .padds(ev, candidates, losses, control),
      dds = .dds_box(job$z, function(z) sum(ev(z) * weights[job$weight_row, ]), control),
      nelder_mead = .nelder_mead_box(job$z, function(z) sum(ev(z) * weights[job$weight_row, ]),
                                     control),
      lbfgsb = stats::optim(job$z, function(z) sum(ev(z) * weights[job$weight_row, ]),
                            method = "L-BFGS-B", lower = rep(0, k), upper = rep(1, k),
                            control = control)
    ))
    list(status = list(job = job$id, weight_row = job$weight_row,
                       convergence = fit$convergence, message = fit$message, value = fit$value),
         archive = store$archive, failures = store$failures)
  }
  workers <- min(as.integer(cores), length(jobs))
  if (workers > 1L) .progress_say(sprintf("%d searches on %d cores", length(jobs), workers))
  runs <- .run_jobs(jobs, run, workers)
  list(archive = c(main$archive, do.call(c, lapply(runs, `[[`, "archive"))),
       failures = main$failures + sum(vapply(runs, `[[`, integer(1), "failures")),
       status = lapply(runs, `[[`, "status"))
}

# Pareto-archived dynamically dimensioned search (PA-DDS; Asadzadeh and Tolson, 2013). It grows
# a front directly instead of minimising weighted sums. It keeps an archive of the sets no other
# set it has seen beats, starting from the front of the sampled points (`z`, unit box, with
# losses `f`). Each step perturbs the current set as DDS does: each coordinate with probability
# 1 - log(i) / log(budget + 1), so the search starts global and ends local, by a normal step of
# sd r, reflected at the bounds. A trial no archived set dominates joins the archive, pushes out
# the sets it dominates, and becomes the current set; otherwise the next current set is drawn
# from the archive, favouring sets in sparse parts of the front (crowding distance), so the
# search spreads along the whole front. The losses are compared raw: positive scales do not
# change who dominates whom.
.padds <- function(evaluate, z, f, control) {
  budget <- control$maxit %||% 100L
  r <- control$r %||% 0.2
  .check(.whole(budget, 1, Inf), "control$maxit must be a whole number of model runs")
  .check(.scalar(r, 0, strict = TRUE), "control$r must be a positive number")
  ok <- apply(f < 1e29, 1, all)
  .check(any(ok), "No sampled set could be scored, so PA-DDS has nothing to start from")
  z <- z[ok, , drop = FALSE]
  f <- f[ok, , drop = FALSE]
  front <- pareto_front(f)
  zs <- z[front, , drop = FALSE]
  fs <- f[front, , drop = FALSE]
  n <- ncol(zs)
  k <- ncol(fs)
  current <- .padds_select(fs)
  for (i in seq_len(budget)) {
    chosen <- stats::runif(n) < 1 - log(i) / log(budget + 1)
    if (!any(chosen)) chosen[sample.int(n, 1L)] <- TRUE
    trial <- .dds_perturb(zs[current, ], chosen, r)
    ft <- evaluate(trial)
    if (any(ft >= 1e29)) {
      current <- .padds_select(fs)
      next
    }
    ftm <- matrix(ft, nrow(fs), k, byrow = TRUE)
    beaten <- any(rowSums(fs <= ftm) == k & rowSums(fs < ftm) > 0)
    same <- any(rowSums(fs == ftm) == k)
    if (beaten || same) {
      current <- .padds_select(fs)
      next
    }
    keep <- !(rowSums(ftm <= fs) == k & rowSums(ftm < fs) > 0)
    zs <- rbind(zs[keep, , drop = FALSE], trial)
    fs <- rbind(fs[keep, , drop = FALSE], ft)
    current <- nrow(zs)
  }
  list(par = zs[1L, ], value = nrow(zs), convergence = 0L,
       message = sprintf("PA-DDS: %d model runs, %d sets on its front", budget, nrow(zs)))
}

# A set drawn from the archive with probability in proportion to its crowding distance.
.padds_select <- function(f) {
  m <- nrow(f)
  if (m <= 2L) return(sample.int(m, 1L))
  sample.int(m, 1L, prob = .crowding_weights(f) + 1e-12)
}

# Each set's crowding distance: the sum over objectives of the gap between its two neighbours,
# over the front's range. The two ends of each objective, whose distance is infinite, get twice
# the largest finite distance, so the extremes keep being pushed outwards.
.crowding_weights <- function(f) {
  m <- nrow(f)
  d <- numeric(m)
  for (j in seq_len(ncol(f))) {
    o <- order(f[, j])
    span <- f[o[m], j] - f[o[1L], j]
    d[o[c(1L, m)]] <- Inf
    if (span > 0 && m > 2L) {
      mid <- o[2:(m - 1L)]
      d[mid] <- d[mid] + (f[o[3:m], j] - f[o[1:(m - 2L)], j]) / span
    }
  }
  finite <- is.finite(d)
  top <- if (any(finite & d > 0)) max(d[finite]) else 1
  d[!finite] <- 2 * top
  d
}

# Builds the result: the archive with scaled losses and a Pareto flag, the configurations on the
# front, and the compromise, the archived point best under the last (by default equal) weights.
.multi_results <- function(search, objectives, scales, weights, parameters, build) {
  table <- unique(data.table::rbindlist(lapply(search$archive, as.list)))
  loss_names <- paste0("loss_", objectives)
  raw <- as.matrix(table[, loss_names, with = FALSE])
  normalized <- sweep(raw, 2, scales, "/")
  front <- pareto_front(raw)
  data.table::set(table, j = "pareto", value = front)
  for (i in seq_along(objectives)) {
    data.table::set(table, j = paste0("scaled_", objectives[i]), value = normalized[, i])
  }
  config_of <- function(i) build(unlist(table[i, parameters, with = FALSE]))
  best <- which.min(as.vector(normalized %*% weights[nrow(weights), ]))
  list(
    archive = table, pareto = table[which(front)], configs = lapply(which(front), config_of),
    compromise = list(config = config_of(best), scores = table[best]),
    weights = weights, scales = scales, optimization = search$status,
    failed_evaluations = search$failures
  )
}
