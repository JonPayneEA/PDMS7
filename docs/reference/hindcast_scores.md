# Score a hindcast by lead time

Scores each method at each lead time, over every origin. Persistence is
the baseline: `skill` is 1 minus the method's mean squared error over
the persistence forecast's, on the same pairs, so 0 means no better than
persistence and 1 is perfect. The lead time at which skill falls to zero
is where a method stops earning its keep.

## Usage

``` r
hindcast_scores(hindcast, thresholds = NULL, response_time_h = NULL)
```

## Arguments

- hindcast:

  A
  [`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md)
  result, or a data.table with the same columns (`origin`, `lead_h`,
  `method`, `forecast`, `observed`) from any model, including
  `persistence` rows.

- thresholds:

  Optional named vector of threshold flows, m3/s.

- response_time_h:

  Time to peak in hours for `lead_ratio`; taken from the hindcast if it
  has one.

## Value

A data.table, one row per method and lead time: `method`, `lead_h`,
`lead_ratio`, `n`, `nse`, `rmse`, `mae`, `bias` (mean forecast minus
observed, m3/s), `skill`, and any threshold scores.

## Details

`lead_ratio` divides the lead time by the model's time to peak, so
catchments of different speeds, and different models of the same
catchment, line up on one axis.

With `thresholds`, the step-based contingency scores at each lead time
are added as `pod:name`, `far:name` and `csi:name`: at that lead, was
the forecast above the threshold when the river was?

## Examples

``` r
set.seed(1)
n <- 24 * 30
forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0), pet = 0.05)
observed <- run_pdm(pdm_model(area_km2 = 40, fc = 1.1), forcing)$output$q_m3s
hc <- pdm_hindcast(pdm_model(area_km2 = 40), forcing, observed, horizon_h = 12)
#> The EA 2024 AR default is defined for 15-minute steps; this model uses 1 h steps
#> Warning: No response_time AR set: The default-family AR set is unstable for a decay of 2.96 h at 1 h steps: one root is 1.1. The family is built for 15-minute steps and is stable only for a decay of at least 4.88 steps (4.88 h here). Use a finer step, a longer decay, ar_ea_default() or fitted coefficients.
scores <- hindcast_scores(hc, thresholds = c(high = 3))
scores[scores$method == "ea_2024" & scores$lead_h %in% c(1, 6, 12), ]
#>     method lead_h lead_ratio     n        nse      rmse        mae         bias
#>     <char>  <num>      <num> <int>      <num>     <num>      <num>        <num>
#> 1: ea_2024      1  0.3382448   108  0.9885051 0.1311254 0.03928045  0.009661769
#> 2: ea_2024      6  2.0294690   107  0.2368216 1.1518652 0.42079175 -0.057543883
#> 3: ea_2024     12  4.0589380   106 -0.1514985 1.4189842 0.61331633 -0.099589356
#>        skill pod:high far:high  csi:high
#>        <num>    <num>    <num>     <num>
#> 1: 0.6518021      1.0      0.0 1.0000000
#> 2: 0.4415588      0.2      0.8 0.1111111
#> 3: 0.3838577      0.0      1.0 0.0000000
```
