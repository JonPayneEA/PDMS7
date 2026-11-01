# ============================================================ #
# Tool:         hindcast
# Description:  Hindcasts from many forecast origins and scores by lead time
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add pdm_hindcast(), hindcast_scores(), plot_hindcast()
# Tier:         3
# Inputs:       A FlodePdmModel; forcing (mm per step); observed flow (m3/s)
# Outputs:      data.table of forecasts by origin, lead and method; scores by lead
# Dependencies: data.table; stats
# ============================================================ #

#' Hindcast forecasts from many origins
#'
#' Reruns past forecasts. From each forecast origin the model forecasts the next
#' `horizon_h` hours, using the rain that actually fell as the forecast rain, so the
#' scores measure the model and its updating, not a rainfall forecast. A forecast LSTM can be
#' given the same origins and scored by the same [hindcast_scores()].
#'
#' **Methods.** Every hindcast includes:
#'
#' | Method | Forecast |
#' |---|---|
#' | `none` | The simulation, without updating |
#' | `persistence` | The last observed flow, held for every lead: the baseline to beat |
#' | each entry of `ar` | The simulation plus the AR projection of recent error, as in IMFS |
#' | `fitted` | As above, with AR(3) coefficients fitted to the errors in `fit_window` only |
#' | `state` | State correction at the origin (Moore 2007, Eq. 28-30), then run forward |
#'
#' By default `ar` holds the Environment Agency 2024 default set and a default-family set
#' whose principal decay is the model's own time to peak at `response_flow`, from
#' [pdm_response_time()]. The 2024 default is defined for 15-minute steps; on other steps it is
#' still applied, as given, with a message.
#'
#' Errors are observed minus simulated flow, in m3/s, additive, as in IMFS. The AR projection at
#' an origin needs the last three errors; if any of those observations is missing, that origin
#' has no AR forecast. Updated flows below `lower_limit` are raised to it.
#'
#' **No leaks.** The simulation runs continuously without updating, so the forecast from an origin
#' uses observations up to that origin only. AR coefficients come from outside the scored
#' period: the fixed sets, or `fit_window`, which should be the calibration window. Fitting on the
#' scored window would let the AR learn the errors it then corrects.
#'
#' @param model A FlodePdmModel.
#' @param forcing Data frame with `rain` and `pet`, mm per step; optional `time`.
#' @param observed Observed flow in m3/s, aligned with `forcing`; NA where missing.
#' @param state Starting state; by default steady state at the first observed flow.
#' @param window Row numbers in which forecast origins may lie, typically the validation or
#'   test window. Default: every row after the first 10 per cent.
#' @param every_h Hours between forecast origins.
#' @param horizon_h Forecast horizon in hours.
#' @param ar Named list of AR coefficient vectors, Deltares convention. `NULL` gives the default
#'   pair described above; `list()` gives none.
#' @param response_flow Reference flow in m3/s for the response time. Default: the 90th
#'   percentile of observed flow, a typical high flow.
#' @param fit_window Optional row numbers on which to fit AR(3) coefficients, method `fitted`.
#' @param state_correction `NULL` for none, or a [state_updater()] to add method `state`.
#' @param lower_limit Lowest allowed updated flow, m3/s.
#'
#' @return A list: `forecasts`, a data.table with `origin` (row), `time` (if `forcing` has
#'   one), `lead` (steps), `lead_h`, `method`, `forecast` and `observed`; `ar`, the coefficient
#'   sets used; `response_time`, the [pdm_response_time()] result; and `dt`.
#'
#' @examples
#' set.seed(1)
#' n <- 24 * 40
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0), pet = 0.05)
#' truth <- pdm_model(area_km2 = 40, fc = 1.1)
#' observed <- run_pdm(truth, forcing, initial_state_from_flow(truth, 2, 0.7))$output$q_m3s
#' model <- pdm_model(area_km2 = 40)
#' hc <- pdm_hindcast(model, forcing, observed, window = (24 * 20 + 1):n, horizon_h = 24)
#' head(hindcast_scores(hc))
#' @seealso [hindcast_scores()], [plot_hindcast()], [pdm_response_time()],
#'   [ar_from_response_time()]
#' @export
pdm_hindcast <- function(model, forcing, observed, state = NULL, window = NULL, every_h = 6,
                         horizon_h = 48, ar = NULL, response_flow = NULL, fit_window = NULL,
                         state_correction = NULL, lower_limit = 0) {
  .check_hindcast_args(model, forcing, observed, every_h, horizon_h)
  n <- nrow(forcing)
  dt <- model@dt
  horizon <- max(1L, round(horizon_h / dt))
  origins <- .hindcast_origins(window %||% seq.int(ceiling(n / 10) + 1L, n), n,
                               max(1L, round(every_h / dt)))
  state <- state %||% initial_state_from_flow(model, .first_flow(observed), 0.7)
  rt <- pdm_response_time(model, response_flow %||% .high_flow(observed))
  ar <- ar %||% .default_ar(rt, dt)
  .check(is.list(ar) && (length(ar) == 0 || !is.null(names(ar)) && all(nzchar(names(ar)))),
         "ar must be a named list of coefficient vectors")
  # Open-loop simulation, kept in segments so the state at each origin is known.
  open <- .open_loop(model, forcing, state, origins, keep_states = !is.null(state_correction))
  sim <- open$q
  if (!is.null(fit_window)) {
    ok <- fit_window[is.finite(observed[fit_window])]
    .check(length(ok) > 20, "fit_window needs more than 20 observed values")
    ar$fitted <- .fit_ar3(errors_in = observed[fit_window] - sim[fit_window])
  }
  leads <- seq_len(horizon)
  target <- outer(origins, leads, `+`)
  inside <- target <= n
  target[!inside] <- NA
  obs_at <- matrix(observed[target], nrow = length(origins))
  sim_at <- matrix(sim[target], nrow = length(origins))
  methods <- list(none = sim_at, persistence = matrix(observed[origins], length(origins), horizon))
  errors <- observed - sim
  for (name in names(ar)) {
    methods[[name]] <- pmax(sim_at + .ar_project(ar[[name]], errors, origins, horizon),
                            lower_limit)
  }
  if (!is.null(state_correction)) {
    methods$state <- .state_forecasts(model, forcing, observed, open$states, origins, horizon,
                                      state_correction)
  }
  known <- !is.na(as.vector(target))
  forecasts <- data.table::rbindlist(lapply(names(methods), function(name) {
    data.table::data.table(
      origin = rep(origins, horizon), lead = rep(leads, each = length(origins)),
      method = name, forecast = as.vector(methods[[name]]), observed = as.vector(obs_at)
    )[known]
  }))
  data.table::set(forecasts, j = "lead_h", value = forecasts[["lead"]] * dt)
  if ("time" %in% names(forcing)) {
    data.table::set(forecasts, j = "time", value = forcing$time[forecasts[["origin"]]])
  }
  data.table::setcolorder(forecasts, intersect(
    c("origin", "time", "lead", "lead_h", "method", "forecast", "observed"), names(forecasts)
  ))
  list(forecasts = forecasts, ar = ar, response_time = rt, dt = dt)
}

