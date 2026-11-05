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
#> 1    1       0                 0    0.1 0.05000000       0.05000000  0.02678571
#> 2    2       5                 5    0.1 0.04996417       0.04996417  0.02676652
#> 3    3       0                 0    0.1 0.05183909       0.05183909  0.02777094
#>   recharge_requested_mm direct_runoff_mm surface_input_mm groundwater_input_mm
#> 1            0.02678571        0.0000000        0.0000000           0.02678571
#> 2            0.02676652        0.9055708        0.9055708           0.02676652
#> 3            0.02777094        0.0000000        0.0000000           0.02777094
#>   surface_out_mm baseflow_out_mm q_natural_m3s        q_m3s    q_end_m3s
#> 1     0.00000000    4.804517e-10  1.334588e-10 1.334588e-10 5.338352e-10
#> 2     0.01570708    7.200921e-09  4.363078e-03 4.363078e-03 1.230799e-02
#> 3     0.07407252    3.196982e-08  2.057571e-02 2.057571e-02 2.663613e-02
#>   qs_end_unlagged_mmh qb_end_unlagged_mmh  soil_mm surface_mm groundwater_mm
#> 1          0.00000000        1.921807e-09 107.0661  0.0000000     0.02678571
#> 2          0.04430876        1.535793e-08 111.0838  0.8898637     0.05355222
#> 3          0.09589001        5.378267e-08 111.0042  0.8157912     0.08132313
#>   delay_mm saturated_fraction balance_error_mm
#> 1        0          0.1794967     0.000000e+00
#> 2        0          0.1884013     0.000000e+00
#> 3        0          0.1882225     1.421085e-14
#> 
#> $state
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 111
#>  @ surface              : num [1:2] 0.432 0.384
#>  @ groundwater          : num 0.0813
#>  @ delay_surface        : num 0
#>  @ delay_groundwater    : num 0
#>  @ delay_surface_end    : num 0
#>  @ delay_groundwater_end: num 0
#>  @ step                 : num 3
#> 
#> $initial_state
#> <pdmS7::FlodePdmState>
#>  @ soil                 : num 107
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
#>  .. @ cmax: num 300
#>  .. @ b   : num 0.4
#>  @ recharge    : <pdmS7::FlodeStandardRecharge>
#>  .. @ kg: num 4000
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
#>    1.421085e-14    1.421085e-14 
#> 
options(old)
read_run_log(log)
#>              timestamp   user  login     tag                      fingerprint
#>                 <POSc> <lgcl> <char>  <char>                           <char>
#> 1: 2026-11-02 22:02:50     NA   root example 5edf9f4dd6c43fa6056569c2474a2767
#>                            data_md5  rows  start    end dt_hours area_km2
#>                              <char> <int> <lgcl> <lgcl>    <int>    <int>
#> 1: ff782f33dc69b2be7e40ab367ad701a6     3     NA     NA        1        1
#>    engine  pdmS7      r seconds status message approval project sign_off
#>    <char> <char> <char>   <num> <char>  <char>   <lgcl>  <char>   <char>
#> 1:      c  0.6.0  4.3.3   0.007     ok               NA                 
```
