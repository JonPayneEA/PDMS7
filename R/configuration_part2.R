# ============================================================ #
# Tool:         configuration
# Description:  calibrate_pdm(): single-objective calibration, multi-start, log scales
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
#               2026-11-10 - A heartbeat during long searches (see R/progress.R)
# Tier:         1
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #
#' Calibrate pdm
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param config Named model configuration list; unknown keys are rejected.
#' @param forcing Data frame or data.table with rain and pet depths in mm per interval; optional
#' POSIXct time.
#' @param observed Observed discharges in cubic metres per second, aligned to forcing or
#' simulation.
#' @param lower Finite named lower calibration bounds. Names are configuration paths such as
#' surface.k1.
#' @param upper Finite named upper calibration bounds with the same names/order as lower.
#' @param warmup Number of initial forcing steps excluded from calibration scoring, but still
#' simulated.
#' @param objective Calibration objective: rmse, nse (minimizes 1-NSE), log_rmse, log_nse
#' (minimizes 1 minus NSE of log flows, which weights low flows), boxcox (1 minus NSE of
#' Box-Cox transformed flows, see [boxcox_flow()]: errors of about the same size at every flow,
#' as least squares assumes, optionally weighted by `weights`), threshold (the threshold
#' term alone; needs thresholds), or events, which scores only the largest events: see
#' `events`.
#' @param boxcox_lambda The Box-Cox power for `objective = "boxcox"`, 0 (log) to 1 (raw).
#' @param weights For `objective = "boxcox"`: `NULL`, or one nonnegative weight for each
#'   observed flow, such as [flow_weights()] gives from rating uncertainty.
#' @param mask `NULL`, or `TRUE` or `FALSE` for each observed flow, from [calibration_mask()]:
#'   the steps to score. The model runs through every step and events are found on the whole
#'   record; masked steps are left out of every term of the objective, and an event whose peak
#'   is masked is dropped from the events objective whole.
#' @param band `NULL`, or each step's `lower` and `upper` shares from [peak_band()]: the peak
#'   tolerance. A simulated flow inside the band scores as a perfect fit, and one outside it as
#'   out by its distance from the band ([tolerate()]). Leave it `NULL` when the forecasts go
#'   back through the same rating, as the rating's error then cancels.
#' @param flow Series to score: q_m3s (interval mean) or q_end_m3s (endpoint flow).
#' @param log_offset Positive offset added before logarithms in log-RMSE and log NSE, cubic
#' metres per second.
#' @param control Named control list forwarded to stats::optim.
#' @param soil_fraction Initial fraction of basin capacity between zero and one: the soil store's
#' start with `start = "soil"`, and with split recharge, whose soil level the flow does not set.
#' @param start How every trial starts. `"flow"` (the default) starts in steady state at the
#' first observed flow, as [initial_state_from_flow()] does, so that a slow groundwater store
#' is already full when scoring begins and does not bias its own parameters. `"soil"` starts
#' with the soil store `soil_fraction` full and the routing stores empty, the behaviour before
#' version 0.4.1; it then needs a warm-up long enough for the slowest store to fill.
#' @param baseflow_fraction With `start = "flow"`, the share of the first flow that is baseflow.
#' @param start_flow With `start = "flow"`, the flow to start from, m3/s. By default the first
#' observed value of `observed`.
#' @param starts Positive integer number of optimiser starts. The default, 1, runs a single
#' start from the values in config, as earlier versions did. With more than one,
#' the first start is still the values in config and the others are drawn uniformly inside
#' lower and upper. Every start is optimised and the best objective is returned.
#' @param seed Optional finite number that seeds the random starting points and, with
#' `method = "dds"`, the search itself. The caller's random number state is restored on exit.
#' Without `dds`, it has no effect when starts is 1.
#' @param method Optimiser: `lbfgsb` (default), gradient-based and fast for smooth objectives,
#' or `nelder_mead`, derivative-free, needed for threshold objectives because event counts
#' change in steps. Nelder-Mead works on a logistic transform of the unit box, so every
#' trial stays within lower and upper; it usually needs several times more model runs. Or
#' `dds`, dynamically dimensioned search (Tolson and Shoemaker, 2007), a derivative-free global
#' search built for watershed models: it perturbs a random subset of parameters around the best
#' point so far, starting with all of them and narrowing to one or two as the budget runs out.
#' With `dds`, `control$maxit` is the number of model runs per start (200 if not given), and
#' `control$r`, the perturbation size as a fraction of each range, defaults to 0.2. It also
#' accepts threshold objectives. On the smooth NSE of the standard structure, L-BFGS-B is the
#' better choice: on 30 synthetic catchments, given the same number of model runs (about 560
#' per start), DDS fitted less well in every one of them. DDS suits objectives with steps or many
#' local optima, and budgets of thousands of runs per start.
#' @param thresholds Optional named vector of threshold flows, m3/s. The objective then
#' becomes the continuous objective plus `threshold_weight` times the mean over thresholds
#' of the threshold loss (1 - score, or the score itself for false alarm ratios), from
#' [pdm_threshold_scores()] over the scored rows. An undefined score counts as the worst.
#' Requires `method = "nelder_mead"` or `"dds"`, and at least one observed event at each
#' threshold.
#' @param threshold_weight Nonnegative weight of the threshold term.
#' @param threshold_score Threshold score: `csi` (default), `pod`, `far`, `csi_step`,
#' `pod_step`, `far_step`, `ets_step` or `pss_step`.
#' @param event_settings List of `tolerance_h`, `gap_h` and `min_duration_h` for event
#' matching; see [pdm_threshold_scores()].
#' @param log_scale Names of parameters to search on a logarithmic scale, so that each
#' tenfold step gets equal room. Use it for parameters spanning orders of magnitude, such as
#' recharge.kg or groundwater.kb. Their lower bounds must be positive. Results stay in the
#' parameters' own units.
#' @param volume_weight Nonnegative weight of a volume penalty added to the objective: the
#' weight times the absolute relative error in total flow over the scored rows. Zero, the
#' default, adds nothing. [calibrate_staged()] uses it to hold the water balance while fitting
#' low flows.
#' @param events With `objective = "events"`, the events to score, from [find_events()]; by
#' default they are found from `forcing$rain` and `observed`. Only events whose flow window
#' lies wholly after the warm-up count, and of those the largest `event_share` by observed
#' peak. The objective is `w_nse` times (1 - pooled event NSE) plus `w_peak` times the mean
#' absolute peak error plus `w_timing` times the mean absolute timing error divided by the
#' response time (see [find_events()]), with weights from `event_weights`. The pooled event NSE
#' sums squared errors over every chosen window and divides by the squared deviations from
#' each window's own mean flow, so long recessions between events do not count. The timing
#' term changes in steps, so use `method = "dds"` or `"nelder_mead"`.
#' @param event_weights Named weights `nse`, `peak` and `timing` of the three terms.
#' @param event_share Share of the events, largest observed peak first, that are scored. Or a
#'   flow floor, so that every event whose observed peak reaches it is scored: a marker of
#'   [flow_markers()] such as `"Q1"` or `"0.5QMED"`, worked out from `observed`, or
#'   `c(peak = 12.5)` for a flow in m3/s. In a project, the name of a registered threshold, or
#'   a multiple of one such as `"0.5QMED"`, uses its registered flow.
#' @param event_screen Settings for [screen_events()], which leaves out events with a rise lost
#' in the baseflow, more quick flow than rain, or gaps; `NULL` scores every event.
#' @param cores Number of R processes to run the starts in, side by side: the starts are
#' independent, so the result is the same as running them one after another. Each process is a
#' fresh R session (a socket cluster, which works on Windows) and takes a few seconds to start,
#' so more than one core pays only for long records or large budgets. Defaults to the
#' `pdmS7.cores` option, which [calibrate_project()] sets from its own `cores`, or 1.
#' @param archive Optional function of the full simulated flow returning one number. When given,
#' every trial's parameters and that number are kept, and returned as `trials`. Calibration
#' projects use it to record the headline score of each trial, from which the equally good
#' parameter sets are drawn.
#'
#' @return A list of config, model, parameters, objective, convergence, message, optim
#' diagnostics, and start_results. The first six describe the best start; optim is its
#' stats::optim result. start_results is a data.table with one row per start: start (1 is the
#' configured point), objective (on the scale given by objective_name, 1e+30 if no valid
#' evaluation), convergence (the stats::optim code), evaluations (every objective call,
#' including the finite-difference gradient calls that stats::optim counts leave out),
#' best (TRUE for the returned start), and one column per calibrated parameter holding the
#' fitted value, which always lies within lower and upper. With `archive`, also `trials`, a
#' data.table of every valid trial's `score` and parameter values, with the trials' positions
#' in the unit search box as its `unit` attribute. With `mask` or `band`, also `scoring`:
#' `masked_steps` (observed steps after the warm-up left out), `scored_steps`,
#' `peak_tolerance` (whether a band was applied) and `band_widest` (the band's widest shares).
#'
#' @examples
#' config <- pdm_presets('standard')
#' f <- data.frame(rain = c(0, 10, 2, 0), pet = rep(0.05, 4))
#' q <- run_pdm(pdm_from_config(config), f)$output$q_m3s
#' calibrate_pdm(config, f, q, lower = c(fc = 0.8), upper = c(fc = 1.2),
#'   control = list(maxit = 2))
#' calibrate_pdm(config, f, q, lower = c(fc = 0.8), upper = c(fc = 1.2),
#'   control = list(maxit = 2), starts = 3L, seed = 1)$start_results
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#'
#' Tolson, B. A. and Shoemaker, C. A. (2007). Dynamically dimensioned search algorithm for
#' computationally efficient watershed model calibration. Water Resources Research, 43, W01413,
#' doi:10.1029/2005WR004723.
#' @export
calibrate_pdm <- function(
  config, forcing, observed, lower, upper, warmup = 0,
  objective = c("rmse", "nse", "log_rmse", "log_nse", "boxcox", "threshold", "events"),
  flow = c("q_m3s", "q_end_m3s"),
  log_offset = 0.01, control = list(maxit = 200),
  soil_fraction = 0.5, starts = 1L, seed = NULL, method = c("lbfgsb", "nelder_mead", "dds"),
  thresholds = NULL, threshold_weight = 1, threshold_score = "csi",
  event_settings = list(tolerance_h = 6, gap_h = 24, min_duration_h = 0),
  log_scale = character(0), volume_weight = 0, start = c("flow", "soil"),
  baseflow_fraction = 0.7, start_flow = NULL, archive = NULL, events = NULL,
  event_weights = c(nse = 1, peak = 0.5, timing = 0.5), event_share = 0.5,
  event_screen = list(), cores = getOption("pdmS7.cores", 1L), boxcox_lambda = 0.5,
  weights = NULL, mask = NULL, band = NULL
) {
  # Outline: check the arguments; map the parameters onto a unit box (log-scaled where asked);
  # build a loss function that runs the model and scores it; minimise that loss from each start;
  # report the best start and every start's result.
  objective <- match.arg(objective)
  flow <- match.arg(flow)
  method <- match.arg(method)
  start <- match.arg(start)
  .check(.scalar(volume_weight, 0), "volume_weight must be a nonnegative number")
  .check(.scalar(cores, 1) && cores == floor(cores), "cores must be a whole number of at least 1")
  .check_threshold_objective(objective, method, thresholds, threshold_weight, threshold_score,
                             event_settings, observed, warmup)
  .check_calibration_args(forcing, observed, warmup, log_offset, lower, upper, starts, seed)
  initial <- vapply(names(lower), function(p) .path_get(config, p), numeric(1))
  .check(all(initial >= lower & initial <= upper), "Initial parameters outside bounds")
  box <- .search_box(lower, upper, log_scale)
  # Rows that are scored: after the warm-up, observed, and kept by the mask. Missing flow is
  # simply left out; masked flow is left out of the scores but not of the run or the events.
  .check(is.null(mask) || (is.logical(mask) && length(mask) == length(observed) &&
                             !anyNA(mask)),
         "mask must be TRUE or FALSE for each observed flow, from calibration_mask()")
  .check(is.null(band) || (is.data.frame(band) && nrow(band) == length(observed) &&
                             all(c("lower", "upper") %in% names(band))),
         "band must give lower and upper for each observed flow, from peak_band()")
  keep <- is.finite(observed) & seq_along(observed) > warmup
  if (!is.null(mask)) keep <- keep & mask
  .check(sum(keep) >= 2, "At least two observed values after warmup are required")
  .check_weights(weights, observed, keep)
  scoring <- .objective_scorer(objective, observed, keep, warmup, log_offset, events,
                               forcing$rain, pdm_from_config(config), event_weights,
                               event_share, event_screen, forcing$time, boxcox_lambda,
                               weights, mask)
  # The threshold term scores the masked flow as missing.
  threshold_obs <- observed
  if (!is.null(mask)) threshold_obs[!mask] <- NA
  # Every trial starts the same way. The start is built once for the configured model first, so
  # a start that cannot work (a first flow below qc, say) stops here with its own message rather
  # than failing every trial.
  start_flow <- start_flow %||% observed[is.finite(observed)][1L]
  begin <- function(mod) {
    .start_state(mod, start, start_flow, baseflow_fraction, soil_fraction)
  }
  # Only the configured start is checked here; whether it balances matters for the fitted model,
  # checked at the end.
  suppressWarnings(begin(pdm_from_config(config)))
  # A configuration with the trial parameter values written in at their paths.
  build <- function(par) {
    out <- config
    for (i in seq_along(par)) {
      out <- .path_set(out, names(lower)[i], par[i])
    }
    out
  }
  # Counts every objective call, including the finite-difference gradient calls that
  # stats::optim leaves out of its own function count.
  counter <- new.env(parent = emptyenv())
  counter$calls <- 0L
  counter$trials <- list()
  .check(is.null(archive) || is.function(archive), "archive must be a function or NULL")
  scored <- seq_along(observed) > warmup
  # The objective for a point z in the unit box. Every trial starts by the same rule, so trials
  # differ only in their parameters. Any
  # trial that fails, for example a parameter set the model rejects, scores 1e30 rather than
  # stopping the search. .quietly() keeps calibration runs out of the run log.
  # Long searches say every minute or so that they are running and how fast (R/progress.R).
  beat <- .heartbeat(as.integer(starts), if (method == "dds") control$maxit %||% 200L)
  loss <- function(z) {
    counter$calls <- counter$calls + 1L
    beat$tick()
    tryCatch(
      {
        mod <- pdm_from_config(build(box$to_value(z)))
        # A trial whose start caps the soil is still scored; the fitted model is checked at the end.
        all_sim <- .quietly(.run_flow(mod, forcing, suppressWarnings(begin(mod)), flow))
        # The peak tolerance: a simulated flow inside the rating's band scores as a perfect fit.
        if (!is.null(band)) all_sim <- tolerate(all_sim, observed, band)
        sim <- all_sim[keep]
        val <- scoring$score(all_sim)
        if (volume_weight > 0) {
          val <- val + volume_weight * abs(sum(sim) / sum(observed[keep]) - 1)
        }
        if (!is.null(thresholds)) {
          val <- val + threshold_weight * .threshold_loss(
            all_sim[scored], threshold_obs[scored], thresholds, threshold_score, event_settings,
            mod@dt
          )
        }
        if (!is.null(archive) && is.finite(val)) {
          counter$trials[[length(counter$trials) + 1L]] <- c(score = archive(all_sim), z)
        }
        if (is.finite(val)) val else 1e+30
      },
      error = function(e) {
        logger::log_debug("Rejected calibration trial: {conditionMessage(e)}")
        1e+30
      }
    )
  }
  # Unit-box scaling helps parameters with very different physical units.
  z_start <- .start_points(box$to_unit(initial), as.integer(starts), seed)
  # One optimisation per start. L-BFGS-B and DDS work on the unit box directly with bounds
  # [0, 1]; Nelder-Mead has no bounds, so it searches a logistic transform of the box instead.
  # Each DDS start draws from its own seed, so a start's search does not depend on the others,
  # and the starts can run side by side on several cores with the same results as one by one.
  one_start <- function(i) {
    z <- z_start[[i]]
    counter$calls <- 0L
    kept <- length(counter$trials)
    beat$start(i)
    fit <- switch(method,
      lbfgsb = stats::optim(z, loss, method = "L-BFGS-B", lower = rep(0, length(lower)),
                            upper = rep(1, length(upper)), control = control),
      nelder_mead = .nelder_mead_box(z, loss, control),
      dds = .seeded(if (!is.null(seed)) seed + i, .dds_box(z, loss, control))
    )
    list(fit = fit, calls = counter$calls,
         trials = counter$trials[seq_len(length(counter$trials) - kept) + kept])
  }
  workers <- min(as.integer(cores), length(z_start))
  if (workers > 1L) {
    .progress_say(sprintf("%d starts on %d cores", length(z_start), workers))
  }
  runs <- .run_jobs(seq_along(z_start), one_start, workers)
  # Trials kept by each start, in start order, whichever process ran it.
  counter$trials <- do.call(c, lapply(runs, `[[`, "trials"))
  out <- .calibration_result(runs, box, build, lower)
  # One warning, for the calibrated model, if its steady start cannot balance at the first flow.
  if (start == "flow") .start_state(out$model, start, start_flow, baseflow_fraction, soil_fraction)
  c(out[c("config", "model", "parameters", "objective")], list(
    objective_name = .objective_name(objective, thresholds, threshold_weight, threshold_score,
                                     volume_weight, scoring$name),
    method = method
  ), out[c("convergence", "message", "optim", "start_results")],
  if (!is.null(archive)) list(trials = .trial_table(counter$trials, box, names(lower))),
  if (!is.null(mask) || !is.null(band)) {
    # What the scores left out and how they treated the peaks, for the record of the run.
    after <- seq_along(observed) > warmup & is.finite(observed)
    list(scoring = list(masked_steps = if (!is.null(mask)) sum(after & !mask) else 0L,
                        scored_steps = sum(keep),
                        peak_tolerance = !is.null(band),
                        band_widest = if (!is.null(band)) {
                          c(lower = min(band$lower[after]), upper = max(band$upper[after]))
                        }))
  })
}

