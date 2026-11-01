# Calibration log

A calibration project is a folder holding an append-only, tamper-evident
record of a calibration: who did what, when, with which data and
parameters, and why. Each function below writes one entry; none edits or
deletes an earlier one.

## Usage

``` r
start_calibration_project(
  path,
  catchment,
  gauge,
  purpose,
  area_km2,
  owner,
  steward,
  description = "",
  id = basename(path)
)

register_data(
  project,
  forcing,
  observed,
  calibration,
  validation = NULL,
  headline = "nse",
  log_offset = 0.01,
  soil_fraction = 0.5,
  copy = TRUE,
  reasoning = "",
  thresholds = NULL,
  rating = NULL,
  event_tolerance_h = 6,
  event_gap_h = 24,
  event_min_duration_h = 0,
  test = NULL
)

select_structure(project, configuration, reasoning)

preview_trial(project, parent, changes)

log_trial(project, parent, changes, verdict, reasoning)

log_auto_calibration(
  project,
  parent,
  lower,
  upper,
  objective = c("nse", "rmse", "log_rmse", "threshold"),
  starts = 1L,
  seed = NULL,
  control = list(maxit = 200),
  reasoning,
  method = c("lbfgsb", "nelder_mead"),
  threshold_objective = NULL,
  threshold_weight = 1,
  threshold_score = "csi",
  log_scale = character(0)
)

log_note(project, text, refers_to = NULL)

propose_candidate(project, entry, reasoning)

validate_candidate(project, reasoning)

test_candidate(project, reasoning)

sign_off_project(
  project,
  statement,
  checklist = c(integrity = FALSE, data = FALSE, calibration_path = FALSE, validation =
    FALSE)
)

reopen_project(project, reason)
```

## Arguments

- path:

  Folder to create for a new project; it must not exist or must be
  empty.

- catchment, gauge, purpose:

  Catchment name, gauge identifier (for example an NRFA station number)
  and the purpose of the calibration.

- area_km2:

  Catchment area, km2. Every configuration must use it.

- owner, steward:

  Names of the accountable Owner and the Steward expected to sign off.

- description:

  Optional free text.

- id:

  Project identifier; defaults to the folder name.

- project:

  Path of the project folder.

- forcing:

  Path of a CSV file, or a data frame, with `rain` and `pet` in mm per
  interval and an optional `time` column.

- observed:

  Path of a CSV file with a `q_m3s` column, a data frame, or a numeric
  vector of observed flow, m3/s, aligned with `forcing`. Missing values
  are allowed.

- calibration, validation, test:

  Scoring windows as `c(start, end)`: row numbers, or times when the
  forcing has a time column. Rows before the calibration window are
  warm-up. `validation` may be `NULL` until it is needed. `test` is an
  optional final window, scored once by `test_candidate()` after every
  choice is made, and by nothing else; the three windows must not
  overlap.

- headline:

  Score used to rank runs: one of `nse`, `log_nse`, `kge`, `rmse`,
  `log_rmse`, `abs_volume_error`, or a threshold score written as
  `metric:name`, such as `csi:Flood Warning`, where metric is `pod`,
  `far`, `csi`, `pod_step`, `far_step`, `csi_step`, `ets_step` or
  `pss_step`.

- log_offset:

  Offset added before logarithms, m3/s.

- soil_fraction:

  Initial soil store as a fraction of capacity for every run.

- copy:

  If `TRUE`, files are copied into the project; if `FALSE` they are
  referenced by path and MD5. Data frames and vectors are always written
  into the project.

- reasoning, statement, reason, text:

  Free text explaining the entry.

