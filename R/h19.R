# ============================================================ #
# Tool:         h19
# Description:  Reads gridded H19 radar from daily NetCDF files, one 15-minute grid at a time,
#               for merge_rainfall(), and checks how the files were saved
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-25 - h19_layouts(); h19_radar(layouts = ); read with ncdf4, one open
#               per file and only the window needed, in place of terra; the layout scan
#               samples a file a month and bisects to each change; a file that will not
#               read is skipped, its steps NA, not the end of the run; h19_processed()
#               reads a polygon from the team's processed yearly Parquet extracts
# Tier:         1
# Inputs:       Daily H19 NetCDF files (British National Grid), an extent in metres
# Outputs:      The cropped grid, the times of every layer, a reader for one step's grid, and
#               the files' layouts
# Dependencies: ncdf4 (suggested); arrow or nanoparquet (suggested, for the extracts)
# ============================================================ #

#' Gridded H19 radar for merging with gauges
#'
#' H19 radar comes as daily NetCDF files, each holding that day's 15-minute accumulations on
#' British National Grid, in year and month folders. Sixteen years of it will not fit in memory
#' at once. `h19_radar()` indexes the files, reads from each only the window of cells around the
#' catchment and its gauges, and returns a reader that gives one step's grid when asked,
#' loading each daily file once as the steps are read in order. Pass its `radar` and `grid` to
#' [merge_rainfall()].
#'
#' **Speed.** Each file is opened once, when its first step is asked for, and its window of
#' cells for every layer is read in one call. On a network drive most of the time goes on
#' opening files: copying the period wanted to a local disk first is often quicker overall.
#'
#' **Variable names.** The archive uses `"radar rain-accum H19"` for 2010 to 2019 and
#' `"rainfall_radar_amount"` from 1 January 2020, when its files were also renamed from
#' `..._1km_H19.nc` to the date alone, such as `20200101000000.nc`; the units (mm), grid and
#' time stamps (the start of each step) are the same either side. By default each file's
#' variable is found among these;
#' name another with `varname`.
#'
#' **Times.** Without `layouts`, each file is opened once at the start to read its times, from
#' its `time` variable and units (such as `"minutes since 1970-01-01 00:00:00"`, in UTC), as
#' they stand: check whether they mark the start or the end of each accumulation. With
#' `layouts` from [h19_layouts()], no file is opened at the start: each day's 96 steps are
#' taken from the date at the start of its file name, at the start of each step, and when the
#' file is read its own times, moved by its layout, are matched to those steps. A step the
#' file does not hold is `NA`.
#'
#' **Extent.** A box that holds the catchment and the gauges used with it, with a margin: the
#' merged field needs radar at every gauge. The cells whose centres fall in the box are read.
#' Cells with no radar value are `NA`, and a merged step that needs one is `NA`.
#'
#' @param files Paths of the daily NetCDF files, in any order; they are sorted by time.
#' @param extent Numeric `c(xmin, xmax, ymin, ymax)` in British National Grid metres.
#' @param varname Name of the radar variable; by default found in each file among the H19 names.
#' @param fallback_crs Kept for compatibility; not used. The grid is read in the files' own
#'   coordinates, British National Grid metres.
#' @param layouts Optional result of [h19_layouts()] for these files. Given it, each file's
#'   times are moved to the start of their step and its values put in mm per step, by the
#'   file's own layout: an archive whose time stamp changed part way through would otherwise
#'   put the last step before the change and the first after it at the same time. Without it,
#'   times and values are as the files hold them.
#'
#' @return A list of class `pdm_h19` with `grid` (cell-centre `x` and `y`, both increasing),
#'   `time` (the time of every step, POSIXct in UTC), `radar` (a function of the step number
#'   returning that step's grid, mm, as a matrix of `length(grid$x)` rows by `length(grid$y)`
#'   columns), `index` (the file and unit factor of every step) and `skipped` (a function
#'   returning the files skipped so far, with the reason, as a data frame).
#'
#'   A file that cannot be read over the extent (its grid elsewhere or of another size, or the
#'   file damaged) does not end the run: a message names it, its steps are `NA`, and it is
#'   listed by `skipped()`. The grid is taken from the first file that reads.
#' @examples
#' \dontrun{
#' files <- list.files("F:/.../01_H19", pattern = "\\.nc$", recursive = TRUE, full.names = TRUE)
#' h19 <- h19_radar(files, extent = c(290000, 330000, 120000, 160000),
#'                  layouts = h19_layouts(files))
#' mask <- catchment_mask(h19$grid$x, h19$grid$y, boundary)
#' merged <- merge_rainfall(gauges, gauge_rain, h19$grid, mask, radar = h19$radar,
#'                          method = "conditional")
#' }
#' @seealso [h19_layouts()], [merge_rainfall()], [catchment_mask()]
#' @export
h19_radar <- function(files, extent, varname = NULL, fallback_crs = "EPSG:27700",
                      layouts = NULL) {
  .check(requireNamespace("ncdf4", quietly = TRUE), "Reading H19 needs the ncdf4 package")
  .check(is.character(files) && length(files) > 0 && all(file.exists(files)),
         "files must be paths of existing NetCDF files")
  .check(is.numeric(extent) && length(extent) == 4L && extent[1] < extent[2] &&
           extent[3] < extent[4], "extent must be c(xmin, xmax, ymin, ymax)")
  shift <- stats::setNames(rep(0, length(files)), files)
  factor <- stats::setNames(rep(1, length(files)), files)
  if (!is.null(layouts)) {
    .check(inherits(layouts, "pdm_h19_layouts"), "layouts must come from h19_layouts()")
    at <- match(files, layouts$files$file)
    .check(!anyNA(at), "layouts must describe every one of files")
    .check(!anyNA(layouts$files$factor[at]), "layouts has files with units it cannot convert")
    shift[] <- layouts$files$shift_minutes[at] * 60
    factor[] <- layouts$files$factor[at]
  }
  day <- as.POSIXct(as.Date(substr(basename(files), 1, 8), "%Y%m%d"))
  attr(day, "tzone") <- "UTC"
  from_names <- !is.null(layouts) & !is.na(day)
  # The steps: from the file names (each day's 96 starts) where layouts are given and the name
  # carries a date; otherwise from each file's own times.
  index <- do.call(rbind, lapply(seq_along(files), function(k) {
    t <- if (from_names[k]) day[k] + 900 * (0:95) else .nc_times(files[k]) - shift[k]
    data.frame(file = files[k], time = t, factor = factor[[k]])
  }))
  index <- index[order(index$time, index$file), ]
  rownames(index) <- NULL
  .check(!anyDuplicated(index$time), "Two files hold layers at the same time")
  state <- new.env(parent = emptyenv())
  state$file <- ""
  state$skipped <- data.frame(file = character(0), reason = character(0))
  skip <- function(path, reason) {
    message("Skipping ", basename(path), ": ", reason, "; its steps are NA")
    state$skipped <- rbind(state$skipped, data.frame(file = path, reason = reason))
  }
  # The grid comes from the first file that reads; a file that will not read (no cells in the
  # extent, a different grid, damaged) is skipped, its steps NA, rather than ending the run.
  first <- NULL
  for (path in unique(index$file)) {
    first <- tryCatch(.h19_window(path, varname, extent), error = function(e) {
      skip(path, conditionMessage(e))
      NULL
    })
    if (!is.null(first)) break
  }
  .check(!is.null(first), paste0("None of the H19 files could be read over the extent; ",
                                 basename(state$skipped$file[1]), ": ",
                                 state$skipped$reason[1]))
  first_file <- path
  load <- function(path) {
    w <- if (identical(path, first_file) && is.null(state$seen_first)) first else
      tryCatch(.h19_window(path, varname, extent), error = function(e) {
        skip(path, conditionMessage(e))
        NULL
      })
    state$seen_first <- TRUE
    if (!is.null(w) && !(identical(w$x, first$x) && identical(w$y, first$y))) {
      skip(path, paste0("its grid differs from that of ", basename(first_file)))
      w <- NULL
    }
    rows <- which(index$file == path)
    state$file <- path
    if (is.null(w)) {
      state$values <- NULL
      state$layer <- stats::setNames(rep(NA_integer_, length(rows)), rows)
      return(invisible())
    }
    times <- round(as.numeric(w$time - shift[[path]]))
    state$values <- w$values
    state$layer <- stats::setNames(match(round(as.numeric(index$time[rows])), times), rows)
  }
  reader <- function(t) {
    .check(.whole(t, 1, nrow(index)), "No such step")
    if (!identical(state$file, index$file[t])) load(index$file[t])
    layer <- state$layer[[as.character(t)]]
    if (is.na(layer)) return(matrix(NA_real_, length(first$x), length(first$y)))
    state$values[, , layer] * index$factor[t]
  }
  structure(list(grid = list(x = first$x, y = first$y), time = index$time, radar = reader,
                 index = index, skipped = function() state$skipped), class = "pdm_h19")
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
  .nc_times_of(nc)
}

