# Box-Cox transformed flow

`((q + offset)^lambda - 1) / lambda`, or `log(q + offset)` for
`lambda = 0`. Flow errors grow with the flow: a gauge's error at a flood
is many times its error at baseflow, and a model's error likewise. Least
squares on the raw flow then counts the largest floods many times over
and the rest of the record hardly at all. On the transformed scale the
errors are much closer to the same size at every flow, which is what
least squares assumes. `lambda = 1` is the raw flow (less one), `0` the
log; between them, `0.5` (the default of the `boxcox` objective) keeps
more weight on high flows than the log does, and `0.2` is closer to the
log (McInerney et al., 2017, compare the choices).

## Usage

``` r
boxcox_flow(q, lambda = 0.5, offset = 0.01)
```

## Arguments

- q:

  Flow, m3/s.

- lambda:

  The transform's power, from 0 (log) to 1 (raw).

- offset:

  A small positive flow added first, m3/s, so zero flows stay finite.

## Value

The transformed flow.

## See also

[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
(`objective = "boxcox"`),
[`flow_weights()`](https://jonpayneea.github.io/PDMS7/reference/flow_weights.md)

## Examples

``` r
boxcox_flow(c(0.1, 1, 10, 100), lambda = 0.5)
#> [1] -1.336675042  0.009975124  4.327716808 18.000999975
```
