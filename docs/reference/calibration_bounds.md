# Calibration bounds for a model structure

Looks up default calibration bounds for every calibrated parameter of a
configuration's components, from the table shipped in
`inst/calibration-bounds.csv`. The rainfall factor and every store
parameter in the table are included; parameters that are usually fixed
(`cmin`, `st`, `bg`, `be`, `td`, `qc`, area and time step) are not.
Parameters that span orders of magnitude, such as recharge and
groundwater constants, are marked for log-scale search.

## Usage

``` r
calibration_bounds(config, overrides = NULL, exclude = NULL)
```

## Arguments

- config:

  A configuration list.

- overrides:

  Optional named list of `c(lower, upper)` pairs by configuration path,
  such as `list(fc = c(0.8, 1.2))`, replacing or adding bounds.

- exclude:

  Optional configuration paths to leave out, holding them at their
  values.

## Value

A data frame with `path`, `lower`, `upper`, `scale` (`linear` or `log`)
and `note`.

## Examples

``` r
calibration_bounds(pdm_presets("standard"))
#>                path lower   upper  scale
#> 1                fc 6e-01 1.6e+00 linear
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
```
