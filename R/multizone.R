# ============================================================ #
# Tool:         multizone
# Description:  The multi-zone PDM: independent PDMs over parts of the catchment, their flows
#               added at the outlet; a fast zone for a flashy part of the response
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-12
# Modified:     2026-11-12 - First version, after the PDM for PCs configuration guide, section 5
# Tier:         1
# Inputs:       A configuration with a zones list; forcing as for run_pdm()
# Outputs:      A FlodeMultiZoneModel; run_pdm() output with zone flows summed
# Dependencies: S7
# ============================================================ #

#' Multi-zone PDM
#'
#' A multi-zone PDM divides the catchment into hydrological zones, each a complete PDM with its
#' own parameters, area and delay, driven by the same rainfall and evaporation; their flows are
#' added at the outlet (PDM for PCs configuration guide, section 5). It gives a catchment a
#' third timescale where one PDM's two routes are not enough: a sharp spike over a few hours,
#' then a slower flood hydrograph, then baseflow.
#'
#' **Configuration.** A multi-zone configuration has `area_km2` and `dt` for the whole
#' catchment and a named list `zones`, each a single-zone configuration without `area_km2` or
#' `dt`. Every zone after the first has a `share`, its fraction of the catchment area; the first
#' zone takes the rest. Parameters are addressed as `zones.<name>.<path>`, such as
#' `zones.fast.share` or `zones.main.surface.k1`.
#'
#' **The fast zone.** `two_zone_config()` adds a zone for the spike to a single-zone
#' configuration, with every parameter set and most of them locked:
#'
#' | Parameter | Value | Searched |
#' |---|---|---|
#' | `share` | 0.1 of the area | 0.01 to 0.3 |
#' | soil store | Pareto, `cmax` 20 mm, `b` 0.5 | `cmax`, 1 to 100 mm |
#' | recharge | split, `alpha` 1: all direct runoff to the surface, none to groundwater | no |
#' | surface | one linear store, `kb` 1 h | `kb`, 0.25 to 12 h |
#' | groundwater | linear, `kb` 1000 h, never fed | no |
#' | `td` | 0 h | 0 to 6 h |
#' | `be`, `fc` | the main zone's | no |
#'
#' The fast zone only ever makes quick runoff, so it cannot trade baseflow with the main zone,
#' which keeps the two zones' roles apart. [calibration_bounds()] gives the main zone its usual
#' bounds and the fast zone the four above; bounds or exclusions given without a `zones.`
#' prefix apply to the first zone.
#'
#' **Running.** [run_pdm()] runs each zone with its own state and adds the flows; depth columns
#' (rain, storage, balance) are area-weighted means over the zones. A start from flow puts the
#' whole observed flow on the first zone and starts the others with their soil at
#' `soil_fraction` and their routing stores empty. Forecast updating, hindcasts, the events
#' workbench and PDM for PCs files are for single-zone models.
#'
#' @param config A single-zone configuration.
#' @param share Starting share of the catchment area for the fast zone.
#' @param names Names of the two zones.
#' @return `two_zone_config()`: a multi-zone configuration for [pdm_from_config()].
#' @references Moore, R.J. (2007). The PDM rainfall-runoff model. Hydrology and Earth System
#'   Sciences, 11(1), 483-499. UKCEH (2022). PDM for PCs, version 3.0.3: Configuration Guide,
#'   section 5.
#' @examples
#' cfg <- pdm_presets("standard")
#' cfg$area_km2 <- 36.7
#' two <- two_zone_config(cfg)
#' model <- pdm_from_config(two)
#' calibration_bounds(two)[, c("path", "lower", "upper")]
#' @export
two_zone_config <- function(config, share = 0.1, names = c("main", "fast")) {
  .check(is.list(config) && is.null(config$zones), "config must be a single-zone configuration")
  .check(.scalar(share, 0, 1) && share > 0 && share < 1, "share must lie in (0, 1)")
  .check(is.character(names) && length(names) == 2L && !anyDuplicated(names) &&
           all(nzchar(names)), "names must be two different zone names")
  main <- config
  main$area_km2 <- NULL
  main$dt <- NULL
  fast <- list(
    distribution = list(type = "pareto", cmin = 0, cmax = 20, b = 0.5),
    recharge = list(type = "split", alpha = 1),
    surface = list(type = "linear", kb = 1),
    groundwater = list(type = "linear", kb = 1000),
    be = config$be %||% 1, fc = config$fc %||% 1, td = 0, qc = 0, share = share
  )
  list(area_km2 = config$area_km2 %||% 1, dt = config$dt %||% 1,
       zones = stats::setNames(list(main, fast), names))
}

