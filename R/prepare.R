# ============================================================ #
# Tool:         prepare
# Description:  Data preparation before registration: read hydrometric CSVs, align series on one
#               time step, convert units, fill gaps, zero negatives, and check the result, each
#               step noted so register_data() can record it in the calibration log
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-08
# Modified:     2026-11-08 - First version, from the Beggearn Huish calibration script
# Tier:         1
# Inputs:       CSV files of rain, potential evaporation and flow
# Outputs:      Aligned, converted, gap-free series with preparation notes; an input check
# Dependencies: data.table; stats
# ============================================================ #

# ---- Preparation notes -------------------------------------------------------------------

# Each preparation step adds a row to a series' "pdm_prep" attribute. Notes survive data frames,
# data.tables, element assignment and arithmetic, but not subsetting.
.add_note <- function(x, step, detail) {
  notes <- attr(x, "pdm_prep") %||% data.frame(step = character(0), detail = character(0))
  attr(x, "pdm_prep") <- rbind(notes, data.frame(step = step, detail = detail))
  x
}

#' What was done to a series before registration
#'
#' Every preparation function ([read_hydro_series()], [align_series()], [convert_units()],
#' [fill_gaps()], [zero_negatives()]) notes what it did on the series it returns.
#' `preparation_notes()` lists those notes. [register_data()] writes them into the calibration
#' log, so a reviewer can see, for instance, that 412 steps of evaporation were interpolated
#' and three negative rain values set to zero.
#'
#' Notes travel with a vector through data frames, data.tables, assignment and arithmetic, but
#' subsetting (`x[1:100]`) drops them: prepare the whole series, then register it.
#'
#' @param x A prepared series, or a data frame of them (such as forcing).
#' @return A data frame with columns `series`, `step` and `detail`; no rows if nothing is noted.
#' @examples
#' rain <- c(0, 1.2, NA, 0.4, -0.1)
#' rain <- zero_negatives(fill_gaps(rain, "zero", label = "rain"), label = "rain")
#' preparation_notes(rain)
#' @seealso [check_inputs()], [register_data()]
#' @export
preparation_notes <- function(x) {
  one <- function(v, name) {
    n <- attr(v, "pdm_prep")
    if (is.null(n) || !nrow(n)) return(NULL)
    data.frame(series = name, step = n$step, detail = n$detail)
  }
  out <- if (is.data.frame(x)) {
    do.call(rbind, lapply(names(x), function(name) one(x[[name]], name)))
  } else {
    one(x, attr(x, "pdm_label") %||% "series")
  }
  out %||% data.frame(series = character(0), step = character(0), detail = character(0))
}

# ---- Reading -----------------------------------------------------------------------------

.time_formats <- c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%SZ",
                   "%Y-%m-%dT%H:%M:%S", "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M",
                   "%d-%m-%Y %H:%M", "%Y/%m/%d %H:%M", "%Y-%m-%d", "%d/%m/%Y")

.time_parts <- list(year = c("year", "years", "yr"), month = c("month", "months", "mon"),
                    day = c("day", "days"), hour = c("hour", "hours", "hr", "hrs"),
                    minute = c("minute", "minutes", "min", "mins"),
                    second = c("second", "seconds", "sec", "secs"))

