# Plot hindcast scores against lead time

Plot hindcast scores against lead time

## Usage

``` r
plot_hindcast(
  scores,
  metric = "skill",
  ratio = FALSE,
  methods = NULL,
  col = NULL,
  ylim = NULL,
  legend = "bottomright"
)

# S3 method for class 'pdm_hindcast_scores'
plot(x, ...)

# S3 method for class 'pdm_hindcast_scores'
autoplot(object, ...)
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

- ylim:

  Optional y-axis limits. Skill can be very negative at the shortest
  lead times, which flattens the rest of the chart; `c(-1, 1)` is often
  clearer.

- legend:

  Kept so older code still runs; the legend now always sits below the
  plot.

- x, object:

  A
  [`hindcast_scores()`](https://jonpayneea.github.io/PDMS7/reference/hindcast_scores.md)
  result.

- ...:

  For [`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
  `autoplot()`: the other arguments of `plot_hindcast()`.

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
#> Warning: No response_time AR set: The default-family AR set is unstable for a decay of 2.96 h at 1 h steps: one root is 1.1. The family is built for 15-minute steps and is stable only for a decay of at least 4.88 steps (4.88 h here). Use a finer step, a longer decay, ar_ea_default() or fitted coefficients.
plot_hindcast(hindcast_scores(hc))
```
