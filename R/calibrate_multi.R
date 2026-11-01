# ============================================================ #
# Tool:         calibrate_multi
# Description:  Search weighted objectives and retain sampled Pareto trade-offs
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Add bounded multi-objective calibration
# Tier:         3
# Inputs:       PDM or coupled configuration, forcing and observed flow
# Outputs:      Candidate archive, nondominated configurations and optimizer status
# Dependencies: data.table; stats
# ============================================================ #

#' Calibrate PDM or coupled snow-PDM against multiple objectives
#'
#' Evaluates the initial configuration and seeded uniform candidates, then refines
#' the best sampled starts for each weight vector with bounded L-BFGS-B. Retains
#' every valid evaluated candidate and its raw metrics, normalized metrics and
#' Pareto membership. This is an approximate sampled front, not a global optimality
#' claim; nonconvex fronts may be missed by weighted searches. Use repeated seeds,
#' sufficient search budgets and independent validation. Random state is restored.
#' @param config PDM configuration, or list(pdm=..., snow=...) for coupled calibration.
#' @param forcing Data frame with rain and pet; coupled runs also require temperature_c.
#' Optional time column contains POSIXct timestamps.
#' @param observed Aligned observed discharge, m3/s. Missing observations are excluded.
#' @param lower,upper Named finite bounds with identical names/order. Coupled paths
#' start with pdm. or snow., for example snow.melt_factor_mmh_c.
#' @param objectives Metric names accepted by pdm_objectives.
#' @param scales Positive named metric divisors in objective order. NULL uses ones;
#' choose meaningful scales before interpreting weighted compromises.
#' @param weights Nonnegative named vector or matrix with objective column names in
#' order. Rows are normalized to sum one. NULL uses individual objectives and equal weights.
#' @param n_samples Nonnegative number of initial uniform random candidates.
#' @param starts Positive number of sampled starts refined per weight vector.
#' @param seed Nonnegative integer random seed.
#' @param warmup Number of initial intervals excluded from scoring, not simulation.
#' @param log_offset Positive offset for log-RMSE, m3/s.
#' @param control Control list forwarded to stats::optim.
#' @return List with archive data.table, pareto data.table, corresponding configs,
#' compromise (best equal/supplied final weight row), weights, scales, optimization
#' status and failed evaluation count. Candidates are not posterior probabilities.
#' @export
calibrate_pdm_multi <- function(config, forcing, observed, lower, upper,
                                objectives = c("nse_loss", "log_rmse", "abs_bias"),
                                scales = NULL, weights = NULL, n_samples = 64L,
                                starts = 2L, seed = 1L, warmup = 0L, log_offset = 0.01,
                                control = list(maxit = 100)) {
  .multi_check_inputs(forcing, observed, lower, upper, n_samples, starts, seed)
  pdm_objectives(observed, observed, objectives, warmup, log_offset)
  scales <- .multi_scales(scales, objectives)
  weights <- .multi_weights(weights, objectives)
  initial <- vapply(names(lower), function(p) .path_get(config, p), numeric(1))
  .check(all(initial >= lower & initial <= upper), "Initial parameters outside bounds")
  .check(!any(names(lower) %in% c("dt", "pdm.dt")), "Do not calibrate the forcing timestep")
  simulate <- .multi_simulator(config, forcing)
  build <- function(par) {
    out <- config
    for (i in seq_along(par)) out <- .path_set(out, names(lower)[i], par[i])
    out
  }
  # Fail early on invalid forcing/configuration rather than hiding it as bad trials.
  pdm_objectives(simulate(config), observed, objectives, warmup, log_offset)
  evaluations <- new.env(parent = emptyenv())
  evaluations$archive <- list()
  evaluations$failures <- 0L
  evaluate <- function(z) {
    par <- lower + z * (upper - lower)
    metrics <- tryCatch(pdm_objectives(
      simulate(build(par)), observed,
      objectives, warmup, log_offset
    ), error = function(e) {
      evaluations$failures <- evaluations$failures + 1L
      logger::log_debug("Rejected multi-objective trial: {conditionMessage(e)}")
      NULL
    })
    if (is.null(metrics)) {
      return(rep(1e30, length(objectives)))
    }
    evaluations$archive[[length(evaluations$archive) + 1L]] <- c(par, stats::setNames(
      metrics,
      paste0("loss_", objectives)
    ))
    metrics / scales
  }
  status <- .with_seed(seed, .multi_search(
    evaluate, (initial - lower) / (upper - lower), n_samples, weights, starts, control
  ))
  .multi_results(evaluations, objectives, scales, weights, lower, build, status)
}

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

.whole <- function(x, lo, hi) .scalar(x, lo, hi) && x == floor(x)

.multi_scales <- function(scales, objectives) {
  if (is.null(scales)) scales <- stats::setNames(rep(1, length(objectives)), objectives)
  .check(is.numeric(scales) && identical(names(scales), objectives) &&
           all(is.finite(scales)) && all(scales > 0),
         "scales must be positive and named in metric order")
  scales
}

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

.multi_search <- function(evaluate, z0, n_samples, weights, starts, control) {
  candidates <- rbind(z0, matrix(stats::runif(n_samples * length(z0)), ncol = length(z0)))
  losses <- do.call(rbind, lapply(seq_len(nrow(candidates)), function(i) evaluate(candidates[i, ])))
  status <- list()
  for (w in seq_len(nrow(weights))) {
    order <- order(as.vector(losses %*% weights[w, ]))
    for (j in order[seq_len(min(length(order), starts))]) {
      fit <- stats::optim(candidates[j, ], function(z) sum(evaluate(z) * weights[w, ]),
        method = "L-BFGS-B", lower = rep(0, length(z0)), upper = rep(1, length(z0)),
        control = control
      )
      status[[length(status) + 1L]] <- list(
        weight_row = w, convergence = fit$convergence,
        message = fit$message, value = fit$value
      )
    }
  }
  status
}

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
