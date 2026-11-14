# Pdm step

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
pdm_step(model, state, rain, pet, abstraction = 0)
```

## Arguments

- model:

  A FlodePdmModel compatible with the supplied state.

- state:

  A compatible FlodePdmState; NULL in sim_pdm initializes the model.

- rain:

  Nonnegative interval rainfall depth in mm.

- pet:

  Interval potential evaporation depth in mm. Negative values are
  condensation and add their whole depth to the soil store.

- abstraction:

  Recorded abstraction over the interval, mm, for a model with the
  groundwater extension
  ([`groundwater_extension()`](https://jonpayneea.github.io/PDMS7/reference/groundwater_extension.md));
  negative for a gain.

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
#>  @ soil                 : num 115
#>  @ surface              : num [1:2] 1.477 0.367
#>  @ groundwater          : num 0.0268
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 1
#> 
#> $flux
#>   step rain_mm rain_corrected_mm pet_mm aet_mm aet_requested_mm recharge_mm
#> 1    1      10                10   0.05  0.025            0.025  0.02678571
#>   recharge_requested_mm direct_runoff_mm surface_input_mm groundwater_input_mm
#> 1            0.02678571          1.87713          1.87713           0.02678571
#>   surface_out_mm baseflow_out_mm q_natural_m3s       q_m3s  q_end_m3s
#> 1     0.03255872    4.804517e-10   0.009044088 0.009044088 0.02551285
#>   qs_end_unlagged_mmh qb_end_unlagged_mmh  soil_mm surface_mm groundwater_mm
#> 1          0.09184627        1.921807e-09 115.2139   1.844571     0.02678571
#>   delay_mm saturated_fraction balance_error_mm
#> 1        0          0.1978172    -1.421085e-14
#> 
```