.nc_times_of <- function(nc) {
  values <- as.numeric(ncdf4::ncvar_get(nc, "time"))
  units <- ncdf4::ncatt_get(nc, "time", "units")$value
  .check(is.character(units) && grepl(" since ", units), paste("No time units in", nc$filename))
  unit <- tolower(sub(" since .*", "", units))
  origin <- as.POSIXct(sub("^.* since ", "", units), tz = "UTC",
                       tryFormats = c("%Y-%m-%d %H:%M:%OS", "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M",
                                      "%Y-%m-%d"))
  seconds <- switch(unit, seconds = 1, minutes = 60, hours = 3600, days = 86400,
                    .check(FALSE, paste("Unknown time unit", unit, "in", nc$filename)))
  origin + values * seconds
}

# The radar variable in an open file: the given name, or the first of the H19 names it holds.
.h19_variable_of <- function(nc, varname = NULL) {
  if (!is.null(varname)) {
    .check(varname %in% names(nc$var), paste("No variable", varname, "in", basename(nc$filename)))
    return(varname)
  }
  known <- c("rainfall_radar_amount", "radar rain-accum H19")
  hit <- intersect(known, names(nc$var))
  .check(length(hit) > 0, paste0("No H19 variable in ", basename(nc$filename), "; it holds ",
                                 toString(names(nc$var)), ". Name it with varname"))
  hit[1]
}

