# Recommend a model structure

Chooses one component at a time, the way a hydrologist would, each by a
structure comparison
([`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md))
on the project's own data, and writes down why.

## Usage

``` r
recommend_structure(
  project,
  components = c("recharge", "distribution", "groundwater"),
  tolerance = NULL,
  n_events = 10L,
  starts = 2L,
  seed = 1,
  control = list(maxit = 100),
  method = "lbfgsb",
  cores = 1L,
  reasoning,
  note = TRUE
)
```

## Arguments

- project:

  A calibration project with registered calibration and validation
  windows.

- components:

  Components to choose, in order, among `recharge`, `distribution` and
  `groundwater`.

- tolerance:

  Width of the band of equally good scores; by default the project's tie
  tolerance (0.02 unless registered otherwise).

- n_events:

  Largest validation events used to break ties.

- starts, seed, control, method, cores:

  Passed to
  [`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md).

- reasoning:

  Why the recommendation is being made; recorded with every comparison.

- note:

  Write each step's choice and reason to the log as a note.

## Value

A list of class `pdm_structure_recommendation`: `configuration` (the
recommended, calibrated structure), `entry` (its calibration entry) and
`steps`, one per component, each with the `table` of the comparison
(with `at_bound`, `equally_good` and `median_abs_peak_error`), the
`choice` and the `reason`.

## Details

**The order** follows what the record can tell apart. On made-up
catchments (see the calibration study article) the recharge rule was
identified every time, by wide margins; the groundwater store only by
margins too small to trust. So the recharge rule comes first, then the
soil store distribution, then the groundwater store, each step starting
from the calibrated structure the step before chose.

**Each choice** follows the same rule:

1.  A structure that ended with a parameter at a bound of its search
    range is set aside: it is being bent to fit, not describing the
    catchment. If every structure did, none is set aside.

2.  The rest are ranked by their headline score on the validation
    window, which no calibration saw. Every structure within `tolerance`
    of the best counts as equally good.

3.  If the structure the step started from is among the equally good, it
    is kept: the record cannot justify a change.

4.  Otherwise, among the equally good, the one with the smallest median
    peak error on the largest validation events wins
    ([`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)),
    then the one with fewer parameters.

Every comparison is logged in the project as usual, and each step's
choice and reason is written as a note, so the recommendation is part of
the audit trail.

## See also

[`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md),
[`structure_set()`](https://jonpayneea.github.io/PDMS7/reference/structure_set.md),
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)

## Examples

``` r
if (FALSE) { # \dontrun{
rec <- recommend_structure("projects/beggearn_huish", reasoning = "First structure choice.")
rec
rec$steps$recharge$table
} # }
```
