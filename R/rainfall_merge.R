# ============================================================ #
# Tool:         rainfall_merge
# Description:  Catchment rainfall from rain gauges and radar: Thiessen polygons, multiquadric
#               interpolation of the gauges, and conditional merging of gauges and radar
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-07
# Modified:     2026-11-07 - First version
# Tier:         1
# Inputs:       Gauge locations and depths (mm per step); optionally radar grids (mm per step);
#               a catchment mask on the grid
# Outputs:      Catchment-average rain (mm per step), with leave-one-gauge-out checks
# Dependencies: stats
# ============================================================ #

#' Catchment rainfall from gauges and radar
#'
#' Rain gauges measure the amount of rain well at a point; radar shows where and when it fell
#' but gets the amount wrong, by beam height, bright band and the conversion from reflectivity.
#' `merge_rainfall()` builds the catchment-average rainfall three ways, so that they can be
#' compared on the gauges and, through the model, on the river.
#'
#' | Method | Field at each step | Uses radar |
#' |---|---|---|
#' | `thiessen` | Each cell takes its nearest gauge with a value | No |
#' | `multiquadric` | A smooth surface through the gauges (Hardy, 1971) | No |
#' | `conditional` | The gauge surface plus the radar's departure from its own surface | Yes |
#'
#' **Multiquadric interpolation.** The surface is a sum of cones, one on each gauge,
#' `f(x) = b + sum a_i sqrt(|x - x_i|^2 + c^2)`, with the weights `a_i` summing to zero so that
#' far from the gauges the surface stays bounded rather than rising without limit. It passes
#' through every gauge, unless `smooth` is positive, which lets it miss them slightly to allow
#' for gauge error. The shape parameter `c` (metres, or whatever the coordinates are in) sets
#' how flat the cones are; by default it is chosen by leaving out one gauge at a time.
#'
#' **Conditional merging** (Sinclair and Pegram, 2005). The gauge surface sets the level; the
#' radar adds the storm's shape between gauges. At each step: fit a surface to the gauges, and
#' another to the radar values in the cells holding the gauges; the merged field is the gauge
#' surface plus the radar minus the radar's own surface. At a gauge it equals the gauge; between
#' gauges a storm the gauges missed keeps its radar shape, scaled to the gauges around it, and
#' rain the radar shows over gauges that stayed dry is taken away as a false echo. Where the
#' gauges and the radar over them are all dry, rain the radar shows elsewhere is kept as it is;
#' where the radar is dry everywhere, the gauge surface alone is used.
#'
#' **Rain is not negative.** Every field is set to zero where an interpolation dips below it.
#'
#' **Checking.** `rainfall_cross_validation()` leaves out each gauge in turn, rebuilds the field
#' from the others, and compares the field in that gauge's cell with what it measured, over the
#' wet steps. It is how `c` is chosen, and how the three methods compare at the gauges. Judge
#' the catchment series through the river as well, with the event tools, and in the end through
#' calibration: a field that is good at the gauges may still be wrong over the catchment.
#'
#' **Practical notes.** Use gauges around the catchment as well as inside it, within about 20
#' to 30 km: a surface needs support on every side. Conditional merging at short steps can be
#' noisy where gauges and radar disagree on timing within the hour; merging hourly totals and
#' sharing each hour's merged total among its 15-minute steps in proportion to the radar keeps
#' both the volume and the radar's timing.
#'
#' @param gauges Data frame of gauges with columns `id`, `x` and `y` (projected coordinates, such
#'   as British National Grid metres).
#' @param gauge_rain Matrix of gauge depths, mm per step: one row per step, one column per gauge,
#'   in the order of `gauges`. Missing values are allowed; a gauge missing at a step is left out
#'   of that step.
#' @param grid List with `x` and `y`, the cell-centre coordinates of the grid's columns and rows.
#' @param mask Weights of the grid's cells in the catchment: a numeric or logical matrix of
#'   `length(grid$x)` rows by `length(grid$y)` columns, such as from `catchment_mask()`.
#' @param radar With `method = "conditional"`, radar depths on the grid, mm per step: an array
#'   of dimension `c(length(grid$x), length(grid$y), steps)`, or, for a record too large to hold
#'   at once, a function of the step number returning that step's grid as a matrix of
#'   `length(grid$x)` rows by `length(grid$y)` columns (such as one that reads that step's file).
#'   Sixteen years of 15-minute radar on a 30 km grid would take about 4 GB as an array.
#' @param method `thiessen`, `multiquadric` or `conditional`.
#' @param c Multiquadric shape parameter, in the units of the coordinates; by default chosen by
#'   `rainfall_cross_validation()` from `c_candidates`.
#' @param smooth Nonnegative smoothing added to the diagonal of the multiquadric system, in the
#'   units of the basis (coordinate units); 0 passes exactly through the gauges.
#' @param c_candidates Multiples of the median distance between neighbouring gauges tried for
#'   `c`.
#' @param wet Depth, mm per step, above which a step counts as wet in the cross-validation.
#' @param max_steps Most wet steps checked; a larger record is sampled, with `seed`, so that a
#'   long 15-minute record is checked in seconds.
#' @param seed Seed for that sample; the caller's random state is restored.
#' @param x,y Cell-centre coordinates of a grid's columns and rows.
#' @param polygon Data frame or matrix with the catchment boundary's `x` and `y`, in order.
#'
#' @return `merge_rainfall()`: a list of class `pdm_rainfall` with `rain` (catchment-average rain,
#'   mm per step), `method`, `c`, `smooth` and the cross-validation table `checks` when `c` was
#'   chosen. `rainfall_cross_validation()`: a data frame with one row per `c` tried (or one row
#'   for a method without `c`), giving the mean absolute error, root mean square error, bias and
#'   correlation of the left-out gauges over the wet steps. `catchment_mask()`: a logical matrix,
#'   `TRUE` for cells whose centres lie inside the polygon.
#' @references Hardy, R. L. (1971). Multiquadric equations of topography and other irregular
#'   surfaces. Journal of Geophysical Research 76(8), 1905-1915.
#'
#'   Sinclair, S. and Pegram, G. (2005). Combining radar and rain gauge rainfall estimates using
#'   conditional merging. Atmospheric Science Letters 6, 19-22.
#' @examples
#' grid <- list(x = seq(500, 9500, by = 1000), y = seq(500, 9500, by = 1000))
#' mask <- catchment_mask(grid$x, grid$y,
#'                        data.frame(x = c(2000, 8000, 8000, 2000), y = c(2000, 2000, 8000, 8000)))
#' gauges <- data.frame(id = c("A", "B", "C", "D", "E"), x = c(1500, 8500, 5000, 1500, 8500),
#'                      y = c(1500, 1500, 5200, 8500, 8500))
#' gauge_rain <- rbind(c(1, 2, 4, 1, 2), c(0, 0, 0, 0, 0), c(3, 1, 2, 2, 1))
#' merge_rainfall(gauges, gauge_rain, grid, mask, method = "multiquadric", c = 3000)$rain
#' @seealso [find_events()], [calibration_checks()]
#' @export
merge_rainfall <- function(gauges, gauge_rain, grid, mask, radar = NULL,
                           method = c("multiquadric", "conditional", "thiessen"), c = NULL,
                           smooth = 0, c_candidates = c(0.1, 0.25, 0.5, 1, 2, 4), wet = 0.1,
                           max_steps = 2000L, seed = 1L) {
  method <- match.arg(method)
  .check_merge_inputs(gauges, gauge_rain, grid, mask, radar, method, smooth)
  checks <- NULL
  if (method != "thiessen" && is.null(c)) {
    checks <- rainfall_cross_validation(gauges, gauge_rain, grid, radar, method, NULL, smooth,
                                        c_candidates, wet, max_steps, seed)
    c <- checks$c[which.min(checks$rmse)]
  }
  .check(method == "thiessen" || .scalar(c, 0, strict = TRUE), "c must be a positive number")
  cells <- .mask_cells(grid, mask)
  at_gauge <- .gauge_cells(gauges, grid)
  rain <- vapply(seq_len(nrow(gauge_rain)), function(t) {
    field <- .rain_field(gauges, gauge_rain[t, ], cells, method, c, smooth,
                         if (method == "conditional") .radar_step(radar, t, cells, at_gauge))
    sum(field * cells$w) / sum(cells$w)
  }, numeric(1))
  structure(list(rain = rain, method = method, c = c, smooth = smooth, checks = checks),
            class = "pdm_rainfall")
}

