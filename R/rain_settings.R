# ============================================================ #
# Tool:         rain_settings
# Description:  Reads and checks the settings for comparing catchment rainfall, the YAML file
#               the script inst/scripts/compare_rain.R runs from, so the script itself need
#               not be edited, and the settings of a run can be kept beside its outputs
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-28
# Modified:     2026-11-28 - First version
# Tier:         1
# Inputs:       A settings file like inst/examples/rain.yml, or settings already read
# Outputs:      A checked, flat list of class pdm_rain_settings, one element a setting
# Dependencies: yaml
# ============================================================ #

# The settings compare_rain.R reads, with their defaults, in the order the template gives
# them. The template, inst/examples/rain.yml, holds the same defaults; a test keeps the two
# in step.
.rain_defaults <- function() {
  list(
    area_km2 = NA_real_, step_hours = 0.25, catchment_boundary = "catchment.shp",
    grid_spacing_m = 500,
    data_folder = "data", output_folder = "rain_comparison", flow_file = "flow.csv",
    pet_file = "pet.csv",
    period_from = "2015-10-01", period_to = "2024-10-01", year_start_month = 1,
    gauge_source = "hydrology_api", search_radius_km = NULL, gauge_ids = NULL,
    gauges = data.frame(name = c("gauge_A", "gauge_B", "gauge_C"),
                        file = c("gauge_a.csv", "gauge_b.csv", "gauge_c.csv"),
                        x = NA_real_, y = NA_real_),
    thiessen_weights = NULL,
    rain_methods = .rain_methods_known,
    lta_rain_file = NULL, lta_correction = "none", correction_from = "2010-10-01",
    correction_to = "2024-10-01",
    radar_folder = NULL, radar_pattern = "^[0-9]{14}.*\\.nc$", radar_scan_only = FALSE,
    radar_processed_folder = NULL, radar_polygon_id = NULL,
    other_rain_files = NULL,
    stage_file = NULL, flow_station_wiski = NULL, top_stage_m = NULL,
    bankfull_stage_m = NULL, stage_uncertainty_m = 0.005, gaugings_file = NULL,
    gauging_station_id = NULL, ratings_file = NULL, rating_station_id = NULL,
    dry_hours = 48, dry_rain_mm = 0.5,
    candidate_rating = "auto", candidate_boot = 500, gauging_uncertainty = NULL,
    gauging_group = NULL,
    event_max_response_h = 150, event_independent = TRUE, missed_share = 0.25,
    missed_min_mm = 2)
}

.rain_methods_known <- c("thiessen", "equal", "equal_all", "idw", "multiquadric",
                         "multiquadric_lta", "kriging", "ked_lta", "h19", "h19_bias",
                         "h19_season", "multiquadric_h19", "ked_h19")

# The folders, made absolute from the settings file's folder; file names stay in data_folder.
.rain_folders <- c("data_folder", "output_folder", "radar_folder", "radar_processed_folder")