# The archive of trials as a table of score and parameter values, with each trial's position in
# the unit search box kept as an attribute for measuring how far apart two trials are.
.trial_table <- function(trials, box, names) {
  if (!length(trials)) {
    out <- data.table::data.table(score = numeric(0))
    attr(out, "unit") <- matrix(numeric(0), 0, length(names), dimnames = list(NULL, names))
    return(out)
  }
  m <- do.call(rbind, trials)
  unit <- m[, -1L, drop = FALSE]
  colnames(unit) <- names
  values <- t(apply(unit, 1L, box$to_value))
  if (length(names) == 1L) values <- t(values)
  colnames(values) <- names
  out <- cbind(data.table::data.table(score = m[, 1L]), data.table::as.data.table(values))
  attr(out, "unit") <- unit
  out
}

# Argument checks for calibrate_pdm(), kept apart so the main function reads as the procedure.
.check_calibration_args <- function(forcing, observed, warmup, log_offset, lower, upper, starts,
                                    seed) {
  .check(is.numeric(observed) && length(observed) == nrow(forcing),
         "observed length must match forcing")
  .check(.whole(warmup, 0, Inf) && warmup < length(observed), "Invalid warmup")
  .check(.scalar(log_offset, 0, strict = TRUE), "log_offset must be positive")
  .check(.named_bounds(lower, upper),
         "Supply finite named lower/upper bounds in the same order")
  .check(.whole(starts, 1, Inf), "starts must be a positive whole number")
  .check(is.null(seed) || .scalar(seed), "seed must be NULL or a finite number")
}

