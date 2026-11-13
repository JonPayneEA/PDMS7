# Multi-zone PDM

A multi-zone PDM divides the catchment into hydrological zones, each a
complete PDM with its own parameters, area and delay, driven by the same
rainfall and evaporation; their flows are added at the outlet (PDM for
PCs configuration guide, section 5). It gives a catchment a third
timescale where one PDM's two routes are not enough: a sharp spike over
a few hours, then a slower flood hydrograph, then baseflow.

## Usage

``` r
two_zone_config(config, share = 0.1, names = c("main", "fast"))

FlodeMultiZoneModel(zones = list(), area_km2 = integer(0), dt = integer(0))

FlodeMultiZoneState(states = list())
```

## Arguments

- config:

  A single-zone configuration.

- share:

  Starting share of the catchment area for the fast zone.

- names:

  Names of the two zones.

## Value

`two_zone_config()`: a multi-zone configuration for
[`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md).

## Details

**Configuration.** A multi-zone configuration has `area_km2` and `dt`
for the whole catchment, optionally one rainfall factor `fc` for every
zone, and a named list `zones`, each a single-zone configuration without
`area_km2` or `dt` (nor `fc`, when it is given at the top). Every zone
after the first has a `share`, its fraction of the catchment area; the
first zone takes the rest. Parameters are addressed as
`zones.<name>.<path>`, such as `zones.fast.share` or
`zones.main.surface.k1`.

**The fast zone.** `two_zone_config()` adds a zone for the spike to a
single-zone configuration, with every parameter set and most of them
locked:

|             |                                                                         |                     |
|-------------|-------------------------------------------------------------------------|---------------------|
| Parameter   | Value                                                                   | Searched            |
| `share`     | 0.1 of the area                                                         | 0.01 to 0.3         |
| soil store  | Pareto, `cmax` 20 mm, `b` 0.5                                           | `cmax`, 1 to 100 mm |
| recharge    | split, `alpha` 1: all direct runoff to the surface, none to groundwater | no                  |
| surface     | one linear store, `kb` 1 h                                              | `kb`, 0.25 to 12 h  |
| groundwater | linear, `kb` 1000 h, never fed                                          | no                  |
| `td`        | 0 h                                                                     | 0 to 6 h            |
| `be`        | the main zone's                                                         | no                  |

**The rain adds up.** Every zone reads the same rain and evaporation
depths, and the zone areas add up to the catchment's, so the rain volume
over the zones is the catchment's. The rainfall factor `fc` is set once,
at the top, for every zone (locked at 1 by default, as for one zone);
unlocked with `overrides = list(fc = ...)`, it scales the rain on every
zone together.

The fast zone only ever makes quick runoff, so it cannot trade baseflow
with the main zone, which keeps the two zones' roles apart.
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
gives the main zone its usual bounds and the fast zone the four above;
bounds or exclusions given without a `zones.` prefix apply to the first
zone.

**Running.**
[`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md)
runs each zone with its own state and adds the flows; depth columns
(rain, storage, balance) are area-weighted means over the zones. A start
from flow puts the whole observed flow on the first zone and starts the
others with their soil at `soil_fraction` and their routing stores
empty. Forecast updating, hindcasts, the events workbench and PDM for
PCs files are for single-zone models.

## References

Moore, R.J. (2007). The PDM rainfall-runoff model. Hydrology and Earth
System Sciences, 11(1), 483-499. UKCEH (2022). PDM for PCs, version
3.0.3: Configuration Guide, section 5.

## Examples

``` r
cfg <- pdm_presets("standard")
cfg$area_km2 <- 36.7
two <- two_zone_config(cfg)
model <- pdm_from_config(two)
calibration_bounds(two)[, c("path", "lower", "upper")]
#>                            path  lower   upper
#> 1  zones.main.distribution.cmax  20.00 8.0e+02
#> 2     zones.main.distribution.b   0.05 2.0e+00
#> 3        zones.main.recharge.kg   1.00 5.0e+03
#> 4         zones.main.surface.k1   0.50 7.2e+01
#> 5         zones.main.surface.k2   0.50 7.2e+01
#> 6     zones.main.groundwater.kb 100.00 1.0e+06
#> 7              zones.fast.share   0.01 3.0e-01
#> 8  zones.fast.distribution.cmax   1.00 1.0e+02
#> 9         zones.fast.surface.kb   0.25 1.2e+01
#> 10                zones.fast.td   0.00 6.0e+00
```
