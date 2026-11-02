# ============================================================ #
# Tool:         updating
# Description:  Forecast updating: state correction (Eq. 28-30) and error updater classes
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-11-01 - State correction runs in the compiled core by default
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
# State correction settings (Moore 2007, Eq. 28-30). At a forecast origin the model's flow is
# compared with the observed flow; the difference is shared between the groundwater and surface
# stores, and optionally the soil store, by changing their contents so the model's flow moves
# towards the observation. Schemes:
#   proportional:       each store takes the share of the error matching its share of the flow;
#   super_proportional: as proportional, with beta1 and beta2 weighting the surface store more;
#   non_proportional:   each store takes the whole error, scaled only by its gain.
# gb, gs and gg are the gains for groundwater, surface and soil. gg multiplies a flow error (mm/h)
# to change a storage (mm), so it has units of hours.
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
        soil_proportional = length(self@soil_proportional) == 1 && !is.na(self@soil_proportional)
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
# Sets a store's contents so that it releases flow q. For a cascade only the downstream store is
# changed, because it alone sets the outflow.
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
  if (.engine_supported(model)) {
    # Compiled state correction; results agree with the R code below (see R/engine.R).
    return(.engine_correct(model, state, observed_m3s, updater))
  }
  # The innovation epsilon: observed flow minus modelled flow at the origin, in mm/h, with the
  # constant flow qc removed from the observation first.
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
  # New target flows for each store, floored at zero, then the storages that give them.
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
  # Optional soil correction, kept within the store's capacity.
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
    state = state, correction_mm = .total_storage(state) - old,
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
# Error prediction settings (Moore 2007, Eq. 31-42): ARMA coefficients in the Deltares convention
# (the next error is ar[1] times the last, plus ar[2] times the one before, ...), on an additive or
# a log scale. offset is added before taking logs so that zero flows are allowed.
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
        scale = length(self@scale) == 1 && self@scale %in% c("additive", "log"),
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
# The error series the ARMA model works on: observed minus simulated, or the log ratio.
.errors <- function(observed, simulated, scale, offset) {
  .check(
    .finite_vector(observed) && .finite_vector(simulated) && length(observed) == length(simulated),
    "Error history needs equal-length, complete finite numeric vectors"
  )
  if (scale == "additive") {
    observed - simulated
  } else {
    .check(
      all(observed + offset > 0) && all(simulated + offset > 0),
      "Log updating requires positive flows plus offset"
    )
    log(observed + offset) - log(simulated + offset)
  }
}