#' @rdname two_zone_config
#' @export
FlodeMultiZoneModel <- S7::new_class(
  "FlodeMultiZoneModel",
  package = "pdmS7",
  properties = list(zones = S7::class_list, area_km2 = S7::class_numeric,
                    dt = S7::class_numeric),
  validator = function(self) .multizone_problems(self)
)

# What is wrong with a multi-zone model, or NULL.
.multizone_problems <- function(self) {
  z <- self@zones
  is_model <- function(m) S7::S7_inherits(m, FlodePdmModel)
  named <- !is.null(names(z)) && !anyDuplicated(names(z))
  if (length(z) < 2L || !named || !all(vapply(z, is_model, logical(1)))) {
    return("zones must be a named list of two or more FlodePdmModel")
  }
  if (any(vapply(z, function(m) abs(m@dt - self@dt) > 1e-9, logical(1)))) {
    return("every zone must have the model's time step")
  }
  total <- sum(vapply(z, function(m) m@area_km2, numeric(1)))
  if (abs(total - self@area_km2) > 1e-9 * self@area_km2) {
    return("the zone areas must add up to area_km2")
  }
  NULL
}

#' @rdname two_zone_config
#' @export
FlodeMultiZoneState <- S7::new_class(
  "FlodeMultiZoneState", package = "pdmS7", properties = list(states = S7::class_list)
)

# TRUE for a multi-zone model, state or configuration.
.is_multizone <- function(x) S7::S7_inherits(x, FlodeMultiZoneModel)
.is_multizone_config <- function(x) is.list(x) && !is.null(x$zones)

# Builds a multi-zone model: each zone's configuration with its area (its share of the whole,
# the first zone taking the rest) and the common time step.
.multizone_from_config <- function(config) {
  .check(all(names(config) %in% c("zones", "area_km2", "dt")),
         "A multi-zone configuration has only zones, area_km2 and dt at the top")
  zones <- config$zones
  .check(is.list(zones) && length(zones) >= 2L && !is.null(names(zones)) &&
           all(nzchar(names(zones))) && !anyDuplicated(names(zones)),
         "zones must be a named list of two or more zone configurations")
  .check(.scalar(config$area_km2, 0, strict = TRUE), "area_km2 must be a positive area")
  .check(.scalar(config$dt, 0, strict = TRUE), "dt must be a positive number of hours")
  .check(!any(vapply(zones, function(z) any(c("area_km2", "dt") %in% names(z)), logical(1))),
         "Zone configurations take their area from share and their step from the model")
  .check(is.null(zones[[1]]$share), "The first zone takes the area the others leave: no share")
  shares <- vapply(zones[-1], function(z) z$share %||% NA_real_, numeric(1))
  .check(all(is.finite(shares) & shares > 0) && sum(shares) < 1,
         "Every zone after the first needs a share in (0, 1), and the shares must leave some area")
  shares <- c(1 - sum(shares), shares)
  models <- Map(function(z, s) {
    z$share <- NULL
    z$area_km2 <- config$area_km2 * s
    z$dt <- config$dt
    pdm_from_config(z)
  }, zones, shares)
  FlodeMultiZoneModel(zones = stats::setNames(models, names(zones)), area_km2 = config$area_km2,
                      dt = config$dt)
}

# Every zone's start: the soil fraction and empty routing stores.
.multizone_initial_state <- function(model, soil_fraction) {
  FlodeMultiZoneState(states = lapply(model@zones, initial_state, soil_fraction = soil_fraction))
}

# A start from flow: the whole observed flow on the first zone, in steady state; the other
# zones from the soil fraction, routing stores empty.
.multizone_state_from_flow <- function(model, observed_m3s, baseflow_fraction, soil_fraction) {
  states <- lapply(seq_along(model@zones), function(i) {
    zone <- model@zones[[i]]
    if (i == 1L) {
      # The first zone carries the whole flow: in steady state over its own area.
      initial_state_from_flow(zone, observed_m3s, baseflow_fraction, soil_fraction)
    } else {
      initial_state(zone, soil_fraction)
    }
  })
  FlodeMultiZoneState(states = stats::setNames(states, names(model@zones)))
}

