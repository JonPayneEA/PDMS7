# Rainfall generator parameters

The built-in parameters of each rainfall generator, one row per calendar
month. They are illustrative, chosen to resemble lowland England (about
760 mm a year, frontal winters and convective summers), and are not
fitted to any site. Use
[`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md)
for parameters that resemble a real gauge.

## Usage

``` r
rain_parameters(method = c("nsrp", "bartlett_lewis", "markov_gamma"))
```

## Arguments

- method:

  One of `nsrp`, `bartlett_lewis` or `markov_gamma`.

## Value

A data frame with `month` and the method's columns, classed
`pdm_rain_parameters`.

## Details

The Neyman-Scott values were set by hand. The Bartlett-Lewis values were
fitted to the Neyman-Scott model's own statistics, and the Markov chain
and gamma values to 200 years of its daily rain, so all three describe
the same climate.

- `nsrp`: `lambda` storms per hour; `beta` rate of the exponential delay
  from a storm's origin to each cell, per hour; `nu` mean cells per
  storm (Poisson); `eta` rate of the exponential cell duration, per
  hour; `mux` mean cell intensity, mm/h (exponential).

- `bartlett_lewis`: `lambda` storms per hour; `gamma` rate at which a
  storm stops producing cells, per hour; `beta` cell arrival rate while
  it does, per hour; `eta` and `mux` as above. A cell starts at the
  storm's origin.

- `markov_gamma`: `p01` chance a day is wet after a dry day; `p11` after
  a wet day; `shape` and `scale` of the gamma wet-day amount, mm.

## See also

[`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md),
[`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md)

## Examples

``` r
rain_parameters("nsrp")
#>    month    lambda       beta       nu       eta       mux
#> 1      1 0.0180000 0.08000000 4.000000 0.6000000 0.8000000
#> 2      2 0.0174641 0.09473721 3.933013 0.6602886 0.9607695
#> 3      3 0.0160000 0.13500000 3.750000 0.8250000 1.4000000
#> 4      4 0.0140000 0.19000000 3.500000 1.0500000 2.0000000
#> 5      5 0.0120000 0.24500000 3.250000 1.2750000 2.6000000
#> 6      6 0.0105359 0.28526279 3.066987 1.4397114 3.0392305
#> 7      7 0.0100000 0.30000000 3.000000 1.5000000 3.2000000
#> 8      8 0.0105359 0.28526279 3.066987 1.4397114 3.0392305
#> 9      9 0.0120000 0.24500000 3.250000 1.2750000 2.6000000
#> 10    10 0.0140000 0.19000000 3.500000 1.0500000 2.0000000
#> 11    11 0.0160000 0.13500000 3.750000 0.8250000 1.4000000
#> 12    12 0.0174641 0.09473721 3.933013 0.6602886 0.9607695
```
