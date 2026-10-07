# Soil step

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
soil_step(distribution, storage, net_depth)
```

## Arguments

- distribution:

  An S7 capacity distribution object.

- storage:

  Basin soil storage in mm for soil_step.

- net_depth:

  Signed net interval depth in mm, after evaporation and recharge.

## Value

A list with storage and runoff, both in mm.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
soil_step(FlodeParetoCapacity(0, 140, 0.4), storage = 50, net_depth = 10)
#> $storage
#> [1] 58.00635
#> 
#> $runoff
#> [1] 1.993649
#> 
```
