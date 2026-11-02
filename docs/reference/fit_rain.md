# Fit a rainfall generator to a record

Estimates a generator's parameters month by month from a rainfall
record, so that
[`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md)
produces rain that resembles it.

## Usage

``` r
fit_rain(
  record,
  method = c("nsrp", "bartlett_lewis", "markov_gamma"),
  wet_threshold = NULL
)
```

## Arguments

- record:

  A data frame with a time column (`time` or `dateTime`) and rain in mm
  per step (`rain` or `value`), at a regular step; or an object from
  `reach.io::read_silver()`.

- method:

  `nsrp`, `bartlett_lewis` or `markov_gamma`.

- wet_threshold:

  A day or interval counts as dry at or below this depth, mm. By default
  0 for the pulse models, whose dry proportion is for exactly no rain,
  and 0.1 for the Markov chain.

## Value

A parameter table as
[`rain_parameters()`](https://jonpayneea.github.io/PDMS7/reference/rain_parameters.md)
returns, with the record's and the fitted statistics as attribute `fit`.

## Details

- **Pulse models** (`nsrp`, `bartlett_lewis`): the method of moments.
  For each calendar month the model's exact mean, variance, lag-1
  autocorrelation and dry proportion (see
  [`rain_statistics()`](https://jonpayneea.github.io/PDMS7/reference/rain_statistics.md))
  are matched to the record's at two interval lengths: 1 and 24 hours
  for a record at an hourly step or finer, 24 and 72 hours for a daily
  record. The mean is matched exactly; the others by least squares on
  relative errors, from several starts.

- **Markov chain with gamma amounts:** maximum likelihood. Transition
  probabilities from counts of consecutive valid days; gamma shape and
  scale from the wet-day totals.

A month with fewer than 60 valid days borrows the parameters of its
neighbours. Fitting takes seconds for the Neyman-Scott model and a few
minutes for Bartlett-Lewis, whose dry proportion needs a double
integral.

The record may come straight from reach.io:
`fit_rain(reach.io::read_silver(root, "SS92F014", "P"))` reads the
`dateTime` and `value` columns of its readings.

## Examples

``` r
# \donttest{
observed <- synthetic_rain("2000-01-01", years = 20, seed = 3, pet = NULL)
fitted <- fit_rain(observed, "nsrp")
round(fitted[1:3, ], 3)
#>   month lambda  beta    nu   eta   mux
#> 1     1  0.014 0.058 3.871 0.541 0.892
#> 2     2  0.029 0.199 1.296 0.412 0.979
#> 3     3  0.019 0.213 3.361 0.752 1.257
# }
```
