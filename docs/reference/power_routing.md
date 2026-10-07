# Power routing

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
power_routing(
  k = 1/10000,
  m = 3,
  solver = "adaptive",
  rtol = 1e-08,
  atol = 1e-10
)
```

## Arguments

- k:

  Positive power-reservoir coefficient, in mm^(1-m) per hour.

- m:

  Positive power-reservoir exponent; 1, 2, and 3 give linear, quadratic,
  and cubic forms.

- solver:

  Character scalar: adaptive or smith. The Smith approximation requires
  m = 3.

- rtol:

  Positive relative integration tolerance; dimensionless.

- atol:

  Positive absolute integration tolerance in mm.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
power_routing(k = 0.0001, m = 2.5)
#> <pdmS7::FlodePowerRouting>
#>  @ k     : num 1e-04
#>  @ m     : num 2.5
#>  @ solver: chr "adaptive"
#>  @ rtol  : num 1e-08
#>  @ atol  : num 1e-10
```
