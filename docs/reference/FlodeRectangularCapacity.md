# Create FlodeRectangularCapacity

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
FlodeRectangularCapacity(cmin = integer(0), cmax = integer(0))
```

## Arguments

- cmin:

  Minimum point storage capacity in mm; nonnegative and below cmax.

- cmax:

  Maximum point storage capacity in mm; strictly above cmin.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeRectangularCapacity(0, 200)
#> <pdmS7::FlodeRectangularCapacity>
#>  @ cmin: num 0
#>  @ cmax: num 200
```