- thresholds:

  Optional data frame of thresholds with columns `name`, `value` and
  `unit`: `flow` (m3/s) or `level` (m, converted to flow through
  `rating`). Every run is then also scored with
  [`pdm_threshold_scores()`](https://jonpayneea.github.io/PDMS7/reference/pdm_threshold_scores.md),
  under names such as `csi:Flood Warning`.

- rating:

  Rating table for level thresholds: a CSV path or data frame with
  `stage_m` and `q_m3s`. Levels outside it are refused, not
  extrapolated. Stored like the data.

- event_tolerance_h, event_gap_h, event_min_duration_h:

  Event matching settings in hours; see
  [`pdm_threshold_scores()`](https://jonpayneea.github.io/PDMS7/reference/pdm_threshold_scores.md).

- configuration:

  A configuration list or the path of a YAML configuration file.

- parent:

  Id of the structure, trial or automatic calibration entry to start
  from.

- changes:

  Named numeric vector of new values, named by configuration path such
  as `surface.k1` or `fc`.

- verdict:

  Your judgement of the trial: `better`, `worse` or `inconclusive`.

- lower, upper, objective, starts, seed, control, method, log_scale:

  Passed to
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

- threshold_objective:

  Optional names of registered thresholds to include in the objective of
  an automatic calibration, with `method = "nelder_mead"`. Their flows
  and the registered event settings are used, so the calibration and the
  scorecard agree.

- threshold_weight, threshold_score:

  Weight and score of the threshold term; see
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

- refers_to:

  Optional id of the entry a note concerns.

- entry:

  Id of the structure, trial or automatic calibration proposed as
  candidate.

- checklist:

  Named logical vector confirming the Steward reviewed `integrity`,
  `data`, `calibration_path` and `validation`; all must be `TRUE`.

## Value

The new entry as a list, invisibly. `preview_trial()` writes nothing and
returns the configuration, scores and series of the proposed trial.

## Details

|                               |                      |                              |
|-------------------------------|----------------------|------------------------------|
| Function                      | Entry                | Role                         |
| `start_calibration_project()` | `project_start`      | Custodian                    |
| `register_data()`             | `data_registered`    | Custodian                    |
| `select_structure()`          | `structure_selected` | Custodian                    |
| `log_trial()`                 | `trial`              | Custodian                    |
| `log_auto_calibration()`      | `auto_calibration`   | Custodian                    |
| `log_note()`                  | `note`               | Any                          |
| `propose_candidate()`         | `candidate`          | Custodian                    |
| `validate_candidate()`        | `validation`         | Custodian                    |
| `test_candidate()`            | `test`               | Custodian                    |
| `sign_off_project()`          | `sign_off`           | Steward or Delegated Steward |
| `reopen_project()`            | `reopen`             | Steward or Delegated Steward |

Declare who you are once per session, with
`options(pdmS7.user = "Your Name", pdmS7.role = "custodian")`, or with
the environment variables `PDMS7_USER` and `PDMS7_ROLE`. Every entry
records the name, the role and the operating-system login. A Steward
cannot sign off a project in which they wrote a trial, automatic
calibration, candidate or validation.

Every run simulates the whole registered record from
`initial_state(model, soil_fraction)`. Trials and automatic calibrations
are scored on the calibration window only; the validation window is
scored once, by `validate_candidate()`, and an optional test window once
more, by `test_candidate()`, after every choice is made. See
[`pdm_scorecard()`](https://jonpayneea.github.io/PDMS7/reference/pdm_scorecard.md)
for the scores and
[`verify_project()`](https://jonpayneea.github.io/PDMS7/reference/verify_project.md)
for the integrity checks.

## Examples

``` r
folder <- file.path(tempdir(), "example-project")
old <- options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
start_calibration_project(folder, catchment = "Example", gauge = "00000",
  purpose = "Illustration", area_km2 = 50, owner = "Deputy Director",
  steward = "A Steward")
#> INFO [2026-11-01 19:06:41] Started calibration project example-project in /tmp/Rtmp00zeOE/example-project
set.seed(1)
forcing <- data.frame(rain = ifelse(runif(500) < 0.1, rexp(500, 0.3), 0), pet = 0.1)
truth <- pdm_presets("standard")
truth$area_km2 <- 50
observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s
register_data(folder, forcing, observed, calibration = c(101, 350),
  validation = c(351, 500))
#> INFO [2026-11-01 19:06:41] Registered data 0002: 500 rows
select_structure(folder, truth, reasoning = "Standard structure as a starting point")
#> Warning: Column name 'time' (colClasses[[1]][1]) not found
#> INFO [2026-11-01 19:06:41] Structure 0003: nse 1
log_trial(folder, parent = 3, changes = c(surface.k1 = 3), verdict = "worse",
  reasoning = "Testing a slower first store")
#> Warning: Column name 'time' (colClasses[[1]][1]) not found
#> INFO [2026-11-01 19:06:41] Trial 0004 from 0003: nse 0.9995
project_trials(folder)
#>        id               type parent            timestamp        author
#>    <char>             <char> <char>               <char>        <char>
#> 1:   0003 structure_selected   <NA> 2026-11-01T19:06:41Z A Hydrologist
#> 2:   0004              trial   0003 2026-11-01T19:06:41Z A Hydrologist
#>              changes verdict                              reasoning       nse
#>               <char>  <char>                                 <char>     <num>
#> 1:                      <NA> Standard structure as a starting point 1.0000000
#> 2: surface.k1 2 -> 3   worse           Testing a slower first store 0.9995394
#>      log_nse      kge     kge_r kge_alpha  kge_beta         rmse     log_rmse
#>        <num>    <num>     <num>     <num>     <num>        <num>        <num>
#> 1: 1.0000000 1.000000 1.0000000  1.000000 1.0000000 8.692858e-15 3.102895e-15
#> 2: 0.9996688 0.995417 0.9997812  1.004578 0.9999963 2.543155e-02 8.173054e-03
#>     volume_error abs_volume_error    peak_error      fdc_high      fdc_mid
#>            <num>            <num>         <num>         <num>        <num>
#> 1: -1.110223e-15     1.110223e-15 -6.439294e-15 -3.434900e-15  4.25082e-16
#> 2: -3.705089e-06     3.705089e-06  2.608090e-03  3.898185e-03 -1.49071e-03
#>          fdc_low
#>            <num>
#> 1: -9.649986e-15
#> 2:  5.571663e-04
options(old)
unlink(folder, recursive = TRUE)
```
