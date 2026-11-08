# Run a project's model over a separate event

Validation events often come as their own files, apart from the
registered record. `event_run()` runs a model entry of the project over
one, from the best start available:

## Usage

``` r
event_run(project, forcing, observed = NULL, entry = NULL)

# S3 method for class 'pdm_event_run'
plot(x, ...)
```

## Arguments

- project:

  A calibration project folder.

- forcing:

  Data frame of the event's `time`, `rain` and, optionally, `pet`, on
  the project's time step.

- observed:

  Observed flow over the event, m3/s; optional.

- entry:

  Model entry; by default the candidate.

- x:

  A `pdm_event_run`.

- ...:

  For [`plot()`](https://rdrr.io/r/graphics/plot.default.html): passed
  to
  [`plot.pdm_series()`](https://jonpayneea.github.io/PDMS7/reference/pdm_series.md).

## Value

A `pdm_event_run` list: `series` (time, rain, pet, observed, simulated),
`start` (`"warm"` or `"steady"`) and `scores` (NSE, observed and
simulated peak, peak error and timing error in hours) when flow is
given. [`plot()`](https://rdrr.io/r/graphics/plot.default.html) draws
its hydrograph.

## Details

- **Warm start**: when the event begins inside the registered record,
  the record is run up to that moment and the model continues from its
  own state then.

- **Steady state**: otherwise the stores start in balance with the
  event's first observed flow. That is only approximate, so give the
  file a few days before the rise and distrust the first hours.

Missing evaporation is taken from the registered record at the same
times, or, outside it, from the record's mean for that month and time of
day.

## See also

[`candidate_model()`](https://jonpayneea.github.io/PDMS7/reference/candidate_model.md),
[`pdm_series()`](https://jonpayneea.github.io/PDMS7/reference/pdm_series.md)

## Examples

``` r
if (FALSE) { # \dontrun{
ev <- event_run("projects/beggearn_huish", event_forcing, event_flow)
ev
plot(ev)
} # }
```
