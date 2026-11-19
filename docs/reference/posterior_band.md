# A predictive band from the posterior

Runs `draws` sets from the posterior of
[`calibrate_bayes()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_bayes.md)
and returns quantiles of the flow at each step. With `noise = FALSE` the
band is the parameters' uncertainty alone; with `noise = TRUE` each run
also gets an error drawn from the fitted error model (the lag-1
autoregression on Box-Cox flows), which is what the observed flow is
expected to scatter by.

## Usage

``` r
posterior_band(
  x,
  forcing,
  draws = 100L,
  probs = c(0.05, 0.5, 0.95),
  noise = TRUE,
  seed = 1L
)
```

## Arguments

- x:

  A `pdm_bayes` result.

- forcing:

  The forcing to run, from the same first row as the calibration's.

- draws:

  Posterior sets to run.

- probs:

  Quantiles to return.

- noise:

  Add the fitted error to each run.

- seed:

  Random seed; the caller's random state is restored.

## Value

A data frame: `row`, `time` (when the forcing has one), and one column a
quantile.

## See also

[`calibrate_bayes()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_bayes.md)
