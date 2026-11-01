# Calibrate many basins in one batch

Runs the same calibration protocol on every basin in a folder, giving
each basin its own calibration-log project, so every calibration is
recorded, can be reviewed, and is done exactly the same way. The batch
can be stopped at any time, by a crash, a power cut or on purpose, and
started again with the same call: each basin carries on from the last
step it completed. Steps already in a basin's log are never repeated, so
a finished basin passes through in moments; a step newly asked for, such
as the test, is added. Changing the protocol does not recalibrate a
basin that already has a calibration: its log keeps the calibration it
had.

## Usage

``` r
calibrate_batch(
  basins,
  output,
  structure = NULL,
  overrides = NULL,
  exclude = NULL,
  objective = c("nse", "rmse", "log_rmse"),
  starts = 10L,
  seed = 1,
  control = list(maxit = 200),
  method = c("lbfgsb", "nelder_mead"),
  test = FALSE,
  cores = 1L,
  only = NULL,
  owner = "Not recorded",
  steward = "Not recorded",
  purpose = "Batch calibration"
)

batch_status(output)

batch_results(output)
```

## Arguments

- basins:

  Folder holding one subfolder per basin.

- output:

  Folder for the projects and the status file; created if needed.

- structure:

  Default configuration (a list or YAML path) for basins whose
  `basin.yml` names none; the standard PDM if `NULL`. The basin's area
  is always applied.

- overrides, exclude:

  Passed to
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md).

- objective, starts, seed, control, method:

  Passed to
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).
  Search scales come from the bounds table.

- test:

  If `TRUE`, score each validated candidate once on its test window, if
  it has one. Use it when the protocol is final; the test window is
  scored only once.

- cores:

  Number of basins to run at once, in parallel worker processes.

- only:

  Optional basin identifiers to run, for example to retry failures.

- owner, steward, purpose:

  Recorded in each new project.

## Value

`calibrate_batch()`: the batch status, invisibly, as from
`batch_status()`. `batch_status()`: a data.table with one row per basin:
`basin`, `state` (`queued`, `running`, `done` or `failed`), `step`
reached, `seconds` and `message`. `batch_results()`:
[`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
for every project, with the batch state.

## Details

**Input folder.** One subfolder per basin, named by its identifier,
holding:

- `forcing.csv`: columns `time` (ISO 8601, UTC), `rain` and `pet` in mm
  per interval;

- `flow.csv`: column `q_m3s` (and optionally `time`), aligned with the
  forcing;

- `basin.yml`: `area_km2` and `calibration` (start and end) are
  required; `catchment`, `gauge`, `validation`, `test`, `config` (a YAML
  configuration file in the folder), `headline`, `thresholds` (a list of
  `name`, `value`, `unit`) and `rating` (a CSV in the folder) are
  optional.

**Steps for each basin**, each written to its project as it completes:
start the project, register the data, select the structure, run the
automatic calibration, propose the best result as candidate, validate
it, and, with `test = TRUE`, test it once on the test window.

**Progress.** `batch-status.csv` in the output folder gets a row
whenever a basin starts, finishes or fails; `batch_status()` summarises
it while the batch runs. A failure is recorded with its reason and the
batch moves on; fix the cause and run the same call again.

**Seeds.** Each basin's random starts are seeded from `seed` and the
basin's name, so a basin's result does not change when others are added
or removed.

## See also

[calibration_log](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md),
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
