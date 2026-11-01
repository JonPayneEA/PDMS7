# Plot hindcast scores against lead time

Plot hindcast scores against lead time

## Usage

``` r
plot_hindcast(
  scores,
  metric = "skill",
  ratio = FALSE,
  methods = NULL,
  col = NULL
)
```

## Arguments

- scores:

  A
  [`hindcast_scores()`](https://jonpayneea.github.io/PDMS7/reference/hindcast_scores.md)
  result.

- metric:

  Column to plot, such as `skill`, `nse`, `rmse` or `csi:Flood Warning`.

- ratio:

  If `TRUE`, plot against lead time over time to peak instead of hours.

- methods:

  Methods to show; default all.

- col:

  Line colours, one per method.

## Value

The scores, invisibly.

## Examples

``` r
set.seed(1)
n <- 24 * 30
forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0), pet = 0.05)
observed <- run_pdm(pdm_model(area_km2 = 40, fc = 1.1), forcing)$output$q_m3s
hc <- pdm_hindcast(pdm_model(area_km2 = 40), forcing, observed, horizon_h = 12)
#> The EA 2024 AR default is defined for 15-minute steps; this model uses 1 h steps
plot_hindcast(hindcast_scores(hc))
```
