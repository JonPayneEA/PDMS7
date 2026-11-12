# ============================================================ #
# Tool:         synthetic_rain
# Description:  Stochastic rainfall: Neyman-Scott and Bartlett-Lewis rectangular pulses,
#               a Markov chain with gamma amounts, and seasonal block resampling of a
#               record; fitting of each to a gauge record; seasonal PET
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-02
# Modified:     2026-11-02 - Add synthetic_rain(), fit_rain() and rain_statistics()
# Tier:         1
# Inputs:       Parameters by calendar month, or a rainfall record (time, mm per step)
# Outputs:      Regular rain and PET series, mm per step; fitted parameter tables
# Dependencies: stats; S7 (reading reach.io objects)
# ============================================================ #

# ---- Parameters ------------------------------------------------------------------------------

# Column names of each method's parameter table, one row per calendar month. Rates are per hour
# and intensities mm per hour.
.rain_columns <- list(
  nsrp = c("lambda", "beta", "nu", "eta", "mux"),
  bartlett_lewis = c("lambda", "gamma", "beta", "eta", "mux"),
  markov_gamma = c("p01", "p11", "shape", "scale")
)

# Illustrative Neyman-Scott parameters: frontal winter storms (many long, gentle cells spread
# over half a day) shading into convective summer storms (few short, intense cells close
# together), about 760 mm a year. Chosen by hand to look like lowland England; not fitted to
# any site.
.nsrp_default <- function() {
  winter <- c(lambda = 0.018, beta = 0.08, nu = 4, eta = 0.6, mux = 0.8)
  summer <- c(lambda = 0.010, beta = 0.30, nu = 3, eta = 1.5, mux = 3.2)
  w <- (1 - cos(2 * pi * (0:11) / 12)) / 2
  out <- as.data.frame(outer(1 - w, winter) + outer(w, summer))
  cbind(month = 1:12, out)
}

#' Rainfall generator parameters
#'
#' The built-in parameters of each rainfall generator, one row per calendar month. They are
#' illustrative, chosen to resemble lowland England (about 760 mm a year, frontal winters and
#' convective summers), and are not fitted to any site. Use [fit_rain()] for parameters that
#' resemble a real gauge.
#'
#' The Neyman-Scott values were set by hand. The Bartlett-Lewis values were fitted to the
#' Neyman-Scott model's own statistics, and the Markov chain and gamma values to 200 years of
#' its daily rain, so all three describe the same climate.
#'
#' - `nsrp`: `lambda` storms per hour; `beta` rate of the exponential delay from a storm's origin
#'   to each cell, per hour; `nu` mean cells per storm (Poisson); `eta` rate of the exponential
#'   cell duration, per hour; `mux` mean cell intensity, mm/h (exponential).
#' - `bartlett_lewis`: `lambda` storms per hour; `gamma` rate at which a storm stops producing
#'   cells, per hour; `beta` cell arrival rate while it does, per hour; `eta` and `mux` as
#'   above. A cell starts at the storm's origin.
#' - `markov_gamma`: `p01` chance a day is wet after a dry day; `p11` after a wet day; `shape` and
#'   `scale` of the gamma wet-day amount, mm.
#'
#' @param method One of `nsrp`, `bartlett_lewis` or `markov_gamma`.
#' @return A data frame with `month` and the method's columns, classed `pdm_rain_parameters`.
#' @examples
#' rain_parameters("nsrp")
#' @seealso [synthetic_rain()], [fit_rain()]
#' @export
rain_parameters <- function(method = c("nsrp", "bartlett_lewis", "markov_gamma")) {
  method <- match.arg(method)
  out <- switch(method,
    nsrp = .nsrp_default(),
    bartlett_lewis = .bl_default(),
    markov_gamma = .mg_default()
  )
  .as_rain_parameters(out, method)
}

.as_rain_parameters <- function(x, method) {
  x <- as.data.frame(x)
  cols <- .rain_columns[[method]]
  .check(all(c("month", cols) %in% names(x)) && nrow(x) == 12L && setequal(x$month, 1:12),
         paste0("Parameters for ", method, " need 12 rows (month 1 to 12) and columns ",
                paste(cols, collapse = ", ")))
  x <- x[order(x$month), c("month", cols)]
  .check(all(is.finite(as.matrix(x[cols]))) && all(x[cols] > 0),
         "Rain parameters must be finite and positive")
  if (method == "markov_gamma") {
    .check(all(x$p01 < 1 & x$p11 < 1), "p01 and p11 must lie below 1")
  }
  rownames(x) <- NULL
  structure(x, class = c("pdm_rain_parameters", "data.frame"), method = method)
}

# ---- Second-order statistics of the pulse models -------------------------------------------

