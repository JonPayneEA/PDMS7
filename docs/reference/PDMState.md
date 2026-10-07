# Compatibility alias for FlodePdmState

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
PDMState(
  soil = integer(0),
  surface = integer(0),
  groundwater = integer(0),
  delay_surface = integer(0),
  delay_groundwater = integer(0),
  delay_surface_end = integer(0),
  delay_groundwater_end = integer(0),
  step = integer(0)
)
```

## Arguments

- soil:

  Scalar nonnegative basin soil storage in mm.

- surface:

  An S7 fast routing component, or initial routing storage vector in mm
  for state functions.

- groundwater:

  An S7 slow routing component, or initial storage vector in mm for
  state functions.

- delay_surface:

  Nonnegative pending fast-path outlet volumes in mm.

- delay_groundwater:

  Nonnegative pending slow-path outlet volumes in mm.

- delay_surface_end:

  Nonnegative pending fast-path endpoint rates in mm/hour.

- delay_groundwater_end:

  Nonnegative pending slow-path endpoint rates in mm/hour.

- step:

  Nonnegative integer-valued completed interval count.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
initial_state(pdm_model())
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 50
#>  @ surface              : num [1:2] 0 0
#>  @ groundwater          : num 0
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 0
```
