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
#'
#' @return A list of class `pdm_h19` with `grid` (cell-centre `x` and `y`, both increasing),
#'   `time` (the time of every step, POSIXct in UTC), `radar` (a function of the step number
#'   returning that step's grid, mm, as a matrix of `length(grid$x)` rows by `length(grid$y)`
#'   columns) and `index` (the file and layer of every step).
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
h19_radar <- function(files, extent, varname = NULL, fallback_crs = "EPSG:27700") {
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
    cache$values[, , index$layer[t]]
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
