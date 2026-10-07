# Capacity mean

Returns mean point capacity, also maximum basin soil storage Smax, in
mm.

## Usage

``` r
capacity_mean(x, ...)
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
capacity_mean(FlodeParetoCapacity(0, 140, 0.4))
#> [1] 100
```