# Unit box <-> parameter values; log-scaled parameters are uniform in log(value).
.search_box <- function(lower, upper, log_scale) {
  .check(is.character(log_scale) && all(log_scale %in% names(lower)) &&
           all(lower[log_scale] > 0), "log_scale must name parameters with positive lower bounds")
  logged <- names(lower) %in% log_scale
  lo <- unname(lower)
  hi <- unname(upper)
  lo[logged] <- log(lower[logged])
  hi[logged] <- log(upper[logged])
  list(
    to_value = function(z) {
      v <- lo + z * (hi - lo)
      v[logged] <- exp(v[logged])
      v[logged] <- pmin(pmax(v[logged], lower[logged]), upper[logged])
      stats::setNames(v, names(lower))
    },
    to_unit = function(v) {
      v <- unname(v)
      v[logged] <- log(v[logged])
      (v - lo) / (hi - lo)
    }
  )
}

# The continuous part of the objective as a function of the full simulated series: the events
# objective scores the event windows, every other objective the kept rows.
.objective_scorer <- function(objective, observed, keep, warmup, log_offset, events, rain,
                              model, event_weights, event_share, event_screen, time = NULL,
                              lambda = 0.5, weights = NULL, mask = NULL) {
  if (objective == "events") {
    return(.event_objective(events, rain, observed, warmup, model@dt, event_weights, event_share,
                            event_screen, model@area_km2, time, mask))
  }
  if (objective == "boxcox") {
    score <- .boxcox_scorer(observed[keep], log_offset, lambda,
                            if (!is.null(weights)) weights[keep])
    return(list(score = function(sim) score(sim[keep]),
                name = sprintf("1 - NSE of Box-Cox flows (lambda %g%s)", lambda,
                               if (!is.null(weights)) ", weighted" else "")))
  }
  score <- .calibration_scorer(objective, observed[keep], log_offset)
  list(score = function(sim) score(sim[keep]), name = NULL)
}

