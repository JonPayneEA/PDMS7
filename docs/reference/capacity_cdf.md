# Capacity cdf

Call capacity_cdf(x, c) for nonnegative point capacities c in mm.

## Usage

``` r
capacity_cdf(x, ...)
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
capacity_cdf(FlodeParetoCapacity(0, 140, 0.4), c = c(0, 70, 140))
#> [1] 0.0000000 0.2421417 1.0000000
```
