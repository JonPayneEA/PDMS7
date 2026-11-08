# Fill gaps in rain or evaporation

The model cannot run through a gap in its inputs, so rain and
evaporation must be complete before registration. Flow need not be:
missing flow is simply left out of scoring, so never fill flow for
scoring.

## Usage

``` r
fill_gaps(
  x,
  rule = c("stop", "zero", "interpolate", "none"),
  time = NULL,
  label = "series",
  max_gap_h = Inf,
  dt = 1
)
```

## Arguments

- x:

  Numeric series on a regular step.

- rule:

  One of the rules above.

- time:

  Optional times of `x`, to name the gaps by date.

- label:

  Name of the series in messages and notes.

- max_gap_h:

  For `interpolate`: longest gap to fill, in hours, with `dt`.

- dt:

  Time step in hours, for `max_gap_h`.

## Value

`x` with gaps filled, noted.

## Details

|               |                                                                     |
|---------------|---------------------------------------------------------------------|
| `rule`        | Does                                                                |
| `stop`        | refuses, listing the five longest gaps, so you infill them yourself |
| `zero`        | sets missing steps to zero, for rain where a gap is known to be dry |
| `interpolate` | joins the values either side; gaps over `max_gap_h` stay missing    |
| `none`        | leaves gaps, and notes how many there are                           |

The rule, the number of steps filled and the longest gap are noted, and
reach the calibration log through
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md).

## See also

[`zero_negatives()`](https://jonpayneea.github.io/PDMS7/reference/zero_negatives.md),
[`preparation_notes()`](https://jonpayneea.github.io/PDMS7/reference/preparation_notes.md)

## Examples

``` r
fill_gaps(c(0.1, NA, NA, 0.4), "interpolate", label = "pet")
#> [1] 0.1 0.2 0.3 0.4
#> attr(,"pdm_prep")
#>   step
#> 1 gaps
#>                                                                                            detail
#> 1 pet: 2 missing steps in 1 gap, longest row 2 for 2 steps; interpolate, 2 filled, 0 left missing
```
