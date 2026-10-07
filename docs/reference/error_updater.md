# Error updater

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
error_updater(ar = c(0.7), ma = numeric(), scale = "additive", offset = 0)
```

## Arguments

- ar:

  Finite vector of R-convention autoregressive coefficients (negative
  phi in Moore).

- ma:

  Finite vector of moving-average coefficients in R convention.

- scale:

  Error scale: additive or log.

- offset:

  Nonnegative offset in cubic metres per second for log error updating.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
error_updater(ar = 0.7)
#> <pdmS7::FlodeErrorUpdater>
#>  @ ar    : num 0.7
#>  @ ma    : num(0) 
#>  @ scale : chr "additive"
#>  @ offset: num 0
```
