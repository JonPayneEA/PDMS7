# Continuous ranked probability score of an ensemble

For each forecast, `mean |X - y| - mean |X - X'| / 2` over the members X
and X' and the observed value y: the ensemble's whole distribution
against what happened, in the units of the flow, 0 for a perfect
forecast and the absolute error for a single member. The fair form
(Ferro, 2014) averages the second term over distinct pairs of members
only, so that a small ensemble is not penalised for its size.

## Usage

``` r
crps_ensemble(ensemble, observed, fair = FALSE)
```

## Arguments

- ensemble:

  A matrix, one row per forecast and one column per member (or a vector,
  one forecast).

- observed:

  The observed value of each forecast.

- fair:

  Use the fair form.

## Value

The score of each forecast.

## See also

[`ensemble_scores()`](https://jonpayneea.github.io/PDMS7/reference/ensemble_scores.md)

## Examples

``` r
crps_ensemble(matrix(c(0, 1), nrow = 1), 0)                # 0.25
#> [1] 0.25
crps_ensemble(matrix(c(0, 1), nrow = 1), 0, fair = TRUE)   # 0
#> [1] 0
```
