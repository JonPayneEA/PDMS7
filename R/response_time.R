# ============================================================ #
# Tool:         response_time
# Description:  Model-derived catchment response time and default-family AR parameters
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add pdm_response_time() and ar_from_response_time()
# Tier:         3
# Inputs:       A FlodePdmModel; a reference flow (m3/s); optional FEH time to peak (h)
# Outputs:      A list of timescales in hours, the pulse response, and an FEH check
# Dependencies: stats
# ============================================================ #

#' Response time of a calibrated model
#'
#' Measures how quickly a model's catchment responds to rain, by experiment rather than by
#' formula, so it works for any structure. The model starts in steady state at a reference
#' flow, a single pulse of rain falls in the first time step, and the extra flow it causes
#' is traced until it has nearly gone. A second run without the pulse is subtracted, so the
#' recession the model was already in does not count.
#'
#' | Result | Meaning |
#' |---|---|
#' | `time_to_peak_h` | From the middle of the pulse to the peak of the extra flow |
#' | `recession_h` | From the peak until the extra flow falls to 1/e (37 per cent) of it |
#' | `centroid_lag_h` | From the middle of the pulse to the centre of mass of the extra flow |
#'
#' The time to peak is interpolated between steps with a parabola through the peak.
#'
#' The answer depends on how wet the catchment is, because the soil store decides how much
#' of the pulse runs off and the groundwater store may be nonlinear. Give the reference flow
#' you care about: a typical flood flow for forecasting, the median for general use.
#'
#' **Comparing with FEH.** If `feh_time_to_peak_h` is given, from catchment descriptors (for
#' example `reach.postproc::feh_time_to_peak()`), the two are compared. A ratio outside
#' 0.5 to 2 is flagged: either the model's fast stores or the descriptors deserve a look.
#' The model's own figure is the better guide for that model, because it reflects the
#' calibration; the FEH figure is an independent check.
#'
#' @param model A FlodePdmModel.
#' @param flow Reference flow in m3/s at which the catchment starts, in steady state.
#' @param baseflow_fraction Share of the reference flow that is baseflow, as in
#'   [initial_state_from_flow()].
#' @param pulse_mm Depth of the rain pulse in mm, falling in the first time step.
#' @param max_hours Longest response to trace, in hours.
#' @param feh_time_to_peak_h Optional FEH time to peak in hours, for comparison.
#'
#' @return A list: `time_to_peak_h`, `recession_h`, `centroid_lag_h`, `peak_m3s` (extra flow at
#'   the peak), `dt` (model step, h), `response` (a data.frame of time in hours from the pulse
#'   centre and the extra flow) and, when FEH is given, `feh` (time to peak, ratio and flag).
#'
#' @examples
#' model <- pdm_model(area_km2 = 50)
#' rt <- pdm_response_time(model, flow = 5)
#' rt[c("time_to_peak_h", "recession_h", "centroid_lag_h")]
#' @seealso [ar_from_response_time()], [pdm_hindcast()]
#' @export
pdm_response_time <- function(model, flow, baseflow_fraction = 0.7, pulse_mm = 10,
                              max_hours = 24 * 60, feh_time_to_peak_h = NULL) {
  .check(S7::S7_inherits(model, FlodePdmModel), "model must be a FlodePdmModel")
  .check(.scalar(flow, 0, strict = TRUE), "flow must be a positive number of m3/s")
  .check(.scalar(pulse_mm, 0, strict = TRUE), "pulse_mm must be positive")
  .check(.scalar(max_hours, 0, strict = TRUE), "max_hours must be positive")
  dt <- model@dt
  n <- max(3L, ceiling(max_hours / dt))
  start <- initial_state_from_flow(model, flow, baseflow_fraction)
  dry <- data.frame(rain = numeric(n), pet = numeric(n))
  wet <- dry
  wet$rain[1] <- pulse_mm
  extra <- run_pdm(model, wet, start)$output$q_m3s - run_pdm(model, dry, start)$output$q_m3s
  .check(max(extra) > 0, "The pulse produced no extra flow; try a larger pulse_mm or flow")
  # Step k is centred at (k - 1) * dt hours after the pulse centre.
  hours <- (seq_len(n) - 1) * dt
  k <- which.max(extra)
  peak_offset <- .parabolic_peak(extra, k)
  after <- which(seq_len(n) > k & extra <= max(extra) / exp(1))
  recession <- if (length(after)) {
    j <- after[1]
    # Interpolate in log flow between the last step above and the first below 1/e.
    above <- extra[j - 1]
    below <- max(extra[j], .Machine$double.xmin)
    frac <- (log(above) - (log(max(extra)) - 1)) / (log(above) - log(below))
    (j - 1 - frac - (k - 1)) * dt
  } else {
    NA_real_
  }
  weight <- pmax(extra, 0)
  out <- list(
    time_to_peak_h = (k - 1 + peak_offset) * dt,
    recession_h = recession,
    centroid_lag_h = sum(weight * hours) / sum(weight),
    peak_m3s = max(extra),
    dt = dt,
    response = data.frame(hours = hours, extra_m3s = extra)
  )
  if (!is.null(feh_time_to_peak_h)) {
    .check(.scalar(feh_time_to_peak_h, 0, strict = TRUE),
           "feh_time_to_peak_h must be a positive number of hours")
    ratio <- out$time_to_peak_h / feh_time_to_peak_h
    out$feh <- list(time_to_peak_h = feh_time_to_peak_h, ratio = ratio,
                    flag = ratio < 0.5 || ratio > 2)
  }
  out
}

