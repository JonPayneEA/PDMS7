# ============================================================ #
# Tool:         updating
# Description:  Configurable PDM framework: updating
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

#' Create FlodeStateUpdater
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param scheme State correction rule: proportional, super_proportional, or non_proportional.
#' @param gb Nonnegative dimensionless baseflow correction gain.
#' @param gs Nonnegative dimensionless surface-flow correction gain.
#' @param gg Nonnegative soil-storage correction gain in hours; zero disables soil correction.
#' @param beta1 Positive surface-flow weighting in super-proportional correction.
#' @param beta2 Groundwater weighting, at least one, in super-proportional correction.
#' @param soil_proportional Logical scalar; use the baseflow proportion for soil correction if
#' TRUE.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeStateUpdater('proportional', 1, 1, 0, 10, 1.1, TRUE)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeStateUpdater <- S7::new_class(
  "FlodeStateUpdater",
  package = "pdmS7", properties = list(
    scheme = S7::class_character,
    gb = S7::class_numeric,
    gs = S7::class_numeric,
    gg = S7::class_numeric,

    beta1 = S7::class_numeric, beta2 = S7::class_numeric, soil_proportional = S7::class_logical
  ),
  validator = function(self) {
    .bounded_params(
      self, list(
        scheme = length(self@scheme) ==
          1L && self@scheme %in% c("proportional", "super_proportional", "non_proportional"),
        gb = .scalar(self@gb, 0),
        gs = .scalar(self@gs, 0),
        gg = .scalar(self@gg, 0),
        beta1 = .scalar(self@beta1, 0, strict = TRUE),
        beta2 = .scalar(self@beta2, 1),
        soil_proportional = length(self@soil_proportional) ==
          1 && !is.na(self@soil_proportional)
      )
    )
  }
)
#' State updater
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param scheme State correction rule: proportional, super_proportional, or non_proportional.
#' @param gb Nonnegative dimensionless baseflow correction gain.
#' @param gs Nonnegative dimensionless surface-flow correction gain.
#' @param gg Nonnegative soil-storage correction gain in hours; zero disables soil correction.
#' @param beta1 Positive surface-flow weighting in super-proportional correction.
#' @param beta2 Groundwater weighting, at least one, in super-proportional correction.
#' @param soil_proportional Logical scalar; use the baseflow proportion for soil correction if
#' TRUE.
#'
#' @return An S7 component object.
#'
#' @examples
#' state_updater(scheme = 'super_proportional')
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
state_updater <- function(
  scheme = "proportional", gb = 1, gs = 1, gg = 0, beta1 = 10, beta2 = 1.1, soil_proportional = TRUE
) {
  FlodeStateUpdater(
    scheme = scheme,
    gb = gb,
    gs = gs,
    gg = gg,
    beta1 = beta1,
    beta2 = beta2,
    soil_proportional = soil_proportional
  )
}
.change_flow <- function(routing, storage, q) {
  if (S7::S7_inherits(routing, FlodeCascadeRouting)) {
    storage[2] <- q * routing@k2
    storage
  } else {
    storage_for_flow(routing, q)
  }
}
#' Correct state
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param model A FlodePdmModel compatible with the supplied state.
#' @param state A compatible FlodePdmState; NULL in sim_pdm initializes the model.
#' @param observed_m3s Finite observed endpoint flow in cubic metres per second; td must be zero.
#' @param updater A compatible FlodeStateUpdater or FlodeErrorUpdater object.
#'
#' @return A list containing corrected state, external correction_mm, corrected flow, innovation,
#' and proportion.
#'
#' @examples
#' model <- pdm_model()
#' correct_state(model, initial_state(model), observed_m3s = 0.1)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
correct_state <- function(model, state, observed_m3s, updater = state_updater()) {
  .validate_state(model, state)
  .check(
    model@td == 0, "State correction requires td=0; delayed observations need a lag-aware smoother"
  )
  .check(
    .scalar(observed_m3s),
    "observed_m3s must be finite"
  )
  qb <- routing_flow(model@groundwater, state@groundwater)
  qs <- routing_flow(model@surface, state@surface)
  epsilon <- (observed_m3s - model@qc) * 3.6 / model@area_km2 - qb - qs
  alpha <- if (qb + qs == 0) {
    0
  } else if (updater@scheme == "super_proportional") {
    qb / (updater@beta1 * qs + updater@beta2 * qb)
  } else {
    qb / (qb + qs)
  }
  wb <- if (updater@scheme == "non_proportional") {
    1
  } else {
    alpha
  }
  ws <- if (updater@scheme == "non_proportional") {
    1
  } else {
    1 - alpha
  }
  newb <- max(0, qb + wb * updater@gb * epsilon)
  news <- max(0, qs + ws * updater@gs * epsilon)
  .check(
    !(S7::S7_inherits(model@groundwater, FlodeExponentialRouting) &&
        newb == 0) && !(S7::S7_inherits(model@surface, FlodeExponentialRouting) &&
                          news == 0), "Exponential storage cannot be corrected to zero flow"
  )
  old <- .total_storage(state)
  state@groundwater <- .change_flow(model@groundwater, state@groundwater, newb)
  state@surface <- .change_flow(model@surface, state@surface, news)
  weight <- if (updater@soil_proportional) {
    alpha
  } else {
    1
  }
  state@soil <- min(
    capacity_mean(model@distribution),
    max(0, state@soil + weight * updater@gg * epsilon)
  )
  list(
    state = state, correction_mm = .total_storage(state) -
      old,
    q_corrected_m3s = (newb + news) * model@area_km2 / 3.6 + model@qc,
    innovation_mmh = epsilon,

    alpha = alpha
  )
}

