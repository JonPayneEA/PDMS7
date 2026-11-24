# ============================================================ #
# Tool:         site_settings
# Description:  Reads and checks the settings for calibrating one site, the YAML file the
#               starter script inst/scripts/calibrate_site.R runs from, so a newcomer can load
#               it into R, look at it, change it and run the script on it
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-24
# Modified:     2026-11-24 - First version
# Tier:         1
# Inputs:       A settings file like inst/examples/site.yml, or settings already read
# Outputs:      A checked list of class pdm_site_settings, every path made absolute
# Dependencies: yaml
# ============================================================ #

#' Read the settings for calibrating one site
#'
#' Reads a settings file like the one in `system.file("examples", "site.yml", package =
#' "pdmS7")`, checks it, fills in the defaults and makes every path absolute. Load the
#' settings into R, look at them, change any of them, then run the starter script, which
#' uses a `settings` object it finds in the session:
#'
#' ```r
#' settings <- read_site_settings("my_site.yml")
#' settings                       # what will be run
#' settings$effort <- "quick"     # change anything, as in the file
#' source(system.file("scripts", "calibrate_site.R", package = "pdmS7"))
#' ```
#'
#' Relative paths are taken from the folder the settings file is in; data files from the
#' `data: folder` under it. Every problem found is reported at once, not one at a time.
#'
#' @param x The path to a settings file, or settings already read (checked again, so changes
#'   made in R are checked too).
#' @return A list of class `pdm_site_settings`: `name`, `gauge`, `area_km2`, `step_hours`,
#'   `flow`, `pet`, `rain` (a named list; the first calibrates), `snow`, `temperature`,
#'   `calibration`, `validation`, `output`, `stop_after_checks`, `effort`,
#'   `rainfall_factor` (`NULL` when fixed, else the range to search), `thresholds` (a data
#'   frame or `NULL`), `highest_gauged_m3s`, `pdm_for_pcs_inp`, `previous_project`,
#'   `rain_gauges` (a named list of single-gauge files, or `NULL`), `rain_error` (the typical
#'   error in a storm's rain, as a fraction), `regional_results` (the CAMELS-GB bulk run's
#'   results file, or `NULL`), `bayes_generations` (the length of the Bayesian calibration
#'   that effort thorough runs), `owner`, `steward`, and `file` and `home`, where the settings
#'   came from.
#' @export
#' @examples
#' settings <- read_site_settings(system.file("examples", "site.yml", package = "pdmS7"))
#' settings$area_km2
read_site_settings <- function(x) {
  if (inherits(x, "pdm_site_settings")) {
    return(.check_site_settings(unclass(x), x$file, x$home))
  }
  .check(is.character(x) && length(x) == 1 && file.exists(x),
         "x must be the path to a settings file that exists")
  raw <- yaml::read_yaml(x)
  .check(is.list(raw), "The settings file holds no settings")
  flat <- list(
    name = raw$site$name, gauge = raw$site$gauge, area_km2 = raw$site$area_km2,
    step_hours = raw$data$step_hours, folder = raw$data$folder, flow = raw$data$flow,
    pet = raw$data$pet, rain = raw$data$rain, snow = raw$snow, temperature = raw$temperature,
    calibration = raw$calibration, validation = raw$validation, output = raw$output,
    stop_after_checks = raw$stop_after_checks, effort = raw$effort,
    rainfall_factor = raw$rainfall_factor, thresholds = raw$thresholds,
    highest_gauged_m3s = raw$highest_gauged_m3s, pdm_for_pcs_inp = raw$pdm_for_pcs_inp,
    previous_project = raw$previous_project, owner = raw$owner, steward = raw$steward,
    rain_gauges = raw$data$rain_gauges, rain_error = raw$rain_error,
    regional_results = raw$regional_results, bayes_generations = raw$bayes_generations)
  path <- normalizePath(x)
  .check_site_settings(flat, path, dirname(path))
}

