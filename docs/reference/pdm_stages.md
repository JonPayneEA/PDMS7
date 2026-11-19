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
  band = NULL,
  events = FALSE,
  event_weights = c(nse = 1, peak = 0.5, timing = 0.5),
  event_share = 0.5,
  event_screen = list(),
  td_max = 6,
  event_budget = 300L,
  thresholds = NULL,
  threshold_weight = 1,
  threshold_score = "csi",
  pareto = NULL,
  pareto_choose = "knee",
  pareto_budget = 300L,
  method = NULL,
  budget = 300L,
  coarse_dt = NULL
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

- events:

  Add stage 4, the events stage.

- event_weights, event_share, event_screen:

  Passed to
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  in stage 4.

- td_max:

  Largest time delay searched in stage 4, hours; `NULL` holds `td`
  fixed.

- event_budget:

  Model runs per start for the DDS searches of stage 4 and of a last
  stage with thresholds.

- thresholds, threshold_weight, threshold_score:

  A threshold term for the last stage; for a trade-off stage, the
  thresholds of a `threshold_loss` among its objectives.

- pareto:

  Losses for a trade-off stage at the end, or `NULL` for none.

- pareto_choose:

  Which front set the trade-off stage keeps.

- pareto_budget:

  Model runs a chain in the trade-off stage.

- method:

  `NULL` to keep each stage's own search, or `"dds"` (or `"lbfgsb"`,
  `"nelder_mead"`) for stages 1 to 3.

- budget:

  Model runs a start for stages 1 to 3 with `method = "dds"`.

- coarse_dt:

  `NULL`, or the step in hours on which stage 1 is fitted, a whole
  number of the model's steps.

## Value

A list of stages.

## Details

|                          |                                               |                                  |
|--------------------------|-----------------------------------------------|----------------------------------|
| Stage                    | Fits                                          | Objective                        |
| 1\. Volume and baseflow  | Soil, recharge, groundwater; `fc` if unlocked | 1 - log NSE + volume             |
| 2\. Fast response        | Surface stores and the store shape `b`        | 1 - NSE                          |
| 3\. Polish               | Everything, over the full bounds              | 1 - NSE                          |
| 4\. Events (optional)    | Surface stores, `b` and the time delay `td`   | events objective                 |
| 5\. Trade-off (optional) | As stage 4                                    | A Pareto front of several losses |

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

NSE over a long record weighs time steps, not events: the many hours of
recession outweigh the few hours around each flood peak, so a model can
score well while its peaks are late and low. `events = TRUE` adds stage
4, which refits the fast response and the time delay on the largest
events alone, with the `events` objective of
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md):
pooled event NSE, peak error and timing error. The slow stores stay as
stage 3 left them, so the water balance is kept. The time delay is not
in the default bounds; stage 4 searches it from 0 to `td_max` hours. Its
timing term changes in steps, so stage 4 uses DDS with `event_budget`
model runs per start.

`pareto` adds a trade-off stage at the end: the same parameters as the
events stage, searched for a Pareto front of the named losses of
[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md)
(at least two, such as `c("nse_loss", "event_nse_loss", "abs_bias")`) by
PA-DDS with `pareto_budget` model runs a chain, and the front set
`pareto_choose` names kept: `"knee"` (the default, no weights needed),
`"compromise"`, one objective, or weights. With the slow stores already
fixed, the front is searched over a few parameters only, so a modest
budget covers it. In a project the whole front is kept in the stage's
entry.

**Speed.** By default stages 1 to 3 search by L-BFGS-B, whose gradients
cost about two model runs per parameter per iteration. `method = "dds"`
searches them by DDS instead, with `budget` model runs a start, which on
bumpy hydrological objectives usually finds as good a fit for fewer runs
(Tolson and Shoemaker, 2007). `coarse_dt` fits stage 1, the water
balance and the slow stores, on the record collapsed to a coarser step
(rain and evaporation summed, flow averaged): `coarse_dt = 1` on a
15-minute record runs stage 1 four times faster. The slow stores'
parameters are in hours and millimetres and do not depend on the timing
within an hour, so they carry back to the model's own step unchanged;
the later stages, and every logged score, use the full record.

`thresholds` adds a threshold term
([`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md))
to the last stage, which then also uses DDS: a named vector of flows
(m3/s) for
[`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md),
or the names of thresholds registered in the project for
[`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md).

Parameters come from
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md),
so every structure gets its own lists: a split recharge adds
`recharge.alpha` to stage 1, an exponential store adds its two
parameters. A stage is a plain list, so you can write your own: `name`,
`parameters` (configuration paths), `objective` (as in
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)),
`volume_weight` and `band` (`NULL`, or the half-width of the narrowed
search, as a fraction of each parameter's range). Optional fields:
`method` and `control`, replacing the calibration's own for this stage;
`event_weights` and `event_share` for the events objective;
`thresholds`, `threshold_weight` and `threshold_score`; and
`extra_bounds`, rows like those of
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
for parameters not in the bounds table, such as `td`.

## See also

[`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md),
[`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)

## Examples

``` r
str(pdm_stages(pdm_presets("standard")), max.level = 2)
#> List of 3
#>  $ :List of 5
#>   ..$ name         : chr "volume and baseflow"
#>   ..$ parameters   : chr [1:4] "distribution.cmax" "distribution.b" "recharge.kg" "groundwater.kb"
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
#>   ..$ parameters   : chr [1:6] "distribution.cmax" "distribution.b" "recharge.kg" "surface.k1" ...
#>   ..$ objective    : chr "nse"
#>   ..$ volume_weight: num 0
#>   ..$ band         : NULL
```
