# ============================================================ #
# Tool:         recharge
# Description:  Recharge schemes from soil to groundwater: standard, demand and split
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         1
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

#' Create FlodeRecharge
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#'
#' @return An S7 component object.
#'
#' @details This is an abstract extension class. Construct a concrete subclass.
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
# Recharge: how water reaches the slow groundwater store. Three schemes:
#   standard: drainage from the soil store, (S - st)^bg / kg mm per hour (Moore 2007, Eq. 10),
#             where st is a threshold storage below which nothing drains;
#   demand:   drainage that depends on how much room the groundwater store has (Eq. 13);
#   split:    no soil drainage; instead a fixed share of the direct runoff goes to groundwater.
FlodeRecharge <- S7::new_class("FlodeRecharge", package = "pdmS7", abstract = TRUE)
#' Create FlodeStandardRecharge
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param kg Positive recharge coefficient, hour mm^(bg-1).
#' @param bg Positive recharge exponent.
#' @param st Nonnegative tension storage threshold in mm; cannot exceed basin capacity.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeStandardRecharge(24, 1, 0)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeStandardRecharge <- S7::new_class(
  "FlodeStandardRecharge",
  parent = FlodeRecharge,
  package = "pdmS7",
  properties = list(kg = S7::class_numeric,
                    bg = S7::class_numeric,
                    st = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        kg = .scalar(self@kg, 0, strict = TRUE),
        bg = .scalar(self@bg, 0, strict = TRUE),
        st = .scalar(self@st, 0)
      )
    )
  }
)
#' Create FlodeDemandRecharge
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param alpha Demand deficit threshold in `(0,1]`, or fast-path split fraction in `[0,1]`.
#' @param beta Positive exponent of groundwater demand.
#' @param qsat Positive saturation recharge rate in mm/hour. Requires positive implied Sgmax.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeDemandRecharge(0.5, 1, 1)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeDemandRecharge <- S7::new_class(
  "FlodeDemandRecharge",
  parent = FlodeRecharge,
  package = "pdmS7",
  properties = list(alpha = S7::class_numeric,
                    beta = S7::class_numeric,
                    qsat = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        alpha = .scalar(self@alpha, 0, 1, TRUE),
        beta = .scalar(self@beta, 0, strict = TRUE),
        qsat = .scalar(self@qsat, 0, strict = TRUE)
      )
    )
  }
)
#' Create FlodeSplitRecharge
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param alpha Demand deficit threshold in `(0,1]`, or fast-path split fraction in `[0,1]`.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeSplitRecharge(0.7)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
# alpha is the share of direct runoff sent to the surface store; 1 - alpha goes to groundwater.
FlodeSplitRecharge <- S7::new_class(
  "FlodeSplitRecharge",
  parent = FlodeRecharge, package = "pdmS7", properties = list(alpha = S7::class_numeric),
  validator = function(self) if (!.scalar(self@alpha, 0, 1)) "alpha must lie in [0,1]"
)
#' Create FlodeUnrestrictedSplitRecharge
#'
#' The unrestricted split of PDM for PCs (runoff model 2): no soil drainage; a share `alpha` of
#' the direct runoff goes to the surface store and a share `beta` to the groundwater store, with
#' no rule that the two sum to one. With `beta = 1 - alpha` it is the split of
#' [FlodeSplitRecharge()] (runoff model 1). Otherwise the routes receive
#' `(alpha + beta - 1)` times the direct runoff more than the soil store gives up, or less when
#' that is negative: a gain or loss of water the model makes on purpose, which the water balance
#' counts as an input (see Details).
#'
#' @details The output's `surface_input_mm + groundwater_input_mm - direct_runoff_mm` is the
#' water gained in each step (negative when lost). `balance_error_mm` includes it, so it stays a
#' rounding error.
#'
#' @param alpha Share of direct runoff sent to the surface store, in `[0,1]`.
#' @param beta Share of direct runoff sent to the groundwater store, at least 0.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeUnrestrictedSplitRecharge(alpha = 0.6, beta = 0.3)
#'
#' @references UKCEH, PDM for PCs user manual, section 3.6 (runoff model index 2, beta_r).
#' @export
FlodeUnrestrictedSplitRecharge <- S7::new_class(
  "FlodeUnrestrictedSplitRecharge",
  parent = FlodeSplitRecharge, package = "pdmS7", properties = list(beta = S7::class_numeric),
  validator = function(self) if (!.scalar(self@beta, 0)) "beta must be a number of at least 0"
)
#' Recharge depth
#'
#' Call recharge_depth(x, soil, smax, groundwater, routing, dt). Storages are mm, dt hours,
#' returned recharge is an interval depth in mm.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' recharge_depth(FlodeStandardRecharge(24, 1, 0), soil = 50, smax = 100,
#'   groundwater = 0, routing = linear_routing(24), dt = 1)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
# recharge_depth(x, soil, smax, groundwater, routing, dt): the recharge requested over one step,
# in mm, from the soil and groundwater storages at the start of the step. The model may grant
# less if the soil store cannot supply it (see pdm_step()).
recharge_depth <- S7::new_generic("recharge_depth", "x")
S7::method(recharge_depth,
           FlodeStandardRecharge) <- function(x,
                                              soil,
                                              smax,
                                              groundwater,
                                              routing, dt) {
  max(0, soil - x@st)^x@bg / x@kg * dt
}
S7::method(recharge_depth,
           FlodeSplitRecharge) <- function(x,
                                           soil,
                                           smax,
                                           groundwater,
                                           routing, dt) {
  0
}
S7::method(recharge_depth,
           FlodeDemandRecharge) <- function(x,
                                            soil,
                                            smax,
                                            groundwater,
                                            routing, dt) {
  # Eq. 13. The groundwater store's capacity Sgmax is the storage at which it would discharge
  # qsat. g is its unfilled share; the demand rises as g grows, reaching one at g = alpha. Recharge
  # then scales between qsat dt (a full soil store with no demand) and Smax (full demand), in
  # proportion to how full the soil store is.
  .check(
    !S7::S7_inherits(routing, FlodeCascadeRouting),
    "Demand recharge requires a single groundwater store"
  )
  sgmax <- storage_for_flow(routing, x@qsat)
  .check(
    .scalar(sgmax, 0, strict = TRUE),
    "Demand recharge requires positive implied Sgmax"
  )
  g <- min(1, max(0, (sgmax - groundwater) / sgmax))
  demand <- min(1, (g / x@alpha)^x@beta)
  dsat <- x@qsat * dt
  .check(dsat <= smax, "qsat*dt must not exceed Smax for the Eq. 13 demand scheme")
  (dsat + (smax - dsat) * demand) * soil / smax
}
