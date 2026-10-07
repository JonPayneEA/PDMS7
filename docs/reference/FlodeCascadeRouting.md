# Create FlodeCascadeRouting

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
FlodeCascadeRouting(k1 = integer(0), k2 = integer(0))
```

## Arguments

- k1:

  Positive first linear-reservoir time constant, hours.

- k2:

  Positive second linear-reservoir time constant, hours.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeCascadeRouting(2, 4)
#> <pdmS7::FlodeCascadeRouting>
#>  @ k1: num 2
#>  @ k2: num 4
```