#' Create FlodeErrorUpdater
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param ar Finite vector of R-convention autoregressive coefficients (negative phi in Moore).
#' @param ma Finite vector of moving-average coefficients in R convention.
#' @param scale Error scale: additive or log.
#' @param offset Nonnegative offset in cubic metres per second for log error updating.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeErrorUpdater(0.7, numeric(), 'additive', 0)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeErrorUpdater <- S7::new_class(
  "FlodeErrorUpdater",
  package = "pdmS7", properties = list(
    ar = S7::class_numeric,
    ma = S7::class_numeric,
    scale = S7::class_character,
    offset = S7::class_numeric
  ),
  validator = function(self) {
    .bounded_params(
      self, list(
        ar = all(is.finite(self@ar)),
        ma = all(is.finite(self@ma)),
        scale = length(self@scale) ==
          1 && self@scale %in% c("additive", "log"),
        offset = .scalar(self@offset, 0)
      )
    )
  }
)
#' Error updater
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param ar Finite vector of R-convention autoregressive coefficients (negative phi in Moore).
#' @param ma Finite vector of moving-average coefficients in R convention.
#' @param scale Error scale: additive or log.
#' @param offset Nonnegative offset in cubic metres per second for log error updating.
#'
#' @return An S7 component object.
#'
#' @examples
#' error_updater(ar = 0.7)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
error_updater <- function(
  ar = c(0.7),
  ma = numeric(), scale = "additive", offset = 0
) {
  FlodeErrorUpdater(ar = ar, ma = ma, scale = scale, offset = offset)
}
.errors <- function(observed, simulated, scale, offset) {
  .check(
    is.numeric(observed) &&
      is.numeric(simulated) &&
      length(observed) ==
        length(simulated) &&
      length(observed) >
        0 && all(is.finite(observed)) &&
      all(is.finite(simulated)),
    "Error history needs equal-length, complete finite numeric vectors"
  )
  if (scale == "additive") {
    observed - simulated
  } else {
    .check(
      all(observed + offset > 0) &&
        all(simulated + offset > 0),
      "Log updating requires positive flows plus offset"
    )
    log(observed + offset) -
      log(simulated + offset)
  }
}
