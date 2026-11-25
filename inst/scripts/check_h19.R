# ============================================================ #
# Tool:         check_h19
# Description:  A quick look at H19 radar: the files' layouts, the rain at a point through
#               time, the catchment average over a polygon, and a map of the total, with the
#               changes of layout marked so a jump at a change shows
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-25
# Modified:     2026-11-25 - the polygon from a shapefile
# Tier:         1
# Inputs:       A folder of daily H19 NetCDF files; a point in metres on British National Grid;
#               a polygon (a shapefile, GeoPackage, or CSV of x and y)
# Outputs:      A folder: h19_layouts.csv, point and catchment series (CSV), and three plots
# Dependencies: pdmS7 (0.43.0 or later), ncdf4, data.table; sf for a shapefile
# ============================================================ #
#
# How to use it
#   Copy the script to your own folder, so you can fill in its settings:
#     file.copy(system.file("scripts", "check_h19.R", package = "pdmS7"), "check_h19.R")
#     file.edit("check_h19.R")
#   Fill in the settings and run the whole script (Ctrl+Shift+S in RStudio). A few months take
#   seconds; ten years take ten minutes or so. H19 is restricted: put the output folder on
#   restricted storage.

library(pdmS7)
library(data.table)

# ---- Settings: fill these in -------------------------------------------------------------

radar_folder <- "C:/.../04_RADAR/01_H19"   # holding a folder for each year: 2010, 2011, ...
# H19 file names: the date and time (14 digits), anything, then .nc. This matches both the
# older 20101201000000_u1024_ng_radar_15min_advect_accum_1km_H19.nc and the newer
# 20210401000000.nc.
radar_pattern <- "^[0-9]{14}.*\\.nc$"
from <- "2010-12-01"                        # first day (inclusive)
to <- "2011-01-01"                          # last day (exclusive)

point <- c(x = 426784, y = 241058)          # British National Grid metres
point_name <- "Shipston gauge"

boundary_file <- "catchment.shp"            # a shapefile or GeoPackage, or a CSV with columns
                                            # x and y; NULL for the point only
output_folder <- "h19_check"

# ---- The files and their layouts ----------------------------------------------------------

say <- function(...) cat(sprintf(...), "\n", sep = "")
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)
# Only the year folders of the period, and their month folders: not other folders beside them
# (processed products, polygons) nor zips. Without year folders, the whole folder is searched.
years <- seq(as.integer(substr(from, 1, 4)), as.integer(format(as.Date(to) - 1, "%Y")))
year_dirs <- file.path(radar_folder, years)
year_dirs <- year_dirs[dir.exists(year_dirs)]
files <- list.files(if (length(year_dirs)) year_dirs else radar_folder, pattern = radar_pattern,
                    recursive = TRUE, full.names = TRUE)
day <- as.Date(substr(basename(files), 1, 8), "%Y%m%d")
files <- files[!is.na(day) & day >= as.Date(from) & day < as.Date(to)]
if (!length(files)) {
  stop("No files matching ", radar_pattern, " from ", from, " to ", to, " in ", radar_folder,
       ". The script reads each file's date from the first eight digits of its name.",
       call. = FALSE)
}
layouts <- h19_layouts(files)
print(layouts)
fwrite(layouts$layouts, file.path(output_folder, "h19_layouts.csv"))
bad <- layouts$layouts[nzchar(layouts$layouts$problems), ]
if (nrow(bad)) {
  stop("Layout problems: ", paste(sprintf("%d (%s to %s): %s", bad$layout, bad$first_day,
                                          bad$last_day, bad$problems), collapse = "; "),
       call. = FALSE)
}
# The days a new layout starts, to mark on the plots.
changes <- as.POSIXct(layouts$layouts$first_day[-1], tz = "UTC")

# ---- Read the radar ---------------------------------------------------------------------

boundary <- if (!is.null(boundary_file)) read_boundary(boundary_file)
px <- c(point[["x"]], boundary$x)
py <- c(point[["y"]], boundary$y)
extent <- c(min(px) - 3000, max(px) + 3000, min(py) - 3000, max(py) + 3000)
h <- h19_radar(files, extent, layouts = layouts)
i <- which.min(abs(h$grid$x - point[["x"]]))
j <- which.min(abs(h$grid$y - point[["y"]]))
if (abs(h$grid$x[i] - point[["x"]]) > 500 || abs(h$grid$y[j] - point[["y"]]) > 500) {
  stop("The point is outside the radar grid.", call. = FALSE)
}
inside <- if (!is.null(boundary)) catchment_mask(h$grid$x, h$grid$y, boundary)
if (!is.null(inside) && !any(inside)) {
  stop("No radar cell centre falls inside the polygon: check its coordinates.", call. = FALSE)
}
say("Reading %d steps from %d files", length(h$time), length(files))
total <- matrix(0, length(h$grid$x), length(h$grid$y))
missing <- total
series <- t(vapply(seq_along(h$time), function(s) {
  r <- h$radar(s)
  r[r < 0] <- NA
  total <<- total + ifelse(is.na(r), 0, r)
  missing <<- missing + is.na(r)
  c(point = r[i, j],
    point_3x3 = mean(r[max(1, i - 1):min(nrow(r), i + 1), max(1, j - 1):min(ncol(r), j + 1)],
                     na.rm = TRUE),
    catchment = if (!is.null(inside)) mean(r[inside]) else NA_real_)
}, numeric(3)))
skipped <- h$skipped()
if (nrow(skipped)) {
  fwrite(skipped, file.path(output_folder, "h19_skipped_files.csv"))
  say("%d files could not be read and were skipped (their steps are missing): see",
      nrow(skipped))
  say("h19_skipped_files.csv")
}
out <- data.table(time = h$time, series)
fwrite(out[, .(time = format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC"), point, point_3x3,
               catchment)], file.path(output_folder, "h19_series.csv"))