# Both pulse models are Poisson clusters of rectangular cells with exponential durations (rate
# eta) and exponential intensities (mean mux), and differ only in where a storm's cells start.
# The covariance of the continuous rain rate at lag tau is then
#   c(tau) = lambda * mc * E[X^2] * exp(-eta tau) / eta
#            + lambda * mx^2 * M2 * E[exp(-eta |tau - D|)] / (2 eta),
# where mc is the mean number of cells per storm, M2 the mean number of ordered pairs of cells,
# and D the difference between the start times of a pair. For both models D is Laplace with rate
# alpha (Neyman-Scott: alpha = beta, M2 = nu^2; Bartlett-Lewis: alpha = gamma,
# M2 = 2 kappa (1 + kappa), kappa = beta / gamma), so c(tau) = A exp(-eta tau) + B exp(-alpha tau).
.pulse_terms <- function(p, method) {
  if (method == "nsrp") {
    mc <- p[["nu"]]
    m2 <- p[["nu"]]^2
    alpha <- p[["beta"]]
  } else {
    kappa <- p[["beta"]] / p[["gamma"]]
    mc <- 1 + kappa
    m2 <- 2 * kappa * (1 + kappa)
    alpha <- p[["gamma"]]
  }
  lambda <- p[["lambda"]]
  eta <- p[["eta"]]
  mx <- p[["mux"]]
  # Equal rates make the two exponentials coincide; nudge alpha, which changes nothing visible.
  if (abs(alpha - eta) < 1e-6 * eta) alpha <- eta * (1 + 1e-6)
  k <- lambda * m2 * mx^2 / (2 * (alpha^2 - eta^2))
  list(mean_rate = lambda * mc * mx / eta, eta = eta, alpha = alpha,
       a = 2 * lambda * mc * mx^2 / eta + k * alpha^2 / eta, b = -k * alpha, mc = mc)
}

# Variance and lag-k autocovariance of rain totals over intervals of h hours, for a covariance
# that is a sum of exponentials K exp(-a tau).
.agg_var <- function(t, h) {
  f <- function(k, a) 2 * k * (a * h - 1 + exp(-a * h)) / a^2
  f(t$a, t$eta) + f(t$b, t$alpha)
}

.agg_cov <- function(t, h, lag = 1) {
  f <- function(k, a) k * (1 - exp(-a * h))^2 * exp(-a * (lag - 1) * h) / a^2
  f(t$a, t$eta) + f(t$b, t$alpha)
}

# Probability that an interval of h hours is dry. A storm with origin s leaves (0, h) dry when
# none of its cells is wet there; storms arrive as a Poisson process, so
#   P(dry) = exp(-lambda * integral over s of P(storm at s wets the interval)).
# A cell starting at u < 0 is still wet at 0 with probability exp(eta u); one starting in [0, h)
# is wet; one starting after h is not.
.pulse_pdry <- function(p, method, h) {
  eta <- p[["eta"]]
  wet_storm <- if (method == "nsrp") {
    beta <- p[["beta"]]
    nu <- p[["nu"]]
    d <- if (abs(eta - beta) < 1e-9) 1e-9 else eta - beta
    function(s) {
      w <- ifelse(s < 0,
                  exp(beta * s) * (1 - exp(-beta * h)) +
                    beta * exp(beta * s) * (1 - exp(d * s)) / d,
                  1 - exp(-beta * (h - s)))
      1 - exp(-nu * w)
    }
  } else {
    beta <- p[["beta"]]
    gamma <- p[["gamma"]]
    # Cumulative wet weight of cell starts up to x: integral of the wet chance w(u).
    omega <- function(x) ifelse(x < 0, exp(eta * x) / eta, 1 / eta + pmin(x, h))
    w1 <- function(s) ifelse(s < 0, exp(eta * s), 1)
    # Expectation over the storm's active time T ~ Exp(gamma), by the substitution
    # T = -log(1 - v) / gamma and the midpoint rule on v in (0, 1).
    v <- (seq_len(400) - 0.5) / 400
    wt <- rep(1 / 400, 400)
    tt <- -log1p(-v) / gamma
    function(s) {
      inner <- exp(-beta * (omega(outer(s, tt, "+")) - omega(s))) %*% wt
      1 - (1 - w1(s)) * as.vector(inner)
    }
  }
  # Integral over s from -infinity to h, split at 0. Below 0 the integrand decays at least like
  # exp(r s), r the slower of the cell rate and the storm (or cell delay) rate, so s = log(y) / r
  # maps it onto y in (0, 1); both parts use the midpoint rule.
  r <- min(eta, if (method == "nsrp") p[["beta"]] else p[["gamma"]])
  y <- (seq_len(300) - 0.5) / 300
  i1 <- sum(wet_storm(log(y) / r) / (r * y)) / 300
  u <- (seq_len(100) - 0.5) / 100 * h
  i2 <- sum(wet_storm(u)) * h / 100
  exp(-p[["lambda"]] * (i1 + i2))
}

