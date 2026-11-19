# Score a Pareto front on another period

Scores every set on the front of
[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md)
on rows the search never saw, by the same losses, events rule and start.
A trade-off that holds on those rows is one to trust; a set that was
good only on the calibration rows is not. `plot(x, "validation")` then
sets each set's calibration loss against its loss on the new rows.

## Usage

``` r
pareto_validate(x, forcing, observed, rows)
```

## Arguments

- x:

  A `pdm_pareto` result.

- forcing, observed:

  The whole record: forcing and observed flow, from the same first row
  as the search's.

- rows:

  The rows to score.

## Value

`x`, with `validation`: one row per front set (`row`, its row in
`x$pareto`) and its losses on `rows` (`check_loss_*`); and
`validation_rows`, the first and last row scored.

## Details

The whole record is run, from the same start as the search, and only
`rows` are scored, so the period scored can follow straight on from the
calibration period. Events for the event losses are found afresh in
`rows`. In a calibration project, keep the registered validation window
for
[`validate_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md):
score the front on a check period cut from the end of the calibration
window instead (`check_share` of
[`log_pareto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)),
so that the validation window still judges a model chosen without it.

## See also

[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md),
[`plot.pdm_pareto()`](https://jonpayneea.github.io/PDMS7/reference/plot.pdm_pareto.md)

## Examples

``` r
# See calibrate_pdm_multi().
```
