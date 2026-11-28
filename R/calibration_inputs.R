# ============================================================ #
# Tool:         calibration_inputs
# Description:  The hand-off from the rain comparison to calibration: compare_rain.R writes
#               calibration_inputs.yml (the rain series recommended, the rain error to start
#               from, the period judged and the warnings a calibration should carry), and
#               read_site_settings() reads it when site.yml names the comparison's folder
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-28
# Tier:         1
# Inputs:       The recommended series and their files; or a calibration_inputs.yml
# Outputs:      calibration_inputs.yml; or a pdm_calibration_inputs list, paths made absolute
# Dependencies: yaml
# ============================================================ #

#' Write the rain comparison's hand-off to calibration
#'
#' Writes `calibration_inputs.yml`, which `read_site_settings()` reads when a site's settings
#' name the comparison's folder (`rain_comparison:`). `compare_rain.R` calls it at the end of
#' every run; it is exported so the file can be written from other work too.
#'
#' @param path The file to write, normally `calibration_inputs.yml` in the comparison's
#'   output folder.
#' @param rain The recommended rain series, in order: a named character vector of files,
#'   relative to the folder `path` is in. The first is the one to calibrate on.
#' @param period The period the series were judged over: two dates, from (inclusive) and to
#'   (exclusive).
#' @param step_hours The series' time step, hours.
#' @param rain_error The typical error in a storm's rain to start from, as a fraction, or
#'   `NA` where none was worked out.
#' @param warnings What a calibration on these series should know, one sentence each.
#' @param made_by What wrote the file, recorded in it.
#' @param mask `NULL`, or periods a calibration on these series should leave out: a data frame
#'   of `from`, `to` (times, `to` inclusive) and `reason`, such as the events the first series
#'   missed and the flow off the applied rating.
#' @param rating_band `NULL`, or the rating's band for the peak tolerance: a data frame of `q`
#'   (m3/s), `lower` (a share, 0 or below) and `upper` (0 or above).
#' @param rating_band_source Where the band came from, recorded beside it.
#' @return `path`, invisibly.
#' @export
#' @examples
#' f <- file.path(tempdir(), "calibration_inputs.yml")
#' write_calibration_inputs(f, c(thiessen = "catchment_rain/thiessen.csv"),
#'                          period = c("2015-10-01", "2024-10-01"), step_hours = 0.25,
#'                          rain_error = 0.12)
#' cat(readLines(f), sep = "\n")
write_calibration_inputs <- function(path, rain, period, step_hours, rain_error = NA_real_,
                                     warnings = character(0), made_by = "pdmS7", mask = NULL,
                                     rating_band = NULL, rating_band_source = NULL) {
  .check(is.character(path) && length(path) == 1 && nzchar(path), "path must be one file")
  .check(is.character(rain) && length(rain) >= 1 && !is.null(names(rain)) &&
           all(nzchar(names(rain))) && !anyNA(rain) && !anyDuplicated(names(rain)),
         "rain must be a named character vector of files, one name a series")
  .check(length(period) == 2 && all(!is.na(as.POSIXct(as.character(period), tz = "UTC",
                                                       optional = TRUE))),
         "period must be two dates, from then to")
  .check(.scalar(step_hours, 0, strict = TRUE), "step_hours must be a number above 0")
  .check(length(rain_error) == 1 && (is.na(rain_error) || .scalar(rain_error, 0, 1)),
         "rain_error must be a fraction between 0 and 1, or NA")
  .check(is.character(warnings), "warnings must be text")
  .check(is.null(mask) || (is.data.frame(mask) && all(c("from", "to", "reason") %in% names(mask))),
         "mask must be a data frame of from, to and reason")
  .check(is.null(rating_band) ||
           (is.data.frame(rating_band) && all(c("q", "lower", "upper") %in% names(rating_band))),
         "rating_band must be a data frame of q, lower and upper")
  stamp <- function(x) {
    if (inherits(x, "POSIXct")) format(x, "%Y-%m-%d %H:%M", tz = "UTC") else as.character(x)
  }
  out <- list(
    made_by = as.character(made_by),
    made_on = format(Sys.Date()),
    period = as.character(period),
    step_hours = step_hours,
    rain = as.list(rain),
    rain_error = if (is.na(rain_error)) NULL else rain_error,
    warnings = as.list(unname(warnings)))
  if (!is.null(mask) && nrow(mask)) {
    out$mask <- lapply(seq_len(nrow(mask)), function(i) {
      list(from = stamp(mask$from[i]), to = stamp(mask$to[i]),
           reason = as.character(mask$reason[i]))
    })
  }
  if (!is.null(rating_band) && nrow(rating_band)) {
    out$rating_band <- list(source = as.character(rating_band_source %||% "not recorded"),
                            q = as.numeric(rating_band$q),
                            lower = as.numeric(rating_band$lower),
                            upper = as.numeric(rating_band$upper))
  }
  header <- c(
    "# The rain comparison's hand-off to calibration, written by compare_rain.R.",
    "# Name its folder in a site's site.yml (rain_comparison: ...) and calibrate_site.R takes",
    "# its rain from here: the first series calibrates, the others are compared. Paths are",
    "# relative to this file's folder. Edit the comparison's rain.yml and run it again rather",
    "# than this file.")
  tmp <- tempfile(fileext = ".yml")
  writeLines(c(header, yaml::as.yaml(out, indent.mapping.sequence = TRUE)), tmp)
  ok <- file.copy(tmp, path, overwrite = TRUE)
  unlink(tmp)
  .check(ok, paste("Could not write", path))
  invisible(path)
}

