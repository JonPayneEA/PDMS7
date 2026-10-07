# Transfer coefficients

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
transfer_coefficients(k1, k2, dt = 1)
```

## Arguments

- k1:

  Positive first linear-reservoir time constant, hours.

- k2:

  Positive second linear-reservoir time constant, hours.

- dt:

  Positive model interval in hours. Internal paper equations use hours.

## Value

Named numeric vector delta1, delta2, omega0, omega1 for endpoint
recursion.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
transfer_coefficients(k1 = 2, k2 = 4, dt = 0.25)
#>       delta1       delta2       omega0       omega1 
#> -1.821909965  0.829029118  0.003670777  0.003448376 
```
