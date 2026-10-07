# Storage from capacity

Call storage_from_capacity(x, c); integrates the capacity survival
function.

## Usage

``` r
storage_from_capacity(x, ...)
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
storage_from_capacity(FlodeExponentialCapacity(100), c = 50)
#> [1] 39.34693
```
