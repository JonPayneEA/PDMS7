# Rainfall statistics

Statistics of rain totals over intervals of a given length: mean,
variance, lag-1 autocorrelation and the proportion of dry intervals. For
a record they are computed from the data, month by month; for a pulse
model's parameters they are the model's exact values, which
[`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md)
matches to a record's.

## Usage

``` r
rain_statistics(x, hours = c(1, 24), wet_threshold = 0)
```

## Arguments

- x:

  A record (see
  [`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md))
  or a parameter table from
  [`rain_parameters()`](https://jonpayneea.github.io/PDMS7/reference/rain_parameters.md)
  or
  [`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md)
  for `nsrp` or `bartlett_lewis`.

- hours:

  Interval lengths, hours.

- wet_threshold:

  A record's interval counts as dry at or below this depth, mm. The
  pulse models' dry proportion is for exactly no rain, so compare them
  at 0.

## Value

A data frame: `month`, `hours`, `mean`, `variance`, `lag1`, `pdry`.

## Examples

``` r
rain_statistics(rain_parameters("nsrp"), hours = c(1, 24))[1:4, ]
#>   month hours       mean   variance      lag1      pdry
#> 1     1     1 0.09600000  0.1449931 0.7210184 0.8512635
#> 2     1    24 2.30400000 18.1775421 0.1535752 0.4503705
#> 3     2     1 0.09994407  0.1795131 0.7015838 0.8669296
#> 4     2    24 2.39865770 21.2954748 0.1367276 0.4856339
```
