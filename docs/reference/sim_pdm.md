# Sim pdm

All intervals are retained. Warm-up is flagged rather than removed. The
attributes final_state, model, and water_balance support restart and
diagnostics. With no datetime, timestamps remain UTC NA values. The
numerical engine retains the paper's hour-based coefficients.

## Usage

``` r
sim_pdm(
  rainfall_mm,
  pet_mm,
  params,
  timestep_min,
  warmup_steps = 0L,
  datetime = NULL,
  state = NULL
)
```

## Arguments

- rainfall_mm:

  Non-empty finite nonnegative numeric rainfall depths in mm per
  interval.

- pet_mm:

  Finite nonnegative numeric PET depths in mm per interval, equal length
  to rainfall_mm.

- params:

  A named configuration list or FlodePdmModel. For a list, timestep_min
  sets dt.

- timestep_min:

  Positive integer-valued interval in minutes; must match a supplied
  model.

- warmup_steps:

  Nonnegative integer number of rows flagged is_warmup, less than the
  forcing length.

- datetime:

  Optional aligned POSIXct interval-end timestamps. Converted to UTC
  without changing instants.

- state:

  A compatible FlodePdmState; NULL in sim_pdm initializes the model.

## Value

A data.table containing datetime (UTC), qsim_cms, qsim_end_cms,
soil_moisture_mm, groundwater_mm, is_warmup, and detailed fluxes. See
Details for attributes.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
sim_pdm(c(0, 10, 5), rep(0.05, 3), pdm_presets('standard'), 60L)
#>     step rain_mm rain_corrected_mm pet_mm     aet_mm aet_requested_mm
#>    <num>   <num>             <num>  <num>      <num>            <num>
#> 1:     1       0                 0   0.05 0.02500000       0.02500000
#> 2:     2      10                10   0.05 0.02498792       0.02498792
#> 3:     3       5                 5   0.05 0.02687144       0.02687144
#>    recharge_mm recharge_requested_mm direct_runoff_mm surface_input_mm
#>          <num>                 <num>            <num>            <num>
#> 1:  0.02678571            0.02678571         0.000000         0.000000
#> 2:  0.02677277            0.02677277         1.875989         1.875989
#> 3:  0.02879083            0.02879083         1.000306         1.000306
#>    groundwater_input_mm surface_out_mm baseflow_out_mm q_natural_m3s
#>                   <num>          <num>           <num>         <num>
#> 1:           0.02678571     0.00000000    4.804517e-10  1.334588e-10
#> 2:           0.02677277     0.03253893    7.202826e-09  9.038594e-03
#> 3:           0.02879083     0.17079962    3.278745e-08  4.744435e-02
#>        qsim_cms qsim_end_cms qs_end_unlagged_mmh qb_end_unlagged_mmh
#>           <num>        <num>               <num>               <num>
#> 1: 1.334588e-10 5.338352e-10          0.00000000        1.921807e-09
#> 2: 9.038594e-03 2.549735e-02          0.09179045        1.536330e-08
#> 3: 4.744435e-02 6.877522e-02          0.24759075        5.584436e-08
#>    soil_moisture_mm surface_mm groundwater_mm delay_mm saturated_fraction
#>               <num>      <num>          <num>    <num>              <num>
#> 1:         107.0911   0.000000     0.02678571        0          0.1795514
#> 2:         115.1633   1.843450     0.05355847        0          0.1977001
#> 3:         119.1074   2.672957     0.08234927        0          0.2069536
#>    balance_error_mm datetime is_warmup
#>               <num>   <POSc>    <lgcl>
#> 1:    -1.421085e-14     <NA>     FALSE
#> 2:     1.421085e-14     <NA>     FALSE
#> 3:     0.000000e+00     <NA>     FALSE
```