#' Rainfall statistics
#'
#' Statistics of rain totals over intervals of a given length: mean, variance, lag-1
#' autocorrelation and the proportion of dry intervals. For a record they are computed from the
#' data, month by month; for a pulse model's parameters they are the model's exact values, which
#' [fit_rain()] matches to a record's.
#'
#' @param x A record (see [fit_rain()]) or a parameter table from [rain_parameters()] or
#'   [fit_rain()] for `nsrp` or `bartlett_lewis`.
#' @param hours Interval lengths, hours.
#' @param wet_threshold A record's interval counts as dry at or below this depth, mm. The pulse
#'   models' dry proportion is for exactly no rain, so compare them at 0.
#' @return A data frame: `month`, `hours`, `mean`, `variance`, `lag1`, `pdry`.
#' @examples
#' rain_statistics(rain_parameters("nsrp"), hours = c(1, 24))[1:4, ]
#' @export
rain_statistics <- function(x, hours = c(1, 24), wet_threshold = 0) {
  .check(is.numeric(hours) && all(hours > 0), "hours must be positive")
  if (inherits(x, "pdm_rain_parameters")) {
    method <- attr(x, "method")
    .check(method %in% c("nsrp", "bartlett_lewis"),
           "Exact statistics are available for the pulse models only")
    rows <- lapply(seq_len(12), function(m) {
      p <- unlist(x[m, .rain_columns[[method]]])
      .model_stats(p, method, hours, m)
    })
    return(do.call(rbind, rows))
  }
  .record_stats(.as_rain_record(x), hours, wet_threshold)
}

.model_stats <- function(p, method, hours, month) {
  t <- .pulse_terms(p, method)
  do.call(rbind, lapply(hours, function(h) {
    v <- .agg_var(t, h)
    data.frame(month = month, hours = h, mean = t$mean_rate * h, variance = v,
               lag1 = .agg_cov(t, h) / v, pdry = .pulse_pdry(p, method, h))
  }))
}

# ---- Records -------------------------------------------------------------------------------

# A rainfall record as a data frame of time (POSIXct, UTC) and rain (mm per step) at a regular
# step. Accepts a data frame with a time column (time, dateTime, datetime or date) and a rain
# column (rain or value), or an object whose readings property holds one, as reach.io's
# read_silver() returns.
.as_rain_record <- function(record) {
  if (!is.data.frame(record) && S7::S7_inherits(record)) {
    record <- tryCatch(S7::prop(record, "readings"), error = function(e) NULL)
  }
  .check(is.data.frame(record), paste(
    "A rainfall record must be a data frame with time and rain columns, or a reach.io object",
    "with readings"
  ))
  tcol <- intersect(c("time", "dateTime", "datetime", "date"), names(record))[1L]
  vcol <- intersect(c("rain", "value"), names(record))[1L]
  .check(!is.na(tcol) && !is.na(vcol),
         "The record needs a time column (time or dateTime) and a rain column (rain or value)")
  time <- record[[tcol]]
  time <- if (inherits(time, "POSIXt")) as.POSIXct(time, tz = "UTC") else .parse_time(time)
  rain <- as.numeric(record[[vcol]])
  o <- order(time)
  time <- time[o]
  rain <- rain[o]
  .check(length(time) > 2L && !anyDuplicated(time), "The record needs unique times")
  step <- stats::median(as.numeric(diff(time), units = "hours"))
  # Fill missing steps with NA so the record is regular.
  grid <- seq(time[1L], time[length(time)], by = step * 3600)
  full <- rep(NA_real_, length(grid))
  full[match(time, grid)] <- rain
  .check(all(full[is.finite(full)] >= 0), "Rainfall must be nonnegative")
  structure(data.frame(time = grid, rain = full), step_h = step)
}

# Totals over intervals of h hours, aligned to midnight UTC; an interval with any missing step is
# missing.
.aggregate_rain <- function(rec, h) {
  step <- attr(rec, "step_h")
  .check(h >= step - 1e-9 && abs(h / step - round(h / step)) < 1e-9,
         paste0("Cannot total ", step, "-hour rain into ", h, "-hour intervals"))
  k <- round(h / step)
  origin <- as.numeric(rec$time[1L]) %/% 86400 * 86400
  idx <- floor((as.numeric(rec$time) - origin) / (h * 3600))
  n <- tapply(rec$rain, idx, length)
  tot <- tapply(rec$rain, idx, sum)
  keep <- n == k
  data.frame(time = as.POSIXct(origin + as.numeric(names(tot)[keep]) * h * 3600,
                               origin = "1970-01-01", tz = "UTC"),
             rain = as.numeric(tot[keep]), index = as.numeric(names(tot)[keep]))
}

