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
scores <- hindcast_scores(hc, thresholds = c(high = 3))
scores[scores$method == "ea_2024" & scores$lead_h %in% c(1, 6, 12), ]
#>     method lead_h lead_ratio     n       nse        rmse         mae
#>     <char>  <num>      <num> <int>     <num>       <num>       <num>
#> 1: ea_2024      1 0.07376612   108 0.9999944 0.003779765 0.001757062
#> 2: ea_2024      6 0.44259672   107 0.9981930 0.067465810 0.029213132
#> 3: ea_2024     12 0.88519343   106 0.9940245 0.122290941 0.064658541
#>            bias     skill  pod:high   far:high  csi:high
#>           <num>     <num>     <num>      <num>     <num>
#> 1: 0.0010178101 0.9969904 1.0000000 0.00000000 1.0000000
#> 2: 0.0009089592 0.9789638 0.9615385 0.03846154 0.9259259
#> 3: 0.0015758778 0.9772074 0.9200000 0.04166667 0.8846154
```
