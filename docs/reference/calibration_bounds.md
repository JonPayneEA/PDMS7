# Calibration bounds for a model structure

Looks up default calibration bounds for every calibrated parameter of a
configuration's components, from the table shipped in
`inst/calibration-bounds.csv`. Every store parameter in the table is
included; parameters that are usually fixed (`cmin`, `st`, `bg`, `be`,
`td`, `qc`, area and time step) are not. Parameters that span orders of
magnitude, such as recharge and groundwater constants, are marked for
log-scale search.

## Usage

``` r
calibration_bounds(config, overrides = NULL, exclude = NULL)
```

## Arguments

- config:

  A configuration list.

- overrides:

  Optional named list of `c(lower, upper)` pairs by configuration path,
  such as `list(fc = c(0.8, 1.2))`, replacing or adding bounds. Naming a
  parameter that is locked by default, such as `fc`, unlocks it.

- exclude:

  Optional configuration paths to leave out, holding them at their
  values.

## Value

A data frame with `path`, `lower`, `upper`, `scale` (`linear` or `log`)
and `note`.

## Details

**Locked parameters.** A parameter left out of the bounds is held at its
value in the configuration by every automatic calibration:
[`calibrate_project()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_project.md),
[`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md),
[`recommend_structure()`](https://jonpayneea.github.io/PDMS7/reference/recommend_structure.md),
[`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md)
and
[`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
all take their search from here. Lock any parameter with `exclude`,
setting its value in the configuration first.

The rainfall factor `fc` is locked by default, at the configuration's
value (1 in the presets and the model's default). A calibrated factor
absorbs errors in the gauge or radar totals of the calibration period,
and carries them into operation, where the rainfall may come from
different gauges or a different product. Search it only when the
rainfall's bias is known and stable, by giving it bounds:
`overrides = list(fc = c(0.8, 1.2))`, or the table's range
`c(0.6, 1.6)`. The table's `default` column marks which parameters are
locked in this way.

## Examples

``` r
calibration_bounds(pdm_presets("standard"))
#>                path lower   upper  scale
#> 1 distribution.cmax 2e+01     800 linear
#> 2    distribution.b 5e-02       2 linear
#> 3       recharge.kg 1e+00    5000    log
#> 4        surface.k1 5e-01      72    log
#> 5        surface.k2 5e-01      72    log
#> 6    groundwater.kb 1e+02 1000000    log
#>                                                    note
#> 1                           Maximum store capacity (mm)
#> 2           Shape: low values give a near-uniform store
#> 3 Recharge time constant (h); spans orders of magnitude
#> 4                  Time constant of the first store (h)
#> 5                 Time constant of the second store (h)
#> 6                                  Cubic store constant
# Search the rainfall factor too
calibration_bounds(pdm_presets("standard"), overrides = list(fc = c(0.8, 1.2)))
#>                path lower   upper  scale
#> 1                fc 8e-01 1.2e+00 linear
#> 2 distribution.cmax 2e+01 8.0e+02 linear
#> 3    distribution.b 5e-02 2.0e+00 linear
#> 4       recharge.kg 1e+00 5.0e+03    log
#> 5        surface.k1 5e-01 7.2e+01    log
#> 6        surface.k2 5e-01 7.2e+01    log
#> 7    groundwater.kb 1e+02 1.0e+06    log
#>                                                                                note
#> 1 Rainfall factor; outside this range question the rain gauge rather than the model
#> 2                                                       Maximum store capacity (mm)
#> 3                                       Shape: low values give a near-uniform store
#> 4                             Recharge time constant (h); spans orders of magnitude
#> 5                                              Time constant of the first store (h)
#> 6                                             Time constant of the second store (h)
#> 7                                                              Cubic store constant
# Lock the store's shape at 0.4
cfg <- pdm_presets("standard")
cfg$distribution$b <- 0.4
calibration_bounds(cfg, exclude = "distribution.b")
#>                path lower   upper  scale
#> 1 distribution.cmax  20.0     800 linear
#> 2       recharge.kg   1.0    5000    log
#> 3        surface.k1   0.5      72    log
#> 4        surface.k2   0.5      72    log
#> 5    groundwater.kb 100.0 1000000    log
#>                                                    note
#> 1                           Maximum store capacity (mm)
#> 2 Recharge time constant (h); spans orders of magnitude
#> 3                  Time constant of the first store (h)
#> 4                 Time constant of the second store (h)
#> 5                                  Cubic store constant
```
