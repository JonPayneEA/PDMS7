# pdmS7 (development version)

- `calibrate_pdm()` gains opt-in multi-start calibration through `starts` and `seed`.
  Start 1 is the configured point; extra starts are drawn uniformly inside the bounds, all
  are optimised, and the best objective is returned. The result gains `start_results`, a
  table of per-start objective, convergence code, evaluation count and fitted parameters.
  The default `starts = 1L` runs the same single optimisation as earlier versions.
- `run_pdm()`, and so `sim_pdm()` and `calibrate_pdm()`, now run a compiled time loop for
  every capacity distribution; standard, split and demand recharge; and cascade, power-law and
  exponential stores on either route. It is about 430 times
  faster. Output agrees with the
  R loop to rounding: bit-identical on R 4.3, with last-place differences on R 4.5 and later,
  where calibrated parameters can differ from earlier versions by about 1e-13 relative.
  `options(pdmS7.engine = "r")` forces the R loop, which remains the reference
  implementation. Building from source now needs a
  compiler (Rtools on Windows); cpp11 is a build-time dependency only.
- Added `inst/benchmarks/time_solvers.R` and a report at `docs/benchmarks/solver-timing.md`
  timing both solvers and both engines on daily and 15-minute series.
- `pdm_model()` (and so `pdm_from_config()` and `sim_pdm()`) warns, once per session, when the
  Smith cubic solver is used with a step above 1 hour. Its error grows with the square of the
  step and reaches 60 to 100 per cent of peak flow at a daily step. Results are unchanged; the
  default adaptive solver is unaffected. `inst/benchmarks/smith_step_error.R` reproduces the
  evidence.
- The compiled time loop now sits behind a language-neutral C interface (`src/pdm_core.h`,
  interface version 2), so other languages can call the same model code. `src/pdm_engine.cpp` is a thin R wrapper over
  it, and results are unchanged. The core validates its own inputs and leaves the caller's
  state untouched on error. `tools/core/README.md` covers building it without R.
- Golden test files in `inst/golden/` hold inputs and expected outputs from the R reference,
  for checking any binding of the core. `tools/core/check_golden.c` checks them from plain C.
- The triangular capacity distribution is now inverted exactly (cube root or the
  trigonometric solution of a cubic) and the lognormal by safeguarded Newton iteration, in
  place of `uniroot()` with a 1e-10 tolerance. Storage round trips improve from about 2e-11 to
  1e-14 mm; model outputs for these two distributions change by at most about 3e-11.
- Fixed: the rectangular distribution's `capacity_mean()` used (cmin + cmax) / 2 while its
  other methods used the Pareto b = 1 form, which can differ in the last place. A soil store
  filled exactly to capacity could then fail with "Soil storage exceeds capacity_mean". Both
  now use the Pareto form, so `capacity_mean()` can change in the last place.
- Fixed: the compiled engine rejected an initial state whose values were all stored as
  integers, for example one read with `read.csv()`. The R loop accepted it.
- A peak timing objective is deferred.

# pdmS7 0.3.1

- Added three executable vignettes: PDM equations and functions, PACK snow
  accounting and defaults, and a synthetic calibration/validation/restart workflow.
- Added reproducible process diagrams, soil/cover curves and workflow hydrographs.
- No changes to the numerical model APIs or equations.

# pdmS7 0.3.0

- Added optional PACK S7 snow components, conservative substep accounting,
  areal depletion, fresh-snow memory and coupled PDM restart.
- Added the image parameter preset (explicit hourly-unit assumption) and a
  distinct report-typical preset, with full parameter mapping and source notes.
- Added multi-objective metrics, weighted multi-start calibration, evaluated
  Pareto trade-offs, configurable scales and joint snow/PDM parameter paths.
- Documented river networks and additional state assimilation as future work.

# pdmS7 0.2.0

## Flode Tier 3 engineering target

- Introduced `Flode`-prefixed S7 classes with existing class names retained as aliases.
- Added `sim_pdm()` with explicit depth units, integer minute steps, data.table
  output, UTC timestamps, and warm-up flags.
- Added safe YAML loading and an illustrative configuration file.
- Replaced CSV input with `fread()` and tabular assembly with `rbindlist()`.
- Added state-object validation and structured debug logging.
- Converted numerical regression checks to testthat and added interface tests.
- Added roxygen source documentation, renv, lintr, and pinned shared Flode CI.
- Retained the earlier simulation functions and output column names for compatibility.

This release targets the Tier 3 technical checks. It is not formally approved
for operations: human maintainer attribution, independent review, and catchment
validation remain required. Version 0.1.0 serialized S7 objects should be rebuilt
from their saved configuration because the canonical class names have changed.