.record_stats <- function(rec, hours, wet_threshold) {
  do.call(rbind, lapply(hours, function(h) {
    a <- .aggregate_rain(rec, h)
    month <- as.POSIXlt(a$time)$mon + 1L
    nxt <- match(a$index + 1, a$index)
    do.call(rbind, lapply(1:12, function(m) {
      r <- a$rain[month == m]
      ok <- is.finite(r)
      pair <- which(month == m & !is.na(nxt))
      pair <- pair[month[nxt[pair]] == m & is.finite(a$rain[pair]) &
                     is.finite(a$rain[nxt[pair]])]
      lag1 <- if (length(pair) > 2L) {
        stats::cor(a$rain[pair], a$rain[nxt[pair]])
      } else {
        NA_real_
      }
      data.frame(month = m, hours = h, mean = mean(r[ok]), variance = stats::var(r[ok]),
                 lag1 = lag1, pdry = mean(r[ok] <= wet_threshold))
    }))
  }))
}

# ---- Simulation ----------------------------------------------------------------------------

#' Synthetic rainfall
#'
#' Generates a regular series of rain and potential evaporation, mm per step, for driving a
#' model. Four rainfall generators are available:
#'
#' - `nsrp` (default): Neyman-Scott rectangular pulses. Storms arrive at random, each spawning
#'   a random number of rain cells, delayed from the storm's origin, each with its own duration
#'   and intensity (Cowpertwait 1996). Widely used for UK rainfall. Any step.
#' - `bartlett_lewis`: Bartlett-Lewis rectangular pulses. As above, but a storm produces cells at
#'   a steady rate until it stops (Rodriguez-Iturbe et al. 1987; the original model, with a
#'   fixed cell duration rate). Any step.
#' - `markov_gamma`: wet and dry days from a two-state Markov chain, wet-day amounts from a gamma
#'   distribution (Richardson 1981). Daily only.
#' - `resample`: a seasonal block bootstrap of a real record: blocks of whole days drawn from
#'   any year within a few weeks of the same date. The rain is real; the sequence is new. It
#'   cannot produce a storm bigger than the record holds. The record's step, or a multiple.
#'
#' Parameters vary by calendar month. Without `parameters` or `record`, the built-in
#' illustrative values of [rain_parameters()] are used. With `record`, the generator is first
#' fitted to it by [fit_rain()] (for `resample`, the record is used directly).
#'
#' PET follows a sine curve through the year (as reach.io's `generate_pe_sine()` does), peaking
#' at `pet$peak_day`, and is spread evenly over the steps of each day. It is never negative.
#'
#' @param start First time, as text or POSIXct (UTC).
#' @param years Length in years (365 days each).
#' @param dt Step, hours: 0.25, 1, 24 or any value that divides a day or is a whole number of
#'   days.
#' @param method Generator; see the table.
#' @param parameters A parameter table from [rain_parameters()] or [fit_rain()].
#' @param record A rainfall record to fit or resample: a data frame with `time` (or `dateTime`)
#'   and `rain` (or `value`, mm per step), or an object from `reach.io::read_silver()`.
#' @param pet List of `mean` (mm per day), `amplitude` (mm per day) and `peak_day` (day of the
#'   year), or `NULL` for no PET column.
#' @param block_days,window_days For `resample`: block length and how far, in days, from the
#'   same date a block may be drawn.
#' @param seed Optional seed; the caller's random state is left untouched.
#'
#' @return A data frame with `time` (POSIXct, UTC), `rain` and, unless `pet = NULL`, `pet`, both
#'   mm per step, ready for [run_pdm()] or [synthetic_catchment()]. Attributes record the method
#'   and the parameters used.
#' @references
#' Cowpertwait, P.S.P. (1996) Further developments of the Neyman-Scott clustered point process
#' for modeling rainfall. Water Resources Research 32(7), 2155-2164.
#'
#' Rodriguez-Iturbe, I., Cox, D.R. and Isham, V. (1987) Some models for rainfall based on
#' stochastic point processes. Proceedings of the Royal Society of London A 410, 269-288.
#'
#' Richardson, C.W. (1981) Stochastic simulation of daily precipitation, temperature, and solar
#' radiation. Water Resources Research 17(1), 182-190.
#' @examples
#' hourly <- synthetic_rain("2020-10-01", years = 1, seed = 1)
#' sum(hourly$rain)
#' daily <- synthetic_rain("2020-10-01", years = 2, dt = 24, method = "markov_gamma", seed = 1)
#' head(daily)
#' @seealso [fit_rain()], [rain_parameters()], [synthetic_catchment()]
#' @export
synthetic_rain <- function(start, years = 10, dt = 1,
                           method = c("nsrp", "bartlett_lewis", "markov_gamma", "resample"),
                           parameters = NULL, record = NULL,
                           pet = list(mean = 1.5, amplitude = 1.3, peak_day = 182),
                           block_days = 10, window_days = 15, seed = NULL) {
  method <- match.arg(method)
  .check(.scalar(years, 0, strict = TRUE), "years must be positive")
  .check(.scalar(dt, 0, strict = TRUE) && (abs(24 / dt - round(24 / dt)) < 1e-9 ||
                                             abs(dt / 24 - round(dt / 24)) < 1e-9),
         "dt must divide a day or be a whole number of days")
  start <- if (inherits(start, "POSIXt")) as.POSIXct(start, tz = "UTC") else .parse_time(start)
  n <- as.integer(round(years * 365 * 24 / dt))
  .check(n >= 2L, "The series needs at least two steps")
  time <- start + (seq_len(n) - 1) * dt * 3600
  .seeded(seed, .synthetic_rain(time, dt, method, parameters, record, pet, block_days,
                                window_days))
}