#' @rdname merge_rainfall
#' @export
rainfall_cross_validation <- function(gauges, gauge_rain, grid, radar = NULL,
                                      method = c("multiquadric", "conditional", "thiessen"),
                                      c = NULL, smooth = 0,
                                      c_candidates = c(0.1, 0.25, 0.5, 1, 2, 4), wet = 0.1,
                                      max_steps = 2000L, seed = 1L) {
  method <- match.arg(method)
  .check(nrow(gauges) >= 3, "Cross-validation needs at least three gauges")
  at_gauge <- .gauge_cells(gauges, grid)
  # The steps worth checking: some gauge measured more than `wet`.
  steps <- which(apply(gauge_rain, 1L, function(r) any(r > wet, na.rm = TRUE)))
  .check(length(steps) > 0, "No wet steps to check")
  .check(.whole(max_steps, 1, Inf), "max_steps must be a positive whole number")
  if (length(steps) > max_steps) {
    steps <- sort(.with_seed(seed, steps[sample.int(length(steps), max_steps)]))
  }
  cs <- if (method == "thiessen") NA_real_ else c %||% (c_candidates * .gauge_spacing(gauges))
  do.call(rbind, lapply(cs, function(cc) {
    errors <- unlist(lapply(steps, function(t) {
      vapply(seq_len(nrow(gauges)), function(g) {
        if (!is.finite(gauge_rain[t, g])) return(NA_real_)
        others <- gauge_rain[t, ]
        others[g] <- NA
        cell <- list(x = gauges$x[g], y = gauges$y[g], w = 1)
        radar_t <- if (method == "conditional") {
          .radar_step(radar, t, list(i = at_gauge$i[g], j = at_gauge$j[g]), at_gauge)
        }
        .rain_field(gauges, others, cell, method, cc, smooth, radar_t) - gauge_rain[t, g]
      }, numeric(1))
    }))
    observed <- unlist(lapply(steps, function(t) gauge_rain[t, ]))
    ok <- is.finite(errors)
    data.frame(method = method, c = cc, mae = mean(abs(errors[ok])),
               rmse = sqrt(mean(errors[ok]^2)), bias = mean(errors[ok]),
               correlation = suppressWarnings(stats::cor(errors[ok] + observed[ok],
                                                         observed[ok])))
  }))
}

