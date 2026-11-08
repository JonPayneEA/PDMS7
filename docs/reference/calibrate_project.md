# Calibrate a catchment from start to finish in one call

Runs the whole logged calibration of [Automatic calibration from start
to
finish](https://jonpayneea.github.io/PDMS7/articles/calibration-journey.html)
for one set of prepared data:
[`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`select_structure()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md),
[`propose_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
(the last stage),
[`validate_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
when a validation window is registered, and
[`test_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
when a test window or wettest years are. Each step is an entry in the
project's log, as if made by hand.

## Usage

``` r
calibrate_project(
  project,
  forcing,
  observed,
  area_km2,
  calibration,
  validation = NULL,
  structure = NULL,
  stages = NULL,
  bounds = NULL,
  starts = 2L,
  seed = 1L,
  control = list(maxit = 40L),
  method = "lbfgsb",
  catchment = basename(project),
  gauge = catchment,
  purpose = "PDM calibration",
  owner = NULL,
  steward = NULL,
  report = FALSE,
  ...
)
```

## Arguments

- project:

  Folder for the project; its name is the project id.

- forcing:

  Data frame of `time`, `rain` and `pet` (mm per step), prepared with
  [`align_series()`](https://jonpayneea.github.io/PDMS7/reference/align_series.md),
  [`convert_units()`](https://jonpayneea.github.io/PDMS7/reference/convert_units.md)
  and
  [`fill_gaps()`](https://jonpayneea.github.io/PDMS7/reference/fill_gaps.md)
  or otherwise.

- observed:

  Observed flow, m3/s, aligned with `forcing`.

- area_km2:

  Catchment area.

- calibration, validation:

  Windows, as for
  [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md).

- structure:

  Model configuration; by default the standard preset at the step of
  `forcing`.

- stages:

  Stages from
  [`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md);
  by default `pdm_stages(structure)`.

- bounds:

  Search ranges from
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md);
  by default the standard ones.

- starts, seed, control, method:

  Passed to
  [`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md).

- catchment, gauge, purpose, owner, steward:

  Passed to
  [`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md);
  the owner and steward default to the user declared.

- report:

  If `TRUE`, build the report with
  [`build_report()`](https://jonpayneea.github.io/PDMS7/reference/build_report.md)
  at the end.

- ...:

  Passed to
  [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  such as `wettest_years`, `thresholds`, `highest_gauged_m3s` or
  `reasoning`.

## Value

The project's row of
[`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md),
invisibly.

## Details

**Existing projects.** A project that already has a candidate is left as
it is, and its summary returned: delete the folder to calibrate again.
An unfinished one, from a run that stopped, is renamed
`<project>_unfinished_<time>` (its log kept) and the calibration starts
afresh.

Declare who you are first
(`options(pdmS7.user = ..., pdmS7.role = "custodian")`).

## See also

[`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
for many catchments laid out in folders.

## Examples

``` r
if (FALSE) { # \dontrun{
options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
calibrate_project("projects/beggearn_huish", forcing, flow, area_km2 = 36.7,
                  calibration = c("2010-10-01", "2019-09-30 23:45"),
                  validation = c("2019-10-01", "2025-06-30 23:45"),
                  stages = pdm_stages(structure, events = TRUE))
} # }
```
