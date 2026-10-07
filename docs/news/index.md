# Changelog

## pdmS7 0.3.1

- Added three executable vignettes: PDM equations and functions, PACK
  snow accounting and defaults, and a synthetic
  calibration/validation/restart workflow.
- Added reproducible process diagrams, soil/cover curves and workflow
  hydrographs.
- No changes to the numerical model APIs or equations.

## pdmS7 0.3.0

- Added optional PACK S7 snow components, conservative substep
  accounting, areal depletion, fresh-snow memory and coupled PDM
  restart.
- Added the image parameter preset (explicit hourly-unit assumption) and
  a distinct report-typical preset, with full parameter mapping and
  source notes.
- Added multi-objective metrics, weighted multi-start calibration,
  evaluated Pareto trade-offs, configurable scales and joint snow/PDM
  parameter paths.
- Documented river networks and additional state assimilation as future
  work.

## pdmS7 0.2.0

### Flode Tier 3 engineering target

- Introduced `Flode`-prefixed S7 classes with existing class names
  retained as aliases.
- Added
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
  with explicit depth units, integer minute steps, data.table output,
  UTC timestamps, and warm-up flags.
- Added safe YAML loading and an illustrative configuration file.
- Replaced CSV input with `fread()` and tabular assembly with
  `rbindlist()`.
- Added state-object validation and structured debug logging.
- Converted numerical regression checks to testthat and added interface
  tests.
- Added roxygen source documentation, renv, lintr, and pinned shared
  Flode CI.
- Retained the earlier simulation functions and output column names for
  compatibility.

This release targets the Tier 3 technical checks. It is not formally
approved for operations: human maintainer attribution, independent
review, and catchment validation remain required. Version 0.1.0
serialized S7 objects should be rebuilt from their saved configuration
because the canonical class names have changed.
