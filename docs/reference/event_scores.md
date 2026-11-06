# Model scores event by event

Scores simulated flow against observed flow within each event's flow
window, as found by
[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md):
how well a model reproduces the peaks, their timing and the volumes of
individual events, which a score over the whole record hides.

## Usage

``` r
event_scores(events, simulated, observed, dt = attr(events, "dt") %||% 1)
```

## Arguments

- events:

  Events from
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md).

- simulated, observed:

  Simulated and observed flow, aligned with the record the events were
  found in.

- dt:

  Time step, hours. By default, the step the events were found at.

## Value

`events` with the observed and simulated peaks and these scores added:
`peak_error` (simulated over observed peak, less one), `timing_error_h`
(hours from the observed to the simulated peak within the window;
positive when the model is late), `volume_error` (relative error in flow
volume over the window) and `nse` (over the window). Steps with no
observation are left out.

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`batch_events()`](https://jonpayneea.github.io/PDMS7/reference/batch_events.md)

## Examples

``` r
river <- synthetic_catchment(years = 2, dt = 1, seed = 1)
events <- find_events(river$forcing$rain, river$observed, dt = 1)
scores <- event_scores(events, river$true_flow, river$observed)
summary(scores$peak_error)
#>      Min.   1st Qu.    Median      Mean   3rd Qu.      Max. 
#> -0.127720 -0.032203  0.001785 -0.001887  0.025619  0.168318 
```
