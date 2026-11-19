# Bayesian calibration

Instead of one best parameter set, a sample from the posterior: every
set consistent with the record and the priors, in proportion to how well
it fits. The spread of the sample is the parameters' uncertainty given
the data, and runs of its sets give a predictive band.

## Usage

``` r
calibrate_bayes(
  config,
  forcing,
  observed,
  lower,
  upper,
  priors = list(),
  generations = 1000L,
  chains = 3L,
  lambda = 0.5,
  log_offset = 0.01,
  ar1 = TRUE,
  temper = 1,
  warmup = 0L,
  log_scale = character(0),
  start = c("flow", "soil"),
  baseflow_fraction = 0.7,
  soil_fraction = 0.5,
  seed = 1L
)
```

## Arguments

- config, forcing, observed, lower, upper:

  As in
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

- priors:

  A named list of priors
  ([`prior_uniform()`](https://jonpayneea.github.io/PDMS7/reference/prior_uniform.md),
  [`prior_normal()`](https://jonpayneea.github.io/PDMS7/reference/prior_uniform.md),
  [`prior_lognormal()`](https://jonpayneea.github.io/PDMS7/reference/prior_uniform.md));
  parameters not named get a uniform prior over their bounds.

- generations:

  Generations of the sampler; the model runs are `chains` x
  `generations` plus the initial archive of 10 x parameters.

- chains:

  Number of chains.

- lambda, log_offset:

  The Box-Cox power and offset.

- ar1:

  Model the errors' lag-1 autocorrelation.

- temper:

  Power on the likelihood, in (0, 1\].

- warmup, log_scale, start, baseflow_fraction, soil_fraction:

  As in
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

- seed:

  Random seed; the caller's random state is restored.

## Value

A `pdm_bayes` list: `samples` (the post-burn-in sets, with
`log_likelihood` and `log_posterior`), `summary` (each parameter's mean,
standard deviation, 5%, 50% and 95% points and `rhat`), `best` (the
configuration of the highest posterior), `error_model` (the best set's
error autocorrelation `rho` and innovation variance `s2`), `acceptance`,
and the settings, for
[`posterior_band()`](https://jonpayneea.github.io/PDMS7/reference/posterior_band.md).

## Details

**The likelihood** treats the errors on Box-Cox transformed flows
([`boxcox_flow()`](https://jonpayneea.github.io/PDMS7/reference/boxcox_flow.md))
as a lag-1 autoregression with normal innovations, the autocorrelation
and the innovation variance set to their best values at each set. Hourly
errors run on from one step to the next; treating them as independent
would make the posterior far too narrow. `temper`, below 1, flattens the
likelihood further where even that is too sure, as a power on it (0.25
counts the record as worth a quarter of its length).

**The sampler** is DREAM(ZS) (ter Braak and Vrugt, 2008; Vrugt, 2016):
`chains` Markov chains that propose jumps from differences between past
states, kept in an archive, with randomised subspace sampling. It suits
the correlated, curved posteriors of hydrological models and needs no
tuning. The first half of each chain is burn-in. `rhat` is the
Gelman-Rubin statistic on the second halves: below about 1.2 for every
parameter, the chains agree.

Each run starts as
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
starts it.

## See also

[`posterior_band()`](https://jonpayneea.github.io/PDMS7/reference/posterior_band.md),
[`prior_uniform()`](https://jonpayneea.github.io/PDMS7/reference/prior_uniform.md),
[`boxcox_flow()`](https://jonpayneea.github.io/PDMS7/reference/boxcox_flow.md)

## Examples

``` r
rain <- synthetic_rain("2021-01-01", years = 1, dt = 1, seed = 2)
cfg <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
flow <- run_pdm(pdm_from_config(cfg), rain[c("rain", "pet")])$output$q_m3s
flow <- flow * exp(rnorm(length(flow), 0, 0.05))
fit <- calibrate_bayes(modifyList(cfg, list(fc = 0.8)), rain[c("time", "rain", "pet")], flow,
                       lower = c(fc = 0.5), upper = c(fc = 1.5),
                       priors = list(fc = prior_normal(1, 0.2)), generations = 100,
                       warmup = 24 * 30, start = "soil")
fit$summary
#>   parameter     mean          sd       q05      q50      q95     rhat
#> 1        fc 1.002829 0.002604072 0.9952765 1.003812 1.006559 1.046141
```
