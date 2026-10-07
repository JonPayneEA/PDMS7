# Create FlodeSplitRecharge

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
FlodeSplitRecharge(alpha = integer(0))
```

## Arguments

- alpha:

  Demand deficit threshold in `(0,1]`, or fast-path split fraction in
  `[0,1]`.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeSplitRecharge(0.7)
#> <pdmS7::FlodeSplitRecharge>
#>  @ alpha: num 0.7
```
