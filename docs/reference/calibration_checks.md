# Acceptance checks of a calibration

A calibration can score well over the whole record and still be wrong
where it matters. NSE over a long record weighs time steps, not events,
so a model whose flood peaks are late and low can score 0.9 when its
recessions are right. These checks look for two warning signs the
headline score hides.

## Usage

``` r
calibration_checks(
  project,
  entry = NULL,
  top = 20L,
  edge = 0.01,
  rain_min = NULL,
  max_response_h = 150,
  screen = list()
)
```

## Arguments

- project:

  A calibration project folder.

- entry:

  Id of a model entry (structure, trial or calibration) or candidate; by
  default the latest candidate.

- top:

  Largest events summarised in each window.

- edge:

  Distance from a bound, as a share of the searched range, within which
  a parameter counts as at the bound.

- rain_min, max_response_h:

  Passed to
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md).

- screen:

  Settings for
  [`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md),
  with the project's highest gauged flow unless they name one; `NULL`
  summarises every event.

## Value

A `pdm_calibration_checks` list of three data frames and the response
times; printing it shows the parameters at a bound and the event
summary. `parameters`: `path`, `value`, `lower`, `upper`, `scale` and
`at_bound` (`"lower"`, `"upper"` or `NA`). `events`: every event with
its `period` and the columns of
[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md).
`summary`: one row per window with `events` (the number summarised),
`median_peak_error`, `median_timing_error_h`, `share_peak_within_20pct`
and `median_event_nse`, and `screened_out`, the events of that window
the screen left out. `response_h`: the response times estimated from the
observed and the simulated flow.

## Details

**Parameters at a bound.** A parameter that ends at the edge of its
search range is usually being bent to make up for something the
structure cannot do, not estimating a property of the catchment. Each
parameter is checked against the widest range any calibration on the way
to the entry searched it over, on a log scale where it was searched on
one. A lower bound of zero, such as no time delay, is a natural limit
rather than an imposed one, and is not flagged.

**The largest events.** Events are found with
[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md)
from the registered rain and observed flow and scored with
[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md).
In each window (calibration, validation, the held-back wettest years,
and any outside them), the `top` largest by observed peak are
summarised: median peak error, median timing error, the share of peaks
within 20% of the observed, and median event NSE. Events are first
screened with
[`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md);
those it leaves out are kept in `events` with their flags, but not
summarised.

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md),
[`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md)

## Examples

``` r
if (FALSE) { # \dontrun{
checks <- calibration_checks("projects/beggearn_huish")
checks$parameters[!is.na(checks$parameters$at_bound), ]
checks$summary
} # }
```
