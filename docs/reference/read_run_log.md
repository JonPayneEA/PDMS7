# Read the run log

With `options(pdmS7.run_log = "path/to/runs.csv")` or the environment
variable `PDMS7_RUN_LOG` set, every call of
[`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md),
and so
[`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
and
[`sim_snow_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_snow_pdm.md),
appends one row to that CSV file: when, who (declared name and login),
an optional `tag` from `options(pdmS7.run_tag = )`, the model's
[`pdm_fingerprint()`](https://jonpayneea.github.io/PDMS7/reference/pdm_fingerprint.md),
a checksum of the forcing, the period, engine and versions, run time,
and whether the run succeeded, with the error message if not. With a
register set (see
[`approved_configurations()`](https://jonpayneea.github.io/PDMS7/reference/approved_configurations.md)),
`approval` is `approved`, `superseded` or `unapproved`, with the project
and sign-off entry matched. Without one it is empty.

## Usage

``` r
read_run_log(path = .run_log_path())
```

## Arguments

- path:

  Path of the run log.

## Value

A data.table, one row per run; `timestamp`, `start` and `end` are UTC
date-times.

## Details

Calibration evaluations, spin-up cycles and the calibration log's own
reruns are not logged. Logging is off unless the option or variable is
set, and a logging failure warns once without stopping the run. A lock
serialises writers, so a team can share one file.

## Examples

``` r
log <- tempfile(fileext = ".csv")
old <- options(pdmS7.run_log = log, pdmS7.run_tag = "example")
run_pdm(pdm_model(), data.frame(rain = c(0, 5, 0), pet = 0.1))
#> $output
#>   step rain_mm rain_corrected_mm pet_mm     aet_mm aet_requested_mm recharge_mm
#> 1    1       0                 0    0.1 0.05000000       0.05000000    2.083333
#> 2    2       5                 5    0.1 0.04786667       0.04786667    1.994444
#> 3    3       0                 0    0.1 0.05030547       0.05030547    2.096061
#>   recharge_requested_mm direct_runoff_mm surface_input_mm groundwater_input_mm
#> 1              2.083333        0.0000000        0.0000000             2.083333
#> 2              1.994444        0.5188884        0.5188884             1.994444
#> 3              2.096061        0.0000000        0.0000000             2.096061
#>   surface_out_mm baseflow_out_mm q_natural_m3s        q_m3s    q_end_m3s
#> 1     0.00000000    0.0002260148  6.278188e-05 6.278188e-05 0.0002510917
#> 2     0.00900009    0.0032247763  3.395796e-03 3.395796e-03 0.0089311606
#> 3     0.04244326    0.0139508984  1.566504e-02 1.566504e-02 0.0217440394
#>   qs_end_unlagged_mmh qb_end_unlagged_mmh  soil_mm surface_mm groundwater_mm
#> 1          0.00000000        0.0009039303 47.86667  0.0000000       2.083107
#> 2          0.02538874        0.0067634400 50.30547  0.5098883       4.074327
#> 3          0.05494459        0.0233339555 48.15910  0.4674450       6.156437
#>   delay_mm saturated_fraction balance_error_mm
#> 1        0          0.1698131     7.105427e-15
#> 2        0          0.1810997     0.000000e+00
#> 3        0          0.1711463     0.000000e+00
#> 
#> $state
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 48.2
#>  @ surface              : num [1:2] 0.248 0.22
#>  @ groundwater          : num 6.16
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 3
#> 
#> $initial_state
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 50
#>  @ surface              : num [1:2] 0 0
#>  @ groundwater          : num 0
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 0
#> 
#> $model
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
#> 
#> $water_balance
#>     residual_mm max_abs_step_mm 
#>    7.105427e-15    7.105427e-15 
#> 
options(old)
read_run_log(log)
#>              timestamp   user  login     tag                      fingerprint
#>                 <POSc> <lgcl> <char>  <char>                           <char>
#> 1: 2026-11-01 18:37:55     NA   root example 63ffbc4eaec1be4bd83a1d7d6c2d3155
#>                            data_md5  rows  start    end dt_hours area_km2
#>                              <char> <int> <lgcl> <lgcl>    <int>    <int>
#> 1: ff782f33dc69b2be7e40ab367ad701a6     3     NA     NA        1        1
#>    engine  pdmS7      r seconds status message approval project sign_off
#>    <char> <char> <char>   <num> <char>  <char>   <lgcl>  <char>   <char>
#> 1:      c  0.3.1  4.3.3   0.007     ok               NA                 
```