#' @rdname merge_rainfall
#' @export
catchment_mask <- function(x, y, polygon) {
  px <- polygon[, 1]
  py <- polygon[, 2]
  if (is.data.frame(polygon) && all(c("x", "y") %in% names(polygon))) {
    px <- polygon$x
    py <- polygon$y
  }
  .check(length(px) >= 3, "polygon needs at least three vertices")
  cx <- rep(x, times = length(y))
  cy <- rep(y, each = length(x))
  inside <- .point_in_polygon(cx, cy, px, py)
  matrix(inside, nrow = length(x), ncol = length(y))
}

#' One step's rainfall field on a grid
#'
#' The field [merge_rainfall()] averages over the catchment, for one time step and every cell of
#' the grid: for mapping a storm, or for seeing what each method does to it.
#'
#' @inheritParams merge_rainfall
#' @param values One step's gauge depths, mm, in the order of `gauges`; `NA` leaves a gauge out.
#' @param radar With `method = "conditional"`, that step's radar grid, mm: a matrix of
#'   `length(grid$x)` rows by `length(grid$y)` columns.
#' @param c Multiquadric shape parameter; by default the median distance between neighbouring
#'   gauges.
#' @return A matrix of rain, mm, with `length(grid$x)` rows and `length(grid$y)` columns.
#' @examples
#' grid <- list(x = seq(500, 9500, by = 1000), y = seq(500, 9500, by = 1000))
#' gauges <- data.frame(id = 1:4, x = c(2000, 8000, 2000, 8000), y = c(2000, 2000, 8000, 8000))
#' field <- rainfall_field(gauges, c(1, 4, 2, 0), grid, method = "multiquadric")
#' image(grid$x, grid$y, field)
#' @seealso [merge_rainfall()]
#' @export
rainfall_field <- function(gauges, values, grid, method = c("multiquadric", "conditional",
                                                            "thiessen"),
                           c = NULL, smooth = 0, radar = NULL) {
  method <- match.arg(method)
  .check_gauge_inputs(gauges, matrix(values, nrow = 1))
  .check(is.list(grid) && is.numeric(grid$x) && is.numeric(grid$y),
         "grid must be a list of cell-centre x and y")
  nx <- length(grid$x)
  ny <- length(grid$y)
  if (method == "conditional") {
    .check(is.matrix(radar) && all(dim(radar) == c(nx, ny)),
           "radar must be one step's grid, a matrix of grid columns by rows")
  }
  c <- c %||% if (nrow(gauges) > 1) .gauge_spacing(gauges) else 1
  cells <- list(i = rep(seq_len(nx), ny), j = rep(seq_len(ny), each = nx))
  cells$x <- grid$x[cells$i]
  cells$y <- grid$y[cells$j]
  at <- .gauge_cells(gauges, grid)
  step <- if (method == "conditional") {
    list(cells = radar[cbind(cells$i, cells$j)], gauges = radar[cbind(at$i, at$j)])
  }
  matrix(.rain_field(gauges, values, cells, method, c, smooth, step), nx, ny)
}

