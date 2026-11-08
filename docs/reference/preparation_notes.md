# What was done to a series before registration

Every preparation function
([`read_hydro_series()`](https://jonpayneea.github.io/PDMS7/reference/read_hydro_series.md),
[`align_series()`](https://jonpayneea.github.io/PDMS7/reference/align_series.md),
[`convert_units()`](https://jonpayneea.github.io/PDMS7/reference/convert_units.md),
[`fill_gaps()`](https://jonpayneea.github.io/PDMS7/reference/fill_gaps.md),
[`zero_negatives()`](https://jonpayneea.github.io/PDMS7/reference/zero_negatives.md))
notes what it did on the series it returns. `preparation_notes()` lists
those notes.
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
writes them into the calibration log, so a reviewer can see, for
instance, that 412 steps of evaporation were interpolated and three
negative rain values set to zero.

## Usage

``` r
preparation_notes(x)
```

## Arguments

- x:

  A prepared series, or a data frame of them (such as forcing).

## Value

A data frame with columns `series`, `step` and `detail`; no rows if
nothing is noted.

## Details

Notes travel with a vector through data frames, data.tables, assignment
and arithmetic, but subsetting (`x[1:100]`) drops them: prepare the
whole series, then register it.

## See also

[`check_inputs()`](https://jonpayneea.github.io/PDMS7/reference/check_inputs.md),
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)

## Examples

``` r
rain <- c(0, 1.2, NA, 0.4, -0.1)
rain <- zero_negatives(fill_gaps(rain, "zero", label = "rain"), label = "rain")
preparation_notes(rain)
#>   series      step
#> 1 series      gaps
#> 2 series negatives
#>                                                                                      detail
#> 1 rain: 1 missing steps in 1 gap, longest row 3 for 1 steps; zero, 1 filled, 0 left missing
#> 2                           rain: 1 negative values (smallest -0.1, total -0.1) set to zero
```
