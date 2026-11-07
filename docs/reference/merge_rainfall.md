# Catchment rainfall from gauges and radar

Rain gauges measure the amount of rain well at a point; radar shows
where and when it fell but gets the amount wrong, by beam height, bright
band and the conversion from reflectivity. `merge_rainfall()` builds the
catchment-average rainfall three ways, so that they can be compared on
the gauges and, through the model, on the river.

## Usage

``` r
merge_rainfall(
  gauges,
  gauge_rain,
  grid,
  mask,
  radar = NULL,
  method = c("multiquadric", "conditional", "thiessen"),
  c = NULL,
  smooth = 0,
  c_candidates = c(0.1, 0.25, 0.5, 1, 2, 4),
  wet = 0.1,
  max_steps = 2000L,
  seed = 1L
)

rainfall_cross_validation(
  gauges,
  gauge_rain,
  grid,
  radar = NULL,
  method = c("multiquadric", "conditional", "thiessen"),
  c = NULL,
  smooth = 0,
  c_candidates = c(0.1, 0.25, 0.5, 1, 2, 4),
  wet = 0.1,
  max_steps = 2000L,
  seed = 1L
)

catchment_mask(x, y, polygon)
```

## Arguments

- gauges:

  Data frame of gauges with columns `id`, `x` and `y` (projected
  coordinates, such as British National Grid metres).

- gauge_rain:

  Matrix of gauge depths, mm per step: one row per step, one column per
  gauge, in the order of `gauges`. Missing values are allowed; a gauge
  missing at a step is left out of that step.

- grid:

  List with `x` and `y`, the cell-centre coordinates of the grid's
  columns and rows.

- mask:

  Weights of the grid's cells in the catchment: a numeric or logical
  matrix of `length(grid$x)` rows by `length(grid$y)` columns, such as
  from `catchment_mask()`.

- radar:

  With `method = "conditional"`, radar depths on the grid, mm per step:
  an array of dimension `c(length(grid$x), length(grid$y), steps)`, or,
  for a record too large to hold at once, a function of the step number
  returning that step's grid as a matrix of `length(grid$x)` rows by
  `length(grid$y)` columns (such as one that reads that step's file).
  Sixteen years of 15-minute radar on a 30 km grid would take about 4 GB
  as an array.

- method:

  `thiessen`, `multiquadric` or `conditional`.

- c:

  Multiquadric shape parameter, in the units of the coordinates; by
  default chosen by `rainfall_cross_validation()` from `c_candidates`.

- smooth:

  Nonnegative smoothing added to the diagonal of the multiquadric
  system, in the units of the basis (coordinate units); 0 passes exactly
  through the gauges.

- c_candidates:

  Multiples of the median distance between neighbouring gauges tried for
  `c`.

- wet:

  Depth, mm per step, above which a step counts as wet in the
  cross-validation.

- max_steps:

  Most wet steps checked; a larger record is sampled, with `seed`, so
  that a long 15-minute record is checked in seconds.

- seed:

  Seed for that sample; the caller's random state is restored.

- x, y:

  Cell-centre coordinates of a grid's columns and rows.

- polygon:

  Data frame or matrix with the catchment boundary's `x` and `y`, in
  order.

## Value

`merge_rainfall()`: a list of class `pdm_rainfall` with `rain`
(catchment-average rain, mm per step), `method`, `c`, `smooth` and the
cross-validation table `checks` when `c` was chosen.
`rainfall_cross_validation()`: a data frame with one row per `c` tried
(or one row for a method without `c`), giving the mean absolute error,
root mean square error, bias and correlation of the left-out gauges over
the wet steps. `catchment_mask()`: a logical matrix, `TRUE` for cells
whose centres lie inside the polygon.

## Details

|                |                                                                   |            |
|----------------|-------------------------------------------------------------------|------------|
| Method         | Field at each step                                                | Uses radar |
| `thiessen`     | Each cell takes its nearest gauge with a value                    | No         |
| `multiquadric` | A smooth surface through the gauges (Hardy, 1971)                 | No         |
| `conditional`  | The gauge surface plus the radar's departure from its own surface | Yes        |

**Multiquadric interpolation.** The surface is a sum of cones, one on
each gauge, `f(x) = b + sum a_i sqrt(|x - x_i|^2 + c^2)`, with the
weights `a_i` summing to zero so that far from the gauges the surface
stays bounded rather than rising without limit. It passes through every
gauge, unless `smooth` is positive, which lets it miss them slightly to
allow for gauge error. The shape parameter `c` (metres, or whatever the
coordinates are in) sets how flat the cones are; by default it is chosen
by leaving out one gauge at a time.

**Conditional merging** (Sinclair and Pegram, 2005). The gauge surface
sets the level; the radar adds the storm's shape between gauges. At each
step: fit a surface to the gauges, and another to the radar values in
the cells holding the gauges; the merged field is the gauge surface plus
the radar minus the radar's own surface. At a gauge it equals the gauge;
between gauges a storm the gauges missed keeps its radar shape, scaled
to the gauges around it, and rain the radar shows over gauges that
stayed dry is taken away as a false echo. Where the gauges and the radar
over them are all dry, rain the radar shows elsewhere is kept as it is;
where the radar is dry everywhere, the gauge surface alone is used.

**Rain is not negative.** Every field is set to zero where an
interpolation dips below it.

**Checking.** `rainfall_cross_validation()` leaves out each gauge in
turn, rebuilds the field from the others, and compares the field in that
gauge's cell with what it measured, over the wet steps. It is how `c` is
chosen, and how the three methods compare at the gauges. Judge the
catchment series through the river as well, with the event tools, and in
the end through calibration: a field that is good at the gauges may
still be wrong over the catchment.

**Practical notes.** Use gauges around the catchment as well as inside
it, within about 20 to 30 km: a surface needs support on every side.
Conditional merging at short steps can be noisy where gauges and radar
disagree on timing within the hour; merging hourly totals and sharing
each hour's merged total among its 15-minute steps in proportion to the
radar keeps both the volume and the radar's timing.

## References

Hardy, R. L. (1971). Multiquadric equations of topography and other
irregular surfaces. Journal of Geophysical Research 76(8), 1905-1915.

Sinclair, S. and Pegram, G. (2005). Combining radar and rain gauge
rainfall estimates using conditional merging. Atmospheric Science
Letters 6, 19-22.

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)

## Examples

``` r
grid <- list(x = seq(500, 9500, by = 1000), y = seq(500, 9500, by = 1000))
mask <- catchment_mask(grid$x, grid$y,
                       data.frame(x = c(2000, 8000, 8000, 2000), y = c(2000, 2000, 8000, 8000)))
gauges <- data.frame(id = c("A", "B", "C", "D", "E"), x = c(1500, 8500, 5000, 1500, 8500),
                     y = c(1500, 1500, 5200, 8500, 8500))
gauge_rain <- rbind(c(1, 2, 4, 1, 2), c(0, 0, 0, 0, 0), c(3, 1, 2, 2, 1))
merge_rainfall(gauges, gauge_rain, grid, mask, method = "multiquadric", c = 3000)$rain
#> [1] 3.124126 0.000000 1.923107
```
