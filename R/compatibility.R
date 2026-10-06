# ============================================================ #
# Tool:         compatibility
# Description:  Configurable PDM framework: compatibility
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

#' Compatibility alias for FlodeRecharge
#'
#' @seealso [FlodeRecharge]
#' @export
Recharge <- FlodeRecharge
#' Compatibility alias for FlodeStandardRecharge
#'
#' @inherit FlodeStandardRecharge
#' @export
StandardRecharge <- FlodeStandardRecharge
#' Compatibility alias for FlodeDemandRecharge
#'
#' @inherit FlodeDemandRecharge
#' @export
DemandRecharge <- FlodeDemandRecharge
#' Compatibility alias for FlodeSplitRecharge
#'
#' @inherit FlodeSplitRecharge
#' @export
SplitRecharge <- FlodeSplitRecharge
#' Compatibility alias for FlodeStateUpdater
#'
#' @inherit FlodeStateUpdater
#' @export
StateUpdater <- FlodeStateUpdater
#' Compatibility alias for FlodeErrorUpdater
#'
#' @inherit FlodeErrorUpdater
#' @export
ErrorUpdater <- FlodeErrorUpdater
#' Compatibility alias for FlodePdmModel
#'
#' @inherit FlodePdmModel
#' @export
PDMModel <- FlodePdmModel
#' Compatibility alias for FlodePdmState
#'
#' @inherit FlodePdmState
#' @export
PDMState <- FlodePdmState
#' Compatibility alias for FlodeCapacityDistribution
#'
#' @seealso [FlodeCapacityDistribution]
#' @export
CapacityDistribution <- FlodeCapacityDistribution
#' Compatibility alias for FlodeParetoCapacity
#'
#' @inherit FlodeParetoCapacity
#' @export
ParetoCapacity <- FlodeParetoCapacity
#' Compatibility alias for FlodeRectangularCapacity
#'
#' @inherit FlodeRectangularCapacity
#' @export
RectangularCapacity <- FlodeRectangularCapacity
#' Compatibility alias for FlodeTriangularCapacity
#'
#' @inherit FlodeTriangularCapacity
#' @export
TriangularCapacity <- FlodeTriangularCapacity
#' Compatibility alias for FlodeExponentialCapacity
#'
#' @inherit FlodeExponentialCapacity
#' @export
ExponentialCapacity <- FlodeExponentialCapacity
#' Compatibility alias for FlodeLognormalCapacity
#'
#' @inherit FlodeLognormalCapacity
#' @export
LognormalCapacity <- FlodeLognormalCapacity
#' Compatibility alias for FlodeRouting
#'
#' @seealso [FlodeRouting]
#' @export
Routing <- FlodeRouting
#' Compatibility alias for FlodePowerRouting
#'
#' @inherit FlodePowerRouting
#' @export
PowerRouting <- FlodePowerRouting
#' Compatibility alias for FlodeCascadeRouting
#'
#' @inherit FlodeCascadeRouting
#' @export
CascadeRouting <- FlodeCascadeRouting
#' Compatibility alias for FlodeExponentialRouting
#'
#' @inherit FlodeExponentialRouting
#' @export
ExponentialRouting <- FlodeExponentialRouting