.synthetic_rain <- function(time, dt, method, parameters, record, pet, block_days, window_days) {
  if (method == "resample") {
    .check(!is.null(record), "method = \"resample\" needs a record")
    rain <- .resample_rain(.as_rain_record(record), time, dt, block_days, window_days)
    used <- NULL
  } else {
    used <- if (!is.null(parameters)) {
      .as_rain_parameters(parameters, method)
    } else if (!is.null(record)) {
      fit_rain(record, method)
    } else {
      rain_parameters(method)
    }
    .check(identical(attr(used, "method"), method),
           "parameters were made for a different method")
    rain <- if (method == "markov_gamma") {
      .check(abs(dt - 24) < 1e-9, paste(
        "markov_gamma makes daily rain only; use dt = 24, or a pulse model or resample for",
        "shorter steps"
      ))
      .simulate_markov_gamma(used, time)
    } else {
      .simulate_pulses(used, method, time, dt)
    }
  }
  out <- data.frame(time = time, rain = rain)
  if (!is.null(pet)) out$pet <- .sine_pet(time, dt, pet)
  structure(out, rain_method = method, rain_parameters = used)
}

# Evaluates expr with the random seed set (by .with_seed(), which restores the caller's random
# state); with a NULL seed, expr runs on the caller's stream.
.seeded <- function(seed, expr) {
  if (is.null(seed)) return(expr)
  .check(.scalar(seed), "seed must be a number")
  .with_seed(seed, expr)
}

# Storm origins month by month, from a few days before the start so cells already running at
# the start are included. Returns origin times in hours from the start, and each origin's month.
.storm_origins <- function(par, start, hours, burn) {
  from <- start - burn * 3600
  edges <- seq(as.POSIXct(format(from, "%Y-%m-01"), tz = "UTC"),
               by = "month", length.out = ceiling((hours + burn) / 24 / 28) + 3)
  edges <- edges[edges <= start + hours * 3600 | seq_along(edges) == 1L]
  edges <- c(edges, start + hours * 3600)
  out <- list()
  for (i in seq_len(length(edges) - 1L)) {
    a <- max(as.numeric(edges[i]), as.numeric(from))
    b <- as.numeric(edges[i + 1L])
    if (b <= a) next
    m <- as.POSIXlt(edges[i])$mon + 1L
    k <- stats::rpois(1L, par$lambda[m] * (b - a) / 3600)
    out[[length(out) + 1L]] <- data.frame(t = (stats::runif(k, a, b) - as.numeric(start)) / 3600,
                                          month = rep(m, k))
  }
  do.call(rbind, out)
}

.simulate_pulses <- function(par, method, time, dt) {
  hours <- length(time) * dt
  storms <- .storm_origins(par, time[1L], hours, burn = 240)
  p <- par[storms$month, ]
  if (method == "nsrp") {
    n <- stats::rpois(nrow(storms), p$nu)
    s <- rep(seq_len(nrow(storms)), n)
    begin <- storms$t[s] + stats::rexp(length(s), p$beta[s])
  } else {
    active <- stats::rexp(nrow(storms), p$gamma)
    extra <- stats::rpois(nrow(storms), p$beta * active)
    s <- c(seq_len(nrow(storms)), rep(seq_len(nrow(storms)), extra))
    begin <- c(storms$t, storms$t[s[-seq_len(nrow(storms))]] +
                 stats::runif(sum(extra)) * rep(active, extra))
  }
  end <- begin + stats::rexp(length(s), p$eta[s])
  x <- stats::rexp(length(s), 1 / p$mux[s])
  .pulse_depths(begin, end, x, seq(0, hours, by = dt))
}

# Rain in each step from rectangular cells: the cumulative depth is piecewise linear between
# the cells' start and end times, so its value at the step boundaries is exact.
.pulse_depths <- function(begin, end, x, bounds) {
  if (!length(begin)) return(rep(0, length(bounds) - 1L))
  t <- c(begin, end)
  dr <- c(x, -x)
  o <- order(t)
  t <- t[o]
  rate <- cumsum(dr[o])
  depth <- c(0, cumsum(rate[-length(rate)] * diff(t)))
  at <- stats::approx(t, depth, xout = bounds, rule = 2, ties = "ordered")$y
  # Before the first change the depth is 0; after the last, it stays at its final value.
  at[bounds < t[1L]] <- 0
  pmax(diff(at), 0)
}

