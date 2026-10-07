# Cubic routing

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
cubic_routing(kb = 10000, solver = "adaptive")
```

## Arguments

- kb:

  Positive reciprocal rate coefficient: hour mm^(m-1).

- solver:

  Character scalar: adaptive or smith. The Smith approximation requires
  m = 3.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
cubic_routing(kb = 10000)
#> <pdmS7::FlodePowerRouting>
#>  @ k     : num 1e-04
#>  @ m     : num 3
#>  @ solver: chr "adaptive"
#>  @ rtol  : num 1e-08
#>  @ atol  : num 1e-10
```
