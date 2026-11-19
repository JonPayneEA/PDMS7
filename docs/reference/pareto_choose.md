# Choose a configuration from a Pareto front

Picks one point of the front from
[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md):
the best on one objective (a corner of the front), the best under a
weighting of the scaled losses, the knee, or, with none of these, the
result's compromise.

## Usage

``` r
pareto_choose(x, objective = NULL, weights = NULL, knee = FALSE)
```

## Arguments

- x:

  A `pdm_pareto` result.

- objective:

  One objective's name: the front point with its lowest loss (ties go to
  the lowest equally weighted, scaled sum).

- weights:

  Nonnegative weights named by objective (missing ones count 0), applied
  to the scaled losses.

- knee:

  `TRUE` for the knee.

## Value

A list: `config`, `scores` (the point's row of the front) and `row` (its
row in `x$pareto`).

## Details

**The knee** is the set where the trade-off turns sharpest: put each
objective on the front's own scale, 0 for the front's best and 1 for its
worst, and take the set with the lowest total. With two objectives this
is exactly the set furthest below the straight line joining the two ends
of the front; with more, the plane through the ends is approximated by
the one through the unit points. It needs no weights, so a batch can
apply it to every catchment alike; but it depends on which sets made the
front's ends, so check it on the plot.

## See also

[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md),
[`plot.pdm_pareto()`](https://jonpayneea.github.io/PDMS7/reference/plot.pdm_pareto.md)

## Examples

``` r
# See calibrate_pdm_multi().
```