.simulate_markov_gamma <- function(par, time) {
  month <- as.POSIXlt(time)$mon + 1L
  n <- length(time)
  wet <- logical(n)
  u <- stats::runif(n)
  wet[1L] <- u[1L] < par$p01[month[1L]] / (1 - par$p11[month[1L]] + par$p01[month[1L]])
  for (i in seq_len(n)[-1L]) {
    wet[i] <- u[i] < if (wet[i - 1L]) par$p11[month[i]] else par$p01[month[i]]
  }
  amount <- stats::rgamma(n, par$shape[month], scale = par$scale[month])
  ifelse(wet, amount, 0)
}

# Seasonal block bootstrap. Output days are filled in blocks; each block is copied from a run of
# whole days in the record that starts within window_days of the same day of the year and has no
# missing step.
.resample_rain <- function(rec, time, dt, block_days, window_days) {
  step <- attr(rec, "step_h")
  .check(abs(dt / step - round(dt / step)) < 1e-9 && dt >= step - 1e-9,
         paste0("Resampling a ", step, "-hour record needs dt to be a multiple of ", step, " h"))
  .check(.scalar(block_days, 1) && .scalar(window_days, 0), "block_days and window_days")
  per_day <- round(24 / step)
  .check(abs(24 / step - per_day) < 1e-9, "Resampling needs a record step that divides a day")
  # Whole days of the record, from its first midnight.
  first <- which(as.numeric(rec$time) %% 86400 == 0)[1L]
  .check(!is.na(first), "The record never starts a day at midnight UTC")
  days <- (length(rec$rain) - first + 1L) %/% per_day
  m <- matrix(rec$rain[first - 1L + seq_len(days * per_day)], nrow = per_day)
  day_ok <- colSums(!is.finite(m)) == 0
  doy <- as.POSIXlt(rec$time[first] + (seq_len(days) - 1) * 86400)$yday
  block_ok <- vapply(seq_len(days), function(d) {
    d + block_days - 1 <= days && all(day_ok[d:(d + block_days - 1)])
  }, logical(1))
  .check(any(block_ok), "The record has no complete block of days to resample")
  need <- ceiling(length(time) * dt / 24) + 1L
  first_doy <- as.POSIXlt(time[1L])$yday
  out <- numeric(0)
  while (length(out) < need * per_day) {
    target <- (first_doy + length(out) / per_day) %% 365
    gap <- abs(doy - target)
    gap <- pmin(gap, 365 - gap)
    candidates <- which(block_ok & gap <= window_days)
    .check(length(candidates) > 0, "No complete block of the record near this time of year")
    d <- candidates[sample.int(length(candidates), 1L)]
    out <- c(out, as.vector(m[, d:(d + block_days - 1)]))
  }
  # Align to the start time within its day, then total to dt.
  offset <- round((as.numeric(time[1L]) %% 86400) / 3600 / step)
  k <- round(dt / step)
  steps <- out[offset + seq_len(length(time) * k)]
  colSums(matrix(steps, nrow = k))
}

.sine_pet <- function(time, dt, pet) {
  .check(is.list(pet) && all(c("mean", "amplitude", "peak_day") %in% names(pet)),
         "pet needs mean, amplitude and peak_day")
  doy <- as.POSIXlt(time)$yday + 1 + (as.numeric(time) %% 86400) / 86400
  daily <- pet$mean + pet$amplitude * cos(2 * pi * (doy - pet$peak_day) / 365.25)
  pmax(daily, 0) * dt / 24
}

# ---- Fitting -------------------------------------------------------------------------------