# Checks the settings, fills the defaults and resolves the paths. Collects every problem
# before stopping, so a newcomer fixes the file once.
.check_site_settings <- function(s, file, home) {
  problems <- character(0)
  fail <- function(...) problems <<- c(problems, paste0(...))
  or <- function(x, y) if (is.null(x) || (length(x) == 1 && is.na(x))) y else x
  absolute <- function(p) grepl("^(/|~|[A-Za-z]:|\\\\)", p)
  from <- function(p, base) if (absolute(p)) path.expand(p) else file.path(base, p)
  data_dir <- from(or(s$folder, "."), home)
  existing <- function(p, what, base = data_dir) {
    if (is.null(p) || !nzchar(p)) {
      fail("Give ", what, ".")
      return(NULL)
    }
    full <- from(p, base)
    if (!file.exists(full)) fail("No ", what, " at ", full, ".")
    full
  }
  window <- function(w, what) {
    t <- if (length(w) == 2) {
      vapply(as.character(w), function(x) {
        as.numeric(as.POSIXct(x, tz = "UTC", optional = TRUE))
      }, numeric(1))
    }
    if (length(t) != 2 || anyNA(t) || t[1] >= t[2]) {
      fail(what, " must be two date-times, start then end, such as [\"2010-10-01\", ",
           "\"2019-09-30 23:45\"].")
      return(NULL)
    }
    as.character(w)
  }

  s$name <- as.character(or(s$name, "My site"))
  s$gauge <- as.character(or(s$gauge, ""))
  s$area_km2 <- suppressWarnings(as.numeric(or(s$area_km2, NA)))
  if (!is.finite(s$area_km2) || s$area_km2 <= 0) {
    fail("site: area_km2 must be the catchment area in km2, a number above 0.")
  }
  s$step_hours <- suppressWarnings(as.numeric(or(s$step_hours, 0.25)))
  if (!is.finite(s$step_hours) || s$step_hours <= 0 || s$step_hours > 24) {
    fail("data: step_hours must be the time step in hours: 0.25 for 15-minute data, 1 hourly.")
  }
  s$flow <- existing(s$flow, "a flow file (data: flow)")
  s$pet <- existing(s$pet, "a potential evaporation file (data: pet)")
  rain <- s$rain
  if (!is.null(rain) && !is.list(rain)) rain <- list(rain = rain)
  if (!length(rain)) {
    fail("Give a rain file (data: rain).")
  } else {
    labels <- names(rain)
    if (is.null(labels) || any(!nzchar(labels))) {
      fail("Name each rain file when giving several, such as thiessen: rain_thiessen.csv.")
      labels <- paste0("rain", seq_along(rain))
    }
    rain <- stats::setNames(lapply(seq_along(rain), function(i) {
      existing(rain[[i]], sprintf("the rain file '%s' (data: rain)", labels[i]))
    }), labels)
  }
  s$rain <- rain
  gauges <- s$rain_gauges
  if (length(gauges)) {
    if (!is.list(gauges) || is.null(names(gauges)) || any(!nzchar(names(gauges)))) {
      fail("Name each rain gauge file, such as rain_gauges: {Gauge A: gauge_a.csv}.")
    } else {
      gauges <- stats::setNames(lapply(names(gauges), function(n) {
        existing(gauges[[n]], sprintf("the rain gauge file '%s' (data: rain_gauges)", n))
      }), names(gauges))
    }
  }
  s$rain_gauges <- if (length(gauges)) gauges
  s$rain_error <- suppressWarnings(as.numeric(or(s$rain_error, 0.15)))
  if (length(s$rain_error) != 1 || !is.finite(s$rain_error) || s$rain_error <= 0 ||
      s$rain_error >= 1) {
    fail("rain_error must be the typical error in a storm's rain, as a fraction: 0.15 for 15%.")
  }
  s$snow <- isTRUE(s$snow)
  s$temperature <- if (s$snow) existing(s$temperature, "a temperature file for snow (temperature)")
  s$calibration <- window(s$calibration, "calibration")
  s$validation <- window(s$validation, "validation")
  if (!is.null(s$calibration) && !is.null(s$validation) &&
      as.POSIXct(s$validation[1], tz = "UTC") <= as.POSIXct(s$calibration[2], tz = "UTC")) {
    fail("validation must start after calibration ends: the model is checked on years it ",
         "has not seen.")
  }
  s$output <- from(as.character(or(s$output, "output")), home)
  s$stop_after_checks <- !identical(s$stop_after_checks, FALSE)
  s$effort <- as.character(or(s$effort, "standard"))
  if (!s$effort %in% c("quick", "standard", "thorough")) {
    fail("effort must be quick, standard or thorough, not '", s$effort, "'.")
  }
  fc <- s$rainfall_factor
  s$rainfall_factor <- if (is.null(fc) || identical(fc, "fixed") || identical(fc, 1) ||
                           identical(fc, 1L)) {
    NULL
  } else if (is.numeric(fc) && length(fc) == 2 && all(is.finite(fc)) && fc[1] > 0 &&
             fc[1] < fc[2]) {
    as.numeric(fc)
  } else {
    fail("rainfall_factor must be fixed, or a range such as [0.9, 1.3].")
    NULL
  }
  th <- s$thresholds
  if (is.list(th) && length(th) && !is.data.frame(th)) {
    ok <- vapply(th, function(t) !is.null(t$name) && is.numeric(t$value), logical(1))
    if (!all(ok)) fail("Each threshold needs a name and a value, such as {name: Alert, value: 12}.")
    th <- if (all(ok)) {
      data.frame(name = vapply(th, function(t) as.character(t$name), ""),
                 value = vapply(th, function(t) as.numeric(t$value), 0), unit = "flow")
    }
  }
  s$thresholds <- if (is.data.frame(th) && nrow(th)) th
  s$highest_gauged_m3s <- if (is.numeric(s$highest_gauged_m3s)) s$highest_gauged_m3s
  if (!is.null(s$pdm_for_pcs_inp)) {
    s$pdm_for_pcs_inp <- existing(s$pdm_for_pcs_inp, "a PDM for PCs file (pdm_for_pcs_inp)", home)
  }
  if (!is.null(s$previous_project)) {
    s$previous_project <- from(s$previous_project, home)
    if (!dir.exists(s$previous_project)) {
      fail("No project folder at ", s$previous_project, " (previous_project).")
    }
  }
  s$bayes_generations <- suppressWarnings(as.integer(or(s$bayes_generations, 2000L)))
  if (length(s$bayes_generations) != 1 || is.na(s$bayes_generations) ||
      s$bayes_generations < 100L) {
    fail("bayes_generations must be a whole number of 100 or more, such as 2000.")
  }
  if (!is.null(s$regional_results)) {
    s$regional_results <- existing(s$regional_results,
                                   "the bulk run's results file (regional_results)", home)
  }
  s$owner <- as.character(or(s$owner, "Not recorded"))
  s$steward <- as.character(or(s$steward, "Not recorded"))
  s$folder <- NULL
  s$file <- file
  s$home <- home
  if (length(problems)) {
    stop("The settings in ", basename(file), " need fixing:\n",
         paste0("- ", problems, collapse = "\n"), call. = FALSE)
  }
  structure(s, class = "pdm_site_settings")
}

