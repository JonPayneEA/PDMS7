# Correct state

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
correct_state(model, state, observed_m3s, updater = state_updater())
```

## Arguments

- model:

  A FlodePdmModel compatible with the supplied state.

- state:

  A compatible FlodePdmState; NULL in sim_pdm initializes the model.

- observed_m3s:

  Finite observed endpoint flow in cubic metres per second; td must be
  zero.

- updater:

  A compatible FlodeStateUpdater or FlodeErrorUpdater object.

## Value

A list containing corrected state, external correction_mm, corrected
flow, innovation, and proportion.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
model <- pdm_model()
correct_state(model, initial_state(model), observed_m3s = 0.1)
#> $state
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 50
#>  @ surface              : num [1:2] 0 1.44
#>  @ groundwater          : num 0
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 0
#> 
#> $correction_mm
#> [1] 1.44
#> 
#> $q_corrected_m3s
#> [1] 0.1
#> 
#> $innovation_mmh
#> [1] 0.36
#> 
#> $alpha
#> [1] 0
#> 
```