#' Read a hydrometric series from a CSV file
#'
#' Reads one series of rain, evaporation or flow from the layouts hydrometric exports use:
#'
#' - **Split date columns**: year, month and day columns, with hour, minute and second if
#'   present, in any of their usual spellings (`hour` or `hours`, `min` or `minute`).
#' - **One time column**, or a date column and a time column side by side, in any of the
#'   common formats (`2021-03-01 09:15`, `01/03/2021 09:15`, ISO 8601 and others).
#'
#' The value is the last numeric column unless named. Times are read in `tz` and returned in
#' UTC. Rows whose time cannot be read are dropped, and a file whose timestamps repeat is
#' refused: repeats mean a time column was missed, and keeping one value per time would
#' calibrate on a fraction of the record.
#'
#' @param file Path of the CSV file.
#' @param value_col Name of the value column; by default the last numeric column.
#' @param time_col Name of the time column, or of a date and a time column; by default found.
#' @param time_formats Formats to try, in order; the first that reads 99% of the times is used.
#' @param tz Time zone of the times in the file. EA telemetry is in GMT all year: `"UTC"`.
#' @param na_strings Strings read as missing.
#' @return A `pdm_hydro_series`: a data frame of `time` (POSIXct, UTC) and `value`, with the
#'   file, the columns used and the median step in minutes as attribute `source`.
#' @examples
#' f <- tempfile(fileext = ".csv")
#' writeLines(c("year,month,day,hour,minute,flow", "2021,3,1,9,0,1.2", "2021,3,1,9,15,1.3"), f)
#' read_hydro_series(f)
#' @seealso [align_series()], [check_inputs()]
#' @export
read_hydro_series <- function(file, value_col = NULL, time_col = NULL,
                              time_formats = .time_formats, tz = "UTC",
                              na_strings = c("", "NA", "NaN", "-", "---", "-9999")) {
  .check(is.character(file) && length(file) == 1L && file.exists(file),
         paste("File not found:", file))
  d <- data.table::fread(file, na.strings = na_strings)
  lower <- tolower(names(d))
  split <- vapply(.time_parts, function(v) any(v %in% lower), logical(1))
  read <- if (is.null(time_col) && all(split[c("year", "month", "day")])) {
    .read_split_time(d, lower, tz)
  } else {
    .read_time_column(d, lower, time_col, time_formats, tz, basename(file))
  }
  numeric <- names(d)[vapply(d, is.numeric, logical(1)) & !names(d) %in% read$columns]
  value_col <- value_col %||% utils::tail(numeric, 1)
  .check(length(value_col) == 1L && value_col %in% names(d),
         paste("No value column in", basename(file), "; name it with value_col"))
  out <- data.frame(time = read$time, value = as.numeric(d[[value_col]]))
  out <- out[!is.na(out$time), ]
  repeats <- sum(duplicated(out$time))
  .check(repeats <= 0.01 * nrow(out), sprintf(paste0(
    "%s: %d of %d timestamps repeat, so its times were not read right (columns used: %s). ",
    "Name the time column with time_col"
  ), basename(file), repeats, nrow(out), paste(read$columns, collapse = ", ")))
  out <- out[!duplicated(out$time), ]
  out <- out[order(out$time), ]
  rownames(out) <- NULL
  step <- if (nrow(out) > 1L) as.numeric(stats::median(diff(out$time)), units = "mins") else NA
  attr(out, "source") <- list(file = normalizePath(file, winslash = "/"),
                              time = paste(read$columns, collapse = " + "),
                              value = value_col, step_minutes = step)
  out$value <- .add_note(out$value, "read", sprintf(
    "%s: %d rows, %s to %s, step %g min, value column %s",
    basename(file), nrow(out), format(min(out$time), "%Y-%m-%d %H:%M"),
    format(max(out$time), "%Y-%m-%d %H:%M"), step, value_col
  ))
  class(out) <- c("pdm_hydro_series", "data.frame")
  out
}

# Times from year, month, day (and hour, minute, second) columns.
.read_split_time <- function(d, lower, tz) {
  part <- function(p) {
    hit <- which(lower %in% .time_parts[[p]])
    if (length(hit)) as.numeric(d[[hit[1]]]) else 0
  }
  time <- ISOdatetime(part("year"), part("month"), part("day"), part("hour"), part("minute"),
                      part("second"), tz = tz)
  list(time = as.POSIXct(format(time, tz = "UTC", usetz = FALSE), tz = "UTC"),
       columns = names(d)[lower %in% unlist(.time_parts)])
}

