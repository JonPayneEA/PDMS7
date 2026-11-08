# Put several series on one regular time step

Builds a regular time grid over the period every series covers and
places each series on it. A step with no reading becomes missing;
nothing is interpolated here (see
[`fill_gaps()`](https://jonpayneea.github.io/PDMS7/reference/fill_gaps.md)).
A series recorded at a coarser step than the grid leaves the steps
between its readings missing, and a note says so.

## Usage

``` r
align_series(..., dt = NULL, start = NULL, end = NULL)
```

## Arguments

- ...:

  Named series:
  [`read_hydro_series()`](https://jonpayneea.github.io/PDMS7/reference/read_hydro_series.md)
  results, or data frames with `time` and `value` columns.

- dt:

  Grid step in hours; by default the finest median step of the series.

- start, end:

  Optional limits of the grid (times); by default the period all series
  share.

## Value

A data frame of `time` and one column per series, each noted.

## See also

[`read_hydro_series()`](https://jonpayneea.github.io/PDMS7/reference/read_hydro_series.md),
[`fill_gaps()`](https://jonpayneea.github.io/PDMS7/reference/fill_gaps.md),
[`check_inputs()`](https://jonpayneea.github.io/PDMS7/reference/check_inputs.md)

## Examples

``` r
t <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 900, length.out = 8)
rain <- data.frame(time = t, value = c(0, 0.2, 0.4, 0, 0, 0, 0.1, 0))
flow <- data.frame(time = t[-3], value = c(1, 1.1, 1.3, 1.2, 1.1, 1.05, 1))
align_series(rain = rain, flow = flow)
#>                  time rain flow
#> 1 2021-01-01 00:00:00  0.0 1.00
#> 2 2021-01-01 00:15:00  0.2 1.10
#> 3 2021-01-01 00:30:00  0.4   NA
#> 4 2021-01-01 00:45:00  0.0 1.30
#> 5 2021-01-01 01:00:00  0.0 1.20
#> 6 2021-01-01 01:15:00  0.0 1.10
#> 7 2021-01-01 01:30:00  0.1 1.05
#> 8 2021-01-01 01:45:00  0.0 1.00
```
