# Compatibility alias for FlodeExponentialCapacity

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
ExponentialCapacity(mean = integer(0))
```

## Arguments

- mean:

  Positive mean point capacity in mm.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeExponentialCapacity(100)
#> <pdmS7::FlodeExponentialCapacity>
#>  @ mean: num 100
```
