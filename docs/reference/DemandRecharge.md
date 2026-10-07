# Compatibility alias for FlodeDemandRecharge

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
DemandRecharge(alpha = integer(0), beta = integer(0), qsat = integer(0))
```

## Arguments

- alpha:

  Demand deficit threshold in `(0,1]`, or fast-path split fraction in
  `[0,1]`.

- beta:

  Positive exponent of groundwater demand.

- qsat:

  Positive saturation recharge rate in mm/hour. Requires positive
  implied Sgmax.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeDemandRecharge(0.5, 1, 1)
#> <pdmS7::FlodeDemandRecharge>
#>  @ alpha: num 0.5
#>  @ beta : num 1
#>  @ qsat : num 1
```