# Times from one column, or a date column and a time column, tried against each format.
.read_time_column <- function(d, lower, time_col, formats, tz, file) {
  if (is.null(time_col)) {
    hit <- names(d)[grepl("time|date", lower)]
    time_col <- if (length(hit)) hit[seq_len(min(2L, length(hit)))] else names(d)[1]
  }
  .check(all(time_col %in% names(d)), paste("No column", toString(time_col), "in", file))
  # fread may have parsed the times already; as text with the time kept (as.character() drops
  # a midnight time).
  text <- function(x) {
    if (inherits(x, "POSIXct")) format(x, "%Y-%m-%d %H:%M:%S", tz = "UTC") else as.character(x)
  }
  pair <- length(time_col) == 2L && !all(grepl(":", utils::head(text(d[[time_col[1]]]), 5)))
  if (!pair) time_col <- time_col[1]
  stamp <- if (pair) paste(text(d[[time_col[1]]]), text(d[[time_col[2]]])) else
    text(d[[time_col]])
  for (f in formats) {
    t <- as.POSIXct(stamp, format = f, tz = tz)
    if (mean(!is.na(t)) > 0.99) {
      return(list(time = as.POSIXct(format(t, tz = "UTC", usetz = FALSE), tz = "UTC"),
                  columns = time_col))
    }
  }
  stop(sprintf("Cannot read the times in %s, for example '%s'. Add their format to time_formats",
               file, stamp[1]), call. = FALSE)
}

#' @export
print.pdm_hydro_series <- function(x, ...) {
  s <- attr(x, "source")
  cat(sprintf("Hydrometric series from %s: %d rows, %s to %s, step %g min, %d missing\n",
              basename(s$file), nrow(x), format(min(x$time), "%Y-%m-%d %H:%M"),
              format(max(x$time), "%Y-%m-%d %H:%M"), s$step_minutes, sum(!is.finite(x$value))))
  cat(sprintf("Columns used: time %s, value %s\n", s$time, s$value))
  invisible(x)
}

# ---- Aligning ----------------------------------------------------------------------------

#' Put several series on one regular time step
#'
#' Builds a regular time grid over the period every series covers and places each series on
#' it. A step with no reading becomes missing; nothing is interpolated here (see
#' [fill_gaps()]). A series recorded at a coarser step than the grid leaves the steps between
#' its readings missing, and a note says so.
#'
#' @param ... Named series: [read_hydro_series()] results, or data frames with `time` and
#'   `value` columns.
#' @param dt Grid step in hours; by default the finest median step of the series.
#' @param start,end Optional limits of the grid (times); by default the period all series share.
#' @return A data frame of `time` and one column per series, each noted.
#' @examples
#' t <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 900, length.out = 8)
#' rain <- data.frame(time = t, value = c(0, 0.2, 0.4, 0, 0, 0, 0.1, 0))
#' flow <- data.frame(time = t[-3], value = c(1, 1.1, 1.3, 1.2, 1.1, 1.05, 1))
#' align_series(rain = rain, flow = flow)
#' @seealso [read_hydro_series()], [fill_gaps()], [check_inputs()]
#' @export
align_series <- function(..., dt = NULL, start = NULL, end = NULL) {
  series <- list(...)
  .check(length(series) > 0 && !is.null(names(series)) && all(nzchar(names(series))),
         "Give the series as name = series")
  for (s in series) {
    .check(is.data.frame(s) && all(c("time", "value") %in% names(s)) &&
             inherits(s$time, "POSIXt"), "Each series needs a POSIXct time column and value")
  }
  steps <- vapply(series, function(s) {
    as.numeric(stats::median(diff(sort(s$time))), units = "hours")
  }, numeric(1))
  dt <- dt %||% min(steps)
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  first <- if (is.null(start)) max(do.call(c, lapply(series, function(s) min(s$time)))) else
    as.POSIXct(start, tz = "UTC")
  last <- if (is.null(end)) min(do.call(c, lapply(series, function(s) max(s$time)))) else
    as.POSIXct(end, tz = "UTC")
  .check(first < last, "The series share no period")
  grid <- seq(first, last, by = dt * 3600)
  out <- data.frame(time = grid)
  for (name in names(series)) {
    s <- series[[name]]
    v <- s$value[!duplicated(s$time)][match(grid, s$time[!duplicated(s$time)])]
    attr(v, "pdm_prep") <- attr(s$value, "pdm_prep")
    detail <- sprintf("on a %g h grid, %s to %s: %d of %d steps missing", dt,
                      format(first, "%Y-%m-%d %H:%M"), format(last, "%Y-%m-%d %H:%M"),
                      sum(!is.finite(v)), length(v))
    if (abs(steps[[name]] - dt) > 1e-9) {
      detail <- paste0(detail, sprintf("; recorded every %g h, so steps between are missing",
                                       steps[[name]]))
    }
    out[[name]] <- .add_note(v, "aligned", detail)
  }
  out
}

