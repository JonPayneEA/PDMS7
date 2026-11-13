# Rainfall-runoff events from rain and flow records

Finds rainfall-runoff events in continuous records objectively, with the
DMCA-based event separation routine (DMCA-ESR) of Giani et al. (2022).
It needs no baseflow separation and one setting, `rain_min`, and applies
at any time step that resolves the delay between rain and flow. Each
event has a rain window and a flow window; a baseflow line joining the
flow windows' ends gives each event's quick flow afterwards.

## Usage

``` r
find_events(
  rain,
  flow,
  time = NULL,
  dt = 1,
  rain_min = NULL,
  max_response_h = 150,
  area_km2 = NULL,
  independent = TRUE,
  separation = 3,
  trough = 2/3
)
```

## Arguments

- rain:

  Rain per step (mm). Missing values count as zero.

- flow:

  Flow per step, m3/s (or any units if `area_km2` is not given).

- time:

  Optional times of the steps, carried into the result.

- dt:

  Time step, hours.

- rain_min:

  Smallest rain intensity that counts at this time step, mm/h. By
  default 0.2 mm/h at an hourly step, scaled by `dt^-0.5` (0.04 mm/h for
  daily data, 0.4 mm/h for 15-minute data), following the guidance of
  Giani et al. (2022) for British catchments. They found results
  insensitive between about 0.1 and 1 mm/h at hourly scale.

- max_response_h:

  Passed to
  [`response_time_dmca()`](https://jonpayneea.github.io/PDMS7/reference/response_time_dmca.md).

- area_km2:

  Optional catchment area, km2. With it, flow volumes are in mm and each
  event has a runoff ratio.

- independent:

  Merge the events of one flood into one. At short time steps a long
  flood fed by several bursts of rain is cut into an event per burst,
  each a slice of the same hydrograph, so a list of the largest events
  counts one flood many times. With `independent = TRUE`, neighbouring
  events are one flood unless their peaks are independent by the rule
  used for UK peaks-over-threshold series: at least `separation`
  response times apart, with the flow between them falling below
  `trough` times the smaller peak; events whose flow windows overlap are
  always one flood. Merged events span all their parts, and their rain,
  peak and volumes are worked out afresh. This is the default. `FALSE`
  gives the published method's events unchanged, an event per burst of
  rain.

- separation, trough:

  The independence rule: the least gap between peaks, in response times,
  and the share of the smaller peak the flow must fall below between
  them.

## Value

A data frame with one row per event: `event`, the first and last rows of
its rain window (`rain_start`, `rain_end`) and flow window
(`flow_start`, `flow_end`), their times when `time` is given, `rain_mm`,
`peak_row` and `peak_flow` (the largest flow in the flow window), and
with `area_km2`, `flow_mm` and `quickflow_mm` (flow above the baseflow
line) and `runoff_ratio` (quick flow over rain). Attributes: `response`
(from
[`response_time_dmca()`](https://jonpayneea.github.io/PDMS7/reference/response_time_dmca.md)),
`rain_min`, `dt` and `baseflow`, the baseflow line.

## Details

The routine, in brief:

1.  Estimate the response time with
    [`response_time_dmca()`](https://jonpayneea.github.io/PDMS7/reference/response_time_dmca.md),
    and take the rain and flow fluctuations at its window. Rain
    fluctuations smaller than the largest that `rain_min` alone could
    cause are set to zero.

2.  An event's core is a run of steps where both fluctuations are
    non-zero; two steps where either is zero end it.

3.  Move the core's ends outwards to where the rain starts and stops
    (rain at or below `rain_min` delimits it), then to where the flow
    starts to rise and finishes receding (from the signs of the flow
    fluctuations, which are negative before the centre of mass and
    positive after it).

4.  Discard events with no dry spell around their rain, or whose flow
    window does not start before the flow's centre of mass and end after
    it; merge events that overlap.

This is an independent implementation from the published description and
its reference code. One detail differs: overlapping events merge into
one spanning all of them, where the reference code takes the end of the
last. Rain windows that would run off either end of the record are
discarded.

It was checked against the authors' reference code
(<https://github.com/giuliagiani/DMCA-ESR>), run in Octave, on three
synthetic records: two years of hourly data from a fast and a slow
catchment, and ten years of daily data. The response times and all 663
event windows were identical. None of those records had overlapping
events, so the one deliberate difference above was not exercised.

The work is done by the C core (`pdm_find_events()` and
`pdm_event_summary()` in `src/pdm_core.h`), which other languages can
call directly; `options(pdmS7.engine = "r")` runs the R reference
implementation instead.

## References

Giani, G., Tarasova, L., Woods, R. A. and Rico-Ramirez, M. A. (2022). An
objective time-series-analysis method for rainfall-runoff event
identification. Water Resources Research, 58, e2021WR031283.
doi:10.1029/2021WR031283

## See also

[`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md),
[`batch_events()`](https://jonpayneea.github.io/PDMS7/reference/batch_events.md),
[`response_time_dmca()`](https://jonpayneea.github.io/PDMS7/reference/response_time_dmca.md)

## Examples

``` r
river <- synthetic_catchment(years = 2, dt = 1, seed = 1)
events <- find_events(river$forcing$rain, river$observed, river$forcing$time, dt = 1,
                      area_km2 = river$truth$area_km2)
attr(events, "response")$response_h
#> [1] 6
head(events[, c("rain_start_time", "flow_end_time", "rain_mm", "runoff_ratio")])
#>       rain_start_time       flow_end_time   rain_mm runoff_ratio
#> 1 2010-10-02 22:00:00 2010-10-05 20:00:00  4.204681   0.15251290
#> 2 2010-10-06 11:00:00 2010-10-07 16:00:00 28.696401   0.06469433
#> 3 2010-10-12 20:00:00 2010-10-18 07:00:00 32.945947   0.21424012
#> 4 2010-10-20 15:00:00 2010-10-28 12:00:00 29.338894   0.21780040
#> 5 2010-10-28 22:00:00 2010-10-30 06:00:00 19.380328   0.09502864
#> 6 2010-10-30 07:00:00 2010-10-31 23:00:00 13.293663   0.12727539
```