#' Box-Cox transformed flow
#'
#' `((q + offset)^lambda - 1) / lambda`, or `log(q + offset)` for `lambda = 0`. Flow errors grow
#' with the flow: a gauge's error at a flood is many times its error at baseflow, and a model's
#' error likewise. Least squares on the raw flow then counts the largest floods many times over
#' and the rest of the record hardly at all. On the transformed scale the errors are much closer
#' to the same size at every flow, which is what least squares assumes. `lambda = 1` is the raw
#' flow (less one), `0` the log; between them, `0.5` (the default of the `boxcox` objective)
#' keeps more weight on high flows than the log does, and `0.2` is closer to the log (McInerney
#' et al., 2017, compare the choices).
#'
#' @param q Flow, m3/s.
#' @param lambda The transform's power, from 0 (log) to 1 (raw).
#' @param offset A small positive flow added first, m3/s, so zero flows stay finite.
#' @return The transformed flow.
#' @examples
#' boxcox_flow(c(0.1, 1, 10, 100), lambda = 0.5)
#' @seealso [calibrate_pdm()] (`objective = "boxcox"`), [flow_weights()]
#' @export
boxcox_flow <- function(q, lambda = 0.5, offset = 0.01) {
  .check(.scalar(lambda, 0, 1), "lambda must be between 0 and 1")
  .check(.scalar(offset, 0, strict = TRUE), "offset must be a positive flow")
  if (lambda == 0) return(log(q + offset))
  ((q + offset)^lambda - 1) / lambda
}

