# ============================================================ #
# Tool:         h19
# Description:  Reads gridded H19 radar from daily NetCDF files, one 15-minute grid at a time,
#               for merge_rainfall()
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         1
# Inputs:       Daily H19 NetCDF files (British National Grid), an extent in metres
# Outputs:      The cropped grid, the times of every layer, and a reader for one step's grid
# Dependencies: terra, ncdf4 (suggested)
# ============================================================ #

#' Gridded H19 radar for merging with gauges
#'
#' H19 radar comes as daily NetCDF files, each holding that day's 15-minute accumulations on
#' British National Grid, in year and month folders. Sixteen years of it will not fit in memory
#' at once. `h19_radar()` indexes the files (the time of every layer in every file), crops them to
#' an extent around the catchment and its gauges, and returns a reader that gives one step's grid
#' when asked, loading each daily file once as the steps are read in order. Pass its `radar`
#' and `grid` to [merge_rainfall()].
#'
#' **Variable names.** The archive uses `"radar rain-accum H19"` for 2010 to 2019 and
#' `"rainfall_radar_amount"` from 2021. By default each file's variable is found among these;
#' name another with `varname`.
#'
#' **Times** are read from each file's `time` variable and its units, such as
#' `"minutes since 1970-01-01 00:00:00"`, in UTC. Check whether they mark the start or the end of
#' each accumulation, and align the gauges to match: an hour's offset moves every peak.
#'
#' **Extent.** Crop to a box that holds the catchment and the gauges used with it, with a margin:
#' the merged field needs radar at every gauge. Cells with no radar value are `NA`, and a merged
#' step that needs one is `NA`.
#'
#' @param files Paths of the daily NetCDF files, in any order; they are sorted by time.
#' @param extent Numeric `c(xmin, xmax, ymin, ymax)` in British National Grid metres.
#' @param varname Name of the radar variable; by default found in each file among the H19 names.
#' @param fallback_crs Coordinate reference system assumed when a file does not state one.
#' @param layouts Optional result of [h19_layouts()] for these files. Given it, each file's
#'   times are moved to the start of their step and its values put in mm per step, by the
#'   file's own layout, before the steps are put in order: an archive whose time stamp changed
#'   part way through would otherwise put the last step before the change and the first after
#'   it at the same time. Without it, times and values are as the files hold them.
#'
#' @return A list of class `pdm_h19` with `grid` (cell-centre `x` and `y`, both increasing),
#'   `time` (the time of every step, POSIXct in UTC), `radar` (a function of the step number
#'   returning that step's grid, mm, as a matrix of `length(grid$x)` rows by `length(grid$y)`
#'   columns) and `index` (the file, layer and unit factor of every step).
#' @examples
#' \dontrun{
#' files <- list.files("F:/.../01_H19", pattern = "\\.nc$", recursive = TRUE, full.names = TRUE)
#' h19 <- h19_radar(files, extent = c(290000, 330000, 120000, 160000))
#' mask <- catchment_mask(h19$grid$x, h19$grid$y, boundary)
#' merged <- merge_rainfall(gauges, gauge_rain, h19$grid, mask, radar = h19$radar,
#'                          method = "conditional")
#' }
#' @seealso [merge_rainfall()], [catchment_mask()]
#' @export
h19_radar <- function(files, extent, varname = NULL, fallback_crs = "EPSG:27700",
                      layouts = NULL) {
  .check(requireNamespace("terra", quietly = TRUE) && requireNamespace("ncdf4", quietly = TRUE),
         "Reading H19 needs the terra and ncdf4 packages")
  .check(is.character(files) && length(files) > 0 && all(file.exists(files)),
         "files must be paths of existing NetCDF files")
  .check(is.numeric(extent) && length(extent) == 4L && extent[1] < extent[2] &&
           extent[3] < extent[4], "extent must be c(xmin, xmax, ymin, ymax)")
  layers <- lapply(files, function(f) {
    t <- .nc_times(f)
    data.frame(file = f, layer = seq_along(t), time = t)
  })
  index <- do.call(rbind, layers)
  index$factor <- 1
  if (!is.null(layouts)) {
    .check(inherits(layouts, "pdm_h19_layouts"), "layouts must come from h19_layouts()")
    at <- match(index$file, layouts$files$file)
    .check(!anyNA(at), "layouts must describe every one of files")
    .check(!anyNA(layouts$files$factor[at]), "layouts has files with units it cannot convert")
    index$time <- index$time - layouts$files$shift_minutes[at] * 60
    index$factor <- layouts$files$factor[at]
  }
  index <- index[order(index$time, index$file, index$layer), ]
  rownames(index) <- NULL
  .check(!anyDuplicated(index$time), "Two files hold layers at the same time")
  first <- .h19_layers(index$file[1], varname, extent, fallback_crs)
  cache <- new.env(parent = emptyenv())
  cache$file <- index$file[1]
  cache$values <- first$values
  reader <- function(t) {
    .check(.whole(t, 1, nrow(index)), "No such step")
    if (!identical(cache$file, index$file[t])) {
      loaded <- .h19_layers(index$file[t], varname, extent, fallback_crs)
      .check(identical(loaded$x, first$x) && identical(loaded$y, first$y),
             paste("The grid of", basename(index$file[t]), "differs from the first file's"))
      cache$file <- index$file[t]
      cache$values <- loaded$values
    }
    cache$values[, , index$layer[t]] * index$factor[t]
  }
  structure(list(grid = list(x = first$x, y = first$y), time = index$time, radar = reader,
                 index = index), class = "pdm_h19")
}

