# ============================================================ #
# Tool:         lta_grid
# Description:  Reads a long-term average rainfall grid (such as the Met Office's HadUK-Grid
#               30-year average, 1991 to 2020) from NetCDF, for a window, and looks up values
#               at points
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-26
# Tier:         1
# Inputs:       A NetCDF grid on British National Grid (metres), mm a year
# Outputs:      The grid's cell centres and values; values at points
# Dependencies: ncdf4 (suggested)
# ============================================================ #

#' Read a long-term average rainfall grid
#'
#' Reads a grid of average annual rainfall from NetCDF, such as the Met Office's HadUK-Grid
#' 30-year average (`rainfall_hadukgrid_uk_1km_ann-30y_199101-202012.nc`), keeping only the
#' cells whose centres fall in `extent`. Such a grid gives a catchment's long-term rainfall
#' pattern: where it is usually wetter or drier between the gauges.
#'
#' **The file.** The grid must be on British National Grid in metres. The two grid dimensions
#' are found by name (`projection_x_coordinate` and `projection_y_coordinate`, or `x` and
#' `y`, or any name with `east`/`north`); a time dimension, if there is one, must have one
#' layer. The variable is `varname`, or else the one variable on the grid's dimensions, `rainfall`
#' first. Its units must be mm (a year); fill values become `NA`.
#'
#' **What it is not.** A grid made from gauges, as HadUK-Grid is, is not independent of the
#' gauges compared with it, and is not corrected for undercatch.
#'
#' @param path Path of the NetCDF file.
#' @param extent Optional `c(xmin, xmax, ymin, ymax)` in metres: only cells whose centres lie
#'   inside are read. `NULL` reads the whole grid.
#' @param varname Optional name of the rainfall variable.
#' @return A list of class `pdm_lta_grid` with `x` and `y` (cell centres, increasing), `values`
#'   (mm a year, a matrix of `length(x)` rows by `length(y)` columns), `cell` (metres) and
#'   `variable`.
#' @examples
#' \dontrun{
#' lta <- read_lta_grid("rainfall_hadukgrid_uk_1km_ann-30y_199101-202012.nc",
#'                      extent = c(440000, 470000, 355000, 385000))
#' lta_at(lta, 455850, 368050)
#' }
#' @seealso [lta_at()], [merge_rainfall()]
#' @export
read_lta_grid <- function(path, extent = NULL, varname = NULL) {
  .check(requireNamespace("ncdf4", quietly = TRUE), "Reading the grid needs the ncdf4 package")
  .check(is.character(path) && length(path) == 1 && file.exists(path),
         paste("Cannot find the grid file", path))
  .check(is.null(extent) || (is.numeric(extent) && length(extent) == 4 &&
                               extent[1] < extent[2] && extent[3] < extent[4]),
         "extent must be c(xmin, xmax, ymin, ymax)")
  nc <- ncdf4::nc_open(path)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  is_x <- function(n) grepl("^(projection_x_coordinate|x|easting)$|east", tolower(n))
  is_y <- function(n) grepl("^(projection_y_coordinate|y|northing)$|north", tolower(n))
  on_grid <- function(v) {
    d <- vapply(v$dim, function(k) k$name, "")
    any(is_x(d)) && any(is_y(d))
  }
  candidates <- names(nc$var)[vapply(nc$var, on_grid, logical(1))]
  if (is.null(varname)) {
    .check(length(candidates) > 0, paste("No variable on an x and y grid in", basename(path)))
    varname <- if ("rainfall" %in% candidates) "rainfall" else candidates[1]
  }
  .check(varname %in% names(nc$var), paste("No variable", varname, "in", basename(path)))
  v <- nc$var[[varname]]
  dims <- vapply(v$dim, function(k) k$name, "")
  xa <- which(is_x(dims))[1]
  ya <- which(is_y(dims))[1]
  .check(!is.na(xa) && !is.na(ya), paste(varname, "is not on an x and y grid"))
  others <- setdiff(seq_along(dims), c(xa, ya))
  .check(all(vapply(v$dim[others], function(k) k$len, numeric(1)) == 1),
         paste(varname, "has more than one layer: give a single long-term average"))
  units <- tolower(v$units %||% "")
  .check(grepl("^mm", units), paste0(varname, " is in '", v$units, "', not mm"))
  xv <- as.numeric(v$dim[[xa]]$vals)
  yv <- as.numeric(v$dim[[ya]]$vals)
  xi <- if (is.null(extent)) seq_along(xv) else which(xv >= extent[1] & xv <= extent[2])
  yj <- if (is.null(extent)) seq_along(yv) else which(yv >= extent[3] & yv <= extent[4])
  .check(length(xi) > 0 && length(yj) > 0,
         paste("No cells of", basename(path), "fall inside the extent"))
  start <- rep(1L, length(dims))
  count <- rep(1L, length(dims))
  start[xa] <- min(xi)
  count[xa] <- max(xi) - min(xi) + 1L
  start[ya] <- min(yj)
  count[ya] <- max(yj) - min(yj) + 1L
  a <- ncdf4::ncvar_get(nc, varname, start = start, count = count, collapse_degen = FALSE)
  a <- array(a, dim = count)
  m <- matrix(aperm(a, c(xa, ya, others)), nrow = count[xa], ncol = count[ya])
  x <- xv[min(xi):max(xi)]
  y <- yv[min(yj):max(yj)]
  if (length(x) > 1 && x[2] < x[1]) {
    m <- m[rev(seq_along(x)), , drop = FALSE]
    x <- rev(x)
  }
  if (length(y) > 1 && y[2] < y[1]) {
    m <- m[, rev(seq_along(y)), drop = FALSE]
    y <- rev(y)
  }
  m[!is.finite(m) | m < 0 | m > 1e5] <- NA
  structure(list(x = x, y = y, values = m,
                 cell = if (length(x) > 1) diff(x[1:2]) else NA_real_, variable = varname),
            class = "pdm_lta_grid")
}

#' Long-term average rainfall at points
#'
#' The value of a long-term average grid in the cell holding each point (the nearest cell
#' centre); `NA` for a point more than half a cell outside the grid.
#'
#' @param lta A grid from [read_lta_grid()].
#' @param x,y The points' coordinates, metres on British National Grid.
#' @return mm a year, one value per point.
#' @seealso [read_lta_grid()]
#' @export
lta_at <- function(lta, x, y) {
  .check(inherits(lta, "pdm_lta_grid"), "lta must come from read_lta_grid()")
  .check(is.numeric(x) && is.numeric(y) && length(x) == length(y),
         "x and y must be numbers of the same length")
  half <- if (is.finite(lta$cell)) lta$cell / 2 else Inf
  vapply(seq_along(x), function(k) {
    i <- which.min(abs(lta$x - x[k]))
    j <- which.min(abs(lta$y - y[k]))
    if (abs(lta$x[i] - x[k]) > half || abs(lta$y[j] - y[k]) > half) NA_real_ else
      lta$values[i, j]
  }, numeric(1))
}

#' @export
print.pdm_lta_grid <- function(x, ...) {
  cat(sprintf("Long-term average rainfall (%s): %d by %d cells of %g m, %.0f to %.0f mm a year\n",
              x$variable, length(x$x), length(x$y), x$cell,
              min(x$values, na.rm = TRUE), max(x$values, na.rm = TRUE)))
  invisible(x)
}
