# Weights for flows by how well they are measured

One weight for each observed flow, for the `weights` of
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md),
so that flows the gauge measures poorly count for less. Two sources,
used together when both are given:

## Usage

``` r
flow_weights(
  observed,
  uncertainty = NULL,
  highest_gauged = NULL,
  extrapolated = 0.25
)
```

## Arguments

- observed:

  Observed flow, m3/s.

- uncertainty:

  `NULL`, or a data frame with `q` and `relative`.

- highest_gauged:

  `NULL`, or the highest gauged flow, m3/s.

- extrapolated:

  Weight factor above the highest gauging.

## Value

A weight for each flow.

## Details

- `uncertainty`, a table of flow (`q`, m3/s) and its relative
  uncertainty (`relative`, for example 0.1 for plus or minus 10%), such
  as a rating's uncertainty at its percentiles. Each flow's relative
  uncertainty is interpolated (held flat beyond the table) and its
  weight is `(smallest / relative)^2`: inverse variance, the
  best-measured flows weighing 1.

- `highest_gauged`: flows above the highest gauging lie on the
  extrapolated rating; they are multiplied by `extrapolated`.

Missing flows get weight 0. Weights scale the Box-Cox objective's
squared errors.

## See also

[`boxcox_flow()`](https://jonpayneea.github.io/PDMS7/reference/boxcox_flow.md),
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)

## Examples

``` r
flow_weights(c(1, 5, 50), uncertainty = data.frame(q = c(1, 50), relative = c(0.05, 0.2)))
#> [1] 1.0000000 0.6452567 0.0625000
```
