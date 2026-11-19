# ============================================================ #
# Tool:         bayes
# Description:  Bayesian calibration: priors on the parameters (from bounds, or from a
#               descriptor model), a likelihood of Box-Cox flow errors with lag-1
#               autocorrelation, the DREAM(ZS) sampler, convergence checks, and a predictive
#               band from the posterior
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       A configuration, forcing, observed flow, bounds and priors
# Outputs:      A pdm_bayes result: posterior samples, diagnostics, the best set
# Dependencies: stats
# ============================================================ #

#' A prior for a parameter
#'
#' Priors for [calibrate_bayes()], each truncated to the parameter's bounds. `prior_uniform()`
#' says only that the value lies within its bounds. `prior_normal()` and `prior_lognormal()`
#' say what value is expected and how sure that is: from experience, from a regional study, or
#' from a model of parameters from catchment descriptors trained on many catchments. Where the
#' record pins a parameter down, the data win; where it cannot, the prior keeps the parameter
#' sensible instead of letting it wander to a bound.
#'
#' @param mean,sd Mean and standard deviation of a normal prior, in the parameter's units.
#' @param median,sdlog A lognormal prior: its median and the standard deviation of log(value);
#'   sdlog 0.3 means about 30% either way.
#' @return A prior: a list with `type` and its numbers.
#' @examples
#' prior_lognormal(median = 250, sdlog = 0.3)   # cmax about 250 mm, give or take 30%
#' @seealso [calibrate_bayes()]
#' @export
prior_uniform <- function() list(type = "uniform")

#' @rdname prior_uniform
#' @export
prior_normal <- function(mean, sd) {
  .check(.scalar(mean) && .scalar(sd, 0, strict = TRUE), "mean must be finite and sd positive")
  list(type = "normal", mean = mean, sd = sd)
}

#' @rdname prior_uniform
#' @export
prior_lognormal <- function(median, sdlog) {
  .check(.scalar(median, 0, strict = TRUE) && .scalar(sdlog, 0, strict = TRUE),
         "median and sdlog must be positive")
  list(type = "lognormal", meanlog = log(median), sdlog = sdlog)
}

#' Priors from a table of predicted parameters
#'
#' Turns a table such as a model of parameters from catchment descriptors would give, one row
#' per parameter, into the priors of [calibrate_bayes()]: a lognormal prior where the table has
#' `median` and `sdlog` (for parameters that must be positive, such as store capacities and
#' time constants), a normal prior where it has `mean` and `sd`. `widen` multiplies every
#' spread, to allow for the prediction being for a catchment the model has not seen.
#'
#' @param table A data frame with `parameter` and either `median` and `sdlog`, or `mean` and
#'   `sd`, for each row.
#' @param widen Factor on every spread.
#' @return A named list of priors.
#' @examples
#' priors_from_table(data.frame(parameter = c("distribution.cmax", "fc"),
#'                              median = c(250, NA), sdlog = c(0.3, NA),
#'                              mean = c(NA, 1), sd = c(NA, 0.1)))
#' @seealso [calibrate_bayes()], [prior_lognormal()]
#' @export
priors_from_table <- function(table, widen = 1) {
  .check(is.data.frame(table) && "parameter" %in% names(table) && !anyDuplicated(table$parameter),
         "table needs a parameter column, one row per parameter")
  .check(.scalar(widen, 0, strict = TRUE), "widen must be positive")
  get <- function(col, i) if (col %in% names(table)) table[[col]][i] else NA_real_
  out <- lapply(seq_len(nrow(table)), function(i) {
    if (is.finite(get("median", i)) && is.finite(get("sdlog", i))) {
      prior_lognormal(get("median", i), widen * get("sdlog", i))
    } else if (is.finite(get("mean", i)) && is.finite(get("sd", i))) {
      prior_normal(get("mean", i), widen * get("sd", i))
    } else {
      stop("Row ", i, " (", table$parameter[i], ") has neither median and sdlog nor mean and sd",
           call. = FALSE)
    }
  })
  stats::setNames(out, table$parameter)
}

