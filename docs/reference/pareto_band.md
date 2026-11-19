# The range of flows across a Pareto front

Runs every set on the front of
[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md)
and returns, for each row of the record, the lowest and highest flow
among them, with the compromise. Every set on the front is defensible by
some balance of the objectives, so the band shows how much the flow
depends on that choice: wide on a storm means the objectives disagree
there. It is a band of plausible calibrations, not a statistical
confidence interval: it says nothing about rain or rating errors.
`plot(x, "band", ...)` draws it.

## Usage

``` r
pareto_band(x, forcing, sets = NULL)
```

## Arguments

- x:

  A `pdm_pareto` result.

- forcing:

  The forcing to run, from the same first row as the search's.

- sets:

  Rows of `x$pareto` to include; by default all. The ends of a front are
  often extreme, so the band of the sets you would actually consider,
  those round the knee, can be much narrower.

## Value

A data frame: `row`, `time` (when the forcing has one), `lower`, `upper`
and `compromise`, in m3/s.

## See also

[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md),
[`plot.pdm_pareto()`](https://jonpayneea.github.io/PDMS7/reference/plot.pdm_pareto.md)

## Examples

``` r
# See calibrate_pdm_multi().
```
