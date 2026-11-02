# Fit error updater

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
fit_error_updater(
  observed,
  simulated,
  order = c(3, 0),
  scale = "additive",
  offset = 0
)
```

## Arguments

- observed:

  Observed discharges in cubic metres per second, aligned to forcing or
  simulation.

- simulated:

  Complete simulated discharges aligned with observed, cubic metres per
  second.

- order:

  Integer vector c(p,q) of nonnegative AR and MA orders.

- scale:

  Error scale: additive or log.

- offset:

  Nonnegative offset in cubic metres per second for log error updating.

## Value

A list with an S7 updater and fitted stats::arima object. The fit is by
exact maximum likelihood; if that optimisation fails, as it can on long
or awkward error series, conditional sum of squares then maximum
likelihood is tried, then conditional sum of squares alone. The method
used is the arima object's `method` element, and a message names any
fallback.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
fit_error_updater(c(1, 2, 1, 3, 2, 1, 2, 4), rep(1, 8), order = c(0, 0))
#> $updater
#> <pdmS7::FlodeErrorUpdater>
#>  @ ar    : num(0) 
#>  @ ma    : num(0) 
#>  @ scale : chr "additive"
#>  @ offset: num 0
#> 
#> $fit
#> 
#> Call:
#> stats::arima(x = ..1, order = ..2, include.mean = FALSE, method = ..4, optim.control = ..5)
#> 
#> 
#> sigma^2 estimated as 2:  log likelihood = -14.12,  aic = 30.25
#> 
```
