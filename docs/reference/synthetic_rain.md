# Synthetic rainfall

Generates a regular series of rain and potential evaporation, mm per
step, for driving a model. Four rainfall generators are available:

## Usage

``` r
synthetic_rain(
  start,
  years = 10,
  dt = 1,
  method = c("nsrp", "bartlett_lewis", "markov_gamma", "resample"),
  parameters = NULL,
  record = NULL,
  pet = list(mean = 1.5, amplitude = 1.3, peak_day = 182),
  block_days = 10,
  window_days = 15,
  seed = NULL
)
```

## Arguments

- start:

  First time, as text or POSIXct (UTC).

- years:

  Length in years (365 days each).

- dt:

  Step, hours: 0.25, 1, 24 or any value that divides a day or is a whole
  number of days.

- method:

  Generator; see the table.

- parameters:

  A parameter table from
  [`rain_parameters()`](https://jonpayneea.github.io/PDMS7/reference/rain_parameters.md)
  or
  [`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md).

- record:

  A rainfall record to fit or resample: a data frame with `time` (or
  `dateTime`) and `rain` (or `value`, mm per step), or an object from
  `reach.io::read_silver()`.

- pet:

  List of `mean` (mm per day), `amplitude` (mm per day) and `peak_day`
  (day of the year), or `NULL` for no PET column.

- block_days, window_days:

  For `resample`: block length and how far, in days, from the same date
  a block may be drawn.

- seed:

  Optional seed; the caller's random state is left untouched.

## Value

A data frame with `time` (POSIXct, UTC), `rain` and, unless
`pet = NULL`, `pet`, both mm per step, ready for
[`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md)
or
[`synthetic_catchment()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_catchment.md).
Attributes record the method and the parameters used.

## Details

- `nsrp` (default): Neyman-Scott rectangular pulses. Storms arrive at
  random, each spawning a random number of rain cells, delayed from the
  storm's origin, each with its own duration and intensity (Cowpertwait
  1996). Widely used for UK rainfall. Any step.

- `bartlett_lewis`: Bartlett-Lewis rectangular pulses. As above, but a
  storm produces cells at a steady rate until it stops (Rodriguez-Iturbe
  et al. 1987; the original model, with a fixed cell duration rate). Any
  step.

- `markov_gamma`: wet and dry days from a two-state Markov chain,
  wet-day amounts from a gamma distribution (Richardson 1981). Daily
  only.

- `resample`: a seasonal block bootstrap of a real record: blocks of
  whole days drawn from any year within a few weeks of the same date.
  The rain is real; the sequence is new. It cannot produce a storm
  bigger than the record holds. The record's step, or a multiple.

Parameters vary by calendar month. Without `parameters` or `record`, the
built-in illustrative values of
[`rain_parameters()`](https://jonpayneea.github.io/PDMS7/reference/rain_parameters.md)
are used. With `record`, the generator is first fitted to it by
[`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md)
(for `resample`, the record is used directly).

PET follows a sine curve through the year (as reach.io's
`generate_pe_sine()` does), peaking at `pet$peak_day`, and is spread
evenly over the steps of each day. It is never negative.

## References

Cowpertwait, P.S.P. (1996) Further developments of the Neyman-Scott
clustered point process for modeling rainfall. Water Resources Research
32(7), 2155-2164.

Rodriguez-Iturbe, I., Cox, D.R. and Isham, V. (1987) Some models for
rainfall based on stochastic point processes. Proceedings of the Royal
Society of London A 410, 269-288.

Richardson, C.W. (1981) Stochastic simulation of daily precipitation,
temperature, and solar radiation. Water Resources Research 17(1),
182-190.

## See also

[`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md),
[`rain_parameters()`](https://jonpayneea.github.io/PDMS7/reference/rain_parameters.md),
[`synthetic_catchment()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_catchment.md)

## Examples

``` r
hourly <- synthetic_rain("2020-10-01", years = 1, seed = 1)
sum(hourly$rain)
#> [1] 841.8127
daily <- synthetic_rain("2020-10-01", years = 2, dt = 24, method = "markov_gamma", seed = 1)
head(daily)
#>         time     rain      pet
#> 1 2020-10-01 7.327184 1.462267
#> 2 2020-10-02 2.397931 1.439920
#> 3 2020-10-03 0.000000 1.417591
#> 4 2020-10-04 0.000000 1.395286
#> 5 2020-10-05 4.307307 1.373012
#> 6 2020-10-06 0.000000 1.350776
```