.multizone_validate_state <- function(model, state) {
  .check(S7::S7_inherits(state, FlodeMultiZoneState) &&
           length(state@states) == length(model@zones),
         "A multi-zone model needs a FlodeMultiZoneState with one state per zone")
  for (i in seq_along(model@zones)) .validate_state(model@zones[[i]], state@states[[i]])
  invisible(TRUE)
}

# The forcing a zone reads: abstraction only for a zone with the groundwater extension.
.zone_forcing <- function(zone, forcing) {
  if ("abstraction" %in% names(forcing) &&
        !S7::S7_inherits(zone@groundwater, FlodeExtendedGroundwater)) {
    forcing$abstraction <- NULL
  }
  forcing
}

# Runs every zone and combines the outputs: flows (m3/s) added, depths and fractions
# area-weighted, the step and time from the first zone.
.multizone_run <- function(model, forcing, state) {
  .multizone_validate_state(model, state)
  runs <- Map(function(z, s) .run_pdm_core(z, .zone_forcing(z, forcing), s), model@zones,
              state@states)
  weights <- vapply(model@zones, function(z) z@area_km2 / model@area_km2, numeric(1))
  outputs <- lapply(runs, `[[`, "output")
  columns <- Reduce(intersect, lapply(outputs, names))
  first <- outputs[[1]]
  combined <- lapply(columns, function(col) {
    if (col %in% c("time", "step")) return(first[[col]])
    values <- lapply(outputs, `[[`, col)
    if (grepl("m3s$", col)) return(Reduce(`+`, values))
    Reduce(`+`, Map(`*`, values, weights))
  })
  output <- data.frame(stats::setNames(combined, columns), check.names = FALSE)
  states <- FlodeMultiZoneState(states = lapply(runs, `[[`, "state"))
  list(output = output, state = states, initial_state = state, model = model,
       water_balance = c(residual_mm = sum(output$balance_error_mm),
                         max_abs_step_mm = max(abs(output$balance_error_mm))))
}

# Simulated flow only, for calibration: each zone's flow, added.
.multizone_flow <- function(model, forcing, state, flow) {
  .multizone_validate_state(model, state)
  sims <- Map(function(z, s) .run_flow(z, .zone_forcing(z, forcing), s, flow), model@zones,
              state@states)
  Reduce(`+`, sims)
}

# Calibration bounds of a multi-zone configuration: the first zone's usual bounds, and for each
# other zone its share, soil capacity, surface time constant and delay. Overrides and exclusions
# without a zones. prefix apply to the first zone.
.multizone_bounds <- function(config, overrides, exclude) {
  pdm_from_config(config)
  zones <- names(config$zones)
  prefix <- function(z) paste0("zones.", z, ".")
  to_first <- function(p) if (startsWith(p, "zones.")) p else paste0(prefix(zones[1]), p)
  main <- config$zones[[1]]
  main$area_km2 <- config$area_km2
  main$dt <- config$dt
  rows <- calibration_bounds(main)
  rows$path <- paste0(prefix(zones[1]), rows$path)
  for (z in zones[-1]) {
    surface <- if (identical(config$zones[[z]]$surface$type, "linear")) "surface.kb" else
      "surface.k1"
    rows <- rbind(rows, data.frame(
      path = paste0(prefix(z), c("share", "distribution.cmax", surface, "td")),
      lower = c(0.01, 1, 0.25, 0), upper = c(0.3, 100, 12, 6),
      scale = c("linear", "log", "log", "linear"),
      note = c("Fast zone: share of the catchment area", "Fast zone: maximum store capacity (mm)",
               "Fast zone: surface time constant (h)", "Fast zone: delay (h)")
    ))
  }
  if (!is.null(overrides)) {
    names(overrides) <- vapply(names(overrides), to_first, "")
    rows <- .apply_bound_overrides(rows, overrides, config)
  }
  if (!is.null(exclude)) rows <- rows[!rows$path %in% vapply(exclude, to_first, ""), ]
  .check(nrow(rows) > 0, "No parameters left to calibrate")
  rownames(rows) <- NULL
  rows
}

# A multi-zone configuration's first zone as a single-zone configuration of the whole area.
.first_zone_config <- function(config) {
  out <- config$zones[[1]]
  out$area_km2 <- config$area_km2
  out$dt <- config$dt
  out
}