#' Fit a rainfall generator to a record
#'
#' Estimates a generator's parameters month by month from a rainfall record, so that
#' [synthetic_rain()] produces rain that resembles it.
#'
#' - **Pulse models** (`nsrp`, `bartlett_lewis`): the method of moments. For each calendar month
#'   the model's exact mean, variance, lag-1 autocorrelation and dry proportion (see
#'   [rain_statistics()]) are matched to the record's at two interval lengths: 1 and 24 hours
#'   for a record at an hourly step or finer, 24 and 72 hours for a daily record. The mean is
#'   matched exactly; the others by least squares on relative errors, from several starts.
#' - **Markov chain with gamma amounts:** maximum likelihood. Transition probabilities from
#'   counts of consecutive valid days; gamma shape and scale from the wet-day totals.
#'
#' A month with fewer than 60 valid days borrows the parameters of its neighbours. Fitting takes
#' seconds for the Neyman-Scott model and a few minutes for Bartlett-Lewis, whose dry
#' proportion needs a double integral.
#'
#' The record may come straight from reach.io:
#' `fit_rain(reach.io::read_silver(root, "SS92F014", "P"))` reads the `dateTime` and `value`
#' columns of its readings.
#'
#' @param record A data frame with a time column (`time` or `dateTime`) and rain in mm per step
#'   (`rain` or `value`), at a regular step; or an object from `reach.io::read_silver()`.
#' @param method `nsrp`, `bartlett_lewis` or `markov_gamma`.
#' @param wet_threshold A day or interval counts as dry at or below this depth, mm. By default 0
#'   for the pulse models, whose dry proportion is for exactly no rain, and 0.1 for the Markov
#'   chain.
#' @return A parameter table as [rain_parameters()] returns, with the record's and the fitted
#'   statistics as attribute `fit`.
#' @examples
#' \donttest{
#' observed <- synthetic_rain("2000-01-01", years = 20, seed = 3, pet = NULL)
#' fitted <- fit_rain(observed, "nsrp")
#' round(fitted[1:3, ], 3)
#' }
#' @export
fit_rain <- function(record, method = c("nsrp", "bartlett_lewis", "markov_gamma"),
                     wet_threshold = NULL) {
  method <- match.arg(method)
  wet_threshold <- wet_threshold %||% if (method == "markov_gamma") 0.1 else 0
  rec <- .as_rain_record(record)
  step <- attr(rec, "step_h")
  if (method == "markov_gamma") return(.fit_markov_gamma(rec, wet_threshold))
  hours <- if (step <= 1 + 1e-9) c(1, 24) else c(24, 72)
  .check(step <= hours[1L] + 1e-9, "Pulse models need a record at a daily step or finer")
  target <- .record_stats(rec, hours, wet_threshold)
  days <- .valid_days(rec)
  rows <- lapply(1:12, function(m) {
    if (days[m] < 60) return(NULL)
    .fit_pulse_month(target[target$month == m, ], method)
  })
  par <- .borrow_months(rows, .rain_columns[[method]])
  out <- .as_rain_parameters(par, method)
  fitted <- rain_statistics(out, hours)
  attr(out, "fit") <- merge(target, fitted, by = c("month", "hours"),
                            suffixes = c("_record", "_model"))
  out
}

.valid_days <- function(rec) {
  a <- .aggregate_rain(rec, 24)
  tabulate(as.POSIXlt(a$time)$mon[is.finite(a$rain)] + 1L, 12L)
}

# Months without enough data take the mean of the nearest months that have it.
.borrow_months <- function(rows, cols) {
  have <- which(!vapply(rows, is.null, logical(1)))
  .check(length(have) > 0, "The record has too few valid days in every month to fit")
  out <- matrix(NA_real_, 12, length(cols), dimnames = list(NULL, cols))
  for (m in have) out[m, ] <- unlist(rows[[m]][cols])
  for (m in setdiff(1:12, have)) {
    d <- pmin(abs(have - m), 12 - abs(have - m))
    out[m, ] <- colMeans(out[have[d == min(d)], , drop = FALSE])
  }
  data.frame(month = 1:12, out)
}

# One month of a pulse model. The search is over the logs of every parameter but the mean cell
# intensity, which is then set so the model's mean equals the record's.
.fit_pulse_month <- function(target, method) {
  cols <- .rain_columns[[method]]
  free <- setdiff(cols, "mux")
  lower <- log(c(lambda = 1e-4, beta = 1e-3, nu = 1.01, gamma = 1e-3, eta = 0.05))[free]
  upper <- log(c(lambda = 0.5, beta = 20, nu = 100, gamma = 20, eta = 50))[free]
  if (method == "bartlett_lewis") {
    lower["beta"] <- log(1e-3)
    upper["beta"] <- log(20)
  }
  mean_1 <- target$mean[1L] / target$hours[1L]
  build <- function(z) {
    p <- exp(pmin(pmax(z, lower), upper))
    p[["mux"]] <- 1
    t <- .pulse_terms(p, method)
    p[["mux"]] <- mean_1 / t$mean_rate
    p
  }
  loss <- function(z) {
    p <- build(z)
    pen <- sum(pmax(z - upper, 0, lower - z)^2) * 1e3
    val <- tryCatch({
      t <- .pulse_terms(p, method)
      err <- unlist(lapply(seq_len(nrow(target)), function(i) {
        h <- target$hours[i]
        v <- .agg_var(t, h)
        c((v / target$variance[i] - 1),
          if (is.finite(target$lag1[i])) (.agg_cov(t, h) / v - target$lag1[i]),
          (.pulse_pdry(p, method, h) - target$pdry[i]) * 2)
      }))
      sum(err^2)
    }, error = function(e) 1e6)
    if (is.finite(val)) val + pen else 1e6
  }
  starts <- if (method == "nsrp") {
    list(c(lambda = 0.015, beta = 0.1, nu = 4, eta = 0.8),
         c(lambda = 0.01, beta = 0.3, nu = 3, eta = 1.5),
         c(lambda = 0.03, beta = 0.05, nu = 8, eta = 0.4))
  } else {
    list(c(lambda = 0.015, gamma = 0.1, beta = 0.4, eta = 0.8),
         c(lambda = 0.01, gamma = 0.5, beta = 1, eta = 1.5),
         c(lambda = 0.03, gamma = 0.05, beta = 0.2, eta = 0.4))
  }
  best <- NULL
  for (s in starts) {
    fit <- stats::optim(log(s[free]), loss, control = list(maxit = 600, reltol = 1e-10))
    if (is.null(best) || fit$value < best$value) best <- fit
  }
  as.list(build(best$par)[cols])
}

