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
#> 2:     2      10                10   0.05 0.02394583       0.02394583
#> 3:     3       5                 5   0.05 0.02719677       0.02719677
#>    recharge_mm recharge_requested_mm direct_runoff_mm surface_input_mm
#>          <num>                 <num>            <num>            <num>
#> 1:    2.083333              2.083333        0.0000000        0.0000000
#> 2:    1.995486              1.995486        1.4786896        1.4786896
#> 3:    2.266398              2.266398        0.5585773        0.5585773
#>    groundwater_input_mm surface_out_mm baseflow_out_mm q_natural_m3s
#>                   <num>          <num>           <num>         <num>
#> 1:             2.083333     0.00000000    0.0002260148  6.278188e-05
#> 2:             1.995486     0.02564779    0.0032266271  8.020672e-03
#> 3:             2.266398     0.13064014    0.0147425057  4.038407e-02
#>        qsim_cms qsim_end_cms qs_end_unlagged_mmh qb_end_unlagged_mmh
#>           <num>        <num>               <num>               <num>
#> 1: 6.278188e-05 0.0002510917          0.00000000        0.0009039303
#> 2: 8.020672e-03 0.0219776566          0.07235094        0.0067686196
#> 3: 4.038407e-02 0.0581209790          0.18390769        0.0253278331
#>    soil_moisture_mm surface_mm groundwater_mm delay_mm saturated_fraction
#>               <num>      <num>          <num>    <num>              <num>
#> 1:         47.89167   0.000000       2.083107        0          0.1699269
#> 2:         54.39355   1.453042       4.075367        0          0.2009408
#> 3:         56.54137   1.880979       6.327022        0          0.2118786
#>    balance_error_mm datetime is_warmup
#>               <num>   <POSc>    <lgcl>
#> 1:     7.105427e-15     <NA>     FALSE
#> 2:     0.000000e+00     <NA>     FALSE
#> 3:     1.421085e-14     <NA>     FALSE
```