# The log density of a prior at value v, up to a constant (the truncation to the bounds is the
# same for every value inside them, so it cancels in the sampler).
.log_prior <- function(prior, v) {
  switch(prior$type,
    uniform = 0,
    normal = stats::dnorm(v, prior$mean, prior$sd, log = TRUE),
    lognormal = stats::dlnorm(v, prior$meanlog, prior$sdlog, log = TRUE),
    stop("Unknown prior type ", prior$type, call. = FALSE)
  )
}

# The log likelihood of Box-Cox flow errors that follow a lag-1 autoregression: e[t] = rho e[t-1]
# + a[t], a[t] independent normal with variance s2. rho and s2 are set to their best values for
# the errors given (rho the lag-1 regression of e on itself, s2 the mean squared innovation),
# which gives -(m / 2) (log(2 pi s2) + 1) for the m innovations. With `ar1 = FALSE`, rho is 0.
# Hourly errors are strongly autocorrelated; treating them as independent would make the
# posterior far too sure of itself.
.boxcox_ar1_loglik <- function(e, ar1 = TRUE) {
  e <- e[is.finite(e)]
  m <- length(e) - 1L
  if (m < 2L) return(-Inf)
  rho <- if (ar1) {
    den <- sum(e[-length(e)]^2)
    if (den > 0) sum(e[-1] * e[-length(e)]) / den else 0
  } else {
    0
  }
  a <- e[-1] - rho * e[-length(e)]
  s2 <- mean(a^2)
  if (!is.finite(s2) || s2 <= 0) return(-Inf)
  -(m / 2) * (log(2 * pi * s2) + 1)
}