# Which of a variable's dimensions are x, y and time, with the grid's coordinates.
.h19_axes <- function(nc, name) {
  v <- nc$var[[name]]
  dim_names <- vapply(v$dim, function(d) d$name, "")
  is_time <- vapply(v$dim, function(d) grepl(" since ", d$units %||% ""), logical(1)) |
    tolower(dim_names) == "time"
  space <- which(!is_time)
  .check(length(space) == 2 && sum(is_time) == 1,
         paste("Expected two grid dimensions and one of time in", basename(nc$filename),
               "; it has", toString(dim_names)))
  is_y <- grepl("^y$|north|projection_y|lat", tolower(dim_names[space]))
  y_at <- if (any(is_y)) space[is_y][1] else space[2]
  x_at <- setdiff(space, y_at)
  list(x = x_at, y = y_at, t = which(is_time), names = dim_names,
       xv = v$dim[[x_at]]$vals, yv = v$dim[[y_at]]$vals)
}

# One file's cells inside the extent, every layer, read in one call: an array of columns (x
# increasing) by rows (y increasing) by layers, with the cell centres and the layer times.
.h19_window <- function(path, varname, extent) {
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  name <- .h19_variable_of(nc, varname)
  ax <- .h19_axes(nc, name)
  xi <- which(ax$xv >= extent[1] & ax$xv <= extent[2])
  yj <- which(ax$yv >= extent[3] & ax$yv <= extent[4])
  .check(length(xi) > 0 && length(yj) > 0,
         paste("No cells of", basename(path), "fall inside the extent"))
  start <- rep(1L, 3)
  count <- rep(-1L, 3)
  start[ax$x] <- min(xi)
  count[ax$x] <- length(xi)
  start[ax$y] <- min(yj)
  count[ax$y] <- length(yj)
  a <- ncdf4::ncvar_get(nc, name, start = start, count = count, collapse_degen = FALSE)
  a <- aperm(a, c(ax$x, ax$y, ax$t))
  x <- ax$xv[min(xi):max(xi)]
  y <- ax$yv[min(yj):max(yj)]
  if (length(x) > 1 && x[2] < x[1]) {
    a <- a[rev(seq_along(x)), , , drop = FALSE]
    x <- rev(x)
  }
  if (length(y) > 1 && y[2] < y[1]) {
    a <- a[, rev(seq_along(y)), , drop = FALSE]
    y <- rev(y)
  }
  list(x = as.numeric(x), y = as.numeric(y), values = a, time = .nc_times_of(nc))
}

