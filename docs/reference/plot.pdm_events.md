# Plot a table of events

Event tables from
[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md),
[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md)
and the `events` of
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)
draw three standard plots:

## Usage

``` r
# S3 method for class 'pdm_events'
plot(x, type = c("balance", "peaks", "timing"), max_ratio = 1, ...)

# S3 method for class 'pdm_events'
autoplot(object, type = c("balance", "peaks", "timing"), max_ratio = 1, ...)
```

## Arguments

- x, object:

  An event table.

- type:

  One of the plots above.

- max_ratio:

  Runoff ratio drawn as the limit on the balance plot.

- ...:

  Not used.

## Value

[`plot()`](https://rdrr.io/r/graphics/plot.default.html): `x`,
invisibly. `autoplot()`: a ggplot.

## Details

|           |                                                              |                                                                                  |
|-----------|--------------------------------------------------------------|----------------------------------------------------------------------------------|
| `type`    | Shows                                                        | Needs                                                                            |
| `balance` | each event's rain against its quick flow, runoff-ratio lines | [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md)   |
| `peaks`   | simulated against observed peak, with 1:1 and a 20% band     | [`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md) |
| `timing`  | the timing error of each peak against its size               | [`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md) |

**The balance plot** is a check on the data before it is a check on the
model. An event can shed no more quick flow than the rain that fell, so
a point above the runoff-ratio line of `max_ratio` means the rain record
missed that storm, the area is wrong, or the flow is. Points far below
the rest mark rain the gauges recorded but the river did not feel.
Screened events
([`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md))
are drawn hollow; when the table has a `period` column (from
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)),
events are coloured by window.

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md),
[`pdm_colours()`](https://jonpayneea.github.io/PDMS7/reference/pdm_colours.md)

## Examples

``` r
rain <- synthetic_rain("2021-01-01", years = 1, dt = 1, seed = 2)
config <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
flow <- run_pdm(pdm_from_config(config), rain[c("rain", "pet")])$output$q_m3s
events <- find_events(rain$rain, flow, rain$time, dt = 1, area_km2 = 20)
plot(events)

plot(event_scores(events, flow * 0.9, flow), type = "peaks")
```
