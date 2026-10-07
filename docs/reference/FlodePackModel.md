# PACK snow model

PACK snow model

## Usage

``` r
FlodePackModel(
  precipitation_factor = 1,
  lower_rate_h = 0.00677,
  upper_rate_h = 0.27095,
  retention_fraction = 0.04,
  melt_factor_mmh_c = 0.16667,
  adc_alpha = 0.25,
  adc_depth_mm = 100,
  melt_threshold_c = 1,
  snow_threshold_c = 0,
  drain_threshold_c = 0,
  areal_depletion = TRUE,
  max_step_min = 60
)
```

## Arguments

- precipitation_factor:

  Nonnegative precipitation multiplier.

- lower_rate_h, upper_rate_h:

  Drainage coefficients per hour.

- retention_fraction:

  Maximum liquid fraction of total pack, in `[0,1)`.

- melt_factor_mmh_c:

  Melt factor in mm/hour/degree Celsius.

- adc_alpha:

  Fresh-snow fraction at which linear cover reversion begins, in
  `(0,1]`.

- adc_depth_mm:

  Total pack water equivalent for full cover, positive mm.

- melt_threshold_c, snow_threshold_c, drain_threshold_c:

  Temperature thresholds, Celsius.

- areal_depletion:

  Logical; FALSE selects a point pack with full cover when nonempty.

- max_step_min:

  Maximum internal Euler accounting interval in minutes.

## Value

A FlodePackModel.
