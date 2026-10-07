# Storage for flow

Call storage_for_flow(x, q), q in mm/hour. Cascade inverse initializes
both stores at equilibrium.

## Usage

``` r
storage_for_flow(x, ...)
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
storage_for_flow(linear_routing(24), q = 1)
#> [1] 24
```
