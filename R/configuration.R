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

# Strict list configuration: misspelled/unused parameter names are errors.
.component <- function(spec, registry) {
  .check(
    is.list(spec) &&
      !is.null(spec$type) &&
      length(spec$type) ==
        1L && spec$type %in% names(registry),
    paste(
      "type must be one of", paste(
        names(registry),
        collapse = ", "
      )
    )
  )
  .check(
    !is.null(names(spec)) &&
      !anyDuplicated(names(spec)) &&
      all(nzchar(names(spec))),
    "Component configuration must have unique names"
  )
  type <- spec$type
  spec$type <- NULL
  do.call(registry[[type]], spec)
}
.dist_registry <- function() {
  list(
    pareto = function(cmin = 0, cmax = 140, b = 0.4) {
      FlodeParetoCapacity(cmin = cmin, cmax = cmax, b = b)
    },

    rectangular = function(cmin = 0, cmax = 200) FlodeRectangularCapacity(cmin = cmin, cmax = cmax),
    triangular = function(cmin = 0, cmax = 200) FlodeTriangularCapacity(cmin = cmin, cmax = cmax),
    exponential = function(mean = 100) FlodeExponentialCapacity(mean = mean),
    lognormal = function(meanlog = log(100) -
                           0.5, sdlog = 1) {
      FlodeLognormalCapacity(meanlog = meanlog, sdlog = sdlog)
    }
  )
}
.route_registry <- function() {
  list(
    cascade = function(k1 = 2, k2 = 4) FlodeCascadeRouting(k1 = k1, k2 = k2),
    linear = linear_routing,
    quadratic = quadratic_routing,
    cubic = cubic_routing,
    power = power_routing,

    exponential = function(a = 0.05, gamma = -5) FlodeExponentialRouting(a = a, gamma = gamma)
  )
}
.recharge_registry <- function() {
  list(
    standard = function(kg = 24, bg = 1, st = 0) FlodeStandardRecharge(kg = kg, bg = bg, st = st),
    demand = function(alpha = 0.5, beta = 1, qsat = 1) {
      FlodeDemandRecharge(alpha = alpha, beta = beta, qsat = qsat)
    },

    split = function(alpha = 0.7) FlodeSplitRecharge(alpha = alpha)
  )
}
#' Pdm from config
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param config Named model configuration list; unknown keys are rejected.
#'
#' @return A validated FlodePdmModel.
#'
#' @examples
#' pdm_from_config(pdm_presets('standard'))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
pdm_from_config <- function(config) {
  allowed <- c(
    "distribution", "recharge", "surface", "groundwater", "be", "fc", "td", "qc", "area_km2",
    "dt"
  )
  .check(
    is.list(config) &&
      !is.null(names(config)) &&
      !anyDuplicated(names(config)) &&
      all(
        names(config) %in%
          allowed
      ),
    "Config contains unknown/duplicate/unnamed keys"
  )
  if (!is.null(config$distribution)) {
    config$distribution <- .component(config$distribution, .dist_registry())
  }
  if (!is.null(config$recharge)) {
    config$recharge <- .component(config$recharge, .recharge_registry())
  }
  if (!is.null(config$surface)) {
    config$surface <- .component(config$surface, .route_registry())
  }
  if (!is.null(config$groundwater)) {
    config$groundwater <- .component(config$groundwater, .route_registry())
  }
  do.call(pdm_model, config)
}
#' Pdm presets
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param name Character preset name; NULL lists available presets.
#'
#' @return A character vector of names when name is NULL; otherwise a configuration list.
#'
#' @examples
#' pdm_presets()
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
pdm_presets <- function(name = NULL) {
  path <- system.file("config", "presets.yml", package = "pdmS7")
  presets <- yaml::read_yaml(path, eval.expr = FALSE)
  if (is.null(name)) {
    return(names(presets))
  }
  .check(
    is.character(name) &&
      length(name) ==
        1L && !is.na(name) &&
      name %in% names(presets),
    "Unknown preset; call pdm_presets() for names"
  )
  presets[[name]]
}
#' Parameter catalog
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#'
#' @return A data.frame of parameters, units, domains, examples, equation references, and
#' provenance.
#'
#' @examples
#' head(parameter_catalog())
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
parameter_catalog <- function() {
  data.table::fread(
    system.file("parameter-catalog.csv", package = "pdmS7"),
    data.table = FALSE
  )
}
.path_get <- function(config, path) {
  keys <- strsplit(path, ".", fixed = TRUE)[[1]]
  for (key in keys) {
    .check(
      is.list(config) &&
        key %in% names(config),
      paste("Unknown parameter path", path)
    )
    config <- config[[key]]
  }
  config
}
.path_set <- function(config, path, value) {
  keys <- strsplit(path, ".", fixed = TRUE)[[1]]
  descend <- function(obj, keys) {
    if (length(keys) ==
          1L) {
      obj[[keys[1L]]] <- value
    } else {
      obj[[keys[1L]]] <- descend(obj[[keys[1L]]], keys[-1L])
    }
    obj
  }
  descend(config, keys)
}
