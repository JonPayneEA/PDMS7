# Plot the acceptance checks of a calibration

[`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
`autoplot()` draw the checks of
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md):

## Usage

``` r
# S3 method for class 'pdm_calibration_checks'
plot(x, type = c("bounds", "peaks", "timing", "balance"), ...)

# S3 method for class 'pdm_calibration_checks'
autoplot(object, type = c("bounds", "peaks", "timing", "balance"), ...)
```

## Arguments

- x, object:

  A result of
  [`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md).

- type:

  One of the plots above.

- ...:

  Passed to
  [`plot.pdm_events()`](https://jonpayneea.github.io/PDMS7/reference/plot.pdm_events.md)
  for the event plots.

## Value

[`plot()`](https://rdrr.io/r/graphics/plot.default.html): `x`,
invisibly. `autoplot()`: a ggplot.

## Details

|                              |                                                                                                                                 |
|------------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| `type`                       | Shows                                                                                                                           |
| `bounds`                     | where each parameter sits within its search range; one at an end is flagged                                                     |
| `peaks`, `timing`, `balance` | the project's events by window, as [`plot.pdm_events()`](https://jonpayneea.github.io/PDMS7/reference/plot.pdm_events.md) draws |

A parameter at an end of its range is the clearest warning sign a
calibration gives: the search wanted to go further than a sensible
value, usually to make up for something the structure cannot do.

## See also

[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md),
[`plot.pdm_events()`](https://jonpayneea.github.io/PDMS7/reference/plot.pdm_events.md)

## Examples

``` r
if (FALSE) { # \dontrun{
checks <- calibration_checks("projects/beggearn_huish")
plot(checks)
plot(checks, type = "peaks")
} # }
```
