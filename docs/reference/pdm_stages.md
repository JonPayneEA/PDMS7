# Calibration stages

The stages of a staged calibration, following how a hydrologist
calibrates by hand: settle the water balance and the slow response
first, then the fast response, then a short joint polish over
everything.

## Usage

``` r
pdm_stages(
  config,
  overrides = NULL,
  exclude = NULL,
  polish = TRUE,
  volume_weight = 1,
  band = NULL
)
```

## Arguments

- config:

  A configuration list.

- overrides, exclude:

  Passed to
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md).

- polish:

  Include stage 3.

- volume_weight:

  Weight of the volume penalty in stage 1.

- band:

  `NULL` (the default) for a stage 3 search over the full bounds, or the
  half-width of a narrowed search, as a fraction of each range.

## Value

A list of stages.

## Details

|                         |                                         |                            |
|-------------------------|-----------------------------------------|----------------------------|
| Stage                   | Fits                                    | Objective                  |
| 1\. Volume and baseflow | `fc`, soil store, recharge, groundwater | 1 - log NSE + volume error |
| 2\. Fast response       | Surface stores and the store shape `b`  | 1 - NSE                    |
| 3\. Polish              | Everything, over the full bounds        | 1 - NSE                    |

Low flows and the total volume depend on the slow stores, and logs stop
the floods dominating stage 1. Peak size and timing depend on the fast
stores, fitted in stage 2 with stage 1's values fixed. Stage 3 starts
from the stage 2 result and searches every parameter over its full
bounds, to fix interactions the stages missed.

The polish must be free to move far. Stage 1 fits with the surface
stores at their starting values; where the true stores are much slower,
stage 1 compensates with the wrong slow stores, and a polish confined
near that point cannot leave it. In a sample of 30 synthetic catchments,
a polish confined to a quarter of each range either side (the default
before version 0.8.0) left two catchments far below the score of their
true parameters. Pass `band` to confine it all the same.

Parameters come from
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md),
so every structure gets its own lists: a split recharge adds
`recharge.alpha` to stage 1, an exponential store adds its two
parameters. A stage is a plain list, so you can write your own: `name`,
`parameters` (configuration paths), `objective` (as in
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)),
`volume_weight` and `band` (`NULL`, or the half-width of the narrowed
search, as a fraction of each parameter's range).

## See also

[`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md),
[`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)

## Examples

``` r
str(pdm_stages(pdm_presets("standard")), max.level = 2)
#> List of 3
#>  $ :List of 5
#>   ..$ name         : chr "volume and baseflow"
#>   ..$ parameters   : chr [1:5] "fc" "distribution.cmax" "distribution.b" "recharge.kg" ...
#>   ..$ objective    : chr "log_nse"
#>   ..$ volume_weight: num 1
#>   ..$ band         : NULL
#>  $ :List of 5
#>   ..$ name         : chr "fast response"
#>   ..$ parameters   : chr [1:3] "distribution.b" "surface.k1" "surface.k2"
#>   ..$ objective    : chr "nse"
#>   ..$ volume_weight: num 0
#>   ..$ band         : NULL
#>  $ :List of 5
#>   ..$ name         : chr "polish"
#>   ..$ parameters   : chr [1:7] "fc" "distribution.cmax" "distribution.b" "recharge.kg" ...
#>   ..$ objective    : chr "nse"
#>   ..$ volume_weight: num 0
#>   ..$ band         : NULL
```