#' @export
print.pdm_rainfall <- function(x, ...) {
  cat(sprintf("Catchment rainfall by %s%s: %d steps, %.1f mm in all\n", x$method,
              if (is.finite(x$c %||% NA)) sprintf(" (c = %.4g)", x$c) else "", length(x$rain),
              sum(x$rain)))
  if (!is.null(x$checks)) {
    cat("Leave-one-gauge-out checks:\n")
    print(x$checks, row.names = FALSE, digits = 3)
  }
  invisible(x)
}

# ---- Helpers -----------------------------------------------------------------------------

.check_merge_inputs <- function(gauges, gauge_rain, grid, mask, radar, method, smooth) {
  .check_gauge_inputs(gauges, gauge_rain)
  .check_grid_inputs(grid, mask, radar, method, nrow(gauge_rain))
  .check(.scalar(smooth, 0), "smooth must be a nonnegative number")
}

.check_gauge_inputs <- function(gauges, gauge_rain) {
  .check(is.data.frame(gauges) && all(c("id", "x", "y") %in% names(gauges)) &&
           nrow(gauges) >= 1, "gauges must be a data frame with id, x and y")
  .check(is.matrix(gauge_rain) && is.numeric(gauge_rain) && ncol(gauge_rain) == nrow(gauges),
         "gauge_rain must be a numeric matrix with one column per gauge")
}

.check_grid_inputs <- function(grid, mask, radar, method, steps) {
  .check(is.list(grid) && is.numeric(grid$x) && is.numeric(grid$y),
         "grid must be a list of cell-centre x and y")
  .check(is.matrix(mask) && nrow(mask) == length(grid$x) && ncol(mask) == length(grid$y) &&
           any(as.numeric(mask) > 0), "mask must be a matrix on the grid with a cell inside")
  if (method == "conditional") .check_radar(radar, grid, steps)
}

# Radar for conditional merging: a function of the step, or an array matching grid and steps.
.check_radar <- function(radar, grid, steps) {
  if (is.function(radar)) return(invisible(TRUE))
  .check(is.array(radar) && length(dim(radar)) == 3L &&
           all(dim(radar) == c(length(grid$x), length(grid$y), steps)),
         "radar must be an array of grid columns by rows by steps, matching gauge_rain")
}

