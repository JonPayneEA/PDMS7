# Compatibility alias for FlodeParetoCapacity

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
ParetoCapacity(cmin = integer(0), cmax = integer(0), b = integer(0))
```

## Arguments

- cmin:

  Minimum point storage capacity in mm; nonnegative and below cmax.

- cmax:

  Maximum point storage capacity in mm; strictly above cmin.

- b:

  Nonnegative Pareto shape exponent; zero represents a point mass at
  cmax.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeParetoCapacity(0, 140, 0.4)
#> <pdmS7::FlodeParetoCapacity>
#>  @ cmin: num 0
#>  @ cmax: num 140
#>  @ b   : num 0.4
```
