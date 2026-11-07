# Screen events before scoring a model on them

A hydrologist calibrating by eye discounts events they do not trust. The
optimiser does not, unless told. `screen_events()` flags them, so the
event objective and the acceptance checks can leave them out and a
reviewer can see why.

## Usage

``` r
screen_events(
  events,
  observed,
  min_rise = 0.2,
  max_ratio = 1,
  max_gap = 0.1,
  highest_gauged_m3s = NULL,
  exclude = c("small_rise", "quickflow_above_rain", "gaps")
)
```

## Arguments

- events:

  Events from
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
  with its `baseflow` attribute; with an area, the runoff ratio is also
  tested.

- observed:

  Observed flow, m3/s, as passed to
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md).

- min_rise:

  Smallest rise of the peak above the baseflow beneath it, as a share of
  that baseflow.

- max_ratio:

  Largest plausible runoff ratio: quick flow over rain.

- max_gap:

  Largest share of the flow window that may be missing.

- highest_gauged_m3s:

  Optional highest gauged flow, m3/s.

- exclude:

  Flags that leave an event out (`use = FALSE`).

## Value

`events` with `rise_ratio` (the peak's rise above the baseflow beneath
it, over that baseflow; `Inf` where the baseflow is zero), `flags` (the
flags raised, separated by `"; "`, or `""`) and `use`.

## Details

|                        |                                                                   |                                 |
|------------------------|-------------------------------------------------------------------|---------------------------------|
| Flag                   | Meaning                                                           | Leaves the event out by default |
| `small_rise`           | The peak rises less than `min_rise` times the baseflow beneath it | Yes                             |
| `quickflow_above_rain` | More quick flow than rain (runoff ratio above `max_ratio`)        | Yes                             |
| `gaps`                 | More than `max_gap` of the flow window is missing                 | Yes                             |
| `above_gauging`        | The peak is above the highest gauged flow                         | No                              |

Every test works on flow above the baseflow line that
[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md)
draws between the events' start and end points, not on total flow, so
that a high, steady baseflow is neither counted as event runoff nor
mistaken for a rise. In a groundwater-fed catchment a small rise on a
large baseflow carries little information about peak size or timing: a
few percent of noise moves the peak by hours. `min_rise` is the share of
the baseflow the rise must reach for the event's peak and timing to
count; raise it where baseflow dominates.

A peak above the highest gauged flow is flagged but kept: the rating may
get its size wrong, but rarely its timing, and these are usually the
events that matter most. Add `"above_gauging"` to `exclude` to leave
them out.

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md),
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)

## Examples

``` r
set.seed(4)
n <- 24 * 120
forcing <- data.frame(rain = ifelse(runif(n) < 0.05, rgamma(n, 0.7, scale = 5), 0),
                      pet = 0.05)
flow <- run_pdm(pdm_model(area_km2 = 20), forcing)$output$q_m3s
events <- find_events(forcing$rain, flow, dt = 1, area_km2 = 20)
screened <- screen_events(events, flow, min_rise = 0.5)
table(screened$flags)
#> 
#>            small_rise 
#>         92         24 
```