# ---- Units -------------------------------------------------------------------------------

# Depth units are converted with the step length; flow units by a fixed factor to m3/s.
.depth_units <- c("mm_per_step", "mm_per_hour", "mm_per_day", "m_per_step")
.flow_factors <- c(m3s = 1, ls = 1e-3, mld = 1 / 86.4)

# Plausible annual totals, mm, for the unit guess: wide enough for the British Isles.
.plausible <- list(rain = c(400, 4000), pet = c(250, 1200))

#' Convert rain, evaporation or flow to the units pdmS7 uses
#'
#' pdmS7 takes rain and potential evaporation as depths in mm per time step, and flow in m3/s.
#' `convert_units()` converts from the usual alternatives:
#'
#' | Quantity | Units accepted |
#' |---|---|
#' | `rain`, `pet` | `mm_per_step`, `mm_per_hour` (an intensity), `mm_per_day`, `m_per_step` |
#' | `flow` | `m3s`, `ls` (litres a second), `mld` (megalitres a day) |
#'
#' With `from = "auto"`, the unit is worked out: for rain and evaporation, the annual total
#' each depth unit implies is compared with a plausible range, and exactly one must fit; for
#' flow, a mean above 100 is read as litres a second. The guess is noted, with the totals it
#' was based on, so a reviewer can check it. Prefer naming the unit when you know it.
#'
#' @param x Numeric series.
#' @param from Units of `x`, or `"auto"`.
#' @param dt Time step in hours.
#' @param quantity `rain`, `pet` or `flow`.
#' @param plausible For `"auto"` with rain or evaporation: the plausible annual total, mm.
#' @return `x` converted, noted.
#' @examples
#' convert_units(c(0, 2, 4), "mm_per_hour", dt = 0.25, quantity = "rain")
#' convert_units(c(1200, 1500), "ls", dt = 0.25, quantity = "flow")
#' @seealso [fill_gaps()], [check_inputs()]
#' @export
convert_units <- function(x, from, dt, quantity = c("rain", "pet", "flow"), plausible = NULL) {
  quantity <- match.arg(quantity)
  .check(is.numeric(x), "x must be numeric")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  kind <- if (quantity == "flow") "flow" else "depth"
  units <- if (kind == "flow") names(.flow_factors) else .depth_units
  .check(is.character(from) && length(from) == 1L && from %in% c(units, "auto"),
         paste("from must be one of", paste(c(units, "auto"), collapse = ", "), "for", quantity))
  guessed <- ""
  if (from == "auto") {
    guess <- .guess_units(x, dt, quantity, plausible %||% .plausible[[quantity]])
    from <- guess$unit
    guessed <- paste0(" (worked out: ", guess$why, ")")
  }
  factor <- if (kind == "flow") .flow_factors[[from]] else
    c(mm_per_step = 1, mm_per_hour = dt, mm_per_day = dt / 24, m_per_step = 1000)[[from]]
  target <- if (kind == "flow") "m3/s" else "mm per step"
  detail <- if (factor == 1) sprintf("%s already in %s%s", quantity, target, guessed) else
    sprintf("%s from %s to %s (x %.6g)%s", quantity, from, target, factor, guessed)
  .add_note(x * factor, "units", detail)
}