#' @export
print.pdm_h19 <- function(x, ...) {
  cat(sprintf("H19 radar: %d steps from %s to %s, on %d by %d cells (%g m)\n", length(x$time),
              format(min(x$time), "%Y-%m-%d %H:%M"), format(max(x$time), "%Y-%m-%d %H:%M"),
              length(x$grid$x), length(x$grid$y), diff(x$grid$x[1:2])))
  invisible(x)
}

# The times of a NetCDF file's layers, from its time variable and units, in UTC.
.nc_times <- function(path) {
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  values <- as.numeric(ncdf4::ncvar_get(nc, "time"))
  units <- ncdf4::ncatt_get(nc, "time", "units")$value
  .check(is.character(units) && grepl(" since ", units), paste("No time units in", path))
  unit <- tolower(sub(" since .*", "", units))
  origin <- as.POSIXct(sub("^.* since ", "", units), tz = "UTC",
                       tryFormats = c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M",
                                      "%Y-%m-%d"))
  seconds <- switch(unit, seconds = 1, minutes = 60, hours = 3600, days = 86400,
                    .check(FALSE, paste("Unknown time unit", unit, "in", path)))
  origin + values * seconds
}

# One file's layers cropped to the extent, as an array of columns (x increasing) by rows
# (y increasing) by layers, with the cell centres.
.h19_layers <- function(path, varname, extent, fallback_crs) {
  name <- varname %||% .h19_variable(path)
  r <- terra::rast(path, subds = name)
  # Only labelled, never reprojected: PROJ may try to fetch datum grids, which is not needed.
  if (is.na(terra::crs(r)) || terra::crs(r) == "") suppressWarnings(terra::crs(r) <- fallback_crs)
  r <- terra::crop(r, terra::ext(extent))
  a <- terra::as.array(r)
  # terra's rows run from north to south; turn them round so that y increases.
  a <- a[rev(seq_len(dim(a)[1])), , , drop = FALSE]
  list(x = terra::xFromCol(r, seq_len(terra::ncol(r))),
       y = rev(terra::yFromRow(r, seq_len(terra::nrow(r)))),
       values = aperm(a, c(2, 1, 3)))
}

# The radar variable in a file: the first of the H19 names it holds.
.h19_variable <- function(path) {
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  known <- c("rainfall_radar_amount", "radar rain-accum H19")
  hit <- intersect(known, names(nc$var))
  .check(length(hit) > 0, paste0("No H19 variable in ", basename(path), "; it holds ",
                                 toString(names(nc$var)), ". Name it with varname"))
  hit[1]
}