# Weights for the boxcox objective: none, or one nonnegative number for each observed flow,
# not all zero on the scored rows.
.check_weights <- function(weights, observed, keep) {
  .check(is.null(weights) || (is.numeric(weights) && length(weights) == length(observed) &&
                                all(is.finite(weights[keep]) & weights[keep] >= 0) &&
                                sum(weights[keep]) > 0),
         "weights must be nonnegative numbers, one for each observed flow")
}

# The boxcox objective: 1 - NSE on Box-Cox flows, each step weighted by `w` when given (a
# weighted sum of squares over the weighted spread about the weighted mean).
.boxcox_scorer <- function(obs, offset, lambda, w = NULL) {
  .check(all(obs + offset > 0), "Invalid observations for the Box-Cox transform")
  zo <- boxcox_flow(obs, lambda, offset)
  w <- w %||% rep(1, length(obs))
  spread <- sum(w * (zo - sum(w * zo) / sum(w))^2)
  .check(spread > 0, "The Box-Cox objective needs variable observations")
  function(sim) {
    if (any(!is.finite(sim)) || any(sim + offset <= 0)) return(1e+30)
    sum(w * (boxcox_flow(sim, lambda, offset) - zo)^2) / spread
  }
}

#' Weights for flows by how well they are measured
#'
#' One weight for each observed flow, for the `weights` of [calibrate_pdm()], so that flows the
#' gauge measures poorly count for less. Two sources, used together when both are given:
#'
#' - `uncertainty`, a table of flow (`q`, m3/s) and its relative uncertainty (`relative`, for
#'   example 0.1 for plus or minus 10%), such as a rating's uncertainty at its percentiles. Each
#'   flow's relative uncertainty is interpolated (held flat beyond the table) and its weight is
#'   `(smallest / relative)^2`: inverse variance, the best-measured flows weighing 1.
#' - `highest_gauged`: flows above the highest gauging lie on the extrapolated rating; they are
#'   multiplied by `extrapolated`.
#'
#' Missing flows get weight 0. Weights scale the Box-Cox objective's squared errors.
#'
#' @param observed Observed flow, m3/s.
#' @param uncertainty `NULL`, or a data frame with `q` and `relative`.
#' @param highest_gauged `NULL`, or the highest gauged flow, m3/s.
#' @param extrapolated Weight factor above the highest gauging.
#' @return A weight for each flow.
#' @examples
#' flow_weights(c(1, 5, 50), uncertainty = data.frame(q = c(1, 50), relative = c(0.05, 0.2)))
#' @seealso [boxcox_flow()], [calibrate_pdm()]
#' @export
flow_weights <- function(observed, uncertainty = NULL, highest_gauged = NULL,
                         extrapolated = 0.25) {
  .check(is.numeric(observed), "observed must be numeric")
  .check(.scalar(extrapolated, 0, 1), "extrapolated must be between 0 and 1")
  w <- rep(1, length(observed))
  if (!is.null(uncertainty)) {
    .check(is.data.frame(uncertainty) && all(c("q", "relative") %in% names(uncertainty)) &&
             nrow(uncertainty) >= 1 && all(uncertainty$relative > 0),
           "uncertainty must be a data frame of q and positive relative")
    u <- uncertainty[order(uncertainty$q), ]
    rel <- if (nrow(u) == 1L) rep(u$relative, length(observed)) else
      stats::approx(u$q, u$relative, observed, rule = 2)$y
    w <- (min(u$relative) / rel)^2
  }
  if (!is.null(highest_gauged)) {
    .check(.scalar(highest_gauged, 0, strict = TRUE), "highest_gauged must be a positive flow")
    w[is.finite(observed) & observed > highest_gauged] <-
      w[is.finite(observed) & observed > highest_gauged] * extrapolated
  }
  w[!is.finite(observed)] <- 0
  w
}

