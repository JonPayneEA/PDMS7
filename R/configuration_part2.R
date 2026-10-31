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
#' @param objective Calibration objective: rmse, nse (minimizes 1-NSE), or log_rmse.
#' @param flow Series to score: q_m3s (interval mean) or q_end_m3s (endpoint flow).
#' @param log_offset Positive offset added before logarithms in log-RMSE, cubic metres per
#' second.
#' @param control Named control list forwarded to stats::optim.
#' @param soil_fraction Initial fraction of basin capacity between zero and one.
#' @param starts Positive integer number of L-BFGS-B starts. The default, 1, runs a single
#' start from the values in config and is identical to earlier versions. With more than one,
#' the first start is still the values in config and the others are drawn uniformly inside
#' lower and upper. Every start is optimised and the best objective is returned.
#' @param seed Optional finite number that seeds the random starting points. The caller's
#' random number state is restored on exit. It has no effect when starts is 1.
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
  config, forcing, observed, lower, upper, warmup = 0, objective = c("rmse", "nse", "log_rmse"),
  flow = c("q_m3s", "q_end_m3s"),
  log_offset = 0.01, control = list(maxit = 200),
  soil_fraction = 0.5, starts = 1L, seed = NULL
) {
  objective <- match.arg(objective)
  flow <- match.arg(flow)
  .check(
    is.numeric(observed) &&
      length(observed) ==
        nrow(forcing),
    "observed length must match forcing"
  )
  .check(
    .scalar(warmup, 0) &&
      warmup == floor(warmup) &&
      warmup < length(observed),
    "Invalid warmup"
  )
  .check(
    .scalar(log_offset, 0, strict = TRUE),
    "log_offset must be positive"
  )
  .check(
    is.numeric(lower) &&
      is.numeric(upper) &&
      length(lower) >
        0 && !is.null(names(lower)) &&
      identical(
        names(lower),
        names(upper)
      ) &&
      !anyDuplicated(names(lower)) &&
      all(is.finite(lower)) &&
      all(is.finite(upper)) &&
      all(lower < upper),
    "Supply finite named lower/upper bounds in the same order"
  )
  initial <- vapply(
    names(lower),
    function(p) .path_get(config, p),
    numeric(1)
  )
  .check(
    all(initial >= lower & initial <= upper),
    "Initial parameters outside bounds"
  )
  .check(
    .scalar(starts, 1) && starts == floor(starts),
    "starts must be a positive whole number"
  )
  .check(
    is.null(seed) || .scalar(seed),
    "seed must be NULL or a finite number"
  )
  keep <- is.finite(observed) &
    seq_along(observed) >
      warmup
  .check(
    sum(keep) >=
      2, "At least two observed values after warmup are required"
  )
  if (objective == "nse") {
    .check(
      stats::var(observed[keep]) >
        0, "NSE needs variable observations"
    )
  }
  if (objective == "log_rmse") {
    .check(
      all(observed[keep] + log_offset > 0),
      "Invalid log observations"
    )
  }
  build <- function(par) {
    out <- config
    for (i in seq_along(par)) {
      out <- .path_set(
        out, names(lower)[i],
        par[i]
      )
    }
    out
  }
  # Counts every objective call, including the finite-difference gradient calls that
  # stats::optim leaves out of its own function count.
  calls <- 0L
  loss <- function(z) {
    calls <<- calls + 1L
    par <- lower + z * (upper - lower)
    tryCatch(
      {
        mod <- pdm_from_config(build(par))
        sim <- .run_flow(mod, forcing, initial_state(mod, soil_fraction), flow)[keep]
        obs <- observed[keep]
        val <- switch(objective,
          rmse = sqrt(mean((sim - obs)^2)),
          nse = sum((sim - obs)^2) / sum((obs - mean(obs))^2),
          log_rmse = if (any(sim + log_offset <= 0)) {
            1e+30
          } else {
            sqrt(
              mean(
                (log(sim + log_offset) -
                   log(obs + log_offset))^2
              )
            )
          }
        )
        if (is.finite(val)) {
          val
        } else {
          1e+30
        }
      },
      error = function(e) {
        logger::log_debug("Rejected calibration trial: {conditionMessage(e)}")
        1e+30
      }
    )
  }
  # Unit-box scaling helps parameters with very different physical units.
  z0 <- (initial - lower) / (upper - lower)
  starts <- as.integer(starts)
  z_start <- list(z0)
  if (starts > 1L) {
    if (!is.null(seed)) {
      if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
        old_seed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
        on.exit(assign(".Random.seed", old_seed, envir = globalenv()), add = TRUE)
      } else {
        on.exit(rm(list = ".Random.seed", envir = globalenv()), add = TRUE)
      }
      set.seed(seed)
    }
    extra <- lapply(seq_len(starts - 1L), function(i) stats::runif(length(z0)))
    z_start <- c(z_start, extra)
  }
  eval_counts <- integer(length(z_start))
  fits <- lapply(
    seq_along(z_start),
    function(i) {
      z <- z_start[[i]]
      calls <<- 0L
      out <- stats::optim(
        z, loss,
        method = "L-BFGS-B", lower = rep(0, length(lower)),
        upper = rep(1, length(upper)),
        control = control
      )
      eval_counts[i] <<- calls
      out
    }
  )
  values <- vapply(fits, function(f) f$value, numeric(1))
  best_index <- which.min(values)
  fit <- fits[[best_index]]
  .check(fit$value < 1e+29, "No valid calibration evaluation; inspect configuration and bounds")
  # One row per start and one column per parameter, including the single-parameter case.
  fitted <- matrix(
    unlist(lapply(fits, function(f) lower + f$par * (upper - lower)), use.names = FALSE),
    nrow = length(fits), byrow = TRUE, dimnames = list(NULL, names(lower))
  )
  start_results <- data.table::data.table(
    start = seq_along(fits),
    objective = values,
    convergence = vapply(fits, function(f) as.integer(f$convergence), integer(1)),
    evaluations = eval_counts,
    best = seq_along(fits) == best_index
  )
  start_results <- cbind(start_results, data.table::as.data.table(fitted))
  parameters <- lower + fit$par * (upper - lower)
  best <- build(parameters)
  list(
    config = best, model = pdm_from_config(best),
    parameters = parameters,
    objective = fit$value,
    objective_name = if (objective == "nse") "1-NSE" else objective,

    convergence = fit$convergence, message = fit$message, optim = fit,
    start_results = start_results
  )
}
