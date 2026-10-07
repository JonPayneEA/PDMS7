# Quadratic routing

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
quadratic_routing(kb = 1000)
```

## Arguments

- kb:

  Positive reciprocal rate coefficient: hour mm^(m-1).

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
quadratic_routing(kb = 1000)
#> <pdmS7::FlodePowerRouting>
#>  @ k     : num 0.001
#>  @ m     : num 2
#>  @ solver: chr "adaptive"
#>  @ rtol  : num 1e-08
#>  @ atol  : num 1e-10
```