# Least-squares AR(3) without a mean, on the steps where an error and its three
# predecessors are all known. Deltares convention.
.fit_ar3 <- function(errors_in) {
  n <- length(errors_in)
  y <- errors_in[4:n]
  x <- cbind(errors_in[3:(n - 1)], errors_in[2:(n - 2)], errors_in[1:(n - 3)])
  ok <- is.finite(y) & rowSums(!is.finite(x)) == 0
  .check(sum(ok) > 20, "fit_window needs more than 20 complete runs of four errors")
  stats::setNames(as.numeric(qr.coef(qr(x[ok, , drop = FALSE]), y[ok])), paste0("a_", 1:3))
}

.check_hindcast_args <- function(model, forcing, observed, every_h, horizon_h) {
  .check(S7::S7_inherits(model, FlodePdmModel), "model must be a FlodePdmModel")
  .check(is.data.frame(forcing) && all(c("rain", "pet") %in% names(forcing)),
         "forcing must be a data frame with rain and pet")
  .check(is.numeric(observed) && length(observed) == nrow(forcing),
         "observed must be numeric with one value per forcing row")
  .check(.scalar(every_h, 0, strict = TRUE) && .scalar(horizon_h, 0, strict = TRUE),
         "every_h and horizon_h must be positive hours")
}