#' Read the settings for comparing catchment rainfall
#'
#' Reads a settings file like the one in `system.file("examples", "rain.yml", package =
#' "pdmS7")`, checks it and fills in the defaults, for the script `compare_rain.R`. The
#' script uses a `rain_settings` object it finds in the session, or reads `rain.yml` in the
#' working directory:
#'
#' ```r
#' file.copy(system.file("examples", "rain.yml", package = "pdmS7"), "rain.yml")
#' # fill in rain.yml, then
#' rain_settings <- read_rain_settings("rain.yml")
#' rain_settings                          # what will be run
#' rain_settings$gauge_ids <- "254336TP"  # change anything, as in the file
#' source(system.file("scripts", "compare_rain.R", package = "pdmS7"))
#' ```
#'
#' Each key in the file is the name of a setting in the script. The file groups them for
#' reading (`catchment`, `files`, `period`, `rain_gauges` and so on), but a key may sit in
#' any group or at the top level; a key the script does not know is an error naming it, so a
#' misspelt key is never silently ignored. A key left out takes its default.
#'
#' The folders (`data_folder`, `output_folder`, `radar_folder`, `radar_processed_folder`) are
#' made absolute from the folder the settings file is in. File names stay as given: the
#' script finds them in `data_folder`. Every problem found is reported at once.
#'
#' @param x The path to a settings file, or settings already read (checked again, so
#'   changes made in R are checked too).
#' @return A flat list of class `pdm_rain_settings`, one element a setting, named as the
#'   script names them. A setting left empty is `NULL`; `gauges` is a data frame with
#'   columns `name`, `file`, `x` and `y`; `thiessen_weights` is a named numeric vector and
#'   `other_rain_files` a named character vector. The attributes `file` and `mtime` say
#'   where the settings came from and when that file was last changed.
#' @export
#' @examples
#' s <- read_rain_settings(system.file("examples", "rain.yml", package = "pdmS7"))
#' s$rain_methods
#' s$period_from
read_rain_settings <- function(x) {
  if (inherits(x, "pdm_rain_settings")) {
    file <- attr(x, "file")
    return(.check_rain_settings(unclass(x), file, attr(x, "mtime"),
                                home = if (!is.null(file)) dirname(file)))
  }
  .check(is.character(x) && length(x) == 1 && file.exists(x),
         "x must be the path to a settings file that exists")
  # YAML 1.1 reads y and n as true and false, so the key y of a gauge's position would be
  # lost: they stay text, and true, false, yes and no stay TRUE and FALSE.
  keep <- function(word, flag) function(v) if (v %in% c(word, toupper(word))) v else flag
  raw <- yaml::read_yaml(x, handlers = list("bool#yes" = keep("y", TRUE),
                                            "bool#no" = keep("n", FALSE)))
  if (is.null(raw)) raw <- list()
  .check(is.list(raw) && (!length(raw) || !is.null(names(raw))),
         "The settings file must hold keys and values, as in rain.yml")
  known <- names(.rain_defaults())
  flat <- list()
  unknown <- character(0)
  repeated <- character(0)
  take <- function(key, value, where) {
    if (!key %in% known) {
      unknown <<- c(unknown, paste0(where, key))
    } else if (key %in% names(flat)) {
      repeated <<- c(repeated, key)
    } else {
      flat[key] <<- list(value)
    }
  }
  for (key in names(raw)) {
    value <- raw[[key]]
    if (key %in% known) {
      take(key, value, "")
    } else if (is.list(value) && !is.null(names(value)) && all(nzchar(names(value)))) {
      for (k in names(value)) take(k, value[[k]], paste0(key, ": "))
    } else {
      unknown <- c(unknown, key)
    }
  }
  .check(!length(unknown),
         paste0("Settings the script does not know: ", paste(unknown, collapse = ", "),
                ". Check the spelling against rain.yml."))
  .check(!length(repeated),
         paste0("Settings given twice: ", paste(unique(repeated), collapse = ", "), "."))
  path <- normalizePath(x)
  .check_rain_settings(flat, path, file.mtime(path), home = dirname(path))
}

