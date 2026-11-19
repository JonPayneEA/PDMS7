# ============================================================ #
# Tool:         camels
# Description:  CAMELS-GB v2 as calibration input: reads the hourly tables the
#               Input_Analysis_Pipeline writes, trims each to the years with hourly rain, splits
#               the record into warm-up, calibration, validation and test water years, and writes
#               the basin folders calibrate_batch() reads
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-19
# Modified:     2026-11-19 - First version, for the bulk CAMELS-GB calibration
# Tier:         1
# Inputs:       gold/camels_gb_v2/hourly/<gauge>.parquet, descriptors.parquet and screening.csv
#               under a store root
# Outputs:      Forcing and observed flow in memory; basin folders (forcing.csv, flow.csv,
#               basin.yml) on disk
# Dependencies: data.table; yaml; arrow or nanoparquet (suggested, for Parquet)
# ============================================================ #

# Reads a Parquet file with whichever reader is installed.
.read_parquet <- function(path) {
  .check(file.exists(path), paste("No file", path))
  if (requireNamespace("arrow", quietly = TRUE)) {
    return(as.data.frame(arrow::read_parquet(path)))
  }
  if (requireNamespace("nanoparquet", quietly = TRUE)) {
    return(as.data.frame(nanoparquet::read_parquet(path)))
  }
  stop("Reading Parquet needs the arrow or nanoparquet package: install.packages(\"arrow\")",
       call. = FALSE)
}

# The folder the pipeline writes CAMELS-GB v2 to, under a store root.
.camels_dir <- function(store) file.path(store, "gold", "camels_gb_v2")

#' Read a CAMELS-GB v2 catchment
#'
#' Reads one catchment's hourly table, as the Input_Analysis_Pipeline writes it
#' (`gold/camels_gb_v2/hourly/<gauge>.parquet` under the store root), and returns it ready for
#' calibration with [camels_forcing()].
#'
#' The table holds `time` (UTC, hour start), `rain_mm` (CEH-GEAR hourly), `rain_gradgb_mm`,
#' `pet_mm` (the day's potential evaporation spread over its daylight hours), `temperature_c`,
#' `flow_m3s`, `flow_mmh`, `flow_flag`, `level_m` and `level_flag`.
#'
#' Reading Parquet needs the arrow package, or nanoparquet.
#'
#' @param store The store root (the pipeline's `store_root`).
#' @param gauge The gauge identifier, such as `"12001"`.
#' @return A data frame, `time` as POSIXct in UTC.
#' @seealso [camels_forcing()], [camels_batch_folders()]
#' @export
camels_read <- function(store, gauge) {
  .check(is.character(store) && length(store) == 1L, "store must be one folder path")
  .check(length(gauge) == 1L, "gauge must be one identifier")
  table <- .read_parquet(file.path(.camels_dir(store), "hourly", paste0(gauge, ".parquet")))
  table$time <- .parse_time(table$time)
  table
}