#' Bayesian calibration
#'
#' Instead of one best parameter set, a sample from the posterior: every set consistent with
#' the record and the priors, in proportion to how well it fits. The spread of the sample is
#' the parameters' uncertainty given the data, and runs of its sets give a predictive band.
#'
#' **The likelihood** treats the errors on Box-Cox transformed flows ([boxcox_flow()]) as a lag-1
#' autoregression with normal innovations, the autocorrelation and the innovation variance set
#' to their best values at each set. Hourly errors run on from one step to the next; treating
#' them as independent would make the posterior far too narrow. `temper`, below 1, flattens the
#' likelihood further where even that is too sure, as a power on it (0.25 counts the record as
#' worth a quarter of its length).
#'
#' **The sampler** is DREAM(ZS) (ter Braak and Vrugt, 2008; Vrugt, 2016): `chains` Markov chains
#' that propose jumps from differences between past states, kept in an archive, with randomised
#' subspace sampling. It suits the correlated, curved posteriors of hydrological models and needs
#' no tuning. The first half of each chain is burn-in. `rhat` is the Gelman-Rubin statistic on
#' the second halves: below about 1.2 for every parameter, the chains agree.
#'
#' Each run starts as [calibrate_pdm()] starts it.
#'
#' @param config,forcing,observed,lower,upper As in [calibrate_pdm()].
#' @param priors A named list of priors ([prior_uniform()], [prior_normal()],
#'   [prior_lognormal()]); parameters not named get a uniform prior over their bounds.
#' @param generations Generations of the sampler; the model runs are `chains` x `generations`
#'   plus the initial archive of 10 x parameters.
#' @param chains Number of chains.
#' @param lambda,log_offset The Box-Cox power and offset.
#' @param ar1 Model the errors' lag-1 autocorrelation.
#' @param temper Power on the likelihood, in (0, 1].
#' @param warmup,log_scale,start,baseflow_fraction,soil_fraction As in [calibrate_pdm()].
#' @param seed Random seed; the caller's random state is restored.
#' @return A `pdm_bayes` list: `samples` (the post-burn-in sets, with `log_likelihood` and
#'   `log_posterior`), `summary` (each parameter's mean, standard deviation, 5%, 50% and 95%
#'   points and `rhat`), `best` (the configuration of the highest posterior), `error_model`
#'   (the best set's error autocorrelation `rho` and innovation variance `s2`), `acceptance`,
#'   and the settings, for [posterior_band()].
#' @examples
#' rain <- synthetic_rain("2021-01-01", years = 1, dt = 1, seed = 2)
#' cfg <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(cfg), rain[c("rain", "pet")])$output$q_m3s
#' flow <- flow * exp(rnorm(length(flow), 0, 0.05))
#' fit <- calibrate_bayes(modifyList(cfg, list(fc = 0.8)), rain[c("time", "rain", "pet")], flow,
#'                        lower = c(fc = 0.5), upper = c(fc = 1.5),
#'                        priors = list(fc = prior_normal(1, 0.2)), generations = 100,
#'                        warmup = 24 * 30, start = "soil")
#' fit$summary
#' @seealso [posterior_band()], [prior_uniform()], [boxcox_flow()]
#' @export
calibrate_bayes <- function(config, forcing, observed, lower, upper, priors = list(),
                            generations = 1000L, chains = 3L, lambda = 0.5, log_offset = 0.01,
                            ar1 = TRUE, temper = 1, warmup = 0L, log_scale = character(0),
                            start = c("flow", "soil"), baseflow_fraction = 0.7,
                            soil_fraction = 0.5, seed = 1L) {
  start <- match.arg(start)
  .check(.named_bounds(lower, upper), "Supply finite, uniquely named ordered bounds")
  .check(.whole(generations, 10, 1e7) && .whole(chains, 2, 100),
         "generations must be at least 10 and chains at least 2")
  .check(.scalar(temper, 0, 1, strict = TRUE), "temper must be in (0, 1]")
  .check(is.list(priors) && all(names(priors) %in% names(lower)),
         "priors must be a list named by parameters in the bounds")
  priors <- lapply(stats::setNames(names(lower), names(lower)),
                   function(p) priors[[p]] %||% prior_uniform())
  keep <- is.finite(observed) & seq_along(observed) > warmup
  .check(sum(keep) > 10L, "Too few observed flows after the warm-up")
  zo <- boxcox_flow(observed[keep], lambda, log_offset)
  box <- .search_box(lower, upper, log_scale)
  logged <- names(lower) %in% log_scale
  settings <- list(start = start, start_flow = observed[is.finite(observed)][1L],
                   baseflow_fraction = baseflow_fraction, soil_fraction = soil_fraction,
                   flow = "q_m3s")
  simulate <- .multi_simulator(config, forcing, settings)
  build <- function(v) {
    cfg <- config
    for (p in names(v)) cfg <- .path_set(cfg, p, unname(v[[p]]))
    cfg
  }
  # Log posterior at a point z of the unit box: the likelihood (tempered), the priors on the
  # values, and for log-scaled parameters the Jacobian of value against z, as the sampler
  # walks in z.
  target <- function(z) {
    v <- box$to_value(z)
    lp <- sum(vapply(names(v), function(p) .log_prior(priors[[p]], v[[p]]), numeric(1))) +
      sum(log(v[logged]))
    if (!is.finite(lp)) return(c(-Inf, -Inf))
    sim <- tryCatch(simulate(build(v)), error = function(e) NULL)
    if (is.null(sim) || any(!is.finite(sim[keep])) || any(sim[keep] + log_offset <= 0)) {
      return(c(-Inf, -Inf))
    }
    ll <- .boxcox_ar1_loglik(boxcox_flow(sim[keep], lambda, log_offset) - zo, ar1)
    c(ll, temper * ll + lp)
  }
  run <- .with_seed(seed, .dream_zs(target, length(lower), generations, chains))
  out <- .bayes_result(run, box, names(lower), build, list(
    priors = priors, lambda = lambda, log_offset = log_offset, ar1 = ar1, temper = temper,
    settings = settings, warmup = warmup, config = config
  ))
  best_sim <- simulate(out$best)
  out$error_model <- .error_model(boxcox_flow(best_sim[keep], lambda, log_offset) - zo, ar1)
  out
}

