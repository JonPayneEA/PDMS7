# Compatibility alias for FlodeLognormalCapacity

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
LognormalCapacity(meanlog = integer(0), sdlog = integer(0))
```

## Arguments

- meanlog:

  Finite mean of log point capacity (capacity measured in mm).

- sdlog:

  Positive standard deviation of log point capacity.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeLognormalCapacity(log(100) - 0.5, 1)
#> <pdmS7::FlodeLognormalCapacity>
#>  @ meanlog: num 4.11
#>  @ sdlog  : num 1
```