#' Forcing and flow from a CAMELS-GB v2 table
#'
#' Turns one catchment's hourly table into the `forcing` and `observed` flow that
#' [register_data()] and [calibrate_pdm()] take, over the years that have rain.
#'
#' **The rain years.** The CEH-GEAR hourly rain ends on 31 December 2016, while the flow runs to
#' 2022. The forcing must have no gaps, so the record is cut to the hours from the first rain
#' to the last. Flow may have gaps; they are left missing and not scored.
#'
#' **Gaps inside the rain years.** A run of missing rain or evaporation up to `fill_gaps_h`
#' hours long is set to zero rain, or interpolated evaporation, and noted; a longer one stops
#' with the count, since a long gap filled with zero is a drought the catchment never had.
#'
#' **Rain source.** `rain = "rain_gradgb_mm"` uses the GradGB series instead. It reads higher
#' than CEH-GEAR at many gauges, so the two should not be mixed in one record.
#'
#' @param table A table from [camels_read()], or a data frame with the same columns.
#' @param rain The rain column: `"rain_mm"` (CEH-GEAR, the default) or `"rain_gradgb_mm"`.
#' @param fill_gaps_h Longest run of missing forcing, in hours, to fill.
#' @return A list: `forcing` (a data frame of `time`, `rain`, `pet` and `temperature`, mm per
#'   hour and deg C), `observed` (flow, m3/s), `flag` (the flow flags as given), and `summary`
#'   (`start`, `end`, `years`, `rain_filled_h`, `pet_filled_h`, `flow_missing_pct`).
#' @examples
#' time <- as.POSIXct("2001-01-01", tz = "UTC") + 3600 * (0:47)
#' table <- data.frame(time = time, rain_mm = c(NA, rep(0.5, 46), NA), pet_mm = 0.1,
#'                     temperature_c = 6, flow_m3s = 2, flow_flag = "100")
#' x <- camels_forcing(table)
#' x$summary$start
#' nrow(x$forcing)
#' @seealso [camels_read()], [camels_windows()], [camels_batch_folders()]
#' @export
camels_forcing <- function(table, rain = c("rain_mm", "rain_gradgb_mm"), fill_gaps_h = 0) {
  rain <- match.arg(rain)
  .check(is.data.frame(table) && all(c("time", rain, "pet_mm", "flow_m3s") %in% names(table)),
         paste0("table needs time, ", rain, ", pet_mm and flow_m3s columns"))
  .check(.scalar(fill_gaps_h, 0), "fill_gaps_h must be a nonnegative number of hours")
  time <- .parse_time(table$time)
  .check(length(time) > 1L, "table needs at least two hours")
  .check(all(abs(as.numeric(diff(time), units = "hours") - 1) < 1e-8),
         "table must be hourly, in time order, with no missing hours")
  have <- which(is.finite(table[[rain]]))
  .check(length(have) > 1L, paste("No", rain, "in the table"))
  rows <- seq.int(have[1L], utils::tail(have, 1L))
  fill <- function(x, name, how) {
    missing <- !is.finite(x)
    if (!any(missing)) return(list(x = x, filled = 0L))
    longest <- .longest_gap(missing)
    .check(longest <= fill_gaps_h,
           paste0(sum(missing), " hours of ", name, " missing inside the rain years, the ",
                  "longest run ", longest, " hours; raise fill_gaps_h to fill them"))
    x[missing] <- if (how == "zero") 0 else
      stats::approx(which(!missing), x[!missing], which(missing), rule = 2)$y
    list(x = x, filled = sum(missing))
  }
  r <- fill(as.numeric(table[[rain]][rows]), "rain", "zero")
  p <- fill(as.numeric(table$pet_mm[rows]), "evaporation", "interpolate")
  temperature <- if ("temperature_c" %in% names(table)) as.numeric(table$temperature_c[rows]) else
    rep(NA_real_, length(rows))
  flow <- as.numeric(table$flow_m3s[rows])
  list(
    forcing = data.frame(time = time[rows], rain = r$x, pet = p$x, temperature = temperature),
    observed = flow,
    flag = if ("flow_flag" %in% names(table)) as.character(table$flow_flag[rows]) else NULL,
    summary = list(start = time[rows[1L]], end = time[utils::tail(rows, 1L)],
                   years = length(rows) / 8766, rain_filled_h = r$filled,
                   pet_filled_h = p$filled, flow_missing_pct = 100 * mean(!is.finite(flow)))
  )
}

# 1 October 00:00 UTC of each year from `from` to `to`.
.water_year_starts <- function(from, to) {
  as.POSIXct(sprintf("%d-10-01", seq.int(from, to)), tz = "UTC")
}

#' Warm-up, calibration, validation and test windows in water years
#'
#' Splits a record into four runs of whole water years (1 October to 30 September), oldest
#' first: a warm-up, the calibration, the validation, and the test. The test takes the last
#' `test_years` water years and the part year after them; the validation the `validation_years`
#' before. The warm-up runs from the start of the record to the `warmup_years`-th 1 October in
#' it, so a part year at the start counts as the first warm-up year. The calibration takes the
#' rest. A water year starts at 00:00 UTC on 1 October.
#'
#' For the CEH-GEAR hourly years (October 1990 to December 2016) the defaults give a warm-up
#' to September 1991, calibration from October 1991 to September 2007 (16 years), validation
#' to September 2012 and the test to December 2016.
#'
#' @param time The record's times (POSIXct, UTC), or its first and last.
#' @param warmup_years Water years of warm-up, at least 1.
#' @param validation_years,test_years Whole water years for each; 0 for none.
#' @param min_calibration_years The fewest calibration years accepted.
#' @return A list of `warmup`, `calibration`, `validation` and `test`, each `c(start, end)` as
#'   ISO 8601 text; ends are the last hour inside the window.
#' @examples
#' camels_windows(as.POSIXct(c("1990-10-01 09:00", "2016-12-31 23:00"), tz = "UTC"))
#' @seealso [camels_forcing()], [camels_batch_folders()]
#' @export
camels_windows <- function(time, warmup_years = 1, validation_years = 5, test_years = 4,
                           min_calibration_years = 5) {
  for (v in list(warmup_years, validation_years, test_years, min_calibration_years)) {
    .check(.scalar(v, 0) && v == round(v), "Window lengths must be whole numbers of years")
  }
  .check(warmup_years >= 1, "warmup_years must be at least 1")
  time <- .parse_time(time)
  first <- min(time)
  last <- max(time)
  year <- function(x) as.integer(format(x, "%Y", tz = "UTC"))
  starts <- .water_year_starts(year(first) - 1L, year(last) + 1L)
  starts <- starts[starts > first & starts <= last + 3600]
  .check(length(starts) >= 1L, "The record does not span the start of a water year")
  # starts[k]: the k-th 1 October inside the record. The calibration starts at the
  # warmup_years-th, and the test test_years before the last.
  n <- length(starts)
  cal_k <- as.integer(warmup_years)
  test_k <- n - as.integer(test_years)
  val_k <- test_k - as.integer(validation_years)
  .check(val_k - cal_k >= min_calibration_years,
         paste0("Too short: ", round(as.numeric(last - first, units = "days") / 365.25, 1),
                " years of record leave fewer than ", min_calibration_years,
                " calibration years after the warm-up, validation and test"))
  before <- function(t) .format_time(t - 3600)
  window <- function(a, b) c(.format_time(a), before(b))
  list(
    warmup = c(.format_time(first), before(starts[cal_k])),
    calibration = window(starts[cal_k], starts[val_k]),
    validation = if (validation_years == 0) NULL else window(starts[val_k], starts[test_k]),
    test = if (test_years == 0) NULL else c(.format_time(starts[test_k]), .format_time(last))
  )
}

