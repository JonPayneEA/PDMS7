# Stress tests of a calibration

A calibration fitted to one climate can fail in another. These calibrate
the same model on different parts of the record and compare.

## Usage

``` r
split_sample_test(
  config,
  forcing,
  observed,
  lower,
  upper,
  split = c("climate", "halves"),
  min_share = 0.9,
  log_offset = 0.01,
  start = c("flow", "soil"),
  baseflow_fraction = 0.7,
  soil_fraction = 0.5,
  ...
)

parameter_drift(
  config,
  forcing,
  observed,
  lower,
  upper,
  periods = 3L,
  min_share = 0.9,
  log_offset = 0.01,
  start = c("flow", "soil"),
  baseflow_fraction = 0.7,
  soil_fraction = 0.5,
  ...
)

# S3 method for class 'pdm_parameter_drift'
plot(x, ...)

# S3 method for class 'pdm_parameter_drift'
autoplot(object, ...)
```

## Arguments

- config, forcing, observed, lower, upper:

  As in
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md);
  `forcing` needs `time`.

- split:

  `"climate"` (dry against wet years) or `"halves"` (early against
  late).

- min_share:

  Share of a water year's flows that must be observed for it to count.

- log_offset:

  Offset for the logs and the Box-Cox scores, m3/s.

- start, baseflow_fraction, soil_fraction:

  How every run starts, as in
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md);
  the scoring runs start the same way.

- ...:

  Passed to
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

- periods:

  Number of periods for `parameter_drift()`.

- x:

  A result.

- object:

  A result.

## Value

`split_sample_test()`: a `pdm_split_sample` list with `scores` (each
calibration, on its own years and on the other years), `parameters` and
`years`. `parameter_drift()`: a `pdm_parameter_drift` list with
`parameters` (one row per period) and `scores`.

## Details

**The differential split-sample test** (`split_sample_test()`, after
Klemes, 1986) sorts the complete water years by rain, calibrates on the
drier half and validates on the wetter half, then the reverse. A model
fit for floods in a wetter future should keep its score from dry to wet;
a large drop means the calibration leans on conditions it will not
always meet. `split = "halves"` uses the first and second halves of the
record instead, the classic split sample, which tests change over time
rather than climate.

**Parameter drift** (`parameter_drift()`) cuts the record into `periods`
runs of consecutive water years and calibrates each on its own.
Parameters that stay put are determined by the data; a steady drift
points to a change in the catchment or the record (a new rain gauge, a
rating change, land use, abstraction) that one long calibration would
average away.

Every calibration simulates the whole record and scores only its own
years, so each starts with the stores as they stand. Arguments in `...`
go to
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
(`objective`, `method`, `control`, `start` and so on).

## See also

[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)

## Examples

``` r
rain <- synthetic_rain("2010-10-01", years = 4, dt = 1, seed = 2)
cfg <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
flow <- run_pdm(pdm_from_config(cfg), rain[c("rain", "pet")])$output$q_m3s
start <- modifyList(cfg, list(fc = 0.8))
sst <- split_sample_test(start, rain[c("time", "rain", "pet")], flow,
                         lower = c(fc = 0.5), upper = c(fc = 1.5), control = list(maxit = 20))
sst$scores
#>   calibrated_on scored_on   own       nse boxcox_nse volume_error
#> 1           dry       dry  TRUE 0.9999999  0.9999999 3.077134e-05
#> 2           dry       wet FALSE 0.9274184  0.8875268 8.965647e-02
#> 3           wet       dry FALSE 0.9915501  0.9951611 4.793478e-02
#> 4           wet       wet  TRUE 0.9344182  0.8969844 4.435909e-02
```
