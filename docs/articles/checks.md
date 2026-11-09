# Checking the data and the events

A calibration fits whatever it is given. If the rain gauges missed a
storm, the search bends the model to make a flood out of no rain; if the
area is wrong, it bends the water balance; if a peak lies above the
highest gauging, it fits a guess. None of these shows in the score. They
show only if you look for them, before and after calibrating.

This article walks through every check pdmS7 offers, in the order to run
them: what each measures, what a failure looks like, and what to do
about it. It uses one record throughout, and a copy of it with faults
put in on purpose, so that each check can be seen to fire.

| When               | Check                 | Asks                                                                                     | Function                                                                                                                                 |
|--------------------|-----------------------|------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| Before registering | Annual totals         | Is the rain and evaporation plausible for the place?                                     | [`check_inputs()`](https://jonpayneea.github.io/PDMS7/reference/check_inputs.md)                                                         |
| Before registering | Runoff ratio          | Does less water leave than falls?                                                        | [`check_inputs()`](https://jonpayneea.github.io/PDMS7/reference/check_inputs.md)                                                         |
| Before registering | Water balance by year | Does each year fit the water and energy limits, and does any year or period stand apart? | [`water_balance()`](https://jonpayneea.github.io/PDMS7/reference/water_balance.md)                                                       |
| Before calibrating | Event balance         | Did each event shed less quick flow than its rain?                                       | [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md), [`plot()`](https://rdrr.io/r/graphics/plot.default.html) |
| Before calibrating | Event screening       | Which events are too small, gappy or doubtful to judge by?                               | [`screen_events()`](https://jonpayneea.github.io/PDMS7/reference/screen_events.md)                                                       |
| After calibrating  | Parameters            | Did the search press against a limit?                                                    | [`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)                                             |
| After calibrating  | Peaks and timing      | Are the largest floods the right size, at the right time?                                | [`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)                                             |
| After calibrating  | The stages            | Did each stage do its job, and did the starts agree?                                     | [`calibration_path()`](https://jonpayneea.github.io/PDMS7/reference/calibration_path.md)                                                 |

## The record

Five years of hourly rain over a 25 km² catchment, and the flow of a
model of it with measurement error added. This is the record as it
should be.

``` r
rain <- synthetic_rain("2019-10-01", years = 5, dt = 1, seed = 11)
forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
truth <- pdm_presets("standard")
truth$area_km2 <- 25
truth$td <- 1
model <- pdm_from_config(truth)
set.seed(11)
flow <- run_pdm(model, forcing, initial_state_from_flow(model, 0.4, 0.7))$output$q_m3s *
  exp(rnorm(nrow(forcing), 0, 0.08))
```

## Before registering: the whole record

The first check looks at the record as a whole. Rain and evaporation
should add up to plausible annual totals for the place, and the flow,
spread over the catchment, should come to less than the rain: some of
what falls evaporates. The share that runs off, the runoff ratio, is
about 0.2 in the dry south-east of England and 0.8 or more in the wet
north and west. A ratio above one means the rain is too low, the flow
too high, or the area wrong.

``` r
check_inputs(forcing, flow, area_km2 = 25)
#> Input check: 5.0 years at 1 h steps
#>   rain  0 missing, 0 negative, mean 0.08118, 712 mm a year
#>   pet   0 missing, 0 negative, mean 0.06251, 548 mm a year
#>   flow  0 missing, 0 negative, mean 0.3469
#>   Runoff is 62% of rain
#> Nothing implausible found
```

Here everything is plausible. Now the same record with the area mistyped
as 2.5 km², the kind of slip that happens when copying from a catchment
descriptor:

``` r
check_inputs(forcing, flow, area_km2 = 2.5)
#> Input check: 5.0 years at 1 h steps
#>   rain  0 missing, 0 negative, mean 0.08118, 712 mm a year
#>   pet   0 missing, 0 negative, mean 0.06251, 548 mm a year
#>   flow  0 missing, 0 negative, mean 0.3469
#>   Runoff is 615% of rain
#> CHECK:
#>   runoff is 615% of rain, outside 10% to 90%: check the area, the units or the rain
```

The water balance is impossible, and the check says so before any
calibration is spent on it. A model given this area would need ten times
the rain it has; the search would push the rainfall factor to its limit
and still fall short.

### Year by year: the water balance

A whole-record check can pass while single years fail. Over a year a
catchment stores little, so what it loses, rain minus flow, is mostly
evaporation. That gives two limits (Budyko, 1974): the loss cannot
exceed the rain, so the flow cannot go negative, and it cannot much
exceed the potential evaporation, because the atmosphere cannot take
more.
[`water_balance()`](https://jonpayneea.github.io/PDMS7/reference/water_balance.md)
measures both for every water year, from October, and looks for years,
or runs of years, that stand apart from the rest:

``` r
wb <- water_balance(forcing, flow, area_km2 = 25)
wb
#> Water balance over 5.0 years with flow: rain 712 mm, potential evaporation 548 mm, flow 438 mm a year
#> Runoff ratio 0.62; loss over potential evaporation 0.50; baseflow index 0.68
#>  year complete rain pet flow ratio loss_pet flag
#>  2020     100%  710 549  498  0.70     0.39     
#>  2021     100%  706 547  430  0.61     0.51     
#>  2022     100%  632 548  347  0.55     0.52     
#>  2023     100%  721 548  447  0.62     0.50     
#>  2024     100%  787 546  466  0.59     0.59     
#> Nothing implausible found
```

``` r
plot(wb)
```

![Each water year's loss over its rain against its potential evaporation
over its rain. Above the dashed lines is impossible; the grey curve is
where a typical catchment lies (Fu,
1981).](checks_files/figure-html/budyko-1.png)

Each water year’s loss over its rain against its potential evaporation
over its rain. Above the dashed lines is impossible; the grey curve is
where a typical catchment lies (Fu, 1981).

The years sit in a cluster below both limits. A part year at the start
or end of a record is reported but not judged, since a winter alone
would look far wetter than a whole year.

Now the same record with a new rating from October 2022, under which
every flow reads 40% higher. No single year stands far from the median,
because half the record is affected; the whole-record runoff ratio still
looks plausible. The change shows when the years are compared before and
after each boundary:

``` r
rerated <- flow
after <- forcing$time >= as.POSIXct("2022-10-01", tz = "UTC")
rerated[after] <- rerated[after] * 1.4
wb_step <- water_balance(forcing, rerated, area_km2 = 25)
wb_step$flags
#> [1] "The runoff ratio changes after water year 2022, from 0.62 to 0.85 (+37%): a new rating, a moved gauge or a changed rain network?"
```

``` r
plot(wb_step, type = "double_mass")
```

![Cumulative flow against cumulative rain. The curve bends upward where
the new rating starts.](checks_files/figure-html/double-mass-1.png)

Cumulative flow against cumulative rain. The curve bends upward where
the new rating starts.

The double-mass curve, cumulative flow against cumulative rain, is
straight while the two records agree and kinks where one of them
changes. Calibrated across the kink, a model would average two
catchments that never existed. The cure is in the data: find out which
record changed, and why, before calibrating; or calibrate on one side of
the change only.

[`water_balance()`](https://jonpayneea.github.io/PDMS7/reference/water_balance.md)
also returns the baseflow index, here 0.68: the share of flow beneath
the baseflow line of the events. It is close to the standard UK index
from five-day minima, about 0.2 on clay and 0.9 on chalk. A value far
from what the geology suggests is worth questioning before the
groundwater store is calibrated.

### What was done to the data

The check also lists what was done to each series, when it was prepared
with pdmS7’s preparation functions (see [Getting started with
data](https://jonpayneea.github.io/PDMS7/articles/data-preparation.md)),
so a gap filled with zeros or a unit converted on a guess is in plain
sight.

## Before calibrating: event by event

The record can balance overall and still be wrong for single storms: a
gauge that missed a storm, a radar outage, a flow record with a step in
it.
[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md)
finds the storms and their responses in the record, and for each one
measures the rain that fell and the quick flow it produced: the flow
above the slow baseflow line, from the rise to the end of the recession,
as depth over the catchment.

An event cannot shed more quick flow than the rain that fell. Its runoff
ratio, quick flow over rain, is usually well below one: some rain wets
the soil, some reaches groundwater.

``` r
events <- screen_events(find_events(forcing$rain, flow, forcing$time, dt = 1, area_km2 = 25),
                        flow)
nrow(events)
#> [1] 527
summary(events$runoff_ratio)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#> 0.00000 0.09943 0.15605 0.16554 0.23292 0.42403
```

``` r
plot(events)
```

![Each event's rain against its quick flow. Dashed: a runoff ratio of
one, the limit. Grey lines: ratios of 0.5 and 0.1. Hollow: events set
aside by screening.](checks_files/figure-html/balance-1.png)

Each event’s rain against its quick flow. Dashed: a runoff ratio of one,
the limit. Grey lines: ratios of 0.5 and 0.1. Hollow: events set aside
by screening.

The events lie in a band below the limit, the larger storms shedding a
larger share, as wetter soil lets more run off. Now the same record with
the rain gauge catching only a twentieth of the largest storm, as when a
funnel blocks or a logger fails part way through:

``` r
biggest <- events[which.max(events$peak_flow), ]
storm <- biggest$rain_start:biggest$rain_end
broken <- forcing
broken$rain[storm] <- broken$rain[storm] * 0.05
bad_events <- screen_events(find_events(broken$rain, flow, broken$time, dt = 1,
                                        area_km2 = 25), flow)
plot(bad_events)
```

![The same record with most of the rain missing for the largest storm.
Its event now lies above the
limit.](checks_files/figure-html/balance-bad-1.png)

The same record with most of the rain missing for the largest storm. Its
event now lies above the limit.

The flood is still in the flow, but nearly all the rain that caused it
is gone, so its event jumps above the limit. The screening flags it, and
the events stage and the acceptance checks leave it out, so the search
does not learn to make floods from nothing:

``` r
flagged <- bad_events[grepl("quickflow_above_rain", bad_events$flags), ]
flagged[, c("rain_start_time", "rain_mm", "quickflow_mm", "runoff_ratio", "use")]
#>        rain_start_time  rain_mm quickflow_mm runoff_ratio   use
#> 39 2020-02-13 13:00:00 1.019897     7.941785     7.786851 FALSE
```

A gauge that recorded nothing at all for a storm is caught differently:
with no rain there is no event to find, so the flood shows up instead as
a rise in the flow with no event around it, and as a dry spell in the
rain record during a wet month. The hydrograph,
`plot(project_series(project))`, shows both.

Screening sets aside four kinds of event. Three are excluded from
scoring by default; the fourth is only marked:

| Flag                   | Means                                                                              | Excluded by default |
|------------------------|------------------------------------------------------------------------------------|---------------------|
| `quickflow_above_rain` | More quick flow than rain: the rain record must be wrong for this event            | Yes                 |
| `small_rise`           | The peak rises less than a fifth of the baseflow beneath it, lost in the baseflow  | Yes                 |
| `gaps`                 | Over a tenth of the event’s flow is missing                                        | Yes                 |
| `above_gauging`        | The peak lies above the highest gauged flow, so it rests on an extrapolated rating | No, only marked     |

In a catchment with a high baseflow, many small storms barely lift the
river. They are the hollow points at the bottom left of the balance
plot, and setting them aside stops the search from fitting noise. The
threshold, `min_rise`, can be raised or lowered.

**Events far below the rest** are the other warning. Rain the gauges
recorded but the river did not feel can be a gauge outside the catchment
catching a storm that missed it, or a heavy shower over one gauge given
too much weight. The rainfall article, [Catchment rainfall from gauges
and radar](https://jonpayneea.github.io/PDMS7/articles/rainfall.md),
shows how to weigh gauges and radar so that each storm’s rain is right.

## After calibrating: the checks a score hides

A calibration run end to end, as [Automatic calibration from start to
finish](https://jonpayneea.github.io/PDMS7/articles/calibration-journey.md)
describes, here in one call:

``` r
options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
project <- file.path(tempdir(), "checks-brook")
unlink(project, recursive = TRUE)
start <- pdm_presets("standard")
start$area_km2 <- 25
calibrate_project(project, forcing, flow, area_km2 = 25,
                  calibration = c("2021-04-01", "2022-12-31 23:00"),
                  validation = c("2023-01-01", "2023-12-31 23:00"), structure = start,
                  starts = 2L, control = list(maxit = 15L), wettest_years = 0)
```

``` r
checks <- calibration_checks(project, top = 10)
checks
#> Acceptance checks. Response time 3.00 h observed, 2.00 h simulated
#> PARAMETERS AT A BOUND (the structure may be bent to fit; review before use):
#>   recharge.kg                4782 at its upper bound (searched 1 to 5000)
#> Largest events in each window:
#>       period events median_peak_error median_timing_error_h
#>  calibration     10             -0.12                    -1
#>   validation     10             -0.07                     0
#>      outside     10             -0.07                    -1
#>  share_peak_within_20pct median_event_nse screened_out
#>                      0.9             0.96           10
#>                      1.0             0.96            9
#>                      0.9             0.96           13
```

### Parameters at a limit

``` r
plot(checks)
```

![Where each parameter ended within its search range, on the scale the
search used. One at either end would be
flagged.](checks_files/figure-html/bounds-1.png)

Where each parameter ended within its search range, on the scale the
search used. One at either end would be flagged.

A parameter pressed against the end of its range is the clearest warning
a calibration gives. The search wanted to go further than any sensible
value, nearly always to make up for something else: rain that is too
low, an area that is wrong, a structure that cannot do what the
catchment does. Widening the range lets the fault hide better; finding
it is the cure. A lower bound of zero, such as no time delay, is not
flagged: zero is a value, not a limit.

Here recharge.kg is flagged: it ended at 4780, at the upper end of a
range of 1 to 5000. Not every parameter pressed to an edge is a fault in
the data: some barely change the flow, and the search moves them because
nothing pulls them back. The recharge and groundwater constants are the
usual drifters; [What limits automatic
calibration](https://jonpayneea.github.io/PDMS7/articles/calibration-study.md)
shows which parameters a record can and cannot pin down. Before widening
a range, ask which: a parameter that matters and sits at its limit
points to a fault elsewhere; one that does not matter can be fixed at a
sensible value with `exclude` in
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md),
so it stops drifting.

### Peaks and timing

``` r
plot(checks, type = "peaks")
```

![Simulated against observed peaks of every event, by window. Dashed:
20% either side.](checks_files/figure-html/peaks-1.png)

Simulated against observed peaks of every event, by window. Dashed: 20%
either side.

``` r
plot(checks, type = "timing")
```

![How late each simulated peak comes, against its
size.](checks_files/figure-html/timing-1.png)

How late each simulated peak comes, against its size.

The score over the whole record is dominated by the many hours of
ordinary flow. These two plots look only at the floods. Here the peaks
run 11% low in the median, while NSE on the calibration window is 0.98:
a short calibration that has the timing right and the size wrong, which
is just what the events stage is for. Peaks consistently low, or
consistently late, outweigh a good score: see [Getting the floods
right](https://jonpayneea.github.io/PDMS7/articles/floods.md) for what
to do about them, from the events stage to adjusting the largest floods
by eye.

### The stages

``` r
path <- calibration_path(project)
path
#> Calibration path: 3 automatic calibrations
#>   0004  1 of 3: volume and baseflow        NSE 0.946, log NSE 0.963, volume -0.0%, 1749 runs
#>   0005  2 of 3: fast response              NSE 0.976, log NSE 0.974, volume +0.3%, 203 runs
#>   0006  3 of 3: polish                     NSE 0.977, log NSE 0.973, volume +0.2%, 630 runs
#> Candidate NSE by window: calibration 0.977, validation 0.975
plot(path)
```

![The scores after each stage of the
calibration.](checks_files/figure-html/stages-1.png)

The scores after each stage of the calibration.

Each stage has its own job. The first should settle the water balance
and the low flows (log NSE); the second should lift the floods (NSE)
with the balance held; the polish should move little. A first stage that
leaves log NSE poor means the slow stores cannot match the record: look
again at the area, the evaporation and the recharge rule.
`plot(path, type = "starts")` shows each start’s result: starts that end
far apart mean the search has more than one valley, and more starts are
worth their cost.

``` r
plot(path, type = "windows")
```

![The candidate's scores in each
window.](checks_files/figure-html/windows-1.png)

The candidate’s scores in each window.

A large fall from the calibration window to validation means the model
has learnt the calibration years rather than the catchment. Some fall is
normal; a fall of a tenth or more in NSE deserves a look at what changed
between the windows.

## The order of work

1.  **Prepare and check the record** with
    [`check_inputs()`](https://jonpayneea.github.io/PDMS7/reference/check_inputs.md),
    then year by year with
    [`water_balance()`](https://jonpayneea.github.io/PDMS7/reference/water_balance.md).
    Fix any flag before going on: a calibration cannot repair a wrong
    area, a misread unit or a change of rating.
2.  **Look at the events** with `plot(events)`. Points above the limit
    are storms the rain missed; screening sets them aside, but several
    from one gauge mean the gauge needs a look.
3.  **Calibrate**, with
    [`calibrate_project()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_project.md)
    or step by step.
4.  **Run the checks**: `plot(calibration_checks(project))` for the
    parameters, then the peaks and timing;
    `plot(calibration_path(project))` for the stages.
5.  **Act on what they show** before proposing the candidate: each
    failure points back to the data, the structure or the stages, as the
    [overview](https://jonpayneea.github.io/PDMS7/articles/calibration-journey.html#step-5-the-checks)
    shows.

Every plot here also draws in ggplot2: replace
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) with
[`ggplot2::autoplot()`](https://rdrr.io/pkg/ggplot2/man/autoplot.html)
to get a ggplot to change or combine.
[`pdm_save()`](https://jonpayneea.github.io/PDMS7/reference/pdm_save.md)
writes any of them at report, slide or journal size.
