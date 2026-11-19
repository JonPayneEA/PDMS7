# Brier score and its decomposition

The mean squared difference between the forecast probability of an event
(a threshold crossed) and whether it happened (1 or 0). Murphy's
decomposition splits it, over the bins of forecast probability, into
reliability (how far each bin's forecast probability lies from how often
the event happened when it was forecast; lower is better), resolution
(how far those frequencies differ from the overall frequency; higher is
better) and uncertainty (the overall frequency's variance, which no
forecast can change): BS = reliability - resolution + uncertainty,
exactly when each bin holds one probability.

## Usage

``` r
brier_score(probability, outcome, bins = NULL)
```

## Arguments

- probability:

  Forecast probabilities.

- outcome:

  What happened: 1 (or TRUE) for the event, 0 for none.

- bins:

  Bin edges for the decomposition and the reliability table; by default
  each distinct probability is its own bin.

## Value

A list: `brier`, `reliability`, `resolution`, `uncertainty`, and
`table`, the reliability table (bin, forecasts, mean probability,
observed frequency).

## See also

[`ensemble_scores()`](https://jonpayneea.github.io/PDMS7/reference/ensemble_scores.md)

## Examples

``` r
brier_score(c(0.9, 0.9, 0.1, 0.1), c(1, 0, 0, 0))
#> $brier
#> [1] 0.21
#> 
#> $reliability
#> [1] 0.085
#> 
#> $resolution
#> [1] 0.0625
#> 
#> $uncertainty
#> [1] 0.1875
#> 
#> $table
#>   bin forecasts probability observed
#> 1 0.1         2         0.1      0.0
#> 2 0.9         2         0.9      0.5
#> 
```
