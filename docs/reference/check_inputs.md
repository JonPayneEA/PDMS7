# Check inputs before registering them

A last look at the data before
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md):
the period, the step, how much is missing, negative values, annual
totals and the runoff ratio, each compared with a plausible range.
Totals far outside the ranges usually mean the wrong units; a runoff
ratio above one means the rain is too low, the flow too high or the area
wrong. The defaults suit the British Isles; give your own ranges
elsewhere. The preparation notes of each series are included.

## Usage

``` r
check_inputs(
  forcing,
  observed = NULL,
  area_km2 = NULL,
  dt = NULL,
  ranges = list(rain = c(400, 4000), pet = c(250, 1200), runoff_ratio = c(0.1, 0.9))
)
```

## Arguments

- forcing:

  Data frame with `rain` and `pet` (mm per step) and, optionally,
  `time`.

- observed:

  Observed flow, m3/s, aligned with `forcing`; optional.

- area_km2:

  Catchment area, for the runoff ratio.

- dt:

  Time step in hours; by default from `forcing$time`.

- ranges:

  Plausible `rain` and `pet` annual totals (mm) and `runoff_ratio`.

## Value

A `pdm_input_check` list: `table` (one row per series), `runoff_ratio`,
`flags` (warnings in words, empty when all is plausible) and `notes`.
Printing it shows all four.

## See also

[`preparation_notes()`](https://jonpayneea.github.io/PDMS7/reference/preparation_notes.md),
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)

## Examples

``` r
n <- 24 * 365
forcing <- data.frame(rain = rep(c(0, 0, 0, 0.9), n / 4), pet = 0.06)
check_inputs(forcing, observed = rep(0.4, n), area_km2 = 20, dt = 1)
#> Input check: 1.0 years at 1 h steps
#>   rain  0 missing, 0 negative, mean 0.225, 1972 mm a year
#>   pet   0 missing, 0 negative, mean 0.06, 526 mm a year
#>   flow  0 missing, 0 negative, mean 0.4
#>   Runoff is 32% of rain
#> Nothing implausible found
```