#' The layouts of a set of H19 files
#'
#' The H19 archive was not written the same way throughout: the radar variable was renamed on
#' 1 January 2020, and a change of time stamp, units or grid would shift or scale part of a record
#' without any error. `h19_layouts()` reads the headers of the files (no radar values), groups
#' the files by layout, and checks each layout before any radar is used.
#'
#' **Sampling.** A layout changes rarely, so by default (`every = "month"`) the first file of
#' each month and the last file are read, and wherever two neighbouring samples differ, the
#' files between them are bisected to find the first of the new layout: ten years take about
#' 130 headers, not 3,650, and each change is still found to the day. Every other file is given
#' the layout of the last file read before it. A layout that came and went within a month
#' between samples would be missed: `every = "file"` reads every header. Files whose names do
#' not start with a date (`YYYYMMDD`) are all read.
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
#' @param every `"month"` (the default) to read a file a month and bisect to each change, or
#'   `"file"` to read every file's header.
#' @return A list of class `pdm_h19_layouts`: `layouts`, one row per layout (its fields, the
#'   number of files, the first and last day, and `problems`, empty when it passes); `files`,
#'   one row per file with its layout number, whether its header was read (`checked`),
#'   `shift_minutes` (to subtract from its times so each marks the start of its step) and
#'   `factor` (to multiply its values by, to give mm per step); and `checked`, the number of
#'   headers read.
#' @examples
#' \dontrun{
#' files <- list.files("F:/.../01_H19", pattern = "\\.nc$", recursive = TRUE, full.names = TRUE)
#' layouts <- h19_layouts(files)
#' layouts
#' }
#' @seealso [h19_radar()]
#' @export
h19_layouts <- function(files, every = c("month", "file")) {
  every <- match.arg(every)
  .check(requireNamespace("ncdf4", quietly = TRUE), "Reading H19 needs the ncdf4 package")
  .check(is.character(files) && length(files) > 0 && all(file.exists(files)),
         "files must be paths of existing NetCDF files")
  keys <- c("variable", "units", "dimensions", "cell_x", "cell_y", "x_offset", "y_offset",
            "y_order", "time_units", "step_minutes", "stamp", "scaled")
  day <- as.Date(substr(basename(files), 1, 8), "%Y%m%d")
  ord <- if (anyNA(day)) seq_along(files) else order(day, files)
  files <- files[ord]
  day <- day[ord]
  headers <- vector("list", length(files))
  key_of <- function(i) {
    if (is.null(headers[[i]])) headers[[i]] <<- .h19_header(files[i])
    do.call(paste, c(headers[[i]][keys], sep = "\r"))
  }
  if (every == "file" || anyNA(day)) {
    for (i in seq_along(files)) key_of(i)
  } else {
    month <- format(day, "%Y-%m")
    samples <- sort(unique(c(which(!duplicated(month)), length(files))))
    for (i in samples) key_of(i)
    # Between neighbouring samples that differ, bisect to the first file of the next layout,
    # and carry on from there in case more than one change falls between them.
    for (s in seq_len(length(samples) - 1)) {
      lo <- samples[s]
      hi <- samples[s + 1]
      while (key_of(lo) != key_of(hi)) {
        a <- lo
        b <- hi
        while (b - a > 1) {
          mid <- (a + b) %/% 2
          if (key_of(mid) == key_of(a)) a <- mid else b <- mid
        }
        lo <- b
      }
    }
  }
  read <- which(!vapply(headers, is.null, logical(1)))
  # Every file takes the layout of the last file read at or before it.
  source <- read[findInterval(seq_along(files), read)]
  checked <- do.call(rbind, headers[read])
  per_file <- checked[match(source, read), ]
  per_file$file <- files
  per_file$checked <- seq_along(files) %in% read
  unread <- !per_file$checked
  per_file$first_time[unread] <- as.POSIXct(day[unread])
  per_file$layers[unread] <- NA_integer_
  key <- do.call(paste, c(per_file[keys], sep = "\r"))
  per_file$layout <- match(key, unique(key))
  layouts <- do.call(rbind, lapply(split(per_file, per_file$layout), function(f) {
    row <- f[1, keys]
    row$layout <- f$layout[1]
    row$files <- nrow(f)
    row$first_day <- format(min(f$first_time), "%Y-%m-%d")
    row$last_day <- format(max(f$first_time), "%Y-%m-%d")
    row$short_days <- sum(!is.na(f$layers) & f$layers != 96)
    row$example_file <- f$file[f$checked][1]
    row
  }))
  layouts <- layouts[order(layouts$first_day), c("layout", "files", "first_day", "last_day",
                                                 keys, "short_days", "example_file")]
  rownames(layouts) <- NULL
  layouts$problems <- vapply(seq_len(nrow(layouts)), function(i) {
    l <- layouts[i, ]
    p <- c(
      if (is.na(l$cell_x) || is.na(l$cell_y)) {
        "no grid cell size: x or y holds fewer than two coordinates"
      } else if (abs(l$cell_x - 1000) > 1 || abs(l$cell_y - 1000) > 1) {
        sprintf("cells %g by %g m, not 1 km", l$cell_x, l$cell_y)
      },
      if (!isTRUE(abs(l$step_minutes - 15) < 0.5)) {
        sprintf("layers %s minutes apart, not 15", format(l$step_minutes))
      },
      if (is.na(.h19_unit_factor(l$units))) sprintf("units '%s' not understood", l$units),
      if (l$stamp == "unknown") "layers stamped neither at 00:00 nor at 00:15",
      if (!isTRUE(l$x_offset == layouts$x_offset[1] && l$y_offset == layouts$y_offset[1])) {
        "cell centres not aligned with the first layout's"
      })
    paste(p, collapse = "; ")
  }, character(1))
  per_file$shift_minutes <- ifelse(per_file$stamp == "end", 15, 0)
  per_file$factor <- vapply(per_file$units, .h19_unit_factor, numeric(1))
  rownames(per_file) <- NULL
  structure(list(layouts = layouts,
                 files = per_file[, c("file", "layout", "checked", "first_time", "layers",
                                      "shift_minutes", "factor")],
                 checked = length(read), every = every),
            class = "pdm_h19_layouts")
}

