# Events and event scores across a batch

Finds the events in every basin of a
[`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
output, from its registered rain and observed flow, and scores the
candidate model on each, so model performance during events can be
compared across a large sample. Each basin's response time is estimated
from the observed and from the simulated flow, which shows whether the
model responds too fast or too slow.

## Usage

``` r
batch_events(output, rain_min = NULL, max_response_h = 150)
```

## Arguments

- output:

  A batch output folder.

- rain_min, max_response_h:

  Passed to
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md).

## Value

A list of two data frames. `events`: one row per event in every basin
with a candidate, with `basin`, `period` (the window holding the
observed peak: `calibration`, `validation`, `wettest` for a held-back
wettest year, or `outside`) and the columns of
[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md).
`basins`: one row per basin, with `response_observed_h`,
`response_simulated_h`, the number of events, and the median absolute
peak error and timing error.

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md),
[`batch_results()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
