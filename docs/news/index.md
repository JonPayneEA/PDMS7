# Changelog

## pdmS7 (development version)

- New article, “Logging a manual calibration”: a complete project from
  start to sign-off, integrity checks and tampering, the report, and
  tracing operational runs with the run log.
- New
  [`calibration_app()`](https://jonpayneea.github.io/PDMS7/reference/calibration_app.md):
  a Shiny app over the calibration log for staff who prefer not to
  script. Setup (start, register data, select structure), Trial (adjust
  parameters, preview the hydrograph and scorecard against the parent,
  save with a verdict and reasoning; notes; automatic calibration),
  History (path, every run, compare two runs, propose and validate a
  candidate), Report (integrity, build and download) and Sign-off. Every
  button calls the exported function a script would, so the same rules
  apply. shiny is a suggested package, needed only for the app.
- New opt-in run log. With `options(pdmS7.run_log = "runs.csv")` or
  `PDMS7_RUN_LOG` set, every
  [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md)
  call, and so
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
  and
  [`sim_snow_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_snow_pdm.md),
  appends one row: who, when, an optional tag, the model’s
  [`pdm_fingerprint()`](https://jonpayneea.github.io/PDMS7/reference/pdm_fingerprint.md),
  a checksum of the forcing, period, versions, run time, and success or
  the error message. Calibration evaluations, spin-up cycles and the
  calibration log’s own reruns are not logged. With a register of
  calibration projects set (`pdmS7.register` or `PDMS7_REGISTER`), each
  run is marked `approved`, `superseded` (its project was reopened) or
  `unapproved`; runs are never blocked. New
  [`read_run_log()`](https://jonpayneea.github.io/PDMS7/reference/read_run_log.md),
  [`approved_configurations()`](https://jonpayneea.github.io/PDMS7/reference/approved_configurations.md)
  and
  [`pdm_fingerprint()`](https://jonpayneea.github.io/PDMS7/reference/pdm_fingerprint.md).
  Logging is off by default and a logging failure never stops a run.
- New calibration log: an append-only, tamper-evident record of a
  calibration project.
  [`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`select_structure()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`log_trial()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`log_auto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`log_note()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`propose_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`validate_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`sign_off_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  and
  [`reopen_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  each write one YAML entry recording who, when, which data and
  parameters, the scores and the reasoning. Entries are chained by MD5,
  data are copied and checksummed, and every run records a checksum of
  its output.
  [`verify_project()`](https://jonpayneea.github.io/PDMS7/reference/verify_project.md)
  detects edits, gaps, changed data and runs that no longer reproduce. A
  Steward cannot sign off their own calibration.
  [`read_project()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md),
  [`project_trials()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  and
  [`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  read the record. Design: `calibration-log-design.md`.
- New
  [`build_report()`](https://jonpayneea.github.io/PDMS7/reference/build_report.md)
  writes a calibration report generated from the log: a self-contained
  HTML file with embedded figures, and a Markdown copy. It shows
  integrity status first, then data and scoring windows, model
  structure, the calibration path as a tree and a table, the candidate’s
  hydrographs, flow-duration curves and scorecard for both windows,
  parameter sensitivity on a shared scale, sign-off history, and the
  final configuration. It uses base graphics only.
- New
  [`pdm_scorecard()`](https://jonpayneea.github.io/PDMS7/reference/pdm_scorecard.md):
  NSE, log NSE, KGE and its components, RMSE, signed and absolute volume
  error, peak error, and the Yilmaz et al. (2008) flow-duration-curve
  signatures.
- Five new illustrated articles on the package website: choosing model
  components, starting states, calibration, forecast updating, and the C
  core. Articles, guides and the function reference are grouped by topic
  in the site navigation. DESCRIPTION gains `URL` and `BugReports`.
- [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  gains opt-in multi-start calibration through `starts` and `seed`.
  Start 1 is the configured point; extra starts are drawn uniformly
  inside the bounds, all are optimised, and the best objective is
  returned. The result gains `start_results`, a table of per-start
  objective, convergence code, evaluation count and fitted parameters.
  The default `starts = 1L` runs the same single optimisation as earlier
  versions.
- [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md),
  and so
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
  and
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md),
  now run a compiled time loop for every capacity distribution;
  standard, split and demand recharge; and cascade, power-law and
  exponential stores on either route. It is about 430 times faster.
  Output agrees with the R loop to rounding: bit-identical on R 4.3,
  with last-place differences on R 4.5 and later, where calibrated
  parameters can differ from earlier versions by about 1e-13 relative.
  `options(pdmS7.engine = "r")` forces the R loop, which remains the
  reference implementation. Building from source now needs a compiler
  (Rtools on Windows); cpp11 is a build-time dependency only.
- Added `inst/benchmarks/time_solvers.R` and a report at
  `docs/benchmarks/solver-timing.md` timing both solvers and both
  engines on daily and 15-minute series.
- [`pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/pdm_model.md)
  (and so
  [`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md)
  and
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md))
  warns, once per session, when the Smith cubic solver is used with a
  step above 1 hour. Its error grows with the square of the step and
  reaches 60 to 100 per cent of peak flow at a daily step. Results are
  unchanged; the default adaptive solver is unaffected.
  `inst/benchmarks/smith_step_error.R` reproduces the evidence.
- The compiled time loop now sits behind a language-neutral C interface
  (`src/pdm_core.h`, interface version 2), so other languages can call
  the same model code. `src/pdm_engine.cpp` is a thin R wrapper over it,
  and results are unchanged. The core validates its own inputs and
  leaves the caller’s state untouched on error. `tools/core/README.md`
  covers building it without R.
- Golden test files in `inst/golden/` hold inputs and expected outputs
  from the R reference, for checking any binding of the core.
  `tools/core/check_golden.c` checks them from plain C.
- The triangular capacity distribution is now inverted exactly (cube
  root or the trigonometric solution of a cubic) and the lognormal by
  safeguarded Newton iteration, in place of
  [`uniroot()`](https://rdrr.io/r/stats/uniroot.html) with a 1e-10
  tolerance. Storage round trips improve from about 2e-11 to 1e-14 mm;
  model outputs for these two distributions change by at most about
  3e-11.
- Fixed: the rectangular distribution’s
  [`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md)
  used (cmin + cmax) / 2 while its other methods used the Pareto b = 1
  form, which can differ in the last place. A soil store filled exactly
  to capacity could then fail with “Soil storage exceeds capacity_mean”.
  Both now use the Pareto form, so
  [`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md)
  can change in the last place.
- The PACK snowpack also runs in the compiled core, about 540 times
  faster than its R loop and bit-identical to it on R 4.3.
  [`sim_pack()`](https://jonpayneea.github.io/PDMS7/reference/sim_pack.md)
  and
  [`sim_snow_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_snow_pdm.md)
  use it automatically. The core gains `pdm_pack_run()` for snow alone
  and `pdm_snow_run()` for snow feeding PDM.
- New
  [`initial_state_from_flow()`](https://jonpayneea.github.io/PDMS7/reference/initial_state_from_flow.md):
  a warm start in steady state with the flow observed at the start of a
  run. Routing stores deliver their share of the flow, the soil store is
  set so that recharge equals baseflow, and delay queues hold the water
  in transit. It replaces an arbitrary soil fraction for short test runs
  and forecasts. Also in the core as `pdm_state_from_flow()`.
- Forecast updating also runs in the compiled core:
  [`correct_state()`](https://jonpayneea.github.io/PDMS7/reference/correct_state.md)
  (state correction, Moore 2007 Eq. 28-30) and
  [`update_forecast()`](https://jonpayneea.github.io/PDMS7/reference/update_forecast.md)
  (ARMA error prediction, Eq. 31-42), with `pdm_correct_state()` and
  `pdm_update_forecast()` for other languages. Results are bit-identical
  to the R code. Fitting the ARMA coefficients stays in R.
- The compiled core is now plain C99 (`src/pdm_core.c`), so other
  languages need only a C compiler to build it. Results are
  bit-identical to the previous C++ version.
- Fixed: the compiled engine rejected an initial state whose values were
  all stored as integers, for example one read with
  [`read.csv()`](https://rdrr.io/r/utils/read.table.html). The R loop
  accepted it.
- A peak timing objective is deferred.

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