# The continuous part of the objective, as a function of the simulated flow on the kept rows.
.calibration_scorer <- function(objective, obs, log_offset) {
  if (objective == "nse") {
    .check(stats::var(obs) > 0, "NSE needs variable observations")
  }
  if (objective %in% c("log_rmse", "log_nse")) {
    .check(all(obs + log_offset > 0), "Invalid log observations")
  }
  log_obs <- if (objective %in% c("log_rmse", "log_nse")) log(obs + log_offset)
  if (objective == "log_nse") {
    .check(stats::var(log_obs) > 0, "Log NSE needs variable observations")
  }
  switch(objective,
    threshold = function(sim) 0,
    rmse = function(sim) sqrt(mean((sim - obs)^2)),
    nse = function(sim) sum((sim - obs)^2) / sum((obs - mean(obs))^2),
    log_rmse = function(sim) {
      if (any(sim + log_offset <= 0)) 1e+30 else sqrt(mean((log(sim + log_offset) - log_obs)^2))
    },
    log_nse = function(sim) {
      if (any(sim + log_offset <= 0)) {
        1e+30
      } else {
        sum((log(sim + log_offset) - log_obs)^2) / sum((log_obs - mean(log_obs))^2)
      }
    }
  )
}

# The configured point, then uniform random points in the unit box. A seed, when given, is
# used and the caller's random number state restored.
.start_points <- function(z0, starts, seed) {
  if (starts == 1L) return(list(z0))
  draw <- function() c(list(z0), lapply(seq_len(starts - 1L), function(i) stats::runif(length(z0))))
  if (is.null(seed)) draw() else .with_seed(seed, draw())
}

