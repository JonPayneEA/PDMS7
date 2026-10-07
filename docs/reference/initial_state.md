# Initial state

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
initial_state(model, soil_fraction = 0.5, surface = NULL, groundwater = NULL)
```

## Arguments

- model:

  A FlodePdmModel compatible with the supplied state.

- soil_fraction:

  Initial fraction of basin capacity between zero and one.

- surface:

  An S7 fast routing component, or initial routing storage vector in mm
  for state functions.

- groundwater:

  An S7 slow routing component, or initial storage vector in mm for
  state functions.

## Value

A validated FlodePdmState.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
initial_state(pdm_model(), soil_fraction = 0.5)
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
