# Staged calibration

Calibrates in stages, each fitting some parameters with the others fixed
at the values the stage before left them: by default the water balance
and slow response, then the fast response, then a short joint polish.
See
[`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md)
for the stages and how to change them.

## Usage

``` r
calibrate_staged(
  config,
  forcing,
  observed,
  stages = pdm_stages(config),
  bounds = calibration_bounds(config),
  warmup = 0,
  starts = 1L,
  seed = NULL,
  control = list(maxit = 200),
  method = c("lbfgsb", "nelder_mead"),
  soil_fraction = 0.5,
  log_offset = 0.01
)

log_staged_calibration(
  project,
  parent,
  reasoning,
  stages = NULL,
  bounds = NULL,
  starts = 1L,
  seed = NULL,
  control = list(maxit = 200),
  method = c("lbfgsb", "nelder_mead")
)
```

## Arguments

- config:

  A configuration list, the starting point.

- forcing, observed, warmup, soil_fraction, log_offset:

  Passed to
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

- stages:

  Stages from
  [`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md),
  or your own.

- bounds:

  Bounds table from
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md).

- starts, seed, control, method:

  Passed to
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  for every stage.

- project:

  A calibration project folder.

- parent:

  Id of the entry to start from, usually the structure.

- reasoning:

  Free text recorded with every stage.

## Value

`calibrate_staged()`: a list with `config`, `model`, `parameters` (every
calibrated value), and `stages`, one
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
result per stage with its `label`. `log_staged_calibration()`: the stage
entries, invisibly.

## Details

`calibrate_staged()` works on data in memory. `log_staged_calibration()`
does the same inside a calibration project, writing one
`auto_calibration` entry per stage, each the parent of the next, with
its stage recorded, so a reviewer can see what each stage changed.

## See also

[`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md),
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md),
[`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)

## Examples

``` r
set.seed(2)
n <- 24 * 20
forcing <- data.frame(rain = ifelse(runif(n) < 0.08, rgamma(n, 0.7, scale = 4), 0),
                      pet = 0.05)
config <- pdm_presets("standard")
truth <- config
truth$fc <- 1.2
truth$surface$k1 <- 4
observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s
fit <- calibrate_staged(config, forcing, observed, warmup = 48,
                        control = list(maxit = 20))
round(fit$parameters, 2)
#>                fc distribution.cmax    distribution.b       recharge.kg 
#>              1.20            142.50              0.43             23.99 
#>    groundwater.kb        surface.k1        surface.k2 
#>          10220.87              4.12              4.11 
```