.guess_units <- function(x, dt, quantity, plausible) {
  if (quantity == "flow") {
    m <- mean(x, na.rm = TRUE)
    return(list(unit = if (m > 100) "ls" else "m3s",
                why = sprintf("mean %.3g, %s 100", m, if (m > 100) "above" else "not above")))
  }
  per_step <- mean(x, na.rm = TRUE) * 8766 / dt
  factor <- c(mm_per_step = 1, mm_per_hour = dt, mm_per_day = dt / 24)
  totals <- per_step * factor
  fits <- names(factor)[totals >= plausible[1] & totals <= plausible[2]]
  .check(length(fits) == 1L, sprintf(paste0(
    "Cannot tell the %s units: %s mm a year as %s; plausible is %g to %g. Name them with from"
  ), quantity, paste(round(totals), collapse = ", "), paste(names(factor), collapse = ", "),
  plausible[1], plausible[2]))
  list(unit = fits, why = sprintf("%.0f mm a year as %s", totals[[fits]], fits))
}

# ---- Gaps and negatives ------------------------------------------------------------------

#' Fill gaps in rain or evaporation
#'
#' The model cannot run through a gap in its inputs, so rain and evaporation must be complete
#' before registration. Flow need not be: missing flow is simply left out of scoring, so never
#' fill flow for scoring.
#'
#' | `rule` | Does |
#' |---|---|
#' | `stop` | refuses, listing the five longest gaps, so you infill them yourself |
#' | `zero` | sets missing steps to zero, for rain where a gap is known to be dry |
#' | `interpolate` | joins the values either side; gaps over `max_gap_h` stay missing |
#' | `none` | leaves gaps, and notes how many there are |
#'
#' The rule, the number of steps filled and the longest gap are noted, and reach the
#' calibration log through [register_data()].
#'
#' @param x Numeric series on a regular step.
#' @param rule One of the rules above.
#' @param time Optional times of `x`, to name the gaps by date.
#' @param label Name of the series in messages and notes.
#' @param max_gap_h For `interpolate`: longest gap to fill, in hours, with `dt`.
#' @param dt Time step in hours, for `max_gap_h`.
#' @return `x` with gaps filled, noted.
#' @examples
#' fill_gaps(c(0.1, NA, NA, 0.4), "interpolate", label = "pet")
#' @seealso [zero_negatives()], [preparation_notes()]
#' @export
fill_gaps <- function(x, rule = c("stop", "zero", "interpolate", "none"), time = NULL,
                      label = "series", max_gap_h = Inf, dt = 1) {
  rule <- match.arg(rule)
  .check(is.numeric(x), "x must be numeric")
  missing <- which(!is.finite(x))
  if (!length(missing)) return(.add_note(x, "gaps", paste(label, "had no gaps")))
  runs <- split(missing, cumsum(c(1, diff(missing) != 1)))
  where <- function(r) {
    at <- if (is.null(time)) paste("row", r[1]) else format(time[r[1]], "%Y-%m-%d %H:%M")
    sprintf("%s for %d steps", at, length(r))
  }
  longest <- runs[order(-lengths(runs))][seq_len(min(5L, length(runs)))]
  if (rule == "stop") {
    stop(sprintf("%d missing %s values; longest gaps from %s. Infill them, or choose a rule",
                 length(missing), label, paste(vapply(longest, where, ""), collapse = "; ")),
         call. = FALSE)
  }
  filled <- 0L
  if (rule == "zero") {
    x[missing] <- 0
    filled <- length(missing)
  } else if (rule == "interpolate") {
    ok <- which(is.finite(x))
    .check(length(ok) >= 2L, paste(label, "has too few values to interpolate"))
    short <- unlist(runs[lengths(runs) * dt <= max_gap_h])
    if (length(short)) {
      x[short] <- stats::approx(ok, x[ok], short, rule = 2)$y
      filled <- length(short)
    }
  }
  .add_note(x, "gaps", sprintf(
    "%s: %d missing steps in %d gap%s, longest %s; %s, %d filled, %d left missing",
    label, length(missing), length(runs), if (length(runs) == 1L) "" else "s",
    where(longest[[1]]), rule, filled,
    length(missing) - filled
  ))
}

