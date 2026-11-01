# Response time of a calibrated model

Measures how quickly a model's catchment responds to rain, by experiment
rather than by formula, so it works for any structure. The model starts
in steady state at a reference flow, a single pulse of rain falls in the
first time step, and the extra flow it causes is traced until it has
nearly gone. A second run without the pulse is subtracted, so the
recession the model was already in does not count.

## Usage

``` r
pdm_response_time(
  model,
  flow,
  baseflow_fraction = 0.7,
  pulse_mm = 10,
  max_hours = 24 * 60,
  feh_time_to_peak_h = NULL
)
```

## Arguments

- model:

  A FlodePdmModel.

- flow:

  Reference flow in m3/s at which the catchment starts, in steady state.

- baseflow_fraction:

  Share of the reference flow that is baseflow, as in
  [`initial_state_from_flow()`](https://jonpayneea.github.io/PDMS7/reference/initial_state_from_flow.md).

- pulse_mm:

  Depth of the rain pulse in mm, falling in the first time step.

- max_hours:

  Longest response to trace, in hours.

- feh_time_to_peak_h:

  Optional FEH time to peak in hours, for comparison.

## Value

A list: `time_to_peak_h`, `recession_h`, `centroid_lag_h`, `peak_m3s`
(extra flow at the peak), `dt` (model step, h), `response` (a data.frame
of time in hours from the pulse centre and the extra flow) and, when FEH
is given, `feh` (time to peak, ratio and flag).

## Details

|                  |                                                                      |
|------------------|----------------------------------------------------------------------|
| Result           | Meaning                                                              |
| `time_to_peak_h` | From the middle of the pulse to the peak of the extra flow           |
| `recession_h`    | From the peak until the extra flow falls to 1/e (37 per cent) of it  |
| `centroid_lag_h` | From the middle of the pulse to the centre of mass of the extra flow |

The time to peak is interpolated between steps with a parabola through
the peak.

The answer depends on how wet the catchment is, because the soil store
decides how much of the pulse runs off and the groundwater store may be
nonlinear. Give the reference flow you care about: a typical flood flow
for forecasting, the median for general use.

**Comparing with FEH.** If `feh_time_to_peak_h` is given, from catchment
descriptors (for example
[`reach.postproc::feh_time_to_peak()`](https://rdrr.io/pkg/reach.postproc/man/feh_time_to_peak.html)),
the two are compared. A ratio outside 0.5 to 2 is flagged: either the
model's fast stores or the descriptors deserve a look. The model's own
figure is the better guide for that model, because it reflects the
calibration; the FEH figure is an independent check.

## See also

[`ar_from_response_time()`](https://jonpayneea.github.io/PDMS7/reference/ar_from_response_time.md),
[`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md)

## Examples

``` r
model <- pdm_model(area_km2 = 50)
rt <- pdm_response_time(model, flow = 5)
rt[c("time_to_peak_h", "recession_h", "centroid_lag_h")]
#> $time_to_peak_h
#> [1] 16.40128
#> 
#> $recession_h
#> [1] 41.34123
#> 
#> $centroid_lag_h
#> [1] 55.75434
#> 
```