.hindcast_origins <- function(window, n, every) {
  .check(is.numeric(window) && all(window >= 1 & window <= n), "window must be row numbers")
  origins <- as.integer(seq.int(min(window), min(max(window), n) - 1L, by = every))
  origins <- origins[origins >= 3L & origins + 1L <= n]
  .check(length(origins) > 0, "No forecast origins fit in the window")
  origins
}

.first_flow <- function(observed) {
  first <- observed[is.finite(observed)][1]
  .check(!is.na(first), "observed has no finite values")
  first
}

.default_ar <- function(rt, dt) {
  if (abs(dt - 0.25) > 1e-9) {
    message("The EA 2024 AR default is defined for 15-minute steps; this model uses ",
            dt, " h steps")
  }
  list(ea_2024 = ar_ea_default(), response_time = ar_from_response_time(rt$time_to_peak_h, dt))
}

.high_flow <- function(observed) {
  q <- stats::quantile(observed, 0.9, na.rm = TRUE, names = FALSE)
  .check(is.finite(q) && q > 0, "Cannot set response_flow from observed; give it directly")
  q
}

# Simulation without updating, run in segments ending at each origin.
.open_loop <- function(model, forcing, state, origins, keep_states) {
  n <- nrow(forcing)
  ends <- unique(c(origins, n))
  q <- numeric(n)
  states <- vector("list", length(origins))
  from <- 1L
  for (end in ends) {
    run <- run_pdm(model, forcing[from:end, c("rain", "pet")], state)
    q[from:end] <- run$output$q_m3s
    state <- run$state
    if (keep_states && end %in% origins) {
      states[[match(end, origins)]] <- state
    }
    from <- end + 1L
  }
  list(q = q, states = states)
}

# AR projection of the error at each origin: one column per lead, NA where the last p errors
# are not all known.
.ar_project <- function(coefficients, errors, origins, horizon) {
  a <- as.numeric(coefficients)
  p <- length(a)
  .check(p > 0 && all(is.finite(a)), "AR coefficients must be finite")
  history <- vapply(seq_len(p) - 1L, function(i) {
    idx <- origins - i
    ifelse(idx >= 1, errors[pmax(idx, 1L)], NA_real_)
  }, numeric(length(origins)))
  history <- matrix(history, nrow = length(origins))
  out <- matrix(NA_real_, length(origins), horizon)
  for (k in seq_len(horizon)) {
    nxt <- as.vector(history %*% a)
    out[, k] <- nxt
    history <- cbind(nxt, history[, -p, drop = FALSE])
  }
  out
}

.state_forecasts <- function(model, forcing, observed, states, origins, horizon, updater) {
  n <- nrow(forcing)
  out <- matrix(NA_real_, length(origins), horizon)
  for (i in seq_along(origins)) {
    o <- origins[i]
    if (!is.finite(observed[o])) {
      next
    }
    corrected <- correct_state(model, states[[i]], observed[o], updater)$state
    rows <- seq.int(o + 1L, min(n, o + horizon))
    out[i, seq_along(rows)] <- run_pdm(model, forcing[rows, c("rain", "pet")],
                                       corrected)$output$q_m3s
  }
  out
}

