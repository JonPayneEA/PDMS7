# ============================================================ #
# Tool:         structures
# Description:  Calibration bounds by component, and sets of model structures to compare
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add structure comparison
# Tier:         3
# Inputs:       Configuration lists; inst/calibration-bounds.csv
# Outputs:      Bounds tables and named lists of configurations
# Dependencies: data.table
# ============================================================ #

.bounds_table <- function() {
  data.table::fread(system.file("calibration-bounds.csv", package = "pdmS7"),
                    data.table = FALSE, colClasses = list(character = "type"))
}

#' Calibration bounds for a model structure
#'
#' Looks up default calibration bounds for every calibrated parameter of a configuration's
#' components, from the table shipped in `inst/calibration-bounds.csv`. The rainfall factor
#' and every store parameter in the table are included; parameters that are usually fixed
#' (`cmin`, `st`, `bg`, `be`, `td`, `qc`, area and time step) are not. Parameters that span
#' orders of magnitude, such as recharge and groundwater constants, are marked for
#' log-scale search.
#'
#' @param config A configuration list.
#' @param overrides Optional named list of `c(lower, upper)` pairs by configuration path,
#'   such as `list(fc = c(0.8, 1.2))`, replacing or adding bounds.
#' @param exclude Optional configuration paths to leave out, holding them at their values.
#' @return A data frame with `path`, `lower`, `upper`, `scale` (`linear` or `log`) and `note`.
#' @examples
#' calibration_bounds(pdm_presets("standard"))
#' @export
calibration_bounds <- function(config, overrides = NULL, exclude = NULL) {
  pdm_from_config(config)
  table <- .bounds_table()
  slots <- c(distribution = "distribution", recharge = "recharge", surface = "route",
             groundwater = "route")
  rows <- list(table[table$slot == "model", ])
  for (name in names(slots)) {
    type <- config[[name]]$type %||% switch(name, distribution = "pareto",
                                            recharge = "standard", surface = "cascade",
                                            groundwater = "cubic")
    hit <- table[table$slot == slots[[name]] & table$type == type, ]
    if (nrow(hit)) {
      hit$parameter <- paste(name, hit$parameter, sep = ".")
      rows <- c(rows, list(hit))
    }
  }
  out <- do.call(rbind, rows)
  out <- data.frame(path = out$parameter, lower = out$lower, upper = out$upper,
                    scale = out$scale, note = out$note)
  if (!is.null(overrides)) out <- .apply_bound_overrides(out, overrides, config)
  if (!is.null(exclude)) out <- out[!out$path %in% exclude, ]
  .check(nrow(out) > 0, "No parameters left to calibrate")
  rownames(out) <- NULL
  out
}

.apply_bound_overrides <- function(out, overrides, config) {
  pair <- function(x) is.numeric(x) && length(x) == 2L && x[1] < x[2]
  .check(is.list(overrides) && !is.null(names(overrides)) &&
           all(vapply(overrides, pair, logical(1))),
         "overrides must be named c(lower, upper) pairs")
  for (p in names(overrides)) {
    .path_get(config, p)
    if (p %in% out$path) {
      out[out$path == p, c("lower", "upper")] <- as.list(overrides[[p]])
    } else {
      out <- rbind(out, data.frame(path = p, lower = overrides[[p]][1],
                                   upper = overrides[[p]][2], scale = "linear",
                                   note = "Added by override"))
    }
  }
  out
}

#' Model structures to compare
#'
#' A named list of configurations for [compare_structures()], each one change from a base
#' structure, so that each comparison answers one question: does a different soil store,
#' recharge rule or groundwater store fit this catchment better?
#'
#' | Name | Change from the base |
#' |---|---|
#' | `standard` | None: Pareto store, standard recharge, cascade surface, cubic groundwater |
#' | `rectangular`, `triangular`, `exponential`, `lognormal` | Soil capacity distribution |
#' | `split` | Split recharge |
#' | `demand` | Demand recharge |
#' | `exponential_groundwater` | Exponential groundwater store |
#'
#' Pick a subset by name, or add your own configurations to the list; any combination is
#' allowed if you have a reason to test it.
#'
#' @param names Structures to include; by default all eight.
#' @param base Configuration whose area, time step, delay, rainfall factor and other
#'   settings carry over. Its components are not used: every structure starts from the
#'   standard PDM's components, so each name means the same structure whatever the base.
#' @return A named list of configuration lists.
#' @examples
#' names(structure_set())
#' structure_set(c("standard", "lognormal"))$lognormal$distribution
#' @export
structure_set <- function(names = NULL, base = pdm_presets("standard")) {
  variants <- list(
    standard = list(),
    rectangular = list(distribution = list(type = "rectangular", cmin = 0, cmax = 200)),
    triangular = list(distribution = list(type = "triangular", cmin = 0, cmax = 250)),
    exponential = list(distribution = list(type = "exponential", mean = 100)),
    lognormal = list(distribution = list(type = "lognormal", meanlog = 4.1, sdlog = 0.8)),
    split = list(recharge = list(type = "split", alpha = 0.7)),
    demand = list(recharge = list(type = "demand", alpha = 0.5, beta = 1, qsat = 0.5)),
    exponential_groundwater = list(groundwater = list(type = "exponential", a = 0.05,
                                                      gamma = -5))
  )
  if (is.null(names)) names <- names(variants)
  .check(is.character(names) && length(names) > 0 && all(names %in% names(variants)),
         paste("Structures must be among", paste(names(variants), collapse = ", ")))
  standard <- pdm_presets("standard")
  for (slot in c("distribution", "recharge", "surface", "groundwater")) {
    base[[slot]] <- standard[[slot]]
  }
  out <- lapply(variants[names], function(change) {
    config <- base
    for (slot in names(change)) config[[slot]] <- change[[slot]]
    config
  })
  for (n in names(out)) pdm_from_config(out[[n]])
  out
}
