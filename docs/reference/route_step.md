# Route step

Call route_step(x, storage, inflow, dt): storage in mm, inflow in
mm/hour, dt in hours. Returns storage, outflow (mm), q_mean and q_end
(mm/hour).

## Usage

``` r
route_step(x, ...)
```

## Arguments

- x:

  An S7 capacity, routing, or recharge component, as required by the
  generic.

- ...:

  Method arguments: see Details for the component-specific calling
  convention.

## Value

Numeric values or a component result as described in Details.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
route_step(linear_routing(24), storage = 1, inflow = 0.1, dt = 1)
#> $storage
#> [1] 1.057135
#> 
#> $outflow
#> [1] 0.04286524
#> 
#> $q_mean
#> [1] 0.04286524
#> 
#> $q_end
#> [1] 0.04404728
#> 
```