#' @export
print.pdm_site_settings <- function(x, ...) {
  window <- function(w) paste(w, collapse = " to ")
  cat("Settings for calibrating ", x$name, if (nzchar(x$gauge)) paste0(" (", x$gauge, ")"),
      ", from ", basename(x$file), "\n", sep = "")
  cat("  Area:         ", x$area_km2, " km2; data every ", x$step_hours, " hours\n", sep = "")
  cat("  Flow:         ", x$flow, "\n", sep = "")
  cat("  Evaporation:  ", x$pet, "\n", sep = "")
  for (n in names(x$rain)) {
    cat(sprintf("  Rain %-9s %s%s\n", paste0(n, ":"), x$rain[[n]],
                if (n == names(x$rain)[1] && length(x$rain) > 1) " (calibrates)" else ""))
  }
  if (length(x$rain_gauges)) {
    cat("  Rain gauges:  ", paste(names(x$rain_gauges), collapse = ", "), "\n", sep = "")
  }
  if (x$snow) cat("  Snow:          PACK, temperature from ", x$temperature, "\n", sep = "")
  cat("  Calibration:  ", window(x$calibration), "\n", sep = "")
  cat("  Validation:   ", window(x$validation), "\n", sep = "")
  cat("  Effort:       ", x$effort, "\n", sep = "")
  cat("  Rain factor:  ", if (is.null(x$rainfall_factor)) "fixed at 1" else
        paste("searched from", window(x$rainfall_factor)), "\n", sep = "")
  cat("  Rain error:   storms ", round(100 * x$rain_error), "% out, typically\n", sep = "")
  if (!is.null(x$regional_results)) {
    cat("  Regional:     ", x$regional_results, "\n", sep = "")
  }
  cat("  Output:       ", x$output, "\n", sep = "")
  cat(if (x$stop_after_checks) {
    "  Stops after checking the data (stop_after_checks is TRUE).\n"
  } else {
    "  Checks the data, then calibrates.\n"
  })
  invisible(x)
}
