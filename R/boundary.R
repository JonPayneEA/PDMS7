# ============================================================ #
# Tool:         boundary
# Description:  Reads a catchment boundary from a shapefile, GeoPackage or CSV onto British
#               National Grid, with its centroid and area; and the distance from points to it
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-25
# Tier:         1
# Inputs:       A boundary file: any polygon format sf reads, or a CSV of x and y
# Outputs:      The boundary's outer ring (x, y in metres), its centroid and area
# Dependencies: sf (suggested; not needed for a CSV)
# ============================================================ #

#' Read a catchment boundary
#'
#' Reads a catchment boundary and returns its outer ring in metres on British National Grid,
#' ready for [catchment_mask()], with the centroid and area as attributes.
#'
#' **Formats.** A `.csv` or `.txt` file needs columns `x` and `y`: the corners in order, in
#' metres on British National Grid. Anything else (a shapefile `.shp`, a GeoPackage `.gpkg`,
#' GeoJSON) is read with sf and moved onto British National Grid (EPSG:27700). A file with no
#' coordinate reference system is taken to be on British National Grid already, with a
#' message.
#'
#' **Several polygons.** Every feature in the file is merged. If the result is in several
#' parts (an island, a detached piece), the largest part is kept, with a message giving the
#' share of the area dropped. Holes are ignored: the outer ring alone bounds the catchment.
#'
#' **Centroid and area.** Both come from the ring returned, by the shoelace formula, so they
#' match what [catchment_mask()] sees. The centroid of a strongly bent catchment can fall
#' outside it; it is still the centre of the catchment's area.
#'
#' @param path Path of the boundary file.
#' @return A data frame with columns `x` and `y` (the outer ring, metres, British National
#'   Grid, not closed: the last corner is not a repeat of the first), with attributes
#'   `centroid` (named `c(x, y)`) and `area_km2`.
#' @examples
#' square <- tempfile(fileext = ".csv")
#' utils::write.csv(data.frame(x = c(0, 2000, 2000, 0), y = c(0, 0, 2000, 2000)), square,
#'                  row.names = FALSE)
#' b <- read_boundary(square)
#' attr(b, "centroid")  # 1000, 1000
#' attr(b, "area_km2")  # 4
#' @seealso [distance_to_boundary()], [catchment_mask()]
#' @export
read_boundary <- function(path) {
  .check(is.character(path) && length(path) == 1 && file.exists(path),
         paste("Cannot find the boundary file", path))
  if (grepl("\\.(csv|txt)$", tolower(path))) {
    ring <- utils::read.csv(path)
    .check(all(c("x", "y") %in% names(ring)), paste(basename(path), "needs columns x and y"))
    ring <- data.frame(x = as.numeric(ring$x), y = as.numeric(ring$y))
  } else {
    .check(requireNamespace("sf", quietly = TRUE),
           "Reading a shapefile or GeoPackage needs the sf package: install.packages(\"sf\")")
    shape <- sf::st_read(path, quiet = TRUE)
    if (is.na(sf::st_crs(shape))) {
      message(basename(path), " has no coordinate reference system: taken to be British ",
              "National Grid")
      sf::st_crs(shape) <- 27700
    }
    shape <- sf::st_transform(sf::st_geometry(shape), 27700)
    parts <- sf::st_cast(sf::st_union(sf::st_make_valid(shape)), "POLYGON")
    .check(length(parts) > 0, paste("No polygon in", basename(path)))
    areas <- as.numeric(sf::st_area(parts))
    if (length(parts) > 1) {
      message(sprintf("%s has %d separate parts: kept the largest, dropping %.1f%% of the area",
                      basename(path), length(parts), 100 * (1 - max(areas) / sum(areas))))
    }
    xy <- sf::st_coordinates(parts[which.max(areas)])
    xy <- xy[xy[, "L1"] == 1, , drop = FALSE]
    ring <- data.frame(x = unname(xy[, "X"]), y = unname(xy[, "Y"]))
  }
  .check(nrow(ring) >= 3 && !anyNA(ring), paste(basename(path), "needs at least three corners"))
  n <- nrow(ring)
  if (ring$x[1] == ring$x[n] && ring$y[1] == ring$y[n]) ring <- ring[-n, ]
  # Shoelace: signed area and centroid of the ring.
  x <- ring$x
  y <- ring$y
  x1 <- c(x[-1], x[1])
  y1 <- c(y[-1], y[1])
  cross <- x * y1 - x1 * y
  a <- sum(cross) / 2
  .check(abs(a) > 0, paste(basename(path), "encloses no area"))
  attr(ring, "centroid") <- c(x = sum((x + x1) * cross) / (6 * a),
                              y = sum((y + y1) * cross) / (6 * a))
  attr(ring, "area_km2") <- abs(a) / 1e6
  rownames(ring) <- NULL
  ring
}

#' Distance from points to a catchment boundary
#'
#' The shortest distance from each point to a polygon: zero for a point inside it, otherwise
#' the distance to its nearest edge. Used to say how far outside a catchment each rain gauge
#' lies.
#'
#' @param x,y Coordinates of the points, metres.
#' @param boundary A data frame with columns `x` and `y`, the polygon's corners in order, such
#'   as from [read_boundary()].
#' @return Distances in metres, one per point.
#' @examples
#' square <- data.frame(x = c(0, 1000, 1000, 0), y = c(0, 0, 1000, 1000))
#' distance_to_boundary(c(500, 1500, 2000), c(500, 500, 2000), square)  # 0, 500, 1414.2
#' @seealso [read_boundary()]
#' @export
distance_to_boundary <- function(x, y, boundary) {
  .check(is.numeric(x) && is.numeric(y) && length(x) == length(y),
         "x and y must be numbers of the same length")
  .check(is.data.frame(boundary) && all(c("x", "y") %in% names(boundary)) &&
           nrow(boundary) >= 3, "boundary needs columns x and y and at least three corners")
  px <- boundary$x
  py <- boundary$y
  qx <- c(px[-1], px[1])
  qy <- c(py[-1], py[1])
  d <- vapply(seq_along(x), function(k) {
    # Each edge from (px, py) to (qx, qy): the nearest point on it to (x, y).
    ex <- qx - px
    ey <- qy - py
    len2 <- ex^2 + ey^2
    t <- ifelse(len2 > 0, ((x[k] - px) * ex + (y[k] - py) * ey) / len2, 0)
    t <- pmin(pmax(t, 0), 1)
    min(sqrt((px + t * ex - x[k])^2 + (py + t * ey - y[k])^2))
  }, numeric(1))
  d[.point_in_polygon(x, y, px, py)] <- 0
  d
}