# ---- Plots -----------------------------------------------------------------------------

png_of <- function(name, draw, width = 1600, height = 900) {
  grDevices::png(file.path(output_folder, name), width = width, height = height, res = 150)
  on.exit(grDevices::dev.off())
  draw()
}
long <- as.numeric(difftime(max(h$time), min(h$time), units = "days")) > 60
# Rain as bars (15-minute steps for a short period, daily totals for a long one) above its
# cumulative total, with the changes of layout as dashed lines.
draw_series <- function(v, title) {
  graphics::par(mfrow = c(2, 1), mar = c(2, 4.5, 2, 1))
  if (long) {
    d <- as.Date(h$time)
    daily <- tapply(v, d, function(x) if (all(is.na(x))) NA else sum(x, na.rm = TRUE))
    graphics::plot(as.POSIXct(names(daily), tz = "UTC"), daily, type = "h", lwd = 2,
                   col = "#1B6F80", xlab = "", ylab = "Rain (mm a day)", main = title)
  } else {
    graphics::plot(h$time, v, type = "h", col = "#1B6F80", xlab = "",
                   ylab = "Rain (mm per 15 min)", main = title)
  }
  graphics::abline(v = changes, lty = 2, col = "#B3261E")
  graphics::plot(h$time, cumsum(ifelse(is.na(v), 0, v)), type = "l", lwd = 2, col = "#13212E",
                 xlab = "", ylab = "Cumulative (mm)")
  graphics::abline(v = changes, lty = 2, col = "#B3261E")
}

# HOW TO READ h19_point.png
# The radar rain in the 1 km cell holding the point: bars above (15-minute steps, or daily
# totals over more than 60 days), the running total below. Dashed red lines mark where the
# files change layout.
# Good: storms as clusters of bars, dry spells flat, the running total rising in steps with no
#   change of slope at a dashed line.
# Worry if: the running total changes slope at a dashed line (a layout handled wrongly: the
#   units, or the time stamp); bars four times larger, or smaller, after a change (a rate read
#   as a depth); a run of zeros or a gap when it rained elsewhere (missing radar).
png_of("h19_point.png", function() {
  draw_series(out$point, sprintf("H19 radar at %s (%.0f, %.0f)", point_name, point[["x"]],
                                 point[["y"]]))
})

if (!is.null(inside)) {
  # HOW TO READ h19_catchment.png
  # The same for the mean of the radar cells whose centres fall inside the polygon (their
  # number is in the title). A catchment average is smoother than a point: storms that miss
  # the point still show here.
  # Good: as for the point, and the catchment's total close to the point's over a long period.
  # Worry if: a change of slope at a dashed line; gaps (a step counts only when every cell
  #   inside has radar); a total far from the point's over months (the point unrepresentative,
  #   or the polygon in the wrong place: check h19_total_map.png).
  png_of("h19_catchment.png", function() {
    draw_series(out$catchment, sprintf("H19 radar, catchment average over %d cells",
                                       sum(inside)))
  })
}

# HOW TO READ h19_total_map.png
# The radar total over the whole period in each 1 km cell, darker for more rain, with the
# polygon outlined and the point marked. Cells missing for more than a tenth of the steps are
# grey.
# Good: a smooth pattern, more rain on high ground, the polygon and point where you expect them.
# Worry if: straight lines or rings (radar artefacts: beam blockage, range), a polygon or point
#   in the wrong place (coordinates in the wrong system, x and y swapped), or many grey cells.
png_of("h19_total_map.png", function() {
  shown <- total
  shown[missing > 0.1 * length(h$time)] <- NA
  graphics::par(mar = c(4, 4.5, 2, 6))
  graphics::image(h$grid$x, h$grid$y, shown, col = grDevices::hcl.colors(30, "Blues", rev = TRUE),
                  asp = 1, xlab = "Easting (m)", ylab = "Northing (m)",
                  main = sprintf("H19 total, %s to %s (mm)", from, to))
  if (any(is.na(shown))) {
    graphics::image(h$grid$x, h$grid$y, ifelse(is.na(shown), 1, NA), col = "grey70", add = TRUE)
  }
  if (!is.null(boundary)) graphics::polygon(boundary$x, boundary$y, border = "#B3261E", lwd = 2)
  graphics::points(point[["x"]], point[["y"]], pch = 21, bg = "#E3A51C", cex = 1.6)
  range_mm <- range(shown, na.rm = TRUE)
  graphics::legend("topright", inset = c(-0.12, 0), xpd = TRUE, bty = "n", title = "mm",
                   legend = round(seq(range_mm[1], range_mm[2], length.out = 5)),
                   fill = grDevices::hcl.colors(5, "Blues", rev = TRUE))
})

# ---- In brief ----------------------------------------------------------------------------

say("\n%s to %s, %d steps of 15 minutes", format(min(h$time), "%Y-%m-%d %H:%M"),
    format(max(h$time), "%Y-%m-%d %H:%M"), length(h$time))
say("At %s: total %.1f mm, wettest 15 minutes %.1f mm, %.1f%% of steps missing", point_name,
    sum(out$point, na.rm = TRUE), max(out$point, na.rm = TRUE), 100 * mean(is.na(out$point)))
if (!is.null(inside)) {
  say("Catchment average (%d cells): total %.1f mm, %.1f%% of steps missing", sum(inside),
      sum(out$catchment, na.rm = TRUE), 100 * mean(is.na(out$catchment)))
}
say("Written to %s", normalizePath(output_folder))
