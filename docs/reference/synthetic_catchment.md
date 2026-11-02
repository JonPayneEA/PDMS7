# Synthetic catchment

Builds a calibration problem with a known answer: synthetic rain and PET
drive a PDM with chosen parameters, and its flow is corrupted the way a
real gauge corrupts it. Calibrating to the result shows what a method
can and cannot recover, since the truth is known.

## Usage

``` r
synthetic_catchment(
  rain = NULL,
  truth = NULL,
  start = "2010-10-01",
  years = 10,
  dt = 24,
  method = "nsrp",
  area_km2 = 60,
  storms = NULL,
  error = list(sd = 0.05, memory_h = 72),
  highest_gauged_m3s = NULL,
  rating_bias = 0.15,
  seed = NULL
)
```

## Arguments

- rain:

  Forcing from
  [`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md)
  or your own data frame; by default
  `synthetic_rain(start, years, dt, method)`.

- truth:

  The true configuration. By default, the standard structure with a
  lowland water balance: soil capacity up to 300 mm (`b` 0.4), recharge
  `kg` 4000 h above a 50 mm threshold, surface stores of 12 h each, and
  `dt` and `area_km2` set. Under the default rain it evaporates about
  350 mm a year and has a baseflow index near 0.5. Every calibrated
  parameter lies inside
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md).
  Its `dt` must match the forcing's step.

- start, years, dt, method:

  Passed to
  [`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md)
  when `rain` is not given.

- area_km2:

  Catchment area, km2, used when `truth` is not given.

- storms:

  Optional data frame of added storms: `time`, `depth_mm`, `duration_h`.

- error:

  List of `sd` (standard deviation of the log error) and `memory_h`
  (e-folding time of the error, hours). `sd = 0` gives exact flow.

- highest_gauged_m3s:

  Optional highest gauged flow, m3/s; flows above it carry the rating
  bias. Returned so it can be passed to
  [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md).

- rating_bias:

  Fractional error of the recorded flow at twice the highest gauged
  flow.

- seed:

  Optional seed for the rain and the error; the caller's random state is
  left untouched.

## Value

A list, classed `pdm_synthetic_catchment`: `forcing` (time, rain, pet),
`observed` (m3/s, as a gauge would record it), `true_flow` (m3/s),
`truth` (configuration), `highest_gauged_m3s`, and `notes`, a list
recording the rain method and parameters, the storms, the error and the
rating bias.

## Details

In order:

1.  **Forcing.** `rain` from
    [`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md),
    or a data frame you supply (with `time`, `rain` and `pet`).

2.  **Storms.** Each row of `storms` adds a storm: `depth_mm` spread
    over `duration_h` hours from `time`, in a symmetric triangular
    profile. Use them to guarantee floods larger than the generator
    would give in a short record.

3.  **True flow.** The `truth` configuration, started from a state spun
    up over the first year of forcing (three cycles), so the record
    starts in balance.

4.  **Rating bias.** With `highest_gauged_m3s`, flows above it are bent
    as an extrapolated rating would bend them: recorded = limit x (true
    / limit)^b, with b chosen so a flow twice the limit is recorded
    `rating_bias` low (15 per cent by default; negative values record
    high). Below the limit the rating is exact.

5.  **Gauge error.** A multiplicative error, persistent in time: in
    logs, an AR(1) process with standard deviation `error$sd` and an
    e-folding memory of `error$memory_h` hours.

The truth is the PDM itself, so the structure is exactly right, the rain
exactly known and the error simpler than a real gauge's. Results on a
synthetic catchment are a best case. Calibrate a different structure
from `truth` to see what structural error does.

## See also

[`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md),
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)

## Examples

``` r
river <- synthetic_catchment(years = 3, seed = 1,
  storms = data.frame(time = "2011-12-01", depth_mm = 120, duration_h = 48),
  highest_gauged_m3s = 20)
river
#> Synthetic catchment: 1095 steps of 24 h from 2010-10-01T00:00:00Z 
#>   Rain: nsrp - 798 mm a year; 1 added storm 
#>   True flow: mean 0.84 m3/s, peak 14.9 m3/s
#>   Gauge error: sd 0.05 in logs, memory 72 h
#>   Rating: exact to 20 m3/s, then 15 per cent low at twice that; 0 steps above
range(river$observed / river$true_flow)
#> [1] 0.8596667 1.1564223
```
