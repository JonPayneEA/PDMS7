# Update forecast

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
update_forecast(updater, observed_history, simulated_history, forecast)
```

## Arguments

- updater:

  A compatible FlodeStateUpdater or FlodeErrorUpdater object.

- observed_history:

  Complete numeric observed flow history in chronological order, cubic
  metres per second.

- simulated_history:

  Complete aligned simulated history, cubic metres per second.

- forecast:

  Finite numeric base forecast, cubic metres per second, in increasing
  lead order.

## Value

A list containing updated forecast, error_forecast, and historical
innovations.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
update_forecast(error_updater(ar = 0.7), c(2, 3), c(1, 2), c(2, 2))
#> $forecast
#> [1] 2.70 2.49
#> 
#> $error_forecast
#> [1] 0.70 0.49
#> 
#> $innovations
#> [1] 1.0 0.3
#> 
```
