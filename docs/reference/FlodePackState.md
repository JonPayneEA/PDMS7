# PACK state including fresh-snow cover memory

PACK state including fresh-snow cover memory

## Usage

``` r
FlodePackState(
  dry_mm = 0,
  wet_mm = 0,
  anchor_mm = 0,
  anchor_fraction = 0,
  fresh_mm = 0
)
```

## Arguments

- dry_mm, wet_mm:

  Catchment-average dry and liquid water stores, mm.

- anchor_mm, anchor_fraction:

  Pack content and cover before latest fresh snowfall.

- fresh_mm:

  Accumulated fresh snowfall defining the cover reversion segment.

## Value

A FlodePackState; persist the complete object for restart.
