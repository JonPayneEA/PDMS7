# Which rain gauge the river answers to

Takes each rain gauge on its own and asks how closely the river's quick
response follows it, over the whole record and flood by flood. It is a
check made before calibrating, from the records alone: no model is run.

## Usage

``` r
gauge_response(
  gauges,
  flow,
  time = NULL,
  dt = 1,
  rain = NULL,
  area_km2 = NULL,
  max_lag_h = 48,
  lead_h = 6,
  floods = 20,
  dry_mm = 5,
  events = NULL
)
```

## Arguments

- gauges:

  A data frame or matrix of rain, mm per step, one column per gauge,
  named. Missing readings are allowed.

- flow:

  Observed flow, m3/s, the same length as the rows of `gauges`.

- time:

  Optional time stamps, for the event table.

- dt:

  Step length, hours.

- rain:

  Catchment rain for finding the events, mm per step. The mean of the
  gauges by default.

- area_km2:

  Catchment area, km2, for the event quick flow. Without it `size_r`
  uses the peak flow.

- max_lag_h:

  Longest lag tried, hours.

- lead_h:

  Longest negative lag tried, hours: rain recorded after the rise it
  caused.

- floods:

  How many of the largest events, by peak flow, to judge flood by flood;
  `NULL` for every event.

- dry_mm:

  Event rain at the other gauges above which a near-empty gauge counts
  as dry.

- events:

  Events from
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
  if already found on the same record.

## Value

A `pdm_gauge_response` list: `summary`, one row per gauge as described
above; `events`, one row per event with its winner and each gauge's rain
(mm) and correlation; `correlation`, the cross-correlations by gauge,
part and lag, for
[`plot()`](https://rdrr.io/r/graphics/plot.default.html).

## Details

**The fast response.** The rise in flow from one step to the next is
moved almost only by quick runoff, so the correlation of a gauge's rain
with the rise a few steps later measures how well that gauge explains
the spikes. `lag_h` is the lag of the strongest correlation, `r` its
value.

**Why not the slow response.** Baseflow answers to the rain of many
storms over days or weeks, and over such spans the gauges' totals
converge: a correlation of gauge rain with baseflow comes out much the
same for every gauge, whichever drives it. Long-term drift between
gauges is a matter for the double-mass curve of
[`water_balance()`](https://jonpayneea.github.io/PDMS7/reference/water_balance.md).

**Flood by flood.** For each of the `floods` largest events found on the
catchment rain, by peak flow, each gauge's rain is correlated with the
rise in flow across the event, at that gauge's own fast lag; the gauge
with the highest correlation wins the event. `event_wins` counts the
wins, `event_share` gives them as a share of the events with a winner.
`size_r` is the correlation, across events, of a gauge's event rain with
the event's quick flow: whether the gauge sees the big storms as big.
`dry_events` counts events where a gauge recorded under a tenth of the
median gauge, when that median is at least `dry_mm`: a funnel blocked, a
logger down, or a storm that missed the gauge. A storm over one gauge
alone leaves the median low and flags nobody.

**Reading it.** A gauge with a clearly higher `r` and most of the wins
drives the spike. Rain cannot follow the flow it causes, so a negative
best lag means the gauge's clock is late, or the flow's early; a gauge
whose lag differs from its neighbours' by a whole number of hours points
the same way. A gauge with no wins, a low `size_r` or many dry events is
worth checking against its neighbours and the map. Correlations between
rain gauges blur the differences, as they do in any cross-correlation
analysis (Larocque et al., 1998): read the ranking and the gaps between
gauges, not the values alone.

## References

Larocque, M., Mangin, A., Razack, M. and Banton, O. (1998). Contribution
of correlation and spectral analyses to the regional study of a large
karst aquifer (Charente, France). Journal of Hydrology, 205, 217-231.
doi:10.1016/S0022-1694(97)00155-8

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`water_balance()`](https://jonpayneea.github.io/PDMS7/reference/water_balance.md)

## Examples

``` r
river <- synthetic_catchment(years = 1, dt = 1, seed = 1)
set.seed(1)
gauges <- data.frame(a = river$forcing$rain * stats::rlnorm(nrow(river$forcing), 0, 0.3),
                     b = river$forcing$rain * stats::rlnorm(nrow(river$forcing), 0, 0.6))
gauge_response(gauges, river$observed, river$forcing$time, area_km2 = river$truth$area_km2)
#> Gauge response: 2 gauges, 20 events
#>  gauge lag_h    r event_wins event_share size_r dry_events
#>      a     2 0.56         17        0.85   0.60          0
#>      b     2 0.48          3        0.15   0.44          0
```
