# Capacity from storage

Call capacity_from_storage(x, s), where 0 \<= s \<= Smax. Unbounded laws
return Inf at Smax.

## Usage

``` r
capacity_from_storage(x, ...)
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
capacity_from_storage(FlodeExponentialCapacity(100), s = 50)
#> [1] 69.31472
```
