# Plot a Pareto front

Three standard views of a front from
[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md):

## Usage

``` r
# S3 method for class 'pdm_pareto'
plot(
  x,
  type = .pareto_types,
  objectives = NULL,
  forcing = NULL,
  observed = NULL,
  window = NULL,
  ...
)

# S3 method for class 'pdm_pareto'
autoplot(
  object,
  type = .pareto_types,
  objectives = NULL,
  forcing = NULL,
  observed = NULL,
  window = NULL,
  ...
)
```

## Arguments

- x, object:

  A `pdm_pareto` result.

- type:

  One of the views above.

- objectives:

  For `pairs` and `parallel`, the objectives to show; by default all.

- forcing, observed:

  For `flows` and `band`, the forcing and observed flow of the
  calibration.

- window:

  For `flows` and `band`, the rows to draw; by default ten days round
  the highest observed flow.

- ...:

  Not used.

## Value

[`plot()`](https://rdrr.io/r/graphics/plot.default.html): `x`,
invisibly. `autoplot()`: a ggplot.

## Details

|              |                                                                              |
|--------------|------------------------------------------------------------------------------|
| `type`       | Shows                                                                        |
| `pairs`      | each pair of objectives: every set tried, the front, the pair's trade-off    |
| `parallel`   | each front set as a line across all the objectives, 0 best to 1 worst        |
| `flows`      | observed flow, the best set on each objective and the compromise, on a storm |
| `validation` | each set's calibration loss against its loss on a check period               |
| `band`       | the lowest and highest flow among the front's sets, on a storm               |

**Reading the pairs.** The front's points run from the best on one
objective to the best on the other. A steep stretch means a large gain
on one costs little on the other; a corner marks the sets where the
trade-off turns. Points far up and right are poor on both. The view of
each pair is cut at half the front's range beyond its worst point, so
the random first samples do not squash it; the subtitle counts those
left out.

**Reading the parallel plot.** Lines that cross between two axes mark a
trade-off between those objectives; lines that run side by side mark
objectives that agree.

**The flows** show what the numbers mean: the same storm as the best
sets for different objectives see it.

**The validation plot** needs
[`pareto_validate()`](https://jonpayneea.github.io/PDMS7/reference/pareto_validate.md)
first. Each panel is one objective: a set's loss on calibration across,
on the check period up. Sets close to the dashed line keep their
quality; sets well above it were good on the calibration rows only. The
knee and the compromise are marked.

**The band**
([`pareto_band()`](https://jonpayneea.github.io/PDMS7/reference/pareto_band.md))
is the spread of flow among all the front's sets, run from the start of
the record.

## See also

[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md),
[`pareto_choose()`](https://jonpayneea.github.io/PDMS7/reference/pareto_choose.md)

## Examples

``` r
# See calibrate_pdm_multi().
```