#' Score a hindcast by lead time
#'
#' Scores each method at each lead time, over every origin. Persistence is the baseline:
#' `skill` is 1 minus the method's mean squared error over the persistence forecast's, on the
#' same pairs, so 0 means no better than persistence and 1 is perfect. The lead time at which
#' skill falls to zero is where a method stops earning its keep.
#'
#' `lead_ratio` divides the lead time by the model's time to peak, so catchments of different
#' speeds, and different models of the same catchment, line up on one axis.
#'
#' With `thresholds`, the step-based contingency scores at each lead time are added as
#' `pod:name`, `far:name` and `csi:name`: at that lead, was the forecast above the threshold
#' when the river was?
#'
#' @param hindcast A [pdm_hindcast()] result, or a data.table with the same columns
#'   (`origin`, `lead_h`, `method`, `forecast`, `observed`) from any model, including
#'   `persistence` rows.
#' @param thresholds Optional named vector of threshold flows, m3/s.
#' @param response_time_h Time to peak in hours for `lead_ratio`; taken from the hindcast if
#'   it has one.
#'
#' @return A data.table, one row per method and lead time: `method`, `lead_h`, `lead_ratio`,
#'   `n`, `nse`, `rmse`, `mae`, `bias` (mean forecast minus observed, m3/s), `skill`, and any
#'   threshold scores.
#'
#' @examples
#' set.seed(1)
#' n <- 24 * 30
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0), pet = 0.05)
#' observed <- run_pdm(pdm_model(area_km2 = 40, fc = 1.1), forcing)$output$q_m3s
#' hc <- pdm_hindcast(pdm_model(area_km2 = 40), forcing, observed, horizon_h = 12)
#' scores <- hindcast_scores(hc, thresholds = c(high = 3))
#' scores[scores$method == "ea_2024" & scores$lead_h %in% c(1, 6, 12), ]
#' @export
hindcast_scores <- function(hindcast, thresholds = NULL, response_time_h = NULL) {
  if (is.data.frame(hindcast)) {
    pairs <- data.table::as.data.table(hindcast)
  } else {
    .check(is.list(hindcast) && is.data.frame(hindcast$forecasts),
           "hindcast must be a pdm_hindcast() result or a data frame of forecasts")
    pairs <- data.table::copy(hindcast$forecasts)
    response_time_h <- response_time_h %||% hindcast$response_time$time_to_peak_h
  }
  need <- c("origin", "lead_h", "method", "forecast", "observed")
  .check(all(need %in% names(pairs)), paste("Forecasts need columns", toString(need)))
  .check("persistence" %in% pairs$method, "Forecasts need persistence rows for skill")
  if (!is.null(thresholds)) {
    .check(is.numeric(thresholds) && length(thresholds) > 0 && !is.null(names(thresholds)),
           "thresholds must be a named numeric vector of flows")
  }
  pairs <- as.data.frame(pairs)
  baseline <- pairs[pairs$method == "persistence", c("origin", "lead_h", "forecast")]
  names(baseline)[3] <- "base"
  pairs <- merge(pairs, baseline, by = c("origin", "lead_h"), all.x = TRUE)
  pairs <- pairs[is.finite(pairs$observed) & is.finite(pairs$forecast), ]
  groups <- split(seq_len(nrow(pairs)), list(pairs$method, pairs$lead_h), drop = TRUE)
  scores <- data.table::rbindlist(lapply(groups, function(i) {
    p <- pairs[i, ]
    row <- c(list(method = p$method[1], lead_h = p$lead_h[1]),
             .lead_scores(p$forecast, p$observed, p$base))
    for (name in names(thresholds)) {
      th <- .contingency(p$forecast >= thresholds[[name]], p$observed >= thresholds[[name]])
      row[paste0(names(th), ":", name)] <- th
    }
    row
  }))
  ratio <- if (is.null(response_time_h)) NA_real_ else scores$lead_h / response_time_h
  data.table::set(scores, j = "lead_ratio", value = ratio)
  first <- c("method", "lead_h", "lead_ratio", "n", "nse", "rmse", "mae", "bias", "skill")
  data.table::setcolorder(scores, c(first, setdiff(names(scores), first)))
  data.table::setorderv(scores, c("method", "lead_h"))
  scores
}

