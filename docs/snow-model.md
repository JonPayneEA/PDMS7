# PACK snow model

Source: Institute of Hydrology, *PACK: A Pragmatic Snowmelt Model for
Real-time Use*, [NORA report
15304](https://nora.nerc.ac.uk/id/eprint/15304/1/N015304CR.pdf),
especially equations 2.1–2.8, Figure 2.2 and Table 2.1. The attached
parameter-file photograph supplies the default numeric set. This is an
independent implementation; it has not been compared against an
IMFS/RFFS executable.

## Parameters and units

The image’s left-hand parameter file and right-hand typical-values table
differ. The file is the default. Its time units are not printed:
**hourly rate units are an explicit assumption**, supported by the
0.16667 melt factor (approximately 4/24), not proof of the
drainage-coefficient convention. Confirm these against the operating
system’s parameter specification before operational use. No undocumented
exponential conversion is applied to the wet-store coefficients.

| Image field    | Config key           | Image default | Canonical unit          |
|----------------|----------------------|--------------:|-------------------------|
| ppt factor     | precipitation_factor |             1 | dimensionless           |
| wet store tc1  | lower_rate_h         |       0.00677 | hour^-1, assumed        |
| wet store tc2  | upper_rate_h         |       0.27095 | hour^-1, assumed        |
| crit retention | retention_fraction   |          0.04 | fraction of total water |
| melt factor    | melt_factor_mmh_c    |       0.16667 | mm/hour/°C, assumed     |
| alpha of adc   | adc_alpha            |          0.25 | dimensionless           |
| adc crit depth | adc_depth_mm         |           100 | mm water equivalent     |
| melt threshold | melt_threshold_c     |             1 | °C                      |
| snow threshold | snow_threshold_c     |             0 | °C                      |

The file-format and parameter-set identity integers are metadata, not
hydrological parameters. `drain_threshold_c=0` is from the report.
`areal_depletion=TRUE` and `max_step_min=60` are implementation
controls. `pack_presets("report_daily")` instead converts the report’s
k1=0.15/day, k2=0.85/day and f=4 mm/day/°C to hours, with snow threshold
1°C and melt threshold 0°C. Both sets are in `inst/config/pack.yml`.

## Accounting

Precipitation is corrected once by the PACK precipitation factor. Below
the snow threshold it enters the dry store W; at equality it is rain.
Melt is `min(W, F * f * max(T - Tm, 0) * dt)` for catchment-average
stores. Rain over the snow-free fraction bypasses the pack. Rain over
covered area and melt enter S. The provisional liquid store defines
`Sc = retention_fraction * (S + W)`. Drainage is
`k1*S + k2*max(S-Sc, 0)`, inhibited below the drainage threshold.
Drainage and melt cannot withdraw more water than their respective
stores contain. All snow fluxes are interval depths; input temperature
is held constant per interval.

The ordinary cover curve is `min(1, log(1+W+S)/log(1+adc_depth_mm))`.
Fresh snow restores full cover. Cover then returns linearly towards its
prior anchor during the final alpha fraction of the fresh-snow
excursion. The report describes this in prose and a diagram rather than
complete event logic. This implementation uses **total pack
water-content depletion**, following the Figure 2.2 horizontal axis:
melt transferring W to S alone does not deplete total pack water.
Consecutive un-depleted snowfall accumulates one excursion; new snowfall
during depletion starts an excursion anchored at the current pack and
cover. This convention, including scaling catchment-average melt by F,
requires independent review.

Explicit accounting follows equation 2.6. The interval is subdivided so
each step is no longer than max_step_min and `(k1+k2)*dt <= 1`. This
avoids negative wet storage without changing coefficients. Choose
shorter internal steps for timestep sensitivity studies. It is not an
exact continuous-time solver. The model does not add refreezing, cold
content, sublimation, wind or elevation bands not specified in the
implemented report formulation.

## Use and restart

``` r
library(pdmS7)
config <- list(pdm = pdm_presets("standard"), snow = pack_presets("image_hourly"))
config$pdm$fc <- 1
out <- sim_snow_pdm(
  precipitation_mm = c(10, 5, 0, 0), temperature_c = c(-2, -1, 3, 6),
  pet_mm = rep(0.05, 4), params = config, timestep_min = 60L
)
checkpoint <- attr(out, "final_state")
next_out <- sim_snow_pdm(0, 5, 0.05, config, state = checkpoint)
attr(out, "water_balance")
```

[`sim_pack()`](https://jonpayneea.github.io/PDMS7/reference/sim_pack.md)
also runs independently. The coupled checkpoint contains both snow and
PDM states, including cover history; storing only dry/wet water loses
that history. Keep configuration and timestep unchanged on restart.
Versioned checkpoint management and configuration fingerprints remain
future extensions.

PACK output becomes PDM effective rainfall. PDM’s fc still acts on that
output; usually set fc=1 and calibrate the snow precipitation factor to
avoid confounding. `pdm_correction_mm` records any second correction.
The combined balance includes that adjustment and the PDM soil, routing
and delay stores. Signed qc retains its existing external-outlet
convention. PET is passed unchanged to PDM; a separate snow-dependent
evapotranspiration formulation is not implied.
