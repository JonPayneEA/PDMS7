# Create FlodeExponentialRouting

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
FlodeExponentialRouting(a = integer(0), gamma = integer(0))
```

## Arguments

- a:

  Positive exponential-routing slope, per mm.

- gamma:

  Finite exponential-routing log-flow intercept, flow measured in
  mm/hour.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeExponentialRouting(0.05, -5)
#> <pdmS7::FlodeExponentialRouting>
#>  @ a    : num 0.05
#>  @ gamma: num -5
```
