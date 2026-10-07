# Spin up

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
spin_up(model, forcing, cycles = 5, state = initial_state(model))
```

## Arguments

- model:

  A FlodePdmModel compatible with the supplied state.

- forcing:

  Data frame or data.table with rain and pet depths in mm per interval;
  optional POSIXct time.

- cycles:

  Positive integer number of complete spin-up forcing cycles.

- state:

  A compatible FlodePdmState; NULL in sim_pdm initializes the model.

## Value

A FlodePdmState after the requested cycles.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
spin_up(pdm_model(), data.frame(rain = c(0, 10), pet = c(0.05, 0.05)), cycles = 2)
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 58.3
#>  @ surface              : num [1:2] 1.69 1.04
#>  @ groundwater          : num 8.46
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 0
```
