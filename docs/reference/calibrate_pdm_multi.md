# Calibrate PDM or coupled snow-PDM against multiple objectives

Evaluates the initial configuration and seeded uniform candidates, then
refines the best sampled starts for each weight vector with bounded
L-BFGS-B. Retains every valid evaluated candidate and its raw metrics,
normalized metrics and Pareto membership. This is an approximate sampled
front, not a global optimality claim; nonconvex fronts may be missed by
weighted searches. Use repeated seeds, sufficient search budgets and
independent validation. Random state is restored.

## Usage

``` r
calibrate_pdm_multi(
  config,
  forcing,
  observed,
  lower,
  upper,
  objectives = c("nse_loss", "log_rmse", "abs_bias"),
  scales = NULL,
  weights = NULL,
  n_samples = 64L,
  starts = 2L,
  seed = 1L,
  warmup = 0L,
  log_offset = 0.01,
  control = list(maxit = 100)
)
```

## Arguments

- config:

  PDM configuration, or list(pdm=..., snow=...) for coupled calibration.

- forcing:

  Data frame with rain and pet; coupled runs also require temperature_c.
  Optional time column contains POSIXct timestamps.

- observed:

  Aligned observed discharge, m3/s. Missing observations are excluded.

- lower, upper:

  Named finite bounds with identical names/order. Coupled paths start
  with pdm. or snow., for example snow.melt_factor_mmh_c.

- objectives:

  Metric names accepted by pdm_objectives.

- scales:

  Positive named metric divisors in objective order. NULL uses ones;
  choose meaningful scales before interpreting weighted compromises.

- weights:

  Nonnegative named vector or matrix with objective column names in
  order. Rows are normalized to sum one. NULL uses individual objectives
  and equal weights.

- n_samples:

  Nonnegative number of initial uniform random candidates.

- starts:

  Positive number of sampled starts refined per weight vector.

- seed:

  Nonnegative integer random seed.

- warmup:

  Number of initial intervals excluded from scoring, not simulation.

- log_offset:

  Positive offset for log-RMSE, m3/s.

- control:

  Control list forwarded to stats::optim.

## Value

List with archive data.table, pareto data.table, corresponding configs,
compromise (best equal/supplied final weight row), weights, scales,
optimization status and failed evaluation count. Candidates are not
posterior probabilities.
