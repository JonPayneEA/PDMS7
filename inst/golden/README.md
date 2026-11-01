# Golden test files for the PDM core

These files define what a correct binding of the PDM core must produce. Any language that
calls `src/pdm_core.h` (R, Python, Scala, Julia or C) should load them, run every case and
pass the tolerance rule below. If it does, it is running the same model as the R reference.

The expected values come from the R reference loop (`options(pdmS7.engine = "r")`), not from
the compiled core, so the files test the core as well as the bindings.

## Files

| File | Content |
|---|---|
| `forcing.csv` | `rain_mm`, `pet_mm`: 150 steps shared by every case, in mm per interval |
| `cases.csv` | One row per case: `case`, then the 40 fields of `pdm_params` in header order. Route fields are prefixed `surface.` or `groundwater.` |
| `<case>_initial_state.csv` | Column `value`: the state array passed to `pdm_run()` |
| `<case>_fluxes.csv` | The 24 flux columns, named and ordered as `pdm_flux_name(0..23)` |
| `<case>_final_state.csv` | Column `value`: the state array after the run |
| `invalid_cases.csv` | Parameter sets that must fail, with `expected_code` 1 (`PDM_ERR_ARGUMENT`) |
| `pack_forcing.csv` | `precipitation_mm`, `temperature_c`, `pet_mm`: 150 intervals for the snow cases |
| `pack_cases.csv` | One row per PACK case: `case`, the 12 fields of `pdm_pack_params`, and `dt` in hours |
| `<case>_pack_initial_state.csv`, `<case>_pack_final_state.csv` | The 5 PACK state values before and after |
| `<case>_pack_fluxes.csv` | The 11 PACK flux columns, named and ordered as `pdm_pack_flux_name(0..10)` |
| `pack_invalid_cases.csv` | PACK parameter sets that must fail |
| `snow_cases.csv` | Coupled runs: `case`, the PACK case and the PDM case whose parameters and initial states to use |
| `<case>_fluxes.csv`, `<case>_final_state.csv`, `<case>_pack_final_state.csv` for each coupled case | PDM fluxes and both final states from `pdm_snow_run()` |
| `correction_cases.csv` | State corrections: the PDM case whose final state is corrected, the `pdm_state_updater` fields, `observed_m3s` and `expected_code` |
| `correction_expected.csv`, `<case>_corrected_state.csv` | The `pdm_correction` results and the corrected state |
| `arma_history.csv`, `arma_forecast.csv` | Observed and simulated history, and the forecast to update |
| `arma_cases.csv` | ARMA cases: `scale` (0 additive, 1 log), `offset`, `p`, `q`, and coefficients `ar1`-`ar3`, `ma1`-`ma2` (only the first p and q are used) |
| `<case>_arma.csv`, `<case>_arma_innovations.csv` | The updated forecast, the error forecast and the innovations |
| `flow_cases.csv` | Steady-state starts: the PDM case, `observed_m3s`, `baseflow_fraction`, `soil_fraction` and `expected_code` |
| `<case>_flow_state.csv` | The state from `pdm_state_from_flow()` |
| `generate_golden.R` | Regenerates every file from the R reference |

All numbers are written with 17 significant digits, so they round-trip exactly to doubles.
There are no infinities or missing values.

The 21 cases cover the default model, the Smith solver, a 15-minute step with a fractional
delay, a daily step, unusual parameters with near-equal cascade constants, linear and
quadratic groundwater, a point-mass capacity distribution and a non-default initial state.
They also cover the rectangular and exponential distributions, split recharge, demand
recharge with power and exponential groundwater, exponential stores starting from negative
storage, power-law and Smith surface stores, a cascade as the groundwater route, the
triangular and lognormal distributions, and a rectangular store filled exactly to capacity. The forcing
includes dry spells and two storms that saturate the soil store.

## Tolerance rule

For each output column, and for the final state, a binding passes if

```
max |got - expected| <= 1e-12 * max(1, max |expected|)
```

Exact equality is not required. R 4.5 and later round `sum()` and `^` slightly differently
from R 4.3, and compilers may differ in the last place; 1e-12 allows for that and nothing more.

For each row of `invalid_cases.csv`, `pdm_run()` must return the expected code, write a
non-empty message, and leave the state array unchanged.

## Checking

- **R:** `tests/testthat/test-golden.R` checks both R engines on every case.
- **C, with no R:** `tools/core/check_golden.c`; see `tools/core/README.md`.

## Regenerating

Only when the model equations change:

```
Rscript inst/golden/generate_golden.R
```

Review the diff before committing. Changed expected values mean changed model results, and
every binding must then be rechecked.