#' @export
print.pdm_h19_layouts <- function(x, ...) {
  l <- x$layouts
  cat(sprintf("H19 files: %d, in %d layout%s (headers read: %d%s)\n", sum(l$files), nrow(l),
              if (nrow(l) == 1) "" else "s", x$checked,
              if (identical(x$every, "month") && x$checked < sum(l$files)) {
                ", a file a month and each change bisected"
              } else ""))
  for (i in seq_len(nrow(l))) {
    cat(sprintf(paste("  %d. %d files, %s to %s: '%s' in %s; %s m cells, rows %s; layers %s",
                      "minutes apart, stamped at the %s of their step%s\n"), l$layout[i],
                l$files[i], l$first_day[i], l$last_day[i], l$variable[i], l$units[i],
                format(l$cell_x[i]), l$y_order[i], format(l$step_minutes[i]), l$stamp[i],
                if (nzchar(l$problems[i])) {
                  paste0(". PROBLEMS: ", l$problems[i], ". For example ", l$example_file[i])
                } else ""))
  }
  invisible(x)
}

# What one file's header says about its layout, from a single open.
.h19_header <- function(path) {
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  name <- .h19_variable_of(nc)
  v <- nc$var[[name]]
  ax <- .h19_axes(nc, name)
  xv <- ax$xv
  yv <- ax$yv
  times <- .nc_times_of(nc)
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
    dimensions = paste(ax$names, collapse = ", "),
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

#' H19 for a catchment from the processed yearly extracts
#'
#' The team's processing scripts (the ProcessingNetCDF repository) have already extracted H19
#' for every current PDM polygon, as one Parquet file a year,
#' `H19_YYYY_all_polygons.parquet`, in the archive's `Processed_Annual` folder: the
#' area-weighted mean rain over each polygon (Hyrad's IDs), mm per 15 minutes. Reading a
#' catchment from them takes seconds, where reading the daily NetCDF files with [h19_radar()]
#' takes hours over a network drive. `h19_processed()` reads the years spanning `from` to `to`,
#' keeps one polygon, and puts it on a complete 15-minute timeline, with `NA` for any step the
#' extracts lack.
#'
#' **Times** are as the extracts hold them, the start of each 15-minute step, in UTC (the
#' archive stamps both its layouts this way). A step held twice keeps its first value, with a
#' warning.
#'
#' **The polygon** is the one in Hyrad, not necessarily your own boundary: check the two
#' agree, or the averages are over different areas. An ID not in the extracts is refused,
#' naming the closest IDs that are.
#'
#' @param folder The folder holding `H19_YYYY_all_polygons.parquet`.
#' @param polygon_id The polygon's ID, as in Hyrad, such as `"02_10_Southern"`.
#' @param from,to The first and last times wanted (POSIXct, or text such as `"2015-10-01"`),
#'   in UTC; both included.
#' @return A data frame with `time` (POSIXct, UTC, every 15 minutes from `from` to `to`) and
#'   `rain` (mm per 15 minutes, `NA` where missing), with attribute `years_missing`, the years
#'   with no file.
#' @examples
#' \dontrun{
#' h19 <- h19_processed("F:/.../01_H19/Processed_Annual", "02_10_Southern",
#'                      "2015-10-01", "2024-09-30 23:45")
#' }
#' @seealso [h19_radar()]
#' @export
h19_processed <- function(folder, polygon_id, from, to) {
  .check(is.character(folder) && length(folder) == 1 && dir.exists(folder),
         paste("No folder", folder))
  .check(is.character(polygon_id) && length(polygon_id) == 1 && nzchar(polygon_id),
         "polygon_id must be one polygon's ID")
  from <- as.POSIXct(from, tz = "UTC")
  to <- as.POSIXct(to, tz = "UTC")
  .check(!is.na(from) && !is.na(to) && from <= to, "from must be a time no later than to")
  from <- as.POSIXct(ceiling(as.numeric(from) / 900) * 900, origin = "1970-01-01", tz = "UTC")
  to <- as.POSIXct(floor(as.numeric(to) / 900) * 900, origin = "1970-01-01", tz = "UTC")
  years <- seq(as.integer(format(from, "%Y", tz = "UTC")),
               as.integer(format(to, "%Y", tz = "UTC")))
  files <- file.path(folder, sprintf("H19_%d_all_polygons.parquet", years))
  have <- file.exists(files)
  .check(any(have), paste0("No H19_YYYY_all_polygons.parquet in ", folder, " for ",
                           min(years), " to ", max(years)))
  if (!all(have)) {
    warning("No processed H19 for ", toString(years[!have]), ": those steps are NA",
            call. = FALSE)
  }
  parts <- lapply(files[have], .h19_processed_polygon, polygon_id = polygon_id)
  found <- vapply(parts, is.data.frame, logical(1))
  if (!any(found)) {
    ids <- parts[[1]]
    near <- ids[order(utils::adist(tolower(polygon_id), tolower(ids)))]
    near <- near[seq_len(min(5, length(near)))]
    .check(FALSE, paste0("No polygon ", polygon_id, " in the processed H19 (", length(ids),
                         " polygons). The closest IDs: ", toString(near)))
  }
  got <- do.call(rbind, parts[found])
  got <- got[got$time >= from & got$time <= to, ]
  twice <- duplicated(got$time)
  if (any(twice)) {
    warning(sum(twice), " steps held twice in the processed H19: the first value kept",
            call. = FALSE)
    got <- got[!twice, ]
  }
  time <- seq(from, to, by = 900)
  out <- data.frame(time = time, rain = got$rain[match(as.numeric(time), as.numeric(got$time))])
  attr(out, "years_missing") <- years[!have]
  out
}

# One year's extract: the polygon's times and rain, or, when the polygon is not in it, the IDs
# it holds. With arrow, only the polygon's rows are read, filtered as the file is scanned;
# with nanoparquet, the three columns are read whole and then filtered.
.h19_processed_polygon <- function(path, polygon_id) {
  cols <- c("polygon_id", "time", "rain_accum_mm_15min")
  if (requireNamespace("arrow", quietly = TRUE)) {
    ds <- arrow::open_dataset(path)
    .check(all(cols %in% names(ds)), paste(basename(path), "needs columns", toString(cols)))
    keep <- arrow::Expression$field_ref("polygon_id") == arrow::Expression$scalar(polygon_id)
    d <- as.data.frame(arrow::Scanner$create(ds, projection = cols, filter = keep)$ToTable())
    if (!nrow(d)) {
      ids <- arrow::read_parquet(path, col_select = "polygon_id")$polygon_id
      return(sort(unique(as.character(ids))))
    }
  } else {
    .check(requireNamespace("nanoparquet", quietly = TRUE),
           "Reading Parquet needs the arrow or nanoparquet package: install.packages(\"arrow\")")
    d <- as.data.frame(nanoparquet::read_parquet(path, col_select = cols))
    .check(all(cols %in% names(d)), paste(basename(path), "needs columns", toString(cols)))
    in_it <- d$polygon_id == polygon_id
    if (!any(in_it)) return(sort(unique(as.character(d$polygon_id))))
    d <- d[in_it, ]
  }
  time <- d$time
  if (!inherits(time, "POSIXct")) time <- as.POSIXct(time, tz = "UTC")
  attr(time, "tzone") <- "UTC"
  data.frame(time = time, rain = as.numeric(d$rain_accum_mm_15min))
}
