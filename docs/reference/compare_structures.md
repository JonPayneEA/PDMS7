# Compare model structures

Calibrates several model structures in exactly the same way and ranks
them by their headline score on the validation window, which no
calibration saw. Each structure is logged as an ordinary
`structure_selected` entry and an `auto_calibration` entry, linked by a
shared comparison id, so the comparison is part of the audit trail and
`structure_comparison()` can rebuild the ranking from the log at any
time.

## Usage

``` r
compare_structures(
  project,
  structures = NULL,
  overrides = NULL,
  exclude = NULL,
  objective = c("nse", "rmse", "log_rmse"),
  starts = 3L,
  seed = 1,
  control = list(maxit = 200),
  method = c("lbfgsb", "nelder_mead"),
  cores = 1L,
  cross_validate = FALSE,
  reasoning
)

structure_comparison(project, comparison = NULL)
```

## Arguments

- project:

  Path of a calibration project with registered data and a validation
  window.

- structures:

  Named list of configurations; by default
  [`structure_set()`](https://jonpayneea.github.io/PDMS7/reference/structure_set.md),
  built on the project's latest structure if there is one. Each is given
  the project's area.

- overrides, exclude:

  Passed to
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
  for every structure.

- objective, starts, seed, control, method:

  Passed to
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

- cores:

  Number of parallel worker processes; 1 runs in this session.

- cross_validate:

  If `TRUE`, also calibrate on the validation window and score on the
  calibration window.

- reasoning:

  Why the comparison is being run.

- comparison:

  A comparison id; by default the latest comparison in the project.

## Value

`compare_structures()` and `structure_comparison()`: a data.table ranked
best first, with `rank`, `structure`, `parameters`, `calibration` and
`validation` (headline scores), `change` (validation minus calibration),
`cross_validated` when requested, `evaluations`, `starts_agree`, and the
two entry ids.

## Details

Every structure gets the bounds from
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
for its components, with log-scale search where the table says so, and
the same objective, starts, seed and iteration limit. A structure with
more parameters nearly always fits the calibration window better; the
ranking uses the validation window instead, and the table shows how much
each structure's score changes between the two. A large drop is the mark
of a structure buying its fit with parameters.

With `cross_validate = TRUE`, each structure is also calibrated on the
validation window and scored on the calibration window, and ranked on
the mean of the two held-out scores. This is more robust for short
records, and doubles the cost.

Choosing a structure on the validation window uses that window; the
optional test window of
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
scored once by
[`test_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
then gives an untouched final check.

## See also

[`structure_set()`](https://jonpayneea.github.io/PDMS7/reference/structure_set.md),
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md),
[calibration_log](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
