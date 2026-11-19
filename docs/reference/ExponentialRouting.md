# Compatibility alias for FlodeExponentialRouting

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
ExponentialRouting(a = integer(0), gamma = integer(0))
```

## Arguments

- a:

  Positive exponential-routing slope, per mm.

- gamma:

  Finite exponential-routing log-flow intercept, flow measured in
  mm/hour. It fixes only the zero of the storage coordinate: the flow
  depends on `a` alone once the store starts from a flow, so calibration
  holds `gamma` at its value.

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
