# Create FlodePdmModel

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
FlodePdmModel(
  distribution = FlodeCapacityDistribution(),
  recharge = FlodeRecharge(),
  surface = FlodeRouting(),
  groundwater = FlodeRouting(),
  be = integer(0),
  fc = integer(0),
  td = integer(0),
  qc = integer(0),
  area_km2 = integer(0),
  dt = integer(0)
)
```

## Arguments

- distribution:

  An S7 capacity distribution object.

- recharge:

  An S7 recharge component.

- surface:

  An S7 fast routing component, or initial routing storage vector in mm
  for state functions.

- groundwater:

  An S7 slow routing component, or initial storage vector in mm for
  state functions.

- be:

  Positive exponent in the actual evaporation function.

- fc:

  Nonnegative dimensionless rainfall correction factor.

- td:

  Nonnegative common outlet delay in hours.

- qc:

  Finite signed external constant flow in cubic metres per second.

- area_km2:

  Positive catchment area in square kilometres.

- dt:

  Positive model interval in hours. Internal paper equations use hours.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
pdm_model()
#> <pdmS7::FlodePdmModel>
#>  @ distribution: <pdmS7::FlodeParetoCapacity>
#>  .. @ cmin: num 0
#>  .. @ cmax: num 140
#>  .. @ b   : num 0.4
#>  @ recharge    : <pdmS7::FlodeStandardRecharge>
#>  .. @ kg: num 24
#>  .. @ bg: num 1
#>  .. @ st: num 0
#>  @ surface     : <pdmS7::FlodeCascadeRouting>
#>  .. @ k1: num 2
#>  .. @ k2: num 4
#>  @ groundwater : <pdmS7::FlodePowerRouting>
#>  .. @ k     : num 1e-04
#>  .. @ m     : num 3
#>  .. @ solver: chr "adaptive"
#>  .. @ rtol  : num 1e-08
#>  .. @ atol  : num 1e-10
#>  @ be          : num 1
#>  @ fc          : num 1
#>  @ td          : num 0
#>  @ qc          : num 0
#>  @ area_km2    : num 1
#>  @ dt          : num 1
```
