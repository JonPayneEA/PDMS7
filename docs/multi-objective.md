# Multi-objective calibration

[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md)
searches PDM alone or a coupled PACK/PDM configuration. It returns raw
losses, explicitly scaled losses, evaluated parameter values, the
nondominated set, corresponding configurations and optimizer convergence
codes. A nondominated candidate cannot improve one objective without
worsening another within the evaluated set. Ties remain available.

| Objective | Quantity minimized | Interpretation |
|----|----|----|
| rmse | Square root of mean squared discharge error | Absolute flow error, m³/s |
| log_rmse | RMSE of log(Q + offset) | Greater emphasis on relative/low-flow error |
| nse_loss | SSE / observed squared deviations | 1 minus NSE |
| kge_loss | Distance from correlation, SD ratio and mean ratio to one | 1 minus original KGE |
| abs_bias | Absolute simulated/observed volume ratio minus one | Relative volume error |
| peak_relative_error | Absolute simulated/observed maximum ratio minus one | Single window’s peak magnitude |

Peak magnitude does not measure timing and does not identify individual
events. NSE and KGE require variable observations; KGE also requires
variable simulation. Relative metrics require positive observed volume.
These undefined cases fail explicitly. Missing observations are omitted;
missing forcing and missing scored simulations are rejected. Warm-up is
simulated but excluded from every metric.

## Example

``` r
config <- list(pdm = pdm_presets("standard"), snow = pack_presets())
config$pdm$fc <- 1
# forcing: rain and pet in mm/interval, temperature_c, optional POSIXct time.
# observed_cms: discharge aligned to those same intervals.
fit <- calibrate_pdm_multi(
  config, forcing, observed_cms,
  lower = c(snow.melt_factor_mmh_c = 0.05, pdm.surface.k1 = 0.5),
  upper = c(snow.melt_factor_mmh_c = 0.4, pdm.surface.k1 = 8),
  objectives = c("nse_loss", "log_rmse", "abs_bias"),
  scales = c(nse_loss = 1, log_rmse = 0.5, abs_bias = 0.1),
  n_samples = 100, starts = 3, seed = 42, warmup = 48
)
fit$pareto
fit$configs                 # aligns with rows of fit$pareto
fit$optimization            # nonzero convergence codes need inspection
fit$compromise$config       # best candidate for the final weight row
```

Bounds and scales here are illustrative, not catchment recommendations.
A scale of 0.1 for abs_bias means a 10% volume error contributes one
scaled loss unit. Choose tolerances/scales in advance and record them.
The default uses divisors of one, which does not make metrics equivalent
in significance.

Supply a named weight vector for one weighted optimization, or a matrix
with columns in objective order for several trade-offs. The default
searches each individual objective plus equal weights. The final row
determines the reported compromise; it does not remove any Pareto
candidates.

The algorithm uses seeded uniform samples followed by multiple bounded
L-BFGS-B searches. Its front is **approximate**, limited to evaluated
candidates. Weighted searches can miss nonconvex parts of a front; snow
thresholds also make the loss surface nonsmooth. Check convergence
codes, repeat seeds and increase the search budget. This is not NSGA-II,
a posterior distribution, or a guarantee of a global optimum. Parameter
bounds must identify existing numeric config paths; the forcing timestep
cannot be calibrated.

Evaluate candidate configurations on independent periods using
[`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md).
Include snow seasons and observed snow water equivalent where available.
Do not interpret a fitted melt factor from a snow-free record as
identified. Avoid jointly fitting both precipitation multipliers without
an explicit identifiability study.
