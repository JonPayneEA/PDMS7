# ============================================================ #
# Tool:         configuration
# Description:  Configurable PDM framework: configuration
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
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
#' (minimizes 1 minus NSE of log flows, which weights low flows), or threshold (the threshold
#' term alone; needs thresholds).
#' @param flow Series to score: q_m3s (interval mean) or q_end_m3s (endpoint flow).
#' @param log_offset Positive offset added before logarithms in log-RMSE and log NSE, cubic
#' metres per second.
#' @param control Named control list forwarded to stats::optim.
#' @param soil_fraction Initial fraction of basin capacity between zero and one.
#' @param starts Positive integer number of L-BFGS-B starts. The default, 1, runs a single
#' start from the values in config, as earlier versions did. With more than one,
#' the first start is still the values in config and the others are drawn uniformly inside
#' lower and upper. Every start is optimised and the best objective is returned.
#' @param seed Optional finite number that seeds the random starting points. The caller's
#' random number state is restored on exit. It has no effect when starts is 1.
#' @param method Optimiser: `lbfgsb` (default), gradient-based and fast for smooth objectives,
#' or `nelder_mead`, derivative-free, needed for threshold objectives because event counts
#' change in steps. Nelder-Mead works on a logistic transform of the unit box, so every
#' trial stays within lower and upper; it usually needs several times more model runs.
#' @param thresholds Optional named vector of threshold flows, m3/s. The objective then
#' becomes the continuous objective plus `threshold_weight` times the mean over thresholds
#' of the threshold loss (1 - score, or the score itself for false alarm ratios), from
#' [pdm_threshold_scores()] over the scored rows. An undefined score counts as the worst.
#' Requires `method = "nelder_mead"`, and at least one observed event at each threshold.
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
#'
#' @return A list of config, model, parameters, objective, convergence, message, optim
#' diagnostics, and start_results. The first six describe the best start; optim is its
#' stats::optim result. start_results is a data.table with one row per start: start (1 is the
#' configured point), objective (on the scale given by objective_name, 1e+30 if no valid
#' evaluation), convergence (the stats::optim code), evaluations (every objective call,
#' including the finite-difference gradient calls that stats::optim counts leave out),
#' best (TRUE for the returned start), and one column per calibrated parameter holding the
#' fitted value, which always lies within lower and upper.
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
#' @export
calibrate_pdm <- function(
  config, forcing, observed, lower, upper, warmup = 0,
  objective = c("rmse", "nse", "log_rmse", "log_nse", "threshold"),
  flow = c("q_m3s", "q_end_m3s"),
  log_offset = 0.01, control = list(maxit = 200),
  soil_fraction = 0.5, starts = 1L, seed = NULL, method = c("lbfgsb", "nelder_mead"),
  thresholds = NULL, threshold_weight = 1, threshold_score = "csi",
  event_settings = list(tolerance_h = 6, gap_h = 24, min_duration_h = 0),
  log_scale = character(0), volume_weight = 0
) {
  objective <- match.arg(objective)
  flow <- match.arg(flow)
  method <- match.arg(method)
  .check(.scalar(volume_weight, 0), "volume_weight must be a nonnegative number")
  .check_threshold_objective(objective, method, thresholds, threshold_weight, threshold_score,
                             event_settings, observed, warmup)
  .check_calibration_args(forcing, observed, warmup, log_offset, lower, upper, starts, seed)
  initial <- vapply(names(lower), function(p) .path_get(config, p), numeric(1))
  .check(all(initial >= lower & initial <= upper), "Initial parameters outside bounds")
  box <- .search_box(lower, upper, log_scale)
  keep <- is.finite(observed) & seq_along(observed) > warmup
  .check(sum(keep) >= 2, "At least two observed values after warmup are required")
  score <- .calibration_scorer(objective, observed[keep], log_offset)
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
  scored <- seq_along(observed) > warmup
  loss <- function(z) {
    counter$calls <- counter$calls + 1L
    tryCatch(
      {
        mod <- pdm_from_config(build(box$to_value(z)))
        all_sim <- .quietly(.run_flow(mod, forcing, initial_state(mod, soil_fraction), flow))
        sim <- all_sim[keep]
        val <- score(sim)
        if (volume_weight > 0) {
          val <- val + volume_weight * abs(sum(sim) / sum(observed[keep]) - 1)
        }
        if (!is.null(thresholds)) {
          val <- val + threshold_weight * .threshold_loss(
            all_sim[scored], observed[scored], thresholds, threshold_score, event_settings,
            mod@dt
          )
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
  runs <- lapply(z_start, function(z) {
    counter$calls <- 0L
    fit <- if (method == "lbfgsb") {
      stats::optim(z, loss, method = "L-BFGS-B", lower = rep(0, length(lower)),
                   upper = rep(1, length(upper)), control = control)
    } else {
      .nelder_mead_box(z, loss, control)
    }
    list(fit = fit, calls = counter$calls)
  })
  out <- .calibration_result(runs, box, build, lower)
  c(out[c("config", "model", "parameters", "objective")], list(
    objective_name = .objective_name(objective, thresholds, threshold_weight, threshold_score,
                                     volume_weight),
    method = method
  ), out[c("convergence", "message", "optim", "start_results")])
}

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

.threshold_loss <- function(sim, obs, thresholds, score, events, dt) {
  table <- pdm_threshold_scores(sim, obs, thresholds, dt, events$tolerance_h, events$gap_h,
                                events$min_duration_h)
  values <- table[[score]]
  lower_better <- .threshold_headlines[[score]] == "lower"
  losses <- if (lower_better) values else 1 - values
  losses[!is.finite(losses)] <- 1
  mean(losses)
}

.check_threshold_objective <- function(objective, method, thresholds, weight, score, events,
                                       observed, warmup) {
  if (is.null(thresholds)) {
    .check(objective != "threshold", "objective = \"threshold\" needs thresholds")
    return(invisible(TRUE))
  }
  .check(method == "nelder_mead", paste(
    "Threshold scores change in steps, which a gradient optimiser cannot follow;",
    "use method = \"nelder_mead\""
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

.objective_name <- function(objective, thresholds, weight, score, volume_weight = 0) {
  base <- switch(objective, nse = "1-NSE", log_nse = "1-log NSE", objective)
  if (volume_weight > 0) {
    base <- paste0(base, " + ", volume_weight, " x |volume error|")
  }
  if (is.null(thresholds)) return(base)
  term <- paste0(weight, " x mean threshold loss (", score, " at ",
                 paste(names(thresholds), collapse = ", "), ")")
  if (objective == "threshold") term else paste(base, "+", term)
}
