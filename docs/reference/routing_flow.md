# Routing flow

Call routing_flow(x, storage), returning endpoint discharge in mm/hour.

## Usage

``` r
routing_flow(x, ...)
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
routing_flow(linear_routing(24), storage = 24)
#> [1] 1
```