# Collects the starts into the returned list: the best start's parameters, configuration and
# model, and a table with every start's objective, convergence code, model runs and parameters.
# If every trial of every start failed, there is no answer, and the call stops.
.calibration_result <- function(runs, box, build, lower) {
  fits <- lapply(runs, function(r) r$fit)
  values <- vapply(fits, function(f) f$value, numeric(1))
  best_index <- which.min(values)
  fit <- fits[[best_index]]
  .check(fit$value < 1e+29, "No valid calibration evaluation; inspect configuration and bounds")
  # One row per start and one column per parameter, including the single-parameter case.
  fitted <- matrix(
    unlist(lapply(fits, function(f) box$to_value(f$par)), use.names = FALSE),
    nrow = length(fits), byrow = TRUE, dimnames = list(NULL, names(lower))
  )
  start_results <- data.table::data.table(
    start = seq_along(fits),
    objective = values,
    convergence = vapply(fits, function(f) as.integer(f$convergence), integer(1)),
    evaluations = vapply(runs, function(r) r$calls, integer(1)),
    best = seq_along(fits) == best_index
  )
  start_results <- cbind(start_results, data.table::as.data.table(fitted))
  parameters <- box$to_value(fit$par)
  best <- build(parameters)
  list(config = best, model = pdm_from_config(best), parameters = parameters,
       objective = fit$value, convergence = fit$convergence, message = fit$message,
       optim = fit, start_results = start_results)
}

# Nelder-Mead on the logistic transform of the unit box: every trial lies inside the bounds.
.nelder_mead_box <- function(z, loss, control) {
  u0 <- stats::qlogis(pmin(pmax(z, 1e-6), 1 - 1e-6))
  fit <- withCallingHandlers(
    stats::optim(u0, function(u) loss(stats::plogis(u)), method = "Nelder-Mead",
                 control = control),
    warning = function(w) {
      if (grepl("one-dimensional", conditionMessage(w))) invokeRestart("muffleWarning")
    }
  )
  fit$par <- stats::plogis(fit$par)
  fit
}