.lead_scores <- function(forecast, observed, base) {
  err <- forecast - observed
  mse <- mean(err^2)
  known <- is.finite(base)
  base_mse <- if (any(known)) mean((base[known] - observed[known])^2) else NA_real_
  own_mse <- if (any(known)) mean(err[known]^2) else NA_real_
  spread <- sum((observed - mean(observed))^2)
  list(
    n = length(err),
    nse = if (spread > 0) 1 - sum(err^2) / spread else NA_real_,
    rmse = sqrt(mse), mae = mean(abs(err)), bias = mean(err),
    skill = if (is.finite(base_mse) && base_mse > 0) 1 - own_mse / base_mse else NA_real_
  )
}

.contingency <- function(forecast_above, observed_above) {
  hits <- sum(forecast_above & observed_above)
  misses <- sum(!forecast_above & observed_above)
  false_alarms <- sum(forecast_above & !observed_above)
  ratio <- function(a, b) if (b > 0) a / b else NA_real_
  list(pod = ratio(hits, hits + misses), far = ratio(false_alarms, hits + false_alarms),
       csi = ratio(hits, hits + misses + false_alarms))
}

#' Plot hindcast scores against lead time
#'
#' @param scores A [hindcast_scores()] result.
#' @param metric Column to plot, such as `skill`, `nse`, `rmse` or `csi:Flood Warning`.
#' @param ratio If `TRUE`, plot against lead time over time to peak instead of hours.
#' @param methods Methods to show; default all.
#' @param col Line colours, one per method.
#' @param legend Legend position, as in [graphics::legend()].
#' @param ylim Optional y-axis limits. Skill can be very negative at the shortest lead times,
#'   which flattens the rest of the chart; `c(-1, 1)` is often clearer.
#'
#' @return The scores, invisibly.
#' @examples
#' set.seed(1)
#' n <- 24 * 30
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0), pet = 0.05)
#' observed <- run_pdm(pdm_model(area_km2 = 40, fc = 1.1), forcing)$output$q_m3s
#' hc <- pdm_hindcast(pdm_model(area_km2 = 40), forcing, observed, horizon_h = 12)
#' plot_hindcast(hindcast_scores(hc))
#' @export
plot_hindcast <- function(scores, metric = "skill", ratio = FALSE, methods = NULL,
                          col = NULL, ylim = NULL, legend = "bottomright") {
  .check(is.data.frame(scores) && metric %in% names(scores),
         paste("scores has no column", metric))
  methods <- methods %||% unique(scores$method)
  if (metric == "skill") {
    methods <- setdiff(methods, "persistence")
  }
  col <- col %||% c("#444444", "#236b83", "#a26421", "#5b8c3a", "#8a3b6b", "#b23b3b",
                    "#9aa7b0")[seq_along(methods)]
  x <- if (ratio) scores$lead_ratio else scores$lead_h
  .check(!ratio || any(is.finite(x)), "scores have no lead_ratio")
  y <- scores[[metric]]
  keep <- scores$method %in% methods
  graphics::plot(range(x[keep], na.rm = TRUE), ylim %||% range(y[keep], na.rm = TRUE),
                 type = "n",
                 xlab = if (ratio) "Lead time / time to peak" else "Lead time (h)",
                 ylab = metric)
  if (metric == "skill") {
    graphics::abline(h = 0, col = "#9aa7b0", lty = 2)
  }
  for (i in seq_along(methods)) {
    rows <- scores$method == methods[i]
    graphics::lines(x[rows], y[rows], col = col[i], lwd = 1.8)
  }
  graphics::legend(legend, methods, col = col, lwd = 1.8, bty = "n")
  invisible(scores)
}
