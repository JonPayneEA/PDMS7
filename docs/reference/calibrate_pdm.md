# Calibrate pdm

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
calibrate_pdm(
  config,
  forcing,
  observed,
  lower,
  upper,
  warmup = 0,
  objective = c("rmse", "nse", "log_rmse"),
  flow = c("q_m3s", "q_end_m3s"),
  log_offset = 0.01,
  control = list(maxit = 200),
  soil_fraction = 0.5
)
```

## Arguments

- config:

  Named model configuration list; unknown keys are rejected.

- forcing:

  Data frame or data.table with rain and pet depths in mm per interval;
  optional POSIXct time.

- observed:

  Observed discharges in cubic metres per second, aligned to forcing or
  simulation.

- lower:

  Finite named lower calibration bounds. Names are configuration paths
  such as surface.k1.

- upper:

  Finite named upper calibration bounds with the same names/order as
  lower.

- warmup:

  Number of initial forcing steps excluded from calibration scoring, but
  still simulated.

- objective:

  Calibration objective: rmse, nse (minimizes 1-NSE), or log_rmse.

- flow:

  Series to score: q_m3s (interval mean) or q_end_m3s (endpoint flow).

- log_offset:

  Positive offset added before logarithms in log-RMSE, cubic metres per
  second.

- control:

  Named control list forwarded to stats::optim.

- soil_fraction:

  Initial fraction of basin capacity between zero and one.

## Value

A list of config, model, parameters, objective, convergence, message,
and optim diagnostics.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
config <- pdm_presets('standard')
f <- data.frame(rain = c(0, 10, 2, 0), pet = rep(0.05, 4))
q <- run_pdm(pdm_from_config(config), f)$output$q_m3s
calibrate_pdm(config, f, q, lower = c(fc = 0.8), upper = c(fc = 1.2),
  control = list(maxit = 2))
#> $config
#> $config$distribution
#> $config$distribution$type
#> [1] "pareto"
#> 
#> $config$distribution$cmin
#> [1] 0
#> 
#> $config$distribution$cmax
#> [1] 140
#> 
#> $config$distribution$b
#> [1] 0.4
#> 
#> 
#> $config$recharge
#> $config$recharge$type
#> [1] "standard"
#> 
#> $config$recharge$kg
#> [1] 24
#> 
#> $config$recharge$bg
#> [1] 1
#> 
#> $config$recharge$st
#> [1] 0
#> 
#> 
#> $config$surface
#> $config$surface$type
#> [1] "cascade"
#> 
#> $config$surface$k1
#> [1] 2
#> 
#> $config$surface$k2
#> [1] 4
#> 
#> 
#> $config$groundwater
#> $config$groundwater$type
#> [1] "cubic"
#> 
#> $config$groundwater$kb
#> [1] 10000
#> 
#> $config$groundwater$solver
#> [1] "adaptive"
#> 
#> 
#> $config$be
#> [1] 1
#> 
#> $config$fc
#> fc 
#>  1 
#> 
#> $config$td
#> [1] 0
#> 
#> $config$qc
#> [1] 0
#> 
#> $config$area_km2
#> [1] 1
#> 
#> $config$dt
#> [1] 1
#> 
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
#>  @ fc          : Named num 1
#>  .. - attr(*, "names")= chr "fc"
#>  @ td          : num 0
#>  @ qc          : num 0
#>  @ area_km2    : num 1
#>  @ dt          : num 1
#> 
#> $parameters
#> fc 
#>  1 
#> 
#> $objective
#> [1] 0
#> 
#> $objective_name
#> [1] "rmse"
#> 
#> $convergence
#> [1] 52
#> 
#> $message
#> [1] "ERROR: ABNORMAL_TERMINATION_IN_LNSRCH"
#> 
#> $optim
#> $optim$par
#>  fc 
#> 0.5 
#> 
#> $optim$value
#> [1] 0
#> 
#> $optim$counts
#> function gradient 
#>       21       21 
#> 
#> $optim$convergence
#> [1] 52
#> 
#> $optim$message
#> [1] "ERROR: ABNORMAL_TERMINATION_IN_LNSRCH"
#> 
#> 
```
