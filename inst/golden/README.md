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
| `cases.csv` | One row per case: `case`, then the 38 fields of `pdm_params` in header order. Route fields are prefixed `surface.` or `groundwater.` |
| `<case>_initial_state.csv` | Column `value`: the state array passed to `pdm_run()` |
| `<case>_fluxes.csv` | The 24 flux columns, named and ordered as `pdm_flux_name(0..23)` |
| `<case>_final_state.csv` | Column `value`: the state array after the run |
| `invalid_cases.csv` | Parameter sets that must fail, with `expected_code` 1 (`PDM_ERR_ARGUMENT`) |
| `generate_golden.R` | Regenerates every file from the R reference |

All numbers are written with 17 significant digits, so they round-trip exactly to doubles.
There are no infinities or missing values.

The 18 cases cover the default model, the Smith solver, a 15-minute step with a fractional
delay, a daily step, unusual parameters with near-equal cascade constants, linear and
quadratic groundwater, a point-mass capacity distribution and a non-default initial state.
They also cover the rectangular and exponential distributions, split recharge, demand
recharge with power and exponential groundwater, exponential stores starting from negative
storage, power-law and Smith surface stores, and a cascade as the groundwater route. The forcing
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