#' The layouts of a set of H19 files
#'
#' The H19 archive was not written the same way throughout: the radar variable was renamed in
#' 2021, and a change of time stamp, units or grid would shift or scale part of a record
#' without any error. `h19_layouts()` reads only the headers of every file (no radar values, so
#' it takes seconds for years of files), groups the files by layout, and checks each layout
#' before any radar is used.
#'
#' A layout is what a file's header says about how its rain is stored: the radar variable and
#' its units, the order of its dimensions, the grid's cell size, alignment and orientation, the
#' time units, the number of 15-minute layers, and where in its step each layer is stamped.
#' Each is checked:
#'
#' | Check | Expected | Otherwise |
#' |---|---|---|
#' | Cell size | 1000 m in x and y | a problem |
#' | Cell centres | aligned alike in every layout | a problem: the grids would not line up |
#' | Layers | 15 minutes apart, 96 a day | a problem; a short day is only counted |
#' | Units | mm per step | mm per hour is converted (`factor` 0.25); else a problem |
#' | Time stamp | the start of each step | end stamps (first at 00:15) move back 15 minutes |
#'
#' @param files Paths of H19 NetCDF files.
#' @return A list of class `pdm_h19_layouts`: `layouts`, one row per layout (its fields, the
#'   number of files, the first and last day, and `problems`, empty when it passes); and
#'   `files`, one row per file with its layout number, `shift_minutes` (to subtract from its
#'   times so each marks the start of its step) and `factor` (to multiply its values by, to give
#'   mm per step).
#' @examples
#' \dontrun{
#' files <- list.files("F:/.../01_H19", pattern = "\\.nc$", recursive = TRUE, full.names = TRUE)
#' layouts <- h19_layouts(files)
#' layouts
#' }
#' @seealso [h19_radar()]
#' @export
h19_layouts <- function(files) {
  .check(requireNamespace("ncdf4", quietly = TRUE), "Reading H19 needs the ncdf4 package")
  .check(is.character(files) && length(files) > 0 && all(file.exists(files)),
         "files must be paths of existing NetCDF files")
  per_file <- do.call(rbind, lapply(files, .h19_header))
  keys <- c("variable", "units", "dimensions", "cell_x", "cell_y", "x_offset", "y_offset",
            "y_order", "time_units", "step_minutes", "stamp", "scaled")
  key <- do.call(paste, c(per_file[keys], sep = "\r"))
  per_file$layout <- match(key, unique(key))
  layouts <- do.call(rbind, lapply(split(per_file, per_file$layout), function(f) {
    row <- f[1, keys]
    row$layout <- f$layout[1]
    row$files <- nrow(f)
    row$first_day <- format(min(f$first_time), "%Y-%m-%d")
    row$last_day <- format(max(f$first_time), "%Y-%m-%d")
    row$short_days <- sum(f$layers != 96)
    row
  }))
  layouts <- layouts[order(layouts$first_day), c("layout", "files", "first_day", "last_day",
                                                 keys, "short_days")]
  rownames(layouts) <- NULL
  layouts$problems <- vapply(seq_len(nrow(layouts)), function(i) {
    l <- layouts[i, ]
    p <- c(
      if (abs(l$cell_x - 1000) > 1 || abs(l$cell_y - 1000) > 1) {
        sprintf("cells %g by %g m, not 1 km", l$cell_x, l$cell_y)
      },
      if (!isTRUE(abs(l$step_minutes - 15) < 0.5)) {
        sprintf("layers %s minutes apart, not 15", format(l$step_minutes))
      },
      if (is.na(.h19_unit_factor(l$units))) sprintf("units '%s' not understood", l$units),
      if (l$stamp == "unknown") "layers stamped neither at 00:00 nor at 00:15",
      if (l$x_offset != layouts$x_offset[1] || l$y_offset != layouts$y_offset[1]) {
        "cell centres not aligned with the first layout's"
      })
    paste(p, collapse = "; ")
  }, character(1))
  per_file$shift_minutes <- ifelse(per_file$stamp == "end", 15, 0)
  per_file$factor <- vapply(per_file$units, .h19_unit_factor, numeric(1))
  structure(list(layouts = layouts,
                 files = per_file[order(per_file$first_time),
                                  c("file", "layout", "first_time", "layers", "shift_minutes",
                                    "factor")]),
            class = "pdm_h19_layouts")
}

