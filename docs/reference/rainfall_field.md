# One step's rainfall field on a grid

The field
[`merge_rainfall()`](https://jonpayneea.github.io/PDMS7/reference/merge_rainfall.md)
averages over the catchment, for one time step and every cell of the
grid: for mapping a storm, or for seeing what each method does to it.

## Usage

``` r
rainfall_field(
  gauges,
  values,
  grid,
  method = c("multiquadric", "conditional", "thiessen"),
  c = NULL,
  smooth = 0,
  radar = NULL
)
```

## Arguments

- gauges:

  Data frame of gauges with columns `id`, `x` and `y` (projected
  coordinates, such as British National Grid metres).

- values:

  One step's gauge depths, mm, in the order of `gauges`; `NA` leaves a
  gauge out.

- grid:

  List with `x` and `y`, the cell-centre coordinates of the grid's
  columns and rows.

- method:

  `thiessen`, `multiquadric` or `conditional`.

- c:

  Multiquadric shape parameter; by default the median distance between
  neighbouring gauges.

- smooth:

  Nonnegative smoothing added to the diagonal of the multiquadric
  system, in the units of the basis (coordinate units); 0 passes exactly
  through the gauges.

- radar:

  With `method = "conditional"`, that step's radar grid, mm: a matrix of
  `length(grid$x)` rows by `length(grid$y)` columns.

## Value

A matrix of rain, mm, with `length(grid$x)` rows and `length(grid$y)`
columns.

## See also

[`merge_rainfall()`](https://jonpayneea.github.io/PDMS7/reference/merge_rainfall.md)

## Examples

``` r
grid <- list(x = seq(500, 9500, by = 1000), y = seq(500, 9500, by = 1000))
gauges <- data.frame(id = 1:4, x = c(2000, 8000, 2000, 8000), y = c(2000, 2000, 8000, 8000))
field <- rainfall_field(gauges, c(1, 4, 2, 0), grid, method = "multiquadric")
image(grid$x, grid$y, field)
```
