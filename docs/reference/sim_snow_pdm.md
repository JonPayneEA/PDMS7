# Simulate coupled PACK and PDM

PACK precipitation_factor is applied before snow partitioning; PDM fc
subsequently multiplies effective rain. Set fc=1 to avoid a second
correction. Combined balance explicitly includes this second correction
as an external input adjustment.

## Usage

``` r
sim_snow_pdm(
  precipitation_mm,
  temperature_c,
  pet_mm,
  params = list(pdm = pdm_presets("standard"), snow = pack_presets()),
  timestep_min = 60L,
  state = NULL,
  datetime = NULL,
  warmup_steps = 0L
)
```

## Arguments

- precipitation_mm, temperature_c:

  Aligned, nonempty numeric forcing vectors.

- pet_mm:

  Nonnegative aligned PET depths.

- params:

  Named list with exactly pdm and snow configurations.

- timestep_min:

  Positive integer interval minutes.

- state:

  NULL or the complete final_state list from a previous coupled run.

- datetime:

  Optional POSIXct interval-end timestamps, validated by sim_pdm.

- warmup_steps:

  Number of initial rows flagged for exclusion from scoring.

## Value

data.table with PDM and snow fluxes, a combined balance residual, and
final_state list containing pdm and snow states. Rain-only sim_pdm is
unchanged.
