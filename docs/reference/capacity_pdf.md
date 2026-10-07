# Capacity pdf

Call capacity_pdf(x, c). The Pareto b=0 point mass has no ordinary
density.

## Usage

``` r
capacity_pdf(x, ...)
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
capacity_pdf(FlodeExponentialCapacity(100), c = c(0, 100))
#> [1] 0.010000000 0.003678794
```
