# Compatibility alias for FlodeStandardRecharge

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
StandardRecharge(kg = integer(0), bg = integer(0), st = integer(0))
```

## Arguments

- kg:

  Positive recharge coefficient, hour mm^(bg-1).

- bg:

  Positive recharge exponent.

- st:

  Nonnegative tension storage threshold in mm; cannot exceed basin
  capacity.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeStandardRecharge(24, 1, 0)
#> <pdmS7::FlodeStandardRecharge>
#>  @ kg: num 24
#>  @ bg: num 1
#>  @ st: num 0
```
