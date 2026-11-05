# ============================================================ #
# Tool:         synthetic_catchment
# Description:  A synthetic catchment for demonstrations and tests: synthetic forcing, a known
#               model, optional added storms, and "observed" flow with persistent gauge error
#               and an optional rating bias above the highest gauged flow
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-02
# Modified:     2026-11-02 - Add synthetic_catchment()
# Tier:         3
# Inputs:       Rain and PET (generated or supplied); a configuration
# Outputs:      Forcing, true and observed flow, and a record of what was done
# Dependencies: stats
# ============================================================ #

#' Synthetic catchment
#'
#' Builds a calibration problem with a known answer: synthetic rain and PET drive a PDM with
#' chosen parameters, and its flow is corrupted the way a real gauge corrupts it. Calibrating
#' to the result shows what a method can and cannot recover, since the truth is known.
#'
#' In order:
#'
#' 1. **Forcing.** `rain` from [synthetic_rain()], or a data frame you supply (with `time`,
#'    `rain` and `pet`).
#' 2. **Storms.** Each row of `storms` adds a storm: `depth_mm` spread over `duration_h` hours
#'    from `time`, in a symmetric triangular profile. Use them to guarantee floods larger than
#'    the generator would give in a short record.
#' 3. **True flow.** The `truth` configuration, started from a state spun up over the first
#'    year of forcing (three cycles), so the record starts in balance.
#' 4. **Rating bias.** With `highest_gauged_m3s`, flows above it are bent as an extrapolated
#'    rating would bend them: recorded = limit x (true / limit)^b, with b chosen so a flow twice
#'    the limit is recorded `rating_bias` low (15 per cent by default; negative values record
#'    high). Below the limit the rating is exact.
#' 5. **Gauge error.** A multiplicative error, persistent in time: in logs, an AR(1) process with
#'    standard deviation `error$sd` and an e-folding memory of `error$memory_h` hours.
#'
#' The truth is the PDM itself, so the structure is exactly right, the rain exactly known and
#' the error simpler than a real gauge's. Results on a synthetic catchment are a best case.
#' Calibrate a different structure from `truth` to see what structural error does.
#'
#' @param rain Forcing from [synthetic_rain()] or your own data frame; by default
#'   `synthetic_rain(start, years, dt, method)`.
#' @param truth The true configuration. By default, the standard preset (a lowland water
#'   balance: soil capacity up to 300 mm, slow recharge with `kg` 4000 h) with
#'   surface stores of 12 h each, and `dt` and `area_km2` set. Under the default rain it
#'   evaporates about 310 mm a year, turns about 60 per cent of the rain into flow, and has a
#'   baseflow index near 0.6. Every calibrated parameter lies inside [calibration_bounds()].
#'   Its `dt` must match the forcing's step.
#' @param start,years,dt,method Passed to [synthetic_rain()] when `rain` is not given.
#' @param area_km2 Catchment area, km2, used when `truth` is not given.
#' @param storms Optional data frame of added storms: `time`, `depth_mm`, `duration_h`.
#' @param error List of `sd` (standard deviation of the log error) and `memory_h`
#'   (e-folding time of the error, hours). `sd = 0` gives exact flow.
#' @param highest_gauged_m3s Optional highest gauged flow, m3/s; flows above it carry the
#'   rating bias. Returned so it can be passed to [register_data()].
#' @param rating_bias Fractional error of the recorded flow at twice the highest gauged flow.
#' @param seed Optional seed for the rain and the error; the caller's random state is left
#'   untouched.
#'
#' @return A list, classed `pdm_synthetic_catchment`: `forcing` (time, rain, pet), `observed`
#'   (m3/s, as a gauge would record it), `true_flow` (m3/s), `truth` (configuration),
#'   `highest_gauged_m3s`, and `notes`, a list recording the rain method and parameters, the
#'   storms, the error and the rating bias.
#' @examples
#' river <- synthetic_catchment(years = 3, seed = 1,
#'   storms = data.frame(time = "2011-12-01", depth_mm = 120, duration_h = 48),
#'   highest_gauged_m3s = 20)
#' river
#' range(river$observed / river$true_flow)
#' @seealso [synthetic_rain()], [register_data()], [calibrate_pdm()]
#' @export
synthetic_catchment <- function(rain = NULL, truth = NULL, start = "2010-10-01", years = 10,
                                dt = 24, method = "nsrp", area_km2 = 60, storms = NULL,
                                error = list(sd = 0.05, memory_h = 72),
                                highest_gauged_m3s = NULL, rating_bias = 0.15, seed = NULL) {
  .check(is.list(error) && .scalar(error$sd, 0) && .scalar(error$memory_h, 0, strict = TRUE),
         "error needs sd (0 or more) and memory_h (positive hours)")
  .check(is.null(highest_gauged_m3s) || .scalar(highest_gauged_m3s, 0, strict = TRUE),
         "highest_gauged_m3s must be a positive flow, or NULL")
  .check(.scalar(rating_bias, -1, 0.99), "rating_bias must lie between -1 and 0.99")
  .seeded(seed, .synthetic_catchment(rain, truth, start, years, dt, method, area_km2, storms,
                                     error, highest_gauged_m3s, rating_bias, seed))
}

