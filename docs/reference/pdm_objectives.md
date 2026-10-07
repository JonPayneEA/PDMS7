# Evaluate hydrological calibration losses

Missing observations are excluded; missing simulations at scored rows
are errors. NSE loss is 1-NSE. KGE loss is the Euclidean distance using
correlation, standard deviation ratio and mean ratio (original KGE).
Bias is absolute relative volume error. Peak loss compares global
maxima, not event-specific peaks. All losses are minimized. RMSE and
log-RMSE have different scales: supply explicit scaling in
multi-objective calibration rather than combining raw metrics
implicitly.

## Usage

``` r
pdm_objectives(
  simulated,
  observed,
  objectives = c("nse_loss", "log_rmse", "abs_bias"),
  warmup = 0L,
  log_offset = 0.01
)
```

## Arguments

- simulated, observed:

  Numeric aligned nonnegative discharge vectors.

- objectives:

  Unique metric names: rmse, log_rmse, nse_loss, kge_loss, abs_bias,
  peak_relative_error.

- warmup:

  Nonnegative number of initial rows excluded from scoring.

- log_offset:

  Positive discharge offset for logarithms, in m3/s.

## Value

Named numeric loss vector.
