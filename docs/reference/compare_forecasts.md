# Compare candidate models as forecasters

A forecasting model's job is not to simulate a whole record but to
forecast a few hours ahead, with updating, against thresholds. This
hindcasts every candidate the same way
([`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md):
forecasts from regular origins, each with the updating methods asked
for, against persistence) and ranks them on what forecasting needs:
skill over persistence at the lead times that matter (`leads_h`), and,
with `thresholds`, the threshold score. A model that is a little worse
over the whole record but warns earlier ranks higher here, as it should
for a forecasting model.

## Usage

``` r
compare_forecasts(
  candidates,
  forcing,
  observed,
  leads_h = NULL,
  method = "best",
  thresholds = NULL,
  threshold_score = c("csi", "pod", "far"),
  rank_on = c("skill", "threshold"),
  ...
)

# S3 method for class 'pdm_forecast_comparison'
plot(x, ...)

# S3 method for class 'pdm_forecast_comparison'
autoplot(object, ...)
```

## Arguments

- candidates:

  A named list of configurations or models.

- forcing, observed:

  The record to hindcast.

- leads_h:

  Lead times to rank on, hours; by default every lead the hindcast
  makes.

- method:

  `"best"`, or one updating method of
  [`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md)
  (such as `"none"`).

- thresholds, threshold_score:

  Named threshold flows (m3/s) for
  [`hindcast_scores()`](https://jonpayneea.github.io/PDMS7/reference/hindcast_scores.md),
  and the score (`csi`, `pod` or `far`) to rank on with
  `rank_on = "threshold"`.

- rank_on:

  `"skill"` or `"threshold"`.

- ...:

  Passed to
  [`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md):
  `window`, `every_h`, `horizon_h`, `ar`, `state_correction` and so on.

- x, object:

  A `pdm_forecast_comparison`.

## Value

A `pdm_forecast_comparison` list: `scores` (candidate, method, lead and
every score), `ranking` (one row per candidate: mean skill, mean
threshold score, rank) and the settings.

## Details

Each candidate is judged with its best updating method at each lead
(`method = "best"`), as it would be run, or with one named method for
all, such as `"none"` for open loop. The ranking is by mean skill over
`leads_h`, or by mean threshold score with `rank_on = "threshold"`.

## See also

[`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md),
[`hindcast_scores()`](https://jonpayneea.github.io/PDMS7/reference/hindcast_scores.md)

## Examples

``` r
set.seed(1)
n <- 24 * 30
forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0),
                      pet = 0.05)
truth <- pdm_model(area_km2 = 40, fc = 1.1)
observed <- run_pdm(truth, forcing)$output$q_m3s
cmp <- compare_forecasts(list(truth = truth, low = pdm_model(area_km2 = 40, fc = 0.9)),
                         forcing, observed, horizon_h = 12, every_h = 12)
#> The EA 2024 AR default is defined for 15-minute steps; this model uses 1 h steps
#> Warning: No response_time AR set: The default-family AR set is unstable for a decay of 2.96 h at 1 h steps: one root is 1.1. The family is built for 15-minute steps and is stable only for a decay of at least 4.88 steps (4.88 h here). Use a finer step, a longer decay, ar_ea_default() or fitted coefficients.
#> The EA 2024 AR default is defined for 15-minute steps; this model uses 1 h steps
#> Warning: No response_time AR set: The default-family AR set is unstable for a decay of 2.96 h at 1 h steps: one root is 1.1. The family is built for 15-minute steps and is stable only for a decay of at least 4.88 steps (4.88 h here). Use a finer step, a longer decay, ar_ea_default() or fitted coefficients.
cmp$ranking
#>    candidate mean_skill mean_threshold leads  rank
#>       <char>      <num>          <num> <int> <int>
#> 1:     truth  0.6404402             NA    12     1
#> 2:       low  0.4785456             NA    12     2
plot(cmp)
```
