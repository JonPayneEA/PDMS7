# Linear routing

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
linear_routing(kb = 24)
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
linear_routing(kb = 24)
#> <pdmS7::FlodePowerRouting>
#>  @ k     : num 0.0417
#>  @ m     : num 1
#>  @ solver: chr "adaptive"
#>  @ rtol  : num 1e-08
#>  @ atol  : num 1e-10
```