# The catchment's cells: their grid indices, centres and weights.
.mask_cells <- function(grid, mask) {
  idx <- which(as.numeric(mask) > 0)
  i <- (idx - 1L) %% length(grid$x) + 1L
  j <- (idx - 1L) %/% length(grid$x) + 1L
  list(i = i, j = j, x = grid$x[i], y = grid$y[j], w = as.numeric(mask)[idx])
}

# The grid cell nearest each gauge.
.gauge_cells <- function(gauges, grid) {
  list(i = vapply(gauges$x, function(v) which.min(abs(grid$x - v)), integer(1)),
       j = vapply(gauges$y, function(v) which.min(abs(grid$y - v)), integer(1)))
}

# The radar at one step, in the target cells and in the cells holding the gauges, from an array
# or from a function returning the step's grid.
.radar_step <- function(radar, t, cells, at_gauge) {
  if (is.function(radar)) {
    grid_t <- radar(t)
    return(list(cells = grid_t[cbind(cells$i, cells$j)],
                gauges = grid_t[cbind(at_gauge$i, at_gauge$j)]))
  }
  list(cells = radar[cbind(cells$i, cells$j, t)], gauges = radar[cbind(at_gauge$i, at_gauge$j, t)])
}

# The median distance from each gauge to its nearest neighbour.
.gauge_spacing <- function(gauges) {
  d <- as.matrix(stats::dist(cbind(gauges$x, gauges$y)))
  diag(d) <- Inf
  stats::median(apply(d, 1L, min))
}

# The rain field at the target points for one step.
.rain_field <- function(gauges, values, target, method, c, smooth, radar) {
  ok <- is.finite(values)
  if (!any(ok)) return(rep(NA_real_, length(target$x)))
  gx <- gauges$x[ok]
  gy <- gauges$y[ok]
  z <- values[ok]
  field <- switch(method,
    thiessen = z[.nearest(target$x, target$y, gx, gy)],
    multiquadric = .multiquadric(gx, gy, z, target$x, target$y, c, smooth),
    conditional = {
      if (all(z <= 0) && all(radar$gauges[ok] <= 0)) {
        radar$cells
      } else if (all(radar$cells <= 0) && all(radar$gauges[ok] <= 0)) {
        .multiquadric(gx, gy, z, target$x, target$y, c, smooth)
      } else {
        .multiquadric(gx, gy, z, target$x, target$y, c, smooth) + radar$cells -
          .multiquadric(gx, gy, radar$gauges[ok], target$x, target$y, c, smooth)
      }
    }
  )
  pmax(field, 0)
}

.nearest <- function(x, y, gx, gy) {
  vapply(seq_along(x), function(k) which.min((gx - x[k])^2 + (gy - y[k])^2), integer(1))
}

# Multiquadric interpolation with a constant term: solve
#   [Phi + smooth I, 1; 1', 0] [a; b] = [z; 0]
# and evaluate b + sum a_i sqrt(d_i^2 + c^2) at the targets. One gauge gives a flat field.
.multiquadric <- function(gx, gy, z, tx, ty, c, smooth) {
  n <- length(z)
  if (n == 1L || stats::var(z) == 0) return(rep(z[1], length(tx)))
  phi <- function(ax, ay, bx, by) sqrt(outer(ax, bx, "-")^2 + outer(ay, by, "-")^2 + c^2)
  a <- rbind(cbind(phi(gx, gy, gx, gy) + diag(smooth, n), 1), c(rep(1, n), 0))
  coef <- tryCatch(solve(a, c(z, 0)), error = function(e) NULL)
  if (is.null(coef)) return(rep(mean(z), length(tx)))
  drop(phi(tx, ty, gx, gy) %*% coef[seq_len(n)]) + coef[n + 1L]
}

# Ray casting: TRUE where a point lies inside the polygon.
.point_in_polygon <- function(x, y, px, py) {
  n <- length(px)
  inside <- logical(length(x))
  j <- n
  for (i in seq_len(n)) {
    crosses <- ((py[i] > y) != (py[j] > y)) &
      (x < (px[j] - px[i]) * (y - py[i]) / (py[j] - py[i]) + px[i])
    inside <- xor(inside, crosses)
    j <- i
  }
  inside
}