# Fills the defaults, converts YAML's lists to the script's vectors and data frames, makes the
# folders absolute from home (when it is given) and checks every value,
# collecting the problems before stopping.
.check_rain_settings <- function(s, file, mtime, home) {
  problems <- character(0)
  fail <- function(...) problems <<- c(problems, paste0(...))
  defaults <- .rain_defaults()
  for (key in setdiff(names(defaults), names(s))) s[key] <- list(defaults[[key]])
  s <- s[c(names(defaults), setdiff(names(s), names(defaults)))]
  extra <- setdiff(names(s), names(defaults))
  if (length(extra)) fail("Settings the script does not know: ", paste(extra, collapse = ", "))
  empty <- function(v) is.null(v) || (is.list(v) && !length(v) && !is.data.frame(v))

  # A single value: a number, a word or TRUE/FALSE, or NULL where the setting may be empty.
  one <- function(key, type, nullable = FALSE, check = NULL, advice = "") {
    v <- s[[key]]
    if (empty(v)) {
      if (!nullable) fail(key, " must be given: ", advice, ".")
      s[key] <<- list(NULL)
      return(invisible())
    }
    ok <- length(v) == 1 && !is.list(v)
    if (ok) {
      v <- switch(type,
                  number = if (is.numeric(v) || (is.logical(v) && is.na(v))) as.numeric(v),
                  text = if (is.character(v) || is.numeric(v)) as.character(v),
                  flag = if (is.logical(v) && !is.na(v)) v)
      ok <- !is.null(v) && (is.null(check) || isTRUE(check(v)))
    }
    if (!ok) {
      fail(key, " must be ", advice, ".")
    } else {
      s[[key]] <<- v
    }
  }
  # Text, several values allowed: a YAML list becomes a character vector.
  several <- function(key, nullable = TRUE) {
    v <- s[[key]]
    if (empty(v)) {
      s[key] <<- list(NULL)
      return(invisible())
    }
    # An ID written without quotes reads as a number: kept as its digits, never 1e+05.
    word <- function(e) {
      if (is.numeric(e) && length(e) == 1 && !is.na(e)) {
        format(e, scientific = FALSE, trim = TRUE)
      } else if (is.character(e) && length(e) == 1 && !is.na(e)) {
        e
      } else {
        NA_character_
      }
    }
    v <- vapply(as.list(v), word, character(1), USE.NAMES = FALSE)
    if (anyNA(v)) {
      fail(key, " must be a list of names, such as [\"254336TP\", \"SS92F014\"].")
    } else {
      s[[key]] <<- v
    }
  }
  # A map, name: value, as a named vector.
  named <- function(key, as, example) {
    v <- s[[key]]
    if (empty(v)) {
      s[key] <<- list(NULL)
      return(invisible())
    }
    n <- names(v)
    flat <- if (is.list(v)) unlist(v) else v
    if (is.null(n) || any(!nzchar(n)) || length(flat) != length(n) || anyNA(flat)) {
      fail(key, " must be name: value pairs, such as ", example, ".")
      return(invisible())
    }
    flat <- if (as == "number") suppressWarnings(as.numeric(flat)) else as.character(flat)
    if (anyNA(flat)) {
      fail(key, " must give a number for each name, such as ", example, ".")
    } else {
      s[[key]] <<- stats::setNames(flat, n)
    }
  }
  date <- function(key) {
    one(key, "text", advice = "a date, such as \"2015-10-01\"")
    v <- s[[key]]
    if (is.character(v) && is.na(as.POSIXct(v, tz = "UTC", optional = TRUE))) {
      fail(key, " must be a date, such as \"2015-10-01\", not ", v, ".")
    }
  }
  positive <- function(x) is.finite(x) && x > 0

  # The area may be left blank: the script stops on it with the advice to fill it in, so the
  # template can be read as it stands.
  one("area_km2", "number", nullable = TRUE,
      check = function(x) is.na(x) || positive(x),
      advice = "the catchment area in km2, a number above 0")
  if (is.null(s$area_km2)) s$area_km2 <- NA_real_
  one("step_hours", "number", check = function(x) positive(x) && x <= 24,
      advice = "the time step in hours: 0.25 for 15-minute data, 1 hourly")
  one("catchment_boundary", "text", nullable = TRUE, advice = "a file name in data_folder")
  one("grid_spacing_m", "number", check = positive, advice = "a spacing in metres above 0")
  for (key in c("data_folder", "output_folder")) one(key, "text", advice = "a folder")
  for (key in c("flow_file", "pet_file")) one(key, "text", advice = "a file name in data_folder")
  date("period_from")
  date("period_to")
  if (is.character(s$period_from) && is.character(s$period_to)) {
    a <- as.POSIXct(s$period_from, tz = "UTC", optional = TRUE)
    b <- as.POSIXct(s$period_to, tz = "UTC", optional = TRUE)
    if (!is.na(a) && !is.na(b) && a >= b) fail("period_from must come before period_to.")
  }
  one("year_start_month", "number", check = function(x) x %in% 1:12,
      advice = "a month from 1 to 12: 1 for calendar years, 10 for water years")
  one("gauge_source", "text", check = function(x) x %in% c("hydrology_api", "files"),
      advice = "hydrology_api or files")
  one("search_radius_km", "number", nullable = TRUE, check = positive,
      advice = "a radius in km above 0, or null")
  several("gauge_ids")
  g <- s$gauges
  if (empty(g)) {
    s["gauges"] <- list(NULL)
  } else if (!is.data.frame(g)) {
    rows <- if (is.list(g) && is.null(names(g))) g else list()
    cell <- function(r, k) {
      v <- r[[k]]
      if (length(v) == 1 && is.numeric(v)) as.numeric(v) else NA_real_
    }
    ok <- length(rows) && all(vapply(rows, function(r) {
      is.list(r) && all(c("name", "file") %in% names(r)) &&
        all(names(r) %in% c("name", "file", "x", "y"))
    }, logical(1)))
    if (!ok) {
      fail("gauges must be a list of gauges, each {name: ..., file: ..., x: ..., y: ...}.")
    } else {
      s$gauges <- data.frame(
        name = vapply(rows, function(r) as.character(r$name), character(1)),
        file = vapply(rows, function(r) as.character(r$file), character(1)),
        x = vapply(rows, cell, numeric(1), k = "x"),
        y = vapply(rows, cell, numeric(1), k = "y"))
    }
  }
  named("thiessen_weights", "number", "{\"254336TP\": 0.264, \"SS92F014\": 0.737}")
  several("rain_methods")
  bad <- setdiff(s$rain_methods, .rain_methods_known)
  if (length(bad)) {
    fail("rain_methods holds ", paste(bad, collapse = ", "), ", which the script does not ",
         "build; the averages it builds are ", paste(.rain_methods_known, collapse = ", "), ".")
  }
  one("lta_rain_file", "text", nullable = TRUE, advice = "a file name in data_folder, or null")
  one("lta_correction", "text", check = function(x) x %in% c("none", "relative", "absolute"),
      advice = "none, relative or absolute")
  date("correction_from")
  date("correction_to")
  for (key in c("radar_folder", "radar_processed_folder")) {
    one(key, "text", nullable = TRUE, advice = "a folder, or null")
  }
  one("radar_pattern", "text", advice = "a regular expression for the H19 file names")
  one("radar_scan_only", "flag", advice = "true or false")
  one("radar_polygon_id", "text", nullable = TRUE, advice = "the polygon's ID in Hyrad, or null")
  named("other_rain_files", "text", "{radar: rain_h19.csv}")
  for (key in c("stage_file", "flow_station_wiski", "gauging_station_id",
                "rating_station_id", "gauging_group")) {
    one(key, "text", nullable = TRUE, advice = "a name, or null")
  }
  # The gaugings and the ratings may be data frames, set in R after reading the file.
  for (key in c("gaugings_file", "ratings_file")) {
    if (!is.data.frame(s[[key]])) {
      one(key, "text", nullable = TRUE,
          advice = "a file name in data_folder, a data frame, or null")
    }
  }
  for (key in c("top_stage_m", "bankfull_stage_m")) {
    one(key, "number", nullable = TRUE, check = is.finite, advice = "a stage in m, or null")
  }
  one("stage_uncertainty_m", "number", check = function(x) is.finite(x) && x >= 0,
      advice = "a stage error in m, 0 or more")
  one("dry_hours", "number", check = positive, advice = "a number of hours above 0")
  one("dry_rain_mm", "number", check = function(x) is.finite(x) && x >= 0,
      advice = "a depth in mm, 0 or more")
  one("candidate_rating", "text", check = function(x) x %in% c("auto", "always", "never"),
      advice = "auto, always or never")
  one("candidate_boot", "number", check = function(x) x == 0 || (x >= 100 && x == round(x)),
      advice = "a whole number of draws, 100 or more, or 0 for no band")
  one("gauging_uncertainty", "number", nullable = TRUE,
      check = function(x) is.finite(x) && x > 0 && x <= 0.5,
      advice = "a fraction above 0 and up to 0.5, such as 0.03, or null")
  one("event_max_response_h", "number", check = positive, advice = "a number of hours above 0")
  one("event_independent", "flag", advice = "true or false")
  one("missed_share", "number", check = function(x) is.finite(x) && x > 0 && x < 1,
      advice = "a fraction between 0 and 1")
  one("missed_min_mm", "number", check = function(x) is.finite(x) && x >= 0,
      advice = "a depth in mm, 0 or more")

  if (length(problems)) {
    stop("The rain settings", if (!is.null(file)) paste0(" in ", file), " need fixing:\n",
         paste0("  - ", problems, collapse = "\n"), call. = FALSE)
  }
  if (!is.null(home)) {
    absolute <- function(p) grepl("^(/|~|[A-Za-z]:|\\\\)", p)
    for (key in .rain_folders) {
      p <- s[[key]]
      if (!is.null(p) && !absolute(p)) s[[key]] <- file.path(home, p)
      if (!is.null(s[[key]])) s[[key]] <- path.expand(s[[key]])
    }
  }
  structure(s, class = "pdm_rain_settings", file = file, mtime = mtime)
}

#' @export
print.pdm_rain_settings <- function(x, ...) {
  v <- unclass(x)
  width <- max(nchar(names(v)))
  show <- function(key) {
    e <- v[[key]]
    if (is.null(e)) return("(none)")
    if (is.data.frame(e)) {
      if (key == "gauges") return(paste0(nrow(e), " gauges: ", paste(e$name, collapse = ", ")))
      return(sprintf("a data frame of %d rows", nrow(e)))
    }
    txt <- if (!is.null(names(e))) paste0(names(e), " = ", e) else as.character(e)
    paste(strwrap(paste(txt, collapse = ", "), width = max(30, getOption("width") - width - 4),
                  exdent = width + 4), collapse = "\n")
  }
  cat("Rain settings", if (!is.null(attr(x, "file"))) paste0(" from ", attr(x, "file")),
      "\n", sep = "")
  for (key in names(v)) cat("  ", formatC(key, width = -width), "  ", show(key), "\n", sep = "")
  invisible(x)
}
