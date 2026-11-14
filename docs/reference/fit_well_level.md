# Fit the well level to an observed well

The groundwater extension's well level is a straight line in the
modelled storage `S`: `hw - Ys (Smax_b - S)`, in m. `Ys` (m of water
table per mm of storage deficit) and `hw` (the datum, m) do not change
the flow, so they need no calibration run: once the flow is calibrated,
a least-squares line of the observed well level on `S` gives `Ys` as its
slope and `hw` from its intercept and `Smax_b`. `Smax_b` itself only
shifts the datum, so any value serves, provided the same one goes into
the model.

## Usage

``` r
fit_well_level(x, well, smax_b = NULL, time = NULL)

# S3 method for class 'pdm_well_fit'
plot(x, type = c("series", "scatter"), ...)
```

## Arguments

- x:

  A
  [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md)
  result, or its `output` data frame, with a `groundwater_mm` column.

- well:

  Observed well levels, m, one per row of the output, `NA` where not
  read.

- smax_b:

  Maximum groundwater storage, mm. By default read from the output's
  `groundwater_deficit_mm` (a model with the groundwater extension);
  otherwise required.

- time:

  Optional times of the rows, for the plot.

- type:

  `"series"`, the modelled level through time with the readings, or
  `"scatter"`, the readings against the modelled level.

- ...:

  Passed to
  [`graphics::plot()`](https://rdrr.io/r/graphics/plot.default.html).

## Value

A list, classed `pdm_well_fit`: `ys` (m/mm), `hw` (m), `smax_b` (mm),
`specific_yield` (`1 / (1000 ys)`), `n` (readings used), `rmse_m`, `r2`,
`bias_m`, and `modelled`, `observed` and `time`, one per row.

## Details

Dip readings are often weekly or monthly: give `well` one value per step
of the run, with `NA` where there is no reading. A slope at or below
zero means the well falls as the modelled store fills, and the function
stops: the store is not following the aquifer this well sees. A good fit
is necessary, not sufficient: a well a long way from the river can lag
the store by weeks, which shows as loops in
`plot(fit, type = "scatter")`.

## Examples

``` r
cfg <- pdm_presets("standard")
cfg$area_km2 <- 20
cfg$groundwater$extension <- list(smax_b = 800, ys = 0.02, hw = 60)
model <- pdm_from_config(cfg)
forcing <- synthetic_rain("2020-01-01", years = 1, dt = 1, seed = 1)
out <- run_pdm(model, forcing)$output
readings <- rep(NA_real_, nrow(out))
weekly <- seq(1, nrow(out), by = 168)
readings[weekly] <- out$well_level_m[weekly] + rnorm(length(weekly), sd = 0.05)
fit <- fit_well_level(out, readings)
fit
#> Well level fitted to 53 readings
#>   ys 0.02261 m/mm (specific yield 0.0442)
#>   hw 62.060 m, with smax_b 800 mm
#>   RMSE 0.049 m, R2 0.219
#> Set extension ys and hw to these values, with the same smax_b.
```
