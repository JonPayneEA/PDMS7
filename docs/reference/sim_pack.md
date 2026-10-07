# Simulate PACK snow

Simulate PACK snow

## Usage

``` r
sim_pack(
  precipitation_mm,
  temperature_c,
  params = pack_presets(),
  timestep_min = 60L,
  state = NULL
)
```

## Arguments

- precipitation_mm, temperature_c:

  Aligned, nonempty numeric forcing vectors.

- params:

  FlodePackModel or named PACK parameter list.

- timestep_min:

  Positive integer interval minutes.

- state:

  NULL for an empty pack, or a complete FlodePackState.

## Value

data.table with snow fluxes, final_state and water_balance attributes.