#' Set negative values to zero
#'
#' Negative rain is a data error. Negative evaporation is not always one (MOSES PE goes slightly
#' negative when condensation exceeds evaporation, and pdmS7 takes it as it is), so use this on
#' evaporation only if your source should never be negative. The count, smallest value and
#' total are noted.
#'
#' @param x Numeric series.
#' @param label Name of the series in the note.
#' @return `x` with negative values set to zero, noted.
#' @examples
#' zero_negatives(c(0.2, -0.01, 0.5), label = "rain")
#' @seealso [fill_gaps()], [preparation_notes()]
#' @export
zero_negatives <- function(x, label = "series") {
  .check(is.numeric(x), "x must be numeric")
  bad <- which(is.finite(x) & x < 0)
  if (!length(bad)) return(x)
  detail <- sprintf("%s: %d negative values (smallest %.4g, total %.4g) set to zero", label,
                    length(bad), min(x[bad]), sum(x[bad]))
  x[bad] <- 0
  .add_note(x, "negatives", detail)
}

# ---- Checking ----------------------------------------------------------------------------

#' Check inputs before registering them
#'
#' A last look at the data before [register_data()]: the period, the step, how much is missing,
#' negative values, annual totals and the runoff ratio, each compared with a plausible range.
#' Totals far outside the ranges usually mean the wrong units; a runoff ratio above one means
#' the rain is too low, the flow too high or the area wrong. The defaults suit the British
#' Isles; give your own ranges elsewhere. The preparation notes of each series are included.
#'
#' @param forcing Data frame with `rain` and `pet` (mm per step) and, optionally, `time`.
#' @param observed Observed flow, m3/s, aligned with `forcing`; optional.
#' @param area_km2 Catchment area, for the runoff ratio.
#' @param dt Time step in hours; by default from `forcing$time`.
#' @param ranges Plausible `rain` and `pet` annual totals (mm) and `runoff_ratio`.
#' @return A `pdm_input_check` list: `table` (one row per series), `runoff_ratio`, `flags`
#'   (warnings in words, empty when all is plausible) and `notes`. Printing it shows all four.
#' @examples
#' n <- 24 * 365
#' forcing <- data.frame(rain = rep(c(0, 0, 0, 0.9), n / 4), pet = 0.06)
#' check_inputs(forcing, observed = rep(0.4, n), area_km2 = 20, dt = 1)
#' @seealso [preparation_notes()], [register_data()]
#' @export
check_inputs <- function(forcing, observed = NULL, area_km2 = NULL, dt = NULL,
                         ranges = list(rain = c(400, 4000), pet = c(250, 1200),
                                       runoff_ratio = c(0.1, 0.9))) {
  .check(is.data.frame(forcing) && all(c("rain", "pet") %in% names(forcing)),
         "forcing needs rain and pet columns")
  dt <- dt %||% if ("time" %in% names(forcing) && nrow(forcing) > 1L) {
    as.numeric(stats::median(diff(forcing$time)), units = "hours")
  }
  .check(.scalar(dt, 0, strict = TRUE), "Give dt, or a time column in forcing")
  .check(is.null(observed) || length(observed) == nrow(forcing),
         "observed must be as long as forcing")
  years <- nrow(forcing) * dt / 8766
  table <- .input_table(forcing, observed, dt)
  ratio <- if (!is.null(observed) && !is.null(area_km2)) {
    # 1 m3/s for an hour over 1 km2 is 3.6 mm of runoff.
    runoff_mm <- mean(observed, na.rm = TRUE) * 3.6 * 8766 / area_km2
    runoff_mm / table$annual[table$series == "rain"]
  } else {
    NA_real_
  }
  out <- list(table = table, runoff_ratio = ratio, years = years, dt = dt,
              flags = .input_flags(table, ratio, ranges),
              notes = preparation_notes(cbind(forcing[c("rain", "pet")],
                                              if (!is.null(observed)) data.frame(flow = observed))))
  structure(out, class = "pdm_input_check")
}