#' @export
print.pdm_h19_layouts <- function(x, ...) {
  l <- x$layouts
  cat(sprintf("H19 files: %d, in %d layout%s\n", sum(l$files), nrow(l),
              if (nrow(l) == 1) "" else "s"))
  for (i in seq_len(nrow(l))) {
    cat(sprintf(paste("  %d. %d files, %s to %s: '%s' in %s; %g m cells, rows %s; layers %s",
                      "minutes apart, stamped at the %s of their step%s\n"), l$layout[i],
                l$files[i], l$first_day[i], l$last_day[i], l$variable[i], l$units[i],
                l$cell_x[i], l$y_order[i], format(l$step_minutes[i]), l$stamp[i],
                if (nzchar(l$problems[i])) paste0(". PROBLEMS: ", l$problems[i]) else ""))
  }
  invisible(x)
}

# What one file's header says about its layout.
.h19_header <- function(path) {
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  name <- .h19_variable(path)
  v <- nc$var[[name]]
  dims <- vapply(v$dim, function(d) d$name, "")
  is_time <- vapply(v$dim, function(d) grepl(" since ", d$units %||% ""), logical(1))
  space <- v$dim[!is_time]
  .check(length(space) == 2, paste("Expected two grid dimensions in", basename(path)))
  is_y <- vapply(space, function(d) grepl("^y$|north|projection_y|lat", tolower(d$name)),
                 logical(1))
  if (!any(is_y)) is_y <- c(FALSE, TRUE)
  xv <- space[[which(!is_y)[1]]]$vals
  yv <- space[[which(is_y)[1]]]$vals
  times <- .nc_times(path)
  day <- as.POSIXct(format(min(times), "%Y-%m-%d"), tz = "UTC")
  offset <- as.numeric(difftime(min(times), day, units = "mins"))
  stamp <- if (abs(offset) < 0.5) "start" else if (abs(offset - 15) < 0.5) "end" else "unknown"
  # A layer stamped 00:00 with end stamps is the previous day's last; tell apart by the last
  # layer: start stamps end at 23:45, end stamps at 24:00 (the next day's 00:00).
  if (stamp == "start" && length(times) > 1 &&
      abs(as.numeric(difftime(max(times), day, units = "mins")) - 1440) < 0.5) {
    stamp <- "end"
  }
  att <- function(a) ncdf4::ncatt_get(nc, name, a)
  data.frame(
    file = path, variable = name, units = v$units %||% "",
    dimensions = paste(dims, collapse = ", "),
    cell_x = if (length(xv) > 1) abs(stats::median(diff(xv))) else NA_real_,
    cell_y = if (length(yv) > 1) abs(stats::median(diff(yv))) else NA_real_,
    x_offset = round(min(xv) %% 1000), y_offset = round(min(yv) %% 1000),
    y_order = if (length(yv) > 1 && yv[2] < yv[1]) "north to south" else "south to north",
    time_units = ncdf4::ncatt_get(nc, "time", "units")$value,
    step_minutes = if (length(times) > 1) {
      stats::median(as.numeric(diff(times), units = "mins"))
    } else NA_real_,
    stamp = stamp, scaled = isTRUE(att("scale_factor")$hasatt) || isTRUE(att("add_offset")$hasatt),
    layers = length(times), first_time = min(times),
    stringsAsFactors = FALSE)
}

# The factor that turns a unit into mm per 15-minute step: 1 for a depth in mm, 0.25 for a
# rate in mm per hour, NA for anything else.
.h19_unit_factor <- function(units) {
  u <- tolower(gsub("\\s+", " ", trimws(units %||% "")))
  if (u %in% c("mm", "millimetres", "millimeters", "mm/15min", "mm per 15 minutes")) return(1)
  if (u %in% c("mm/h", "mm/hr", "mm h-1", "mm hr-1", "mm/hour", "mm per hour")) return(0.25)
  NA_real_
}
