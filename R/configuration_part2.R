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
#'
#' @return A list of config, model, parameters, objective, convergence, message, and optim
#' diagnostics.
#'
#' @examples
#' config <- pdm_presets('standard')
#' f <- data.frame(rain = c(0, 10, 2, 0), pet = rep(0.05, 4))
#' q <- run_pdm(pdm_from_config(config), f)$output$q_m3s
#' calibrate_pdm(config, f, q, lower = c(fc = 0.8), upper = c(fc = 1.2),
#'   control = list(maxit = 2))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
calibrate_pdm <- function(
  config, forcing, observed, lower, upper, warmup = 0, objective = c("rmse", "nse", "log_rmse"),
  flow = c("q_m3s", "q_end_m3s"),
  log_offset = 0.01, control = list(maxit = 200),
  soil_fraction = 0.5
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
  loss <- function(z) {
    par <- lower + z * (upper - lower)
    tryCatch(
      {
        mod <- pdm_from_config(build(par))
        sim <- run_pdm(mod, forcing, initial_state(mod, soil_fraction))$output[[flow]][keep]
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
  fit <- stats::optim(
    (initial - lower) / (upper - lower), loss,
    method = "L-BFGS-B", lower = rep(0, length(lower)),
    upper = rep(1, length(upper)),
    control = control
  )
  .check(fit$value < 1e+29, "No valid calibration evaluation; inspect configuration and bounds")
  parameters <- lower + fit$par * (upper - lower)
  best <- build(parameters)
  list(
    config = best, model = pdm_from_config(best),
    parameters = parameters,
    objective = fit$value,
    objective_name = if (objective == "nse") "1-NSE" else objective,

    convergence = fit$convergence, message = fit$message, optim = fit
  )
}