# One row per series: steps, missing, negatives, mean and, for rain and pet, the annual total.
.input_table <- function(forcing, observed, dt) {
  series <- list(rain = forcing$rain, pet = forcing$pet)
  if (!is.null(observed)) series$flow <- observed
  do.call(rbind, lapply(names(series), function(name) {
    v <- series[[name]]
    data.frame(series = name, steps = length(v), missing = sum(!is.finite(v)),
               negative = sum(v < 0, na.rm = TRUE), mean = mean(v, na.rm = TRUE),
               annual = if (name == "flow") NA_real_ else mean(v, na.rm = TRUE) * 8766 / dt)
  }))
}

# TRUE when a value is known and outside its range.
.outside <- function(v, range) is.finite(v) && (v < range[1] || v > range[2])

.input_flags <- function(table, ratio, ranges) {
  flags <- character(0)
  for (name in intersect(c("rain", "pet"), table$series)) {
    total <- table$annual[table$series == name]
    if (.outside(total, ranges[[name]])) {
      flags <- c(flags, sprintf("%s totals %.0f mm a year, outside %g to %g: check the units",
                                name, total, ranges[[name]][1], ranges[[name]][2]))
    }
  }
  if (any(table$missing[table$series %in% c("rain", "pet")] > 0)) {
    flags <- c(flags, "rain or pet has gaps: the model cannot run through them (fill_gaps())")
  }
  if (any(table$negative[table$series == "rain"] > 0)) {
    flags <- c(flags, "rain has negative values (zero_negatives())")
  }
  r <- ranges$runoff_ratio
  if (.outside(ratio, r)) {
    flags <- c(flags, sprintf(paste0("runoff is %.0f%% of rain, outside %g%% to %g%%: check ",
                                     "the area, the units or the rain"),
                              100 * ratio, 100 * r[1], 100 * r[2]))
  }
  flags
}

#' @export
print.pdm_input_check <- function(x, ...) {
  cat(sprintf("Input check: %.1f years at %g h steps\n", x$years, x$dt))
  t <- x$table
  for (i in seq_len(nrow(t))) {
    cat(sprintf("  %-5s %s missing, %d negative, mean %.4g%s\n", t$series[i],
                format(t$missing[i], big.mark = ","), t$negative[i], t$mean[i],
                if (is.finite(t$annual[i])) sprintf(", %.0f mm a year", t$annual[i]) else ""))
  }
  if (is.finite(x$runoff_ratio)) {
    cat(sprintf("  Runoff is %.0f%% of rain\n", 100 * x$runoff_ratio))
  }
  if (nrow(x$notes)) {
    cat("Preparation:\n")
    for (i in seq_len(nrow(x$notes))) {
      cat(sprintf("  %-5s %-9s %s\n", x$notes$series[i], x$notes$step[i], x$notes$detail[i]))
    }
  }
  if (length(x$flags)) {
    cat("CHECK:\n", paste0("  ", x$flags, "\n"), sep = "")
  } else {
    cat("Nothing implausible found\n")
  }
  invisible(x)
}
