# Events workbench

A hydrologist calibrating by eye looks at the largest floods, changes a
parameter, and looks again. `event_workbench()` sets that up for a
calibration project: it finds the events in the registered record with
[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
screens them with
[`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md),
and keeps the `n` largest in the chosen window. `workbench_try()` reruns
those events with some parameters changed and scores each one;
`plot_workbench()` draws them side by side, before and after. The Events
tab of
[`calibration_app()`](https://jonpayneea.github.io/PDMS7/reference/calibration_app.md)
puts the same on sliders, and saves a setting you accept as a logged
trial.

## Usage

``` r
event_workbench(
  project,
  entry = NULL,
  n = 10L,
  window = c("calibration", "validation", "all"),
  screen = list()
)

workbench_try(wb, changes)

plot_workbench(wb, trial = NULL, ncol = 2L)
```

## Arguments

- project:

  A calibration project folder.

- entry:

  Id of the model entry to start from (structure, trial or calibration),
  or of a candidate, which stands for the entry it proposed. By default
  the latest candidate, or the latest model entry if there is none.

- n:

  Number of events, largest observed peak first.

- window:

  Window the events' peaks must lie in: `calibration`, `validation` or
  `all`.

- screen:

  Settings for
  [`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md);
  `NULL` keeps every event.

- wb:

  A workbench from `event_workbench()`.

- changes:

  Named numeric vector of new parameter values by configuration path,
  such as `c(surface.k1 = 3, td = 1.5)`, as for
  [`log_trial()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md).

- trial:

  A result of `workbench_try()` to draw beside the starting run.

- ncol:

  Panels per row.

## Value

`event_workbench()`: a `pdm_workbench` list with the project path, the
starting entry (`parent`) and its configuration, the chosen `events`,
the saved states, the starting run's flow in each event window (`base`)
and its `scores`. `workbench_try()`: a list with the changed
`configuration`, the flow in each window (`runs`), `scores` (one row per
event: observed and simulated peak, peak error, timing error in hours
and event NSE), and `full_run`, whether the whole record had to be
rerun. `plot_workbench()`: `wb`, invisibly.

## Details

**Speed.** A change to the surface stores or the time delay reruns only
the event windows, from states saved just before each
([`event_states()`](https://jonpayneea.github.io/PDMS7/reference/event_states.md)),
with a lead-in long enough for the slowest surface stores the bounds
allow; that takes a fraction of a second. A change to anything else,
such as the store shape `b`, alters the soil and groundwater stores
before each event, so the whole record is rerun, which takes about a
second for sixteen years of 15-minute data.

## See also

[`calibration_app()`](https://jonpayneea.github.io/PDMS7/reference/calibration_app.md),
[`event_states()`](https://jonpayneea.github.io/PDMS7/reference/event_states.md),
[`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md),
[`log_trial()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)

## Examples

``` r
if (FALSE) { # \dontrun{
wb <- event_workbench("projects/beggearn_huish", n = 10)
faster <- workbench_try(wb, c(surface.k1 = 3, surface.k2 = 6, td = 1))
plot_workbench(wb, faster)
faster$scores
} # }
```