# DREAM(ZS) on the unit box (ter Braak and Vrugt, 2008; Vrugt, 2016, algorithm 5, without the
# snooker step). `target(z)` returns c(log likelihood, log posterior). An archive Z starts with
# 10 d uniform draws; each chain starts at a draw of its own. Each generation, each chain
# proposes x + (1 + e) gamma (Z[r1] - Z[r2]) + eps over a random subset of coordinates (each
# kept with the crossover probability CR, drawn from 1/3, 2/3 and 1, at least one), with gamma =
# 2.38 / sqrt(2 d*), or 1 one generation in five so the chains can jump between modes;
# e ~ U(-0.05, 0.05) and eps ~ N(0, 1e-6). A proposal past a bound is reflected back. The
# Metropolis rule accepts it with probability exp(new - old). Every 10 generations the chains'
# states join the archive.
.dream_zs <- function(target, d, generations, chains) {
  m0 <- max(10L * d, 2L * chains)
  z_arch <- matrix(stats::runif(m0 * d), m0, d)
  x <- z_arch[seq_len(chains), , drop = FALSE]
  fx <- t(apply(x, 1, target))
  runs <- chains
  out <- array(NA_real_, c(generations, chains, d))
  lls <- lps <- matrix(NA_real_, generations, chains)
  accepted <- 0L
  for (g in seq_len(generations)) {
    gamma_one <- g %% 5L == 0L
    for (i in seq_len(chains)) {
      r <- sample.int(nrow(z_arch), 2L)
      cr <- sample(c(1 / 3, 2 / 3, 1), 1L)
      dims <- stats::runif(d) < cr
      if (!any(dims)) dims[sample.int(d, 1L)] <- TRUE
      gamma <- if (gamma_one) 1 else 2.38 / sqrt(2 * sum(dims))
      jump <- (1 + stats::runif(sum(dims), -0.05, 0.05)) * gamma *
        (z_arch[r[1], dims] - z_arch[r[2], dims]) + stats::rnorm(sum(dims), 0, 1e-6)
      prop <- x[i, ]
      prop[dims] <- prop[dims] + jump
      prop <- .reflect_unit(prop)
      fp <- target(prop)
      runs <- runs + 1L
      if (is.finite(fp[2]) && log(stats::runif(1)) < fp[2] - fx[i, 2]) {
        x[i, ] <- prop
        fx[i, ] <- fp
        accepted <- accepted + 1L
      }
      out[g, i, ] <- x[i, ]
      lls[g, i] <- fx[i, 1]
      lps[g, i] <- fx[i, 2]
    }
    if (g %% 10L == 0L) z_arch <- rbind(z_arch, x)
  }
  list(chains = out, log_likelihood = lls, log_posterior = lps,
       acceptance = accepted / (generations * chains), runs = runs + m0 - chains)
}

# A point folded back into [0, 1]: reflected at each bound, as often as needed.
.reflect_unit <- function(z) {
  z <- abs(z) %% 2
  ifelse(z > 1, 2 - z, z)
}

# The Gelman-Rubin statistic for each coordinate, from chains (draws x chains x coordinates).
.gelman_rubin <- function(draws) {
  n <- dim(draws)[1]
  apply(draws, 3, function(x) {
    means <- colMeans(x)
    w <- mean(apply(x, 2, stats::var))
    b <- n * stats::var(means)
    if (w <= 0) return(NA_real_)
    sqrt(((n - 1) / n * w + b / n) / w)
  })
}

# The result: the second half of every chain, its values, a summary with R-hat, and the set of
# highest posterior.
.bayes_result <- function(run, box, names, build, settings) {
  g <- dim(run$chains)[1]
  kept <- seq.int(floor(g / 2) + 1L, g)
  draws <- run$chains[kept, , , drop = FALSE]
  z <- matrix(draws, ncol = length(names))
  values <- t(apply(z, 1, box$to_value))
  if (length(names) == 1L) values <- t(values)
  colnames(values) <- names
  samples <- data.frame(values, log_likelihood = as.vector(run$log_likelihood[kept, ]),
                        log_posterior = as.vector(run$log_posterior[kept, ]),
                        check.names = FALSE)
  rhat <- .gelman_rubin(draws)
  summary <- data.frame(
    parameter = names, mean = colMeans(values), sd = apply(values, 2, stats::sd),
    q05 = apply(values, 2, stats::quantile, 0.05), q50 = apply(values, 2, stats::median),
    q95 = apply(values, 2, stats::quantile, 0.95), rhat = rhat, row.names = NULL
  )
  best <- values[which.max(samples$log_posterior), ]
  structure(c(list(samples = samples, summary = summary, best = build(best),
                   acceptance = run$acceptance, runs = run$runs, parameters = names,
                   generations = g, chains = dim(run$chains)[2]), settings),
            class = c("pdm_bayes", "list"))
}