.synthetic_catchment <- function(rain, truth, start, years, dt, method, area_km2, storms, error,
                                 limit, bias, seed) {
  if (is.null(rain)) rain <- synthetic_rain(start, years, dt, method)
  .check(is.data.frame(rain) && all(c("time", "rain", "pet") %in% names(rain)),
         "rain needs time, rain and pet columns")
  forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
  forcing$time <- if (inherits(forcing$time, "POSIXt")) {
    as.POSIXct(forcing$time, tz = "UTC")
  } else {
    .parse_time(forcing$time)
  }
  step <- as.numeric(forcing$time[2L] - forcing$time[1L], units = "hours")
  if (is.null(truth)) truth <- .synthetic_truth(step, area_km2)
  model <- pdm_from_config(truth)
  .check(abs(model@dt - step) < 1e-9, paste0(
    "truth has dt = ", model@dt, " h but the forcing's step is ", step, " h"
  ))
  added <- .add_storms(forcing, storms, step)
  forcing$rain <- added$rain
  # Spin up over the first year (or the whole record if shorter), then run the record.
  first_year <- forcing[seq_len(min(nrow(forcing), round(8760 / step))), c("rain", "pet")]
  state <- spin_up(model, first_year, cycles = 3)
  true_flow <- .quietly(run_pdm(model, forcing[c("rain", "pet")], state))$output$q_m3s
  recorded <- .rating_bend(true_flow, limit, bias)
  phi <- exp(-step / error$memory_h)
  e <- stats::arima.sim(list(ar = phi), n = length(true_flow),
                        sd = error$sd * sqrt(1 - phi^2))
  structure(list(
    forcing = forcing, observed = recorded * exp(as.numeric(e)), true_flow = true_flow,
    truth = truth, highest_gauged_m3s = limit,
    notes = list(rain_method = attr(rain, "rain_method") %||% "supplied",
                 rain_parameters = attr(rain, "rain_parameters"), storms = added$storms,
                 error = error, rating_bias = if (!is.null(limit)) bias, seed = seed)
  ), class = "pdm_synthetic_catchment")
}

# The default true model: the standard preset (a lowland water balance) with surface stores of
# 12 hours, slower than the preset's 2 and 4, to suit a catchment of tens of km2. Under the
# illustrative rain (about 760 mm a year) it evaporates about 310 mm, turns about 60 per cent of
# the rain into flow, and has a baseflow index near 0.6. Every calibrated parameter lies inside
# calibration_bounds(), so a calibration can recover it.
.synthetic_truth <- function(dt, area_km2) {
  truth <- pdm_presets("standard")
  truth$dt <- dt
  truth$area_km2 <- area_km2
  truth$surface$k1 <- 12
  truth$surface$k2 <- 12
  truth
}

# Adds each storm as a symmetric triangle over its duration; the steps it covers receive the
# triangle's area within them, so the storm's total is exact.
.add_storms <- function(forcing, storms, step) {
  if (is.null(storms) || !nrow(storms)) return(list(rain = forcing$rain, storms = NULL))
  .check(is.data.frame(storms) && all(c("time", "depth_mm", "duration_h") %in% names(storms)),
         "storms needs time, depth_mm and duration_h")
  .check(all(storms$depth_mm > 0) && all(storms$duration_h > 0),
         "Storm depths and durations must be positive")
  rain <- forcing$rain
  t0 <- as.numeric(forcing$time[1L])
  begin <- (as.numeric(.parse_time(storms$time)) - t0) / 3600
  .check(all(begin >= 0 & begin + storms$duration_h <= nrow(forcing) * step),
         "Every storm must lie within the forcing")
  bounds <- seq(0, nrow(forcing) * step, by = step)
  for (i in seq_len(nrow(storms))) {
    d <- storms$duration_h[i]
    # Cumulative share of a triangle on [0, d] peaking at d / 2.
    share <- function(x) {
      x <- pmin(pmax(x, 0), d)
      ifelse(x <= d / 2, 2 * x^2 / d^2, 1 - 2 * (d - x)^2 / d^2)
    }
    rain <- rain + storms$depth_mm[i] * diff(share(bounds - begin[i]))
  }
  list(rain = rain, storms = storms)
}

# Recorded flow from true flow through a rating that is right up to the limit and bent beyond it:
# limit x (q / limit)^b, with 2^b = 2 (1 - bias), so twice the limit is recorded bias low.
.rating_bend <- function(q, limit, bias) {
  if (is.null(limit)) return(q)
  b <- log2(2 * (1 - bias))
  ifelse(q > limit, limit * (q / limit)^b, q)
}

# "no added storms", "1 added storm", "2 added storms".
.count_text <- function(n, noun) {
  paste(if (n == 0) "no" else n, if (n == 1) noun else paste0(noun, "s"))
}

#' @export
print.pdm_synthetic_catchment <- function(x, ...) {
  n <- nrow(x$forcing)
  step <- as.numeric(x$forcing$time[2L] - x$forcing$time[1L], units = "hours")
  cat("Synthetic catchment:", n, "steps of", step, "h from", .format_time(x$forcing$time[1L]),
      "\n")
  cat("  Rain:", x$notes$rain_method, "-", round(sum(x$forcing$rain) / (n * step / 8766)),
      "mm a year;", .count_text(NROW(x$notes$storms), "added storm"), "\n")
  cat("  True flow: mean", signif(mean(x$true_flow), 3), "m3/s, peak", signif(max(x$true_flow), 3),
      "m3/s\n")
  cat("  Gauge error: sd", x$notes$error$sd, "in logs, memory", x$notes$error$memory_h, "h\n")
  if (!is.null(x$highest_gauged_m3s)) {
    cat("  Rating: exact to", x$highest_gauged_m3s, "m3/s, then", 100 * x$notes$rating_bias,
        "per cent low at twice that;", sum(x$true_flow > x$highest_gauged_m3s), "steps above\n")
  }
  invisible(x)
}