# Sub-step peak position from a parabola through the peak and its neighbours.
.parabolic_peak <- function(y, k) {
  if (k <= 1 || k >= length(y)) {
    return(0)
  }
  denom <- y[k - 1] - 2 * y[k] + y[k + 1]
  if (denom >= 0) {
    return(0)
  }
  max(-0.5, min(0.5, 0.5 * (y[k - 1] - y[k + 1]) / denom))
}

#' AR coefficients for forecast updating
#'
#' Two sources of third-order AR coefficients for error post-processing, in the Deltares
#' sign convention used by [error_updater()] and by the Environment Agency's IMFS:
#' the error at step t is a1 times the error at t - 1, plus a2 times that at t - 2, plus a3
#' times that at t - 3.
#'
#' `ar_ea_default()` gives the Environment Agency 2024 default set, defined for 15-minute
#' steps.
#'
#' `ar_from_response_time()` builds a member of the continuous default family from one
#' timescale, the principal decay time. It follows the published construction of
#' `reach.postproc::default_family_ar_parameters()`: the first coefficient is fixed at
#' 1.765; a rapid negative root decays in a third of a step; the principal root is
#' exp(-1 / decay) with the decay in steps; the remaining root makes the three sum to the
#' first coefficient. As in reach.postproc, equating a catchment's time to peak with the
#' decay of its forecast errors is an approximation, a starting estimate to be checked
#' against past events, not a derived result. Check any set with `reach.postproc::assess()`
#' before operational use.
#'
#' @param decay_h Principal decay time in hours, typically `pdm_response_time()$time_to_peak_h`.
#' @param dt Model time step in hours.
#' @param first_coefficient The fixed first coefficient of the family.
#'
#' @return A named numeric vector `a_1`, `a_2`, `a_3` with attribute `roots`.
#'
#' @examples
#' ar_ea_default()
#' ar_from_response_time(9, dt = 0.25)
#' @seealso [pdm_response_time()], [pdm_hindcast()]
#' @export
ar_from_response_time <- function(decay_h, dt, first_coefficient = 1.765) {
  .check(.scalar(decay_h, 0, strict = TRUE), "decay_h must be a positive number of hours")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  z1 <- exp(-1 / (decay_h / dt))
  z3 <- -exp(-3)
  z2 <- first_coefficient - z1 - z3
  # (z - z1)(z - z2)(z - z3) = z^3 - a1 z^2 - a2 z - a3
  a <- c(
    a_1 = z1 + z2 + z3,
    a_2 = -(z1 * z2 + z1 * z3 + z2 * z3),
    a_3 = z1 * z2 * z3
  )
  attr(a, "roots") <- c(z1, z2, z3)
  a
}

#' @rdname ar_from_response_time
#' @export
ar_ea_default <- function() {
  c(a_1 = 1.765, a_2 = -0.72625, a_3 = -0.040656)
}
