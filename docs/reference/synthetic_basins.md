# A large sample of synthetic catchments

Writes `n` synthetic catchments as basin folders that
[`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
reads directly, each with its own climate and its own true model.
Calibrating the whole sample then shows, across many catchments at once,
what automatic calibration recovers, because every truth is known.

## Usage

``` r
synthetic_basins(
  folder,
  n = 30,
  years = 10,
  dt = 24,
  start = "2010-10-01",
  seed = 1,
  ranges = list()
)
```

## Arguments

- folder:

  Folder to write the basin folders into; created if needed. Existing
  basin folders of the same names are refused.

- n:

  Number of catchments.

- years, dt, start:

  Length (years), step (hours) and first time of every record.

- seed:

  Seed for the whole sample; each catchment is reproducible from it.

- ranges:

  Named list of `c(low, high)` ranges for `area_km2`, `wetness`,
  `storminess`, `pet_mean` (mm/day), `fc`, `cmax` (mm), `b`, `kg` (h),
  `k1` (h) and `kb`. Names left out keep their defaults.

## Value

The sample, invisibly: a data frame with one row per basin giving its
climate (mean annual rain and PET, mm), its true parameters, its mean
flow and its highest gauged flow. It is also written to `sample.csv` in
`folder`. Each basin folder holds `forcing.csv`, `flow.csv`, `basin.yml`
and `truth.yml`, the true configuration.

## Details

**Climate.** Each catchment's rain comes from the Neyman-Scott generator
([`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md))
with the built-in parameters changed in two ways: `wetness` scales the
cell intensity, and so the annual total; `storminess` multiplies the
number of cells per storm and divides their intensity by the same
factor, so storms grow more clustered and intense with no change in the
total. Potential evaporation has its own annual mean.

**Catchment.** The true model is the standard structure. Its area and
parameters are drawn independently for each catchment: uniformly for
`fc` and `b`, and uniformly on a log scale for the area and for the
parameters that span orders of magnitude. The second surface store is
the first times a factor between 1 and 3. Every drawn value lies inside
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md).
The ranges are arguments, so a sample can be made of any kind of
catchment.

**Gauge.** Each catchment is recorded with persistent gauge error and,
above the flow exceeded 0.5 per cent of the time, a rating 15 per cent
low at twice that flow, as
[`synthetic_catchment()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_catchment.md)
describes. The highest gauged flow goes into `basin.yml`, so
registration flags the flows above it.

**Windows.** After a warm-up of three months, the first 70 per cent of
the record is for calibration and the rest for validation. With seven
years or more, the batch holds back each record's two wettest years;
shorter records hold back none (`wettest_years: 0`).

## See also

[`synthetic_catchment()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_catchment.md),
[`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)

## Examples

``` r
# \donttest{
folder <- file.path(tempdir(), "sample")
sample <- synthetic_basins(folder, n = 3, years = 4, seed = 1)
sample[, c("basin", "area_km2", "rain_mm", "cmax", "kg")]
#>   basin  area_km2   rain_mm     cmax       kg
#> 1  S001 363.44064  614.8391 451.5064  603.834
#> 2  S002  50.97558 1127.0547 427.3862 1763.074
#> 3  S003 201.46167  504.1416 515.9590 1029.217
unlink(folder, recursive = TRUE)
# }
```