# Dynamically dimensioned search (Tolson and Shoemaker, 2007) in the unit box. Each run perturbs
# a random subset of coordinates of the best point so far by a normal step of sd r; a coordinate
# is chosen with probability 1 - log(i) / log(budget), so the search starts global and ends local.
# A step past a bound is reflected back inside; if the reflection overshoots the other bound, the
# coordinate goes to the bound it crossed. A trial at least as good as the best replaces it. The
# result is shaped like an stats::optim result, so the rest of calibrate_pdm() treats it alike.
.dds_box <- function(z, loss, control) {
  budget <- control$maxit %||% 200L
  r <- control$r %||% 0.2
  .check(.whole(budget, 1, Inf), "control$maxit must be a whole number of model runs for dds")
  .check(.scalar(r, 0, strict = TRUE), "control$r must be a positive number")
  n <- length(z)
  best <- z
  best_value <- loss(z)
  for (i in seq_len(budget - 1L)) {
    chosen <- stats::runif(n) < 1 - log(i) / log(budget)
    if (!any(chosen)) chosen[sample.int(n, 1L)] <- TRUE
    trial <- .dds_perturb(best, chosen, r)
    value <- loss(trial)
    if (value <= best_value) {
      best <- trial
      best_value <- value
    }
  }
  list(par = best, value = best_value, counts = c(`function` = budget, gradient = NA),
       convergence = 0L, message = paste("DDS:", budget, "model runs"))
}

# One DDS step from `z` in the unit box: the chosen coordinates move by a normal step of sd r; a
# step past a bound is reflected back inside, and one that overshoots the other bound goes to the
# bound it crossed.
.dds_perturb <- function(z, chosen, r) {
  step <- z[chosen] + r * stats::rnorm(sum(chosen))
  low <- step < 0
  step[low] <- -step[low]
  step[low & step > 1] <- 0
  high <- step > 1
  step[high] <- 2 - step[high]
  step[high & step < 0] <- 1
  z[chosen] <- step
  z
}

# The threshold part of the objective: for each threshold, 1 - score (or the score itself for a
# false alarm ratio, where lower is better), averaged. An undefined score, such as CSI with no
# events in either series, counts as the worst value, so the search cannot exploit it.
.threshold_loss <- function(sim, obs, thresholds, score, events, dt) {
  table <- pdm_threshold_scores(sim, obs, thresholds, dt, events$tolerance_h, events$gap_h,
                                events$min_duration_h)
  values <- table[[score]]
  lower_better <- .threshold_headlines[[score]] == "lower"
  losses <- if (lower_better) values else 1 - values
  losses[!is.finite(losses)] <- 1
  mean(losses)
}

# A threshold term is only allowed with a derivative-free search (event counts change in steps,
# so gradients are zero almost everywhere), and only for thresholds the observed flow actually
# exceeds in the scored period: a threshold never crossed gives the search nothing to learn from.
.check_threshold_objective <- function(objective, method, thresholds, weight, score, events,
                                       observed, warmup) {
  if (is.null(thresholds)) {
    .check(objective != "threshold", "objective = \"threshold\" needs thresholds")
    return(invisible(TRUE))
  }
  .check(method %in% c("nelder_mead", "dds"), paste(
    "Threshold scores change in steps, which a gradient optimiser cannot follow;",
    "use method = \"nelder_mead\" or \"dds\""
  ))
  .check(is.numeric(thresholds) && length(thresholds) > 0 && !is.null(names(thresholds)) &&
           all(is.finite(thresholds) & thresholds > 0), "thresholds must be named positive flows")
  .check(.scalar(weight, 0), "threshold_weight must be nonnegative")
  .check(length(score) == 1L && score %in% names(.threshold_headlines),
         paste("threshold_score must be one of", paste(names(.threshold_headlines),
                                                       collapse = ", ")))
  .check(is.list(events) && all(c("tolerance_h", "gap_h", "min_duration_h") %in% names(events)),
         "event_settings needs tolerance_h, gap_h and min_duration_h")
  scored <- observed[seq_along(observed) > warmup]
  for (name in names(thresholds)) {
    .check(any(scored > thresholds[[name]], na.rm = TRUE), paste0(
      "Observed flow never exceeds threshold ", name, " in the scored period, so its score ",
      "cannot guide calibration"
    ))
  }
  invisible(TRUE)
}

# A readable description of the objective, recorded with every logged calibration, such as
# "1-NSE + 1 x mean threshold loss (csi at Flood Warning)".
.objective_name <- function(objective, thresholds, weight, score, volume_weight = 0,
                            events_name = NULL) {
  base <- switch(objective, nse = "1-NSE", log_nse = "1-log NSE", events = events_name,
                 boxcox = events_name, objective)
  if (volume_weight > 0) {
    base <- paste0(base, " + ", volume_weight, " x |volume error|")
  }
  if (is.null(thresholds)) return(base)
  term <- paste0(weight, " x mean threshold loss (", score, " at ",
                 paste(names(thresholds), collapse = ", "), ")")
  if (objective == "threshold") term else paste(base, "+", term)
}
