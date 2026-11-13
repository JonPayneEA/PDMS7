# The PDM groundwater extension

Extends a linear, quadratic or cubic groundwater store as in the
extended PDM of Moore and Bell (2002) and the PDM for PCs scientific
guide (UKCEH, 2022, section 3 and Appendix B), for catchments with
pumped abstractions, ephemeral streams and losses below or beyond the
gauge.

## Usage

``` r
groundwater_extension(
  store,
  ku = Inf,
  dbu = 0,
  alpha_b = 0,
  ca = 0,
  fa = 1,
  smax_b = 0,
  ys = 0,
  hw = 0
)

FlodeExtendedGroundwater(
  store = FlodePowerRouting(),
  ku = integer(0),
  dbu = integer(0),
  alpha_b = integer(0),
  ca = integer(0),
  fa = integer(0),
  smax_b = integer(0),
  ys = integer(0),
  hw = integer(0)
)
```

## Arguments

- store:

  A linear, quadratic or cubic groundwater store, from
  [`linear_routing()`](https://jonpayneea.github.io/PDMS7/reference/linear_routing.md),
  [`quadratic_routing()`](https://jonpayneea.github.io/PDMS7/reference/quadratic_routing.md),
  [`cubic_routing()`](https://jonpayneea.github.io/PDMS7/reference/cubic_routing.md)
  or
  [`power_routing()`](https://jonpayneea.github.io/PDMS7/reference/power_routing.md)
  with `m` 1, 2 or 3.

- ku:

  Underflow time constant, h; `Inf` (the default) for no underflow.

- dbu:

  Baseflow-underflow deficit, mm: how far below the baseflow outlet the
  underflow outlet lies.

- alpha_b:

  Fraction of the store's outflow lost to springs outside the catchment;
  negative for an import. At most 1.

- ca:

  Constant abstraction, mm/h.

- fa:

  Factor on the recorded abstraction.

- smax_b:

  Maximum groundwater storage, mm, for the deficit and well level.

- ys:

  Well factor, m of water-table depth per mm of storage deficit (PDM for
  PCs `wellfac`): `1 / (1000 Sy)` for a specific yield `Sy`; 0 (the
  default) for no well level.

- hw:

  Well level datum: the height of the ground at the well, m.

## Value

A `FlodeExtendedGroundwater` store.

## Details

**Abstraction and negative storage.** The input to the store is recharge
less abstraction, `u = d - A`, with `A = cA + fA Ar` where `Ar` is the
recorded abstraction (Eq. 9). A negative input drains the store, and
when it empties flow at the outlet stops: the time to cessation within
the step, `T'`, is exact for each store (Eqs. B.1, B.3 and B.5), and the
storage at the end of that step is `u (dt - T')` (Eqs. B.2, B.4 and
B.6). Below zero the storage changes by continuity alone, with no
outflow, until recharge refills it and flow starts again for the rest of
that step.

**Underflow** leaves through a lower outlet below the gauge, linearly in
the water above it: `qu = (S + Dbu) / ku` while `S > -Dbu` (Eq. 10, with
`Dbu = Du - Sbmax`, the baseflow-underflow deficit). Neither source
states how underflow is integrated within a step. Here the store and
both its outlets are integrated together,
`dS/dt = u - k max(S, 0)^m - qu`, by RK4 with step doubling to the
store's tolerances (`rtol`, `atol`), whatever its solver. Each outlet
stops at its own threshold within the step, so neither draws the store
below it, and the two share the water as the continuous equation does.
(Before 0.26.0 the underflow was held at its start-of-step rate, which
over a long step could drain the store well below its outlets.)

**External springs.** A fraction `alpha_b` of the store's outflow leaves
the catchment as springs and the rest is baseflow at the outlet. A
negative fraction brings water in: an inter-catchment exchange
(scientific guide, section 4). The import is then `-alpha_b` times the
store's release: the baseflow exceeds the release, the spring column is
negative, and the water balance counts it as a gain. `alpha_b` must lie
below 1; there is no lower limit in the model, and calibration searches
-1 to 0.9 unless told otherwise.

**Well level.** The storage deficit is `D = Sbmax - S` (Eq. 8), in mm,
and the depth to the water table `W = Ys D` (Eq. 11), in m, so `Ys` is
metres of water table per mm of deficit: `1 / (1000 Sy)` for an aquifer
of specific yield `Sy` (0.02 for a specific yield of 5%). With the datum
`hw`, the height of the ground at the well (m), the modelled well level
is `hw - W`, in m.
[`fit_well_level()`](https://jonpayneea.github.io/PDMS7/reference/fit_well_level.md)
fits `Ys` and `hw` to an observed well. (Before 0.27.0 the depth was
divided by a further 1000, so modelled well levels barely moved.)

The exponential store cannot be extended: it needs positive flow at all
times, so it cannot run dry (scientific guide, Appendices A and B).

**Negative input.** When abstraction exceeds recharge, the linear and
quadratic stores cease flowing and drain by the exact published
solutions (Eqs. B.1 to B.4). The cubic store follows its solver: with
`solver = "smith"`, Smith's method as published (Eqs. 4, 6 and 7); with
the adaptive solver, the continuous equation integrated to the store's
tolerances, through the moment flow ceases and on into deficit by
continuity. (Before 0.26.0 the adaptive cubic store switched to Smith's
method whenever its input was negative.) Below zero there is no outflow
and the store changes by continuity until it refills, then routes by its
own solver for the rest of the step.

Models with the extension run in the compiled engine, like the standard
model, and give the same results as the step-by-step R loop. Starting
from a flow
([`initial_state_from_flow()`](https://jonpayneea.github.io/PDMS7/reference/initial_state_from_flow.md))
and state correction use the R loop. Abstraction enters as a forcing
column `abstraction`, mm per step over the catchment.

## References

Moore, R.J. and Bell, V.A. (2002). Incorporation of groundwater losses
and well level data in rainfall-runoff models illustrated using the PDM.
Hydrology and Earth System Sciences, 6(1), 25-38. UKCEH (2022). A Guide
to the PDM Rainfall-Runoff Model, in PDM for PCs, version 3.0.3.

## Examples

``` r
store <- groundwater_extension(cubic_routing(5000), ku = 12000, dbu = 400, ca = 0.002,
                               smax_b = 1600, ys = 0.02, hw = 84)
cfg <- pdm_presets("standard")
cfg$groundwater$extension <- list(ku = 12000, dbu = 400, ca = 0.002)
model <- pdm_from_config(cfg)
```