.fit_markov_gamma <- function(rec, wet_threshold) {
  a <- .aggregate_rain(rec, 24)
  month <- as.POSIXlt(a$time)$mon + 1L
  wet <- a$rain > wet_threshold
  nxt <- match(a$index + 1, a$index)
  days <- tabulate(month[is.finite(a$rain)], 12L)
  rows <- lapply(1:12, function(m) {
    if (days[m] < 60) return(NULL)
    i <- which(month == m & !is.na(nxt) & is.finite(a$rain))
    i <- i[is.finite(a$rain[nxt[i]])]
    from_dry <- i[!wet[i]]
    from_wet <- i[wet[i]]
    amounts <- a$rain[month == m & is.finite(a$rain) & wet]
    g <- .gamma_mle(amounts)
    list(p01 = mean(wet[nxt[from_dry]]), p11 = mean(wet[nxt[from_wet]]), shape = g[["shape"]],
         scale = g[["scale"]])
  })
  .as_rain_parameters(.borrow_months(rows, .rain_columns$markov_gamma), "markov_gamma")
}

# Gamma maximum likelihood: the scale is the mean over the shape, and the shape solves
# log(k) - digamma(k) = log(mean) - mean(log x).
.gamma_mle <- function(x) {
  x <- x[x > 0]
  .check(length(x) >= 5L, "Too few wet days to fit a gamma distribution")
  s <- log(mean(x)) - mean(log(x))
  k <- stats::uniroot(function(k) log(k) - digamma(k) - s, c(1e-3, 1e3))$root
  c(shape = k, scale = mean(x) / k)
}

# Bartlett-Lewis parameters fitted, month by month, to the exact 1- and 24-hour statistics of the
# Neyman-Scott defaults, so both describe the same illustrative climate. (Fitted to an earlier
# table with every intensity a quarter higher; scaling intensities scales mux alone.)
.bl_default <- function() {
  data.frame(
    month = 1:12,
    lambda = c(0.02368, 0.02253, 0.01975, 0.01639, 0.01335, 0.01134, 0.01064, 0.01134, 0.01335,
               0.01639, 0.01975, 0.02253),
    gamma = c(0.08655, 0.1066, 0.1722, 0.2931, 0.3947, 0.4591, 0.4812, 0.4591, 0.3947, 0.2931,
              0.1722, 0.1066),
    beta = c(0.1909, 0.2501, 0.471, 0.9678, 1.388, 1.59, 1.641, 1.59, 1.388, 0.9678, 0.471,
             0.2501),
    eta = c(0.6249, 0.7091, 0.9599, 1.349, 1.731, 1.992, 2.082, 1.992, 1.731, 1.349, 0.9599,
            0.7091),
    mux = c(0.7901, 0.94, 1.3248, 1.7848, 2.2832, 2.6856, 2.84, 2.6856, 2.2832, 1.7848, 1.3248,
            0.94)
  )
}

# Markov chain and gamma parameters fitted to 200 years of daily rain from the Neyman-Scott
# defaults (seed 9, wet above 0.1 mm).
.mg_default <- function() {
  data.frame(
    month = 1:12,
    p01 = c(0.3613, 0.3527, 0.3104, 0.2821, 0.2351, 0.2034, 0.2092, 0.203, 0.2403, 0.2851, 0.3085,
            0.3318),
    p11 = c(0.672, 0.6195, 0.5739, 0.4847, 0.4073, 0.3525, 0.34, 0.3832, 0.424, 0.4763, 0.575,
            0.6497),
    shape = c(0.9149, 0.9177, 0.9202, 0.9323, 0.8872, 0.9002, 0.8986, 0.8918, 0.8998, 0.8725,
              0.9216, 0.943),
    scale = c(4.869, 5.395, 6.311, 6.884, 7.598, 7.18, 7.442, 7.671, 7.221, 7.392, 6.427, 5.48)
  )
}