#' Write CAMELS-GB v2 catchments as basin folders for a batch
#'
#' Writes one folder per catchment, as [calibrate_batch()] reads them: `forcing.csv` (time,
#' rain, pet and temperature), `flow.csv` (time, `q_m3s` and the CAMELS flow flag) and
#' `basin.yml` (area, name, gauge, and the calibration, validation and test windows from
#' [camels_windows()]). The forcing starts with the warm-up, so the calibration's warm-up is
#' the rows before its window.
#'
#' By default only the catchments the pipeline's screening kept are written (`use` in
#' `screening.csv`). A folder whose `basin.yml` exists is left alone unless `refresh = TRUE`,
#' so a stopped run can be started again.
#'
#' @param store The store root (the pipeline's `store_root`).
#' @param basins The folder to write the basin folders into; created if needed.
#' @param gauges Gauge identifiers to write; all those screened in if `NULL`.
#' @param screened If `TRUE`, write only gauges the screening kept.
#' @param rain,fill_gaps_h Passed to [camels_forcing()].
#' @param windows A list of arguments for [camels_windows()].
#' @param refresh If `TRUE`, write folders that already exist again.
#' @return A data frame with one row per gauge: `gauge`, `state` (`written`, `kept` or
#'   `failed`), the record's `start`, `end` and `years`, `flow_missing_pct` and `message`.
#' @seealso [camels_read()], [camels_forcing()], [calibrate_batch()]
#' @export
camels_batch_folders <- function(store, basins, gauges = NULL, screened = TRUE,
                                 rain = c("rain_mm", "rain_gradgb_mm"), fill_gaps_h = 0,
                                 windows = list(), refresh = FALSE) {
  rain <- match.arg(rain)
  .check(is.list(windows), "windows must be a list of arguments for camels_windows()")
  dir <- .camels_dir(store)
  desc <- .read_parquet(file.path(dir, "descriptors.parquet"))
  desc$gauge_id <- as.character(desc$gauge_id)
  screen <- data.table::fread(file.path(dir, "screening.csv"),
                              colClasses = list(character = "gauge_id"))
  ids <- if (is.null(gauges)) screen$gauge_id else as.character(gauges)
  if (screened) ids <- intersect(ids, screen$gauge_id[as.logical(screen$use)])
  .check(length(ids) > 0L, "No gauges to write")
  dir.create(basins, showWarnings = FALSE, recursive = TRUE)
  rows <- lapply(ids, function(g) {
    folder <- file.path(basins, g)
    if (!refresh && file.exists(file.path(folder, "basin.yml"))) {
      return(data.frame(gauge = g, state = "kept", start = NA_character_, end = NA_character_,
                        years = NA_real_, flow_missing_pct = NA_real_, message = ""))
    }
    tryCatch({
      d <- desc[desc$gauge_id == g, , drop = FALSE]
      .check(nrow(d) == 1L && .scalar(as.numeric(d$area), 0, strict = TRUE),
             "No positive area in the descriptors")
      x <- camels_forcing(camels_read(store, g), rain = rain, fill_gaps_h = fill_gaps_h)
      w <- do.call(camels_windows, c(list(x$forcing$time), windows))
      dir.create(folder, showWarnings = FALSE, recursive = TRUE)
      times <- .format_time(x$forcing$time)
      data.table::fwrite(data.frame(time = times, rain = x$forcing$rain, pet = x$forcing$pet,
                                    temperature = x$forcing$temperature),
                         file.path(folder, "forcing.csv"))
      data.table::fwrite(data.frame(time = times, q_m3s = x$observed,
                                    flag = x$flag %||% NA_character_),
                         file.path(folder, "flow.csv"))
      meta <- list(area_km2 = as.numeric(d$area),
                   catchment = if ("gauge_name" %in% names(d)) as.character(d$gauge_name) else g,
                   gauge = g, calibration = w$calibration, validation = w$validation,
                   test = w$test, source = paste("CAMELS-GB v2,", rain))
      yaml::write_yaml(Filter(Negate(is.null), meta), file.path(folder, "basin.yml"))
      s <- x$summary
      data.frame(gauge = g, state = "written", start = .format_time(s$start),
                 end = .format_time(s$end), years = round(s$years, 2),
                 flow_missing_pct = round(s$flow_missing_pct, 1), message = "")
    }, error = function(e) {
      data.frame(gauge = g, state = "failed", start = NA_character_, end = NA_character_,
                 years = NA_real_, flow_missing_pct = NA_real_, message = conditionMessage(e))
    })
  })
  do.call(rbind, rows)
}
