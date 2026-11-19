# Priors from a table of predicted parameters

Turns a table such as a model of parameters from catchment descriptors
would give, one row per parameter, into the priors of
[`calibrate_bayes()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_bayes.md):
a lognormal prior where the table has `median` and `sdlog` (for
parameters that must be positive, such as store capacities and time
constants), a normal prior where it has `mean` and `sd`. `widen`
multiplies every spread, to allow for the prediction being for a
catchment the model has not seen.

## Usage

``` r
priors_from_table(table, widen = 1)
```

## Arguments

- table:

  A data frame with `parameter` and either `median` and `sdlog`, or
  `mean` and `sd`, for each row.

- widen:

  Factor on every spread.

## Value

A named list of priors.

## See also

[`calibrate_bayes()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_bayes.md),
[`prior_lognormal()`](https://jonpayneea.github.io/PDMS7/reference/prior_uniform.md)

## Examples

``` r
priors_from_table(data.frame(parameter = c("distribution.cmax", "fc"),
                             median = c(250, NA), sdlog = c(0.3, NA),
                             mean = c(NA, 1), sd = c(NA, 0.1)))
#> $distribution.cmax
#> $distribution.cmax$type
#> [1] "lognormal"
#> 
#> $distribution.cmax$meanlog
#> [1] 5.521461
#> 
#> $distribution.cmax$sdlog
#> [1] 0.3
#> 
#> 
#> $fc
#> $fc$type
#> [1] "normal"
#> 
#> $fc$mean
#> [1] 1
#> 
#> $fc$sd
#> [1] 0.1
#> 
#> 
```
