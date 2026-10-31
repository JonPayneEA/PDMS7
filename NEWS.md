# pdmS7 (development version)

- `calibrate_pdm()` gains opt-in multi-start calibration through `starts` and `seed`.
  Start 1 is the configured point; extra starts are drawn uniformly inside the bounds, all
  are optimised, and the best objective is returned. The result gains `start_results`, a
  table of per-start objective, convergence code, evaluation count and fitted parameters.
  The default `starts = 1L` runs the same single optimisation as earlier versions.
- `run_pdm()`, and so `sim_pdm()` and `calibrate_pdm()`, now run a compiled time loop for
  Pareto capacity, standard recharge, cascade surface routing and power-law groundwater
  routing (the default configuration). It is about 430 times faster. Output agrees with the
  R loop to rounding: bit-identical on R 4.3, with last-place differences on R 4.5 and later,
  where calibrated parameters can differ from earlier versions by about 1e-13 relative.
  Other models use the R loop as before. `options(pdmS7.engine = "r")` forces the R loop,
  which remains the reference implementation. Building from source now needs a
  C++ compiler (Rtools on Windows); cpp11 is a build-time dependency only.
- Added `inst/benchmarks/time_solvers.R` and a report at `docs/benchmarks/solver-timing.md`
  timing both solvers and both engines on daily and 15-minute series.
- `pdm_model()` (and so `pdm_from_config()` and `sim_pdm()`) warns, once per session, when the
  Smith cubic solver is used with a step above 1 hour. Its error grows with the square of the
  step and reaches 60 to 100 per cent of peak flow at a daily step. Results are unchanged; the
  default adaptive solver is unaffected. `inst/benchmarks/smith_step_error.R` reproduces the
  evidence.
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
