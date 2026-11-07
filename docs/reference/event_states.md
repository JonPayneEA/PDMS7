# Rerun events on their own, from saved states

Looking at how a model handles the largest events, while changing its
parameters, needs each change to show at once. Rerunning a 15-minute
record of sixteen years takes seconds; the events in it are a small part
of the record. `event_states()` runs the record once and saves the
model's state at the start of each event's window. `run_events()` then
runs only the windows, from those states.

## Usage

``` r
event_states(model, forcing, events, state = NULL, lead_h = NULL, tail_h = 12)

run_events(model, forcing, saved, which = NULL)
```

## Arguments

- model:

  A model from
  [`pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/pdm_model.md)
  or
  [`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md).

- forcing:

  Forcing as for
  [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md).

- events:

  Events from
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md)
  on the same record.

- state:

  Starting state of the full run; by default
  [`initial_state()`](https://jonpayneea.github.io/PDMS7/reference/initial_state.md).

- lead_h:

  Hours before each event (the earlier of its rain and flow starts) at
  which its window starts.

- tail_h:

  Hours after each event's flow window that its window runs on.

- saved:

  Saved states from `event_states()`.

- which:

  Events to run, by row of `events`; all by default.

## Value

`event_states()`: a list with `first` and `last` (each window's first
and last row of the record), `states` (the state before each window's
first row), `lead_h`, `tail_h`, `events` and the `model` the states were
saved from. `run_events()`: a list with one element per event run, each
a list of `rows` (rows of the record) and `q_m3s` (simulated flow on
those rows).

## Details

**Same parameters, same answer.** With the model the states were saved
from, `run_events()` reproduces the full run exactly.

**Changed fast parameters: a lead-in.** A saved state belongs to the
parameters it was saved with. When the surface stores or the time delay
change, the surface store and delay queues at the event's start would be
those of the old parameters. So each window starts `lead_h` hours before
its event, and the fast stores settle to the new parameters before the
rain arrives. A lead-in five times the sum of the surface time constants
is enough: on a 15-minute record, slowing the stores from 6 and 10 hours
to 12 and 24 hours left peaks 15% out after a 24-hour lead-in, 2% after
72 hours and 0.02% after 180 hours. `run_events()` warns when the
lead-in is shorter than that. Save with a lead-in long enough for the
slowest stores you will try. A time delay that changes the length of the
delay queues has its queues resized, with any water past the new end
added to the last place.

**Changed slow parameters: save again.** The soil and groundwater stores
are kept from the saved run, and they depend on every other parameter:
changing `b` or `cmax` moved event peaks by 50 to 130% in the same test,
however long the lead-in. `run_events()` therefore refuses a model that
differs from the saved one in anything but the surface stores and the
time delay.

The default lead-in is three response times of the catchment, and at
least a day.

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md)

## Examples

``` r
set.seed(4)
n <- 24 * 120
forcing <- data.frame(rain = ifelse(runif(n) < 0.05, rgamma(n, 0.7, scale = 5), 0),
                      pet = 0.05)
model <- pdm_model(area_km2 = 20)
flow <- run_pdm(model, forcing)$output$q_m3s
events <- find_events(forcing$rain, flow, dt = 1)
saved <- event_states(model, forcing, events)
faster <- pdm_model(area_km2 = 20, surface = FlodeCascadeRouting(k1 = 1, k2 = 2))
reruns <- run_events(faster, forcing, saved, which = 1:3)
lengths(lapply(reruns, `[[`, "q_m3s"))
#> [1] 69 47 62
```