#' @export
print.pdm_bayes <- function(x, ...) {
  cat(sprintf(paste("Bayesian calibration: %d chains x %d generations, %d model runs,",
                    "acceptance %.0f%%; %d posterior sets\n"),
              x$chains, x$generations, x$runs, 100 * x$acceptance, nrow(x$samples)))
  print(x$summary, digits = 4, row.names = FALSE)
  if (any(x$summary$rhat > 1.2, na.rm = TRUE)) {
    cat("R-hat above 1.2: the chains disagree; run more generations\n")
  }
  invisible(x)
}

#' A predictive band from the posterior
#'
#' Runs `draws` sets from the posterior of [calibrate_bayes()] and returns quantiles of the
#' flow at each step. With `noise = FALSE` the band is the parameters' uncertainty alone; with
#' `noise = TRUE` each run also gets an error drawn from the fitted error model (the lag-1
#' autoregression on Box-Cox flows), which is what the observed flow is expected to scatter by.
#'
#' @param x A `pdm_bayes` result.
#' @param forcing The forcing to run, from the same first row as the calibration's.
#' @param draws Posterior sets to run.
#' @param probs Quantiles to return.
#' @param noise Add the fitted error to each run.
#' @param seed Random seed; the caller's random state is restored.
#' @return A data frame: `row`, `time` (when the forcing has one), and one column a quantile.
#' @seealso [calibrate_bayes()]
#' @export
posterior_band <- function(x, forcing, draws = 100L, probs = c(0.05, 0.5, 0.95),
                           noise = TRUE, seed = 1L) {
  .check(inherits(x, "pdm_bayes"), "x must come from calibrate_bayes()")
  .check(.whole(draws, 1, 1e5), "draws must be a positive whole number")
  simulate <- .multi_simulator(x$config, forcing, x$settings)
  build <- function(v) {
    cfg <- x$config
    for (p in names(v)) cfg <- .path_set(cfg, p, unname(v[[p]]))
    cfg
  }
  flows <- .with_seed(seed, {
    rows <- sample.int(nrow(x$samples), draws, replace = nrow(x$samples) < draws)
    vapply(rows, function(r) {
      q <- simulate(build(unlist(x$samples[r, x$parameters])))
      if (noise) q <- .add_error(q, x)
      q
    }, numeric(nrow(forcing)))
  })
  if (is.null(dim(flows))) flows <- matrix(flows, nrow = 1L)
  out <- data.frame(row = seq_len(nrow(forcing)))
  if ("time" %in% names(forcing)) out$time <- forcing$time
  qs <- t(apply(flows, 1, stats::quantile, probs, names = FALSE))
  if (length(probs) == 1L) qs <- t(qs)
  for (k in seq_along(probs)) out[[sprintf("q%02.0f", 100 * probs[k])]] <- qs[, k]
  out
}

# A run with an error drawn from the error model fitted to the best set: on the Box-Cox scale,
# a lag-1 autoregression with the best set's autocorrelation and innovation variance, then back.
.add_error <- function(q, x) {
  fit <- x$error_model
  z <- boxcox_flow(q, x$lambda, x$log_offset)
  eps <- stats::filter(stats::rnorm(length(z), 0, sqrt(fit$s2)), fit$rho, method = "recursive")
  .boxcox_inverse(z + as.numeric(eps), x$lambda, x$log_offset)
}

# The error model of a set: the lag-1 autocorrelation and innovation variance of its Box-Cox
# errors, as the likelihood sets them.
.error_model <- function(e, ar1) {
  e <- e[is.finite(e)]
  rho <- if (ar1) sum(e[-1] * e[-length(e)]) / sum(e[-length(e)]^2) else 0
  list(rho = rho, s2 = mean((e[-1] - rho * e[-length(e)])^2))
}

# The inverse of boxcox_flow(), floored at zero flow.
.boxcox_inverse <- function(z, lambda, offset) {
  q <- if (lambda == 0) exp(z) - offset else (pmax(lambda * z + 1, 0))^(1 / lambda) - offset
  pmax(q, 0)
}
