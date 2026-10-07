# Recharge depth

Call recharge_depth(x, soil, smax, groundwater, routing, dt). Storages
are mm, dt hours, returned recharge is an interval depth in mm.

## Usage

``` r
recharge_depth(x, ...)
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
recharge_depth(FlodeStandardRecharge(24, 1, 0), soil = 50, smax = 100,
  groundwater = 0, routing = linear_routing(24), dt = 1)
#> [1] 2.083333
```
