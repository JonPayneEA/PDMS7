# A prior for a parameter

Priors for
[`calibrate_bayes()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_bayes.md),
each truncated to the parameter's bounds. `prior_uniform()` says only
that the value lies within its bounds. `prior_normal()` and
`prior_lognormal()` say what value is expected and how sure that is:
from experience, from a regional study, or from a model of parameters
from catchment descriptors trained on many catchments. Where the record
pins a parameter down, the data win; where it cannot, the prior keeps
the parameter sensible instead of letting it wander to a bound.

## Usage

``` r
prior_uniform()

prior_normal(mean, sd)

prior_lognormal(median, sdlog)
```

## Arguments

- mean, sd:

  Mean and standard deviation of a normal prior, in the parameter's
  units.

- median, sdlog:

  A lognormal prior: its median and the standard deviation of
  log(value); sdlog 0.3 means about 30% either way.

## Value

A prior: a list with `type` and its numbers.

## See also

[`calibrate_bayes()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_bayes.md)

## Examples

``` r
prior_lognormal(median = 250, sdlog = 0.3)   # cmax about 250 mm, give or take 30%
#> $type
#> [1] "lognormal"
#> 
#> $meanlog
#> [1] 5.521461
#> 
#> $sdlog
#> [1] 0.3
#> 
```