#' Read the rain comparison's hand-off to calibration
#'
#' Reads `calibration_inputs.yml`, as [write_calibration_inputs()] writes it, and checks that
#' every rain file it names is there. `read_site_settings()` calls it when a site's settings
#' name the comparison's folder.
#'
#' @param x The file, or the folder it is in (the comparison's output folder).
#' @return A `pdm_calibration_inputs` list: `file`, `made_by`, `made_on`, `period`,
#'   `step_hours`, `rain` (a named list of absolute paths, the first to calibrate on),
#'   `rain_error` (`NA` if none), `warnings` (text, possibly empty), `mask` (a data frame of
#'   `from`, `to` and `reason`, or `NULL`), `rating_band` (a data frame of `q`, `lower` and
#'   `upper`, or `NULL`) and `rating_band_source`.
#' @export
#' @examples
#' folder <- file.path(tempdir(), "rain_comparison")
#' dir.create(file.path(folder, "catchment_rain"), recursive = TRUE, showWarnings = FALSE)
#' writeLines("time,value", file.path(folder, "catchment_rain", "thiessen.csv"))
#' write_calibration_inputs(file.path(folder, "calibration_inputs.yml"),
#'                          c(thiessen = "catchment_rain/thiessen.csv"),
#'                          period = c("2015-10-01", "2024-10-01"), step_hours = 0.25)
#' read_calibration_inputs(folder)
read_calibration_inputs <- function(x) {
  .check(is.character(x) && length(x) == 1 && nzchar(x), "x must be one file or folder")
  file <- if (dir.exists(x)) file.path(x, "calibration_inputs.yml") else x
  .check(file.exists(file),
         paste0("No calibration_inputs.yml at ", file, ": run compare_rain.R (pdmS7 0.55.0 or ",
                "later) to write it, or give the folder it wrote"))
  raw <- yaml::read_yaml(file)
  home <- dirname(normalizePath(file))
  .check(is.list(raw) && is.list(raw$rain) && length(raw$rain) >= 1 && !is.null(names(raw$rain)),
         paste(file, "names no rain series"))
  absolute <- function(p) grepl("^(/|~|[A-Za-z]:|\\\\)", p)
  rain <- lapply(raw$rain, function(p) {
    p <- as.character(p)
    if (absolute(p)) path.expand(p) else file.path(home, p)
  })
  missing <- names(rain)[!file.exists(unlist(rain))]
  .check(!length(missing),
         paste0("The rain comparison's files are missing for ", paste(missing, collapse = ", "),
                ", in ", home, ": run compare_rain.R again"))
  step <- suppressWarnings(as.numeric(raw$step_hours))
  .check(length(step) == 1 && is.finite(step) && step > 0, paste(file, "gives no step_hours"))
  structure(list(file = normalizePath(file),
                 made_by = as.character(if (is.null(raw$made_by)) "" else raw$made_by),
                 made_on = as.character(if (is.null(raw$made_on)) "" else raw$made_on),
                 period = as.character(unlist(raw$period)),
                 step_hours = step,
                 rain = rain,
                 rain_error = if (is.numeric(raw$rain_error)) raw$rain_error else NA_real_,
                 warnings = as.character(unlist(raw$warnings)),
                 mask = if (length(raw$mask)) {
                   data.frame(from = vapply(raw$mask, function(m) as.character(m$from), ""),
                              to = vapply(raw$mask, function(m) as.character(m$to), ""),
                              reason = vapply(raw$mask, function(m) as.character(m$reason), ""))
                 },
                 rating_band = if (length(raw$rating_band$q)) {
                   data.frame(q = as.numeric(unlist(raw$rating_band$q)),
                              lower = as.numeric(unlist(raw$rating_band$lower)),
                              upper = as.numeric(unlist(raw$rating_band$upper)))
                 },
                 rating_band_source = as.character(raw$rating_band$source %||% "")),
            class = "pdm_calibration_inputs")
}

#' @export
print.pdm_calibration_inputs <- function(x, ...) {
  cat("Calibration inputs from ", x$file, " (", x$made_by, ", ", x$made_on, ")\n", sep = "")
  cat("  Period judged: ", paste(x$period, collapse = " to "), "; steps of ", x$step_hours,
      " h\n", sep = "")
  for (i in seq_along(x$rain)) {
    cat(sprintf("  Rain %-16s %s%s\n", paste0(names(x$rain)[i], ":"), basename(x$rain[[i]]),
                if (i == 1) " (calibrates)" else ""))
  }
  if (is.finite(x$rain_error)) cat("  Rain error: ", x$rain_error, "\n", sep = "")
  if (!is.null(x$mask)) cat("  Mask: ", nrow(x$mask), " periods to leave out\n", sep = "")
  if (!is.null(x$rating_band)) {
    cat("  Rating band: ", nrow(x$rating_band), " flows, from ", x$rating_band_source, "\n",
        sep = "")
  }
  if (length(x$warnings)) {
    cat("  Warnings:\n")
    cat(paste0("    - ", x$warnings), sep = "\n")
  } else {
    cat("  No warnings.\n")
  }
  invisible(x)
}
