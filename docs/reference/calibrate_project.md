# Calibrate a catchment from start to finish in one call

Runs the whole logged calibration of [Calibrating a catchment from start
to
finish](https://jonpayneea.github.io/PDMS7/articles/calibration-journey.html)
for one set of prepared data:
[`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`select_structure()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`recommend_structure()`](https://jonpayneea.github.io/PDMS7/reference/recommend_structure.md)
when `recommend = TRUE`,
[`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md),
[`propose_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
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
  recommend = FALSE,
  overrides = NULL,
  exclude = NULL,
  cores = 1L,
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
  zones = 1,
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
  `forcing`. With `recommend = TRUE`, the structure the recommendation
  starts from.

- stages:

  Stages from
  [`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md),
  or a function of the configuration that returns them; by default
  `pdm_stages(structure, overrides, exclude)`.

- bounds:

  Search ranges from
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md),
  or a function of the configuration that returns them; by default
  `calibration_bounds(structure, overrides, exclude)`.

- recommend:

  Choose the recharge rule, soil store distribution and groundwater
  store with
  [`recommend_structure()`](https://jonpayneea.github.io/PDMS7/reference/recommend_structure.md)
  before the stages.

- overrides, exclude:

  Passed to
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
  for the default stages and bounds and, with `recommend = TRUE`, for
  every structure compared.

- cores:

  Cores for the structure comparisons, with `recommend = TRUE`, and for
  the starts of every search, which run side by side with the same
  results (see
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)).

- starts, seed, control, method:

  Passed to
  [`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)
  and, with `recommend = TRUE`, to
  [`recommend_structure()`](https://jonpayneea.github.io/PDMS7/reference/recommend_structure.md).

- catchment, gauge, purpose, owner, steward:

  Passed to
  [`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md);
  the owner and steward default to the user declared.

- report:

  If `TRUE`, build the report with
  [`build_report()`](https://jonpayneea.github.io/PDMS7/reference/build_report.md)
  at the end.

- zones:

  `1` (one zone), `2` (always two: a fast zone added), or `c(1, 2)` to
  compare them as a last structure step, with `recommend = TRUE`.

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

**Zones.** `zones = c(1, 2)` with `recommend = TRUE` adds a last
structure step comparing one zone with two, a fast zone added for a
flashy part of the response
([`two_zone_config()`](https://jonpayneea.github.io/PDMS7/reference/two_zone_config.md));
two zones are kept only if better on validation by more than the tie
tolerance. `zones = 2` gives the structure a fast zone without a
comparison. The default, 1, keeps one zone.

**Choosing the candidate.** The candidate is the last stage, unless
another fit in hand scores better on the calibration headline by more
than the project's tie tolerance (0.02 for NSE): an earlier stage, or,
with `recommend = TRUE`, the structure comparison's fit of the chosen
structure. A final events stage trades a little of the headline for the
floods, and a loss within the tolerance keeps it; a larger loss means
the stages ended worse than a fit already found, which is proposed
instead, with the reason recorded.

**Choosing the structure.** With `recommend = TRUE`, `structure` is only
the starting point.
[`recommend_structure()`](https://jonpayneea.github.io/PDMS7/reference/recommend_structure.md)
then chooses the recharge rule, the soil store distribution and the
groundwater store in turn, each by a structure comparison on this
record, and the stages start from the calibration of the structure it
recommends. Each comparison and each choice, with its reason, is in the
log. It needs a validation window, since the choice is made on
validation scores, and it costs one calibration per option compared:
twelve in all. The stages then need to suit whichever structure is
chosen, so give `stages` and `bounds` as functions of a configuration,
such as `function(config) pdm_stages(config, events = TRUE)`, or leave
them `NULL`.

**Test years need a validation window.** The test scores a validated
candidate, so a record with test years, or long enough for the wettest
years to be held back (the default), needs a validation window. Without
one the call stops after registering the data and before the search;
give `validation`, or `wettest_years = 0`.

**Progress.** A calibration of a long record takes hours, so it reports
as it goes: the plan at the start, each structure step and calibration
stage as it begins, each structure's scores and time when its comparison
ends, with the time left for the rest at that pace, and, every minute or
so during a search, the model runs made so far and the time each takes.
Comparisons run on several cores (`cores > 1`) cannot write to this
console, so each structure's progress goes to `progress.log` in the
project folder; open it to follow them.
`options(pdmS7.progress_every = 0)` turns the minute-by-minute lines
off, and any number sets their interval in seconds.

**Existing projects.** A project that already has a candidate keeps it:
a rerun only does whichever of the validation, the test and (with
`report = TRUE`) the report are still missing, so a run that stopped
after proposing the candidate can be finished, and a report added later.
Delete the folder to calibrate again. A project without a candidate,
from a run that stopped earlier, is renamed
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
# Choose the structure on this record first, then run the stages on it
calibrate_project("projects/beggearn_huish", forcing, flow, area_km2 = 36.7,
                  calibration = c("2010-10-01", "2019-09-30 23:45"),
                  validation = c("2019-10-01", "2025-06-30 23:45"), recommend = TRUE,
                  stages = function(config) pdm_stages(config, events = TRUE))
} # }
```
