# Pdm step

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
pdm_step(model, state, rain, pet)
```

## Arguments

- model:

  A FlodePdmModel compatible with the supplied state.

- state:

  A compatible FlodePdmState; NULL in sim_pdm initializes the model.

- rain:

  Nonnegative interval rainfall depth in mm.

- pet:

  Nonnegative interval potential evaporation depth in mm.

## Value

A list with state and a one-row flux data.frame.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
model <- pdm_model()
pdm_step(model, initial_state(model), rain = 10, pet = 0.05)
#> $state
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 56.4
#>  @ surface              : num [1:2] 1.212 0.301
#>  @ groundwater          : num 2.08
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 1
#> 
#> $flux
#>   step rain_mm rain_corrected_mm pet_mm aet_mm aet_requested_mm recharge_mm
#> 1    1      10                10   0.05  0.025            0.025    2.083333
#>   recharge_requested_mm direct_runoff_mm surface_input_mm groundwater_input_mm
#> 1              2.083333         1.539898         1.539898             2.083333
#>   surface_out_mm baseflow_out_mm q_natural_m3s       q_m3s  q_end_m3s
#> 1     0.02670945    0.0002260148   0.007482073 0.007482073 0.02118048
#>   qs_end_unlagged_mmh qb_end_unlagged_mmh  soil_mm surface_mm groundwater_mm
#> 1          0.07534581        0.0009039303 56.35177   1.513189       2.083107
#>   delay_mm saturated_fraction balance_error_mm
#> 1        0          0.2108977     7.105427e-15
#> 
```
