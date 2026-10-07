# ============================================================ #
# Tool:         pack_model
# Description:  Configure the PACK snow model and restart state
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-05
# Modified:     2026-10-05 - CX: Add PACK snow components
# Tier:         3
# Inputs:       Snow parameters in mm, hours and degrees Celsius
# Outputs:      Validated S7 model and state objects
# Dependencies: S7 (typed model components); yaml (configuration)
# ============================================================ #

#' PACK snow model
#' @param precipitation_factor Nonnegative precipitation multiplier.
#' @param lower_rate_h,upper_rate_h Drainage coefficients per hour.
#' @param retention_fraction Maximum liquid fraction of total pack, in `[0,1)`.
#' @param melt_factor_mmh_c Melt factor in mm/hour/degree Celsius.
#' @param adc_alpha Fresh-snow fraction at which linear cover reversion begins, in `(0,1]`.
#' @param adc_depth_mm Total pack water equivalent for full cover, positive mm.
#' @param melt_threshold_c,snow_threshold_c,drain_threshold_c Temperature thresholds, Celsius.
#' @param areal_depletion Logical; FALSE selects a point pack with full cover when nonempty.
#' @param max_step_min Maximum internal Euler accounting interval in minutes.
#' @return A FlodePackModel.
#' @export
FlodePackModel <- S7::new_class("FlodePackModel", properties = list(
  precipitation_factor = S7::new_property(S7::class_numeric, default = 1),
  lower_rate_h = S7::new_property(S7::class_numeric, default = 0.00677),
  upper_rate_h = S7::new_property(S7::class_numeric, default = 0.27095),
  retention_fraction = S7::new_property(S7::class_numeric, default = 0.04),
  melt_factor_mmh_c = S7::new_property(S7::class_numeric, default = 0.16667),
  adc_alpha = S7::new_property(S7::class_numeric, default = 0.25),
  adc_depth_mm = S7::new_property(S7::class_numeric, default = 100),
  melt_threshold_c = S7::new_property(S7::class_numeric, default = 1),
  snow_threshold_c = S7::new_property(S7::class_numeric, default = 0),
  drain_threshold_c = S7::new_property(S7::class_numeric, default = 0),
  areal_depletion = S7::new_property(S7::class_logical, default = TRUE),
  max_step_min = S7::new_property(S7::class_numeric, default = 60)
), validator = function(self) {
  .bounded_params(self, list(
    precipitation_factor = .scalar(self@precipitation_factor, 0),
    lower_rate_h = .scalar(self@lower_rate_h, 0),
    upper_rate_h = .scalar(self@upper_rate_h, 0),
    retention_fraction = .scalar(self@retention_fraction, 0) && self@retention_fraction < 1,
    melt_factor_mmh_c = .scalar(self@melt_factor_mmh_c, 0),
    adc_alpha = .scalar(self@adc_alpha, 0, 1, strict = TRUE),
    adc_depth_mm = .scalar(self@adc_depth_mm, 0, strict = TRUE),
    melt_threshold_c = .scalar(self@melt_threshold_c),
    snow_threshold_c = .scalar(self@snow_threshold_c),
    drain_threshold_c = .scalar(self@drain_threshold_c),
    areal_depletion = length(self@areal_depletion) == 1 && !is.na(self@areal_depletion),
    max_step_min = .scalar(self@max_step_min, 0, strict = TRUE)
  ))
})

#' PACK state including fresh-snow cover memory
#' @param dry_mm,wet_mm Catchment-average dry and liquid water stores, mm.
#' @param anchor_mm,anchor_fraction Pack content and cover before latest fresh snowfall.
#' @param fresh_mm Accumulated fresh snowfall defining the cover reversion segment.
#' @return A FlodePackState; persist the complete object for restart.
#' @export
FlodePackState <- S7::new_class("FlodePackState", properties = list(
  dry_mm = S7::new_property(S7::class_numeric, default = 0),
  wet_mm = S7::new_property(S7::class_numeric, default = 0),
  anchor_mm = S7::new_property(S7::class_numeric, default = 0),
  anchor_fraction = S7::new_property(S7::class_numeric, default = 0),
  fresh_mm = S7::new_property(S7::class_numeric, default = 0)
), validator = function(self) {
  .bounded_params(self, list(
    dry_mm = .scalar(self@dry_mm, 0), wet_mm = .scalar(self@wet_mm, 0),
    anchor_mm = .scalar(self@anchor_mm, 0),
    anchor_fraction = .scalar(self@anchor_fraction, 0, 1),
    fresh_mm = .scalar(self@fresh_mm, 0)
  ))
})

#' PACK parameter presets
#' @param name Either image_hourly (user image; assumed hourly rates) or report_daily.
#' @return Named list accepted by pack_from_config; canonical coefficients use hours.
#' @export
pack_presets <- function(name = c("image_hourly", "report_daily")) {
  name <- match.arg(name)
  path <- system.file("config", "pack.yml", package = "pdmS7")
  yaml::read_yaml(path)[[name]]
}

#' Build PACK from a configuration
#' @param config Named list of FlodePackModel properties; unknown keys are rejected.
#' @return A validated FlodePackModel.
#' @export
pack_from_config <- function(config = pack_presets()) {
  .check(
    is.list(config) && !is.null(names(config)) && !anyDuplicated(names(config)),
    "PACK config must be a uniquely named list"
  )
  do.call(FlodePackModel, config)
}

.pack_cover <- function(model, state) {
  theta <- state@dry_mm + state@wet_mm
  if (theta <= 0) {
    return(0)
  }
  if (!model@areal_depletion) {
    return(1)
  }
  base <- min(1, log1p(theta) / log1p(model@adc_depth_mm))
  if (state@fresh_mm == 0 || theta <= state@anchor_mm) {
    return(base)
  }
  fresh <- state@anchor_fraction + (1 - state@anchor_fraction) *
    min(1, (theta - state@anchor_mm) / (model@adc_alpha * state@fresh_mm))
  max(base, fresh)
}
