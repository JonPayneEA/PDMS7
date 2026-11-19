# Counting every error fairly: the Box-Cox objective

A calibration can only be as good as its idea of a good fit. NSE, the
usual idea, counts every hour’s squared error alike. That sounds fair
and is not: an error of 5 m3/s at the peak of a flood counts 2,500 times
as much as an error of 0.1 m3/s on a summer recession, though both may
be the same 10% of the flow. A calibration by NSE therefore fits a
handful of floods closely and the rest of the record loosely. This
article shows the effect, and the cure.

## A record with a known answer

Three years of synthetic hourly rain through the standard PDM, with
errors on the flow that grow with it: each hour is the true flow times a
random factor, a 15% error at any flow. Real gauges and models behave
much the same way.

``` r
rain <- synthetic_rain("2017-10-01", years = 3, dt = 1, seed = 5)
truth <- modifyList(pdm_presets("standard"), list(area_km2 = 25))
model <- pdm_from_config(truth)
forcing <- rain[c("time", "rain", "pet")]
set.seed(8)
flow <- run_pdm(model, forcing[c("rain", "pet")], initial_state(model, 0.5))$output$q_m3s
observed <- flow * exp(rnorm(length(flow), 0, 0.15))
scored <- seq_along(observed) > 24 * 90
```

## Where NSE’s attention goes

Run the true model and ask where its squared errors come from: the share
of the total that falls in the wettest 1% of hours, against the share in
the driest half.

``` r
err <- (flow - observed)[scored]
q <- observed[scored]
top <- q >= stats::quantile(q, 0.99)
low <- q <= stats::median(q)
share <- function(e) c(wettest_1pc = sum(e[top]^2), driest_half = sum(e[low]^2)) / sum(e^2)
round(100 * share(err), 1)
#> wettest_1pc driest_half 
#>        57.0         3.1
```

Even for the true model, the wettest 1% of hours, about 240 of them,
carry more than half of the squared error, and the driest half of the
record about 3%. Any calibration that minimises squared errors will
listen to those hours above all others.

## The Box-Cox transform

The cure is to measure the errors on a scale where they are about the
same size at every flow.
[`boxcox_flow()`](https://jonpayneea.github.io/PDMS7/reference/boxcox_flow.md)
does that:

$$z = \frac{(q + c)^{\lambda} - 1}{\lambda}$$

with a small offset $c$ so that zero flows stay finite. The power
$\lambda$ sets how hard the large flows are squeezed: $\lambda = 1$
leaves the flow as it is, $\lambda = 0$ takes its log, and values
between are compromises.

``` r
qq <- seq(0, 20, length.out = 200)
plot(qq, boxcox_flow(qq, 1), type = "l", ylim = c(-5, 20), xlab = "Flow (m3/s)",
     ylab = "Transformed flow", lwd = 2)
for (l in c(0.5, 0.2, 0)) lines(qq, boxcox_flow(qq, l), lwd = 2, lty = match(l, c(0.5, 0.2, 0)) + 1)
legend("topleft", c("lambda 1 (raw)", "0.5", "0.2", "0 (log)"), lty = 1:4, lwd = 2, bty = "n")
```

![](fair-errors_files/figure-html/curves-1.png)

The same errors on the transformed scale:

``` r
for (l in c(1, 0.5, 0)) {
  e <- boxcox_flow(flow[scored], l) - boxcox_flow(observed[scored], l)
  cat(sprintf("lambda %.1f: %s\n", l, paste(names(share(e)), sprintf("%.1f%%", 100 * share(e)),
                                            collapse = ", ")))
}
#> lambda 1.0: wettest_1pc 57.0%, driest_half 3.1%
#> lambda 0.5: wettest_1pc 13.4%, driest_half 22.7%
#> lambda 0.0: wettest_1pc 1.1%, driest_half 50.7%
```

With the log, the wettest 1% of hours carry about 1% of the error and
the driest half about half: every hour counts alike, which is what least
squares assumes.

## Choosing the power

The right power is the one that makes the errors the same size at every
flow. Fit a model, cut its flows into fifths, and look at the spread of
the transformed errors in each:

``` r
spread_by_flow <- function(l) {
  e <- boxcox_flow(flow[scored], l) - boxcox_flow(observed[scored], l)
  fifth <- cut(q, stats::quantile(q, 0:5 / 5), include.lowest = TRUE, labels = 1:5)
  round(tapply(e, fifth, stats::sd), 3)
}
rbind(`lambda 1` = spread_by_flow(1), `lambda 0.5` = spread_by_flow(0.5),
      `lambda 0` = spread_by_flow(0))
#>                1     2     3     4     5
#> lambda 1   0.020 0.034 0.037 0.045 0.269
#> lambda 0.5 0.050 0.070 0.069 0.074 0.166
#> lambda 0   0.132 0.148 0.131 0.124 0.155
```

The columns run from the lowest fifth of flows to the highest. On the
raw scale the spread grows many times over; at 0.5 it still grows; with
the log it is flat. These errors were made proportional to the flow, so
the log is right for them. Real errors usually sit between: the log is
often close, 0.2 to 0.5 when the largest flows are better measured than
their size suggests (McInerney et al., 2017). Run the same table on your
own calibrated model and pick the power that flattens it. The default of
the objective, 0.5, is a safe middle.

## Calibrating with it

`objective = "boxcox"` in
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
scores 1 minus NSE on the transformed flows:

``` r
start <- modifyList(truth, list(fc = 0.8))
start$distribution$cmax <- 200
lower <- c(fc = 0.6, distribution.cmax = 100, surface.k1 = 1, distribution.b = 0.1)
upper <- c(fc = 1.4, distribution.cmax = 500, surface.k1 = 30, distribution.b = 2)
fits <- lapply(c(nse = "nse", boxcox = "boxcox"), function(o) {
  calibrate_pdm(start, forcing, observed, lower, upper, warmup = 24 * 90, objective = o,
                start = "soil", control = list(maxit = 60))
})
rbind(truth = c(fc = 1, distribution.cmax = 300, surface.k1 = 2, distribution.b = 0.4),
      t(vapply(fits, function(f) f$parameters, numeric(4))))
#>               fc distribution.cmax surface.k1 distribution.b
#> truth  1.0000000          300.0000   2.000000      0.4000000
#> nse    0.9996364          305.3337   1.999157      0.4183938
#> boxcox 1.0043510          301.6843   1.970166      0.4011965
```

Both come close on a clean synthetic record; the Box-Cox calibration
comes closer on the soil store, whose shape `b` governs the whole range
of flows, not only the peaks. On real records, where a few large floods
may carry rating errors of 20% or more, the difference is usually
larger. `boxcox_lambda` sets the power;
[`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md)
and
[`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md)
offer the same score as `boxcox_loss`, so it can sit on a Pareto front
beside event scores.

## Flows the gauge measures poorly

Not every flow is measured equally well. A rating is tight where it was
gauged and loose where it is extrapolated, above the highest gauging.
[`flow_weights()`](https://jonpayneea.github.io/PDMS7/reference/flow_weights.md)
turns what is known about that into a weight for each hour, for the
`weights` of
[`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md):

``` r
rating <- data.frame(q = c(0.2, 2, 8), relative = c(0.05, 0.08, 0.15))
w <- flow_weights(observed, uncertainty = rating, highest_gauged = 10)
round(tapply(w, cut(observed, c(0, 0.2, 2, 8, 10, Inf)), mean), 3)
#>  (0,0.2]  (0.2,2]    (2,8]   (8,10] (10,Inf] 
#>    1.000    0.880    0.294    0.111    0.028
```

The weights are inverse variances: a flow measured to 15% counts
(5/15)^2, about a ninth, as much as one measured to 5%. Above the
highest gauging each weight is cut again, by `extrapolated` (a quarter
by default). In CAMELS-GB the rating uncertainty comes with each
catchment, at six flow percentiles; for an EA gauge, the hydrometry
team’s rating review gives it.

``` r
calibrate_pdm(start, forcing, observed, lower, upper, objective = "boxcox", weights = w)
```

## In a calibration project

[`log_auto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
and the stages of
[`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md)
take `objective = "boxcox"` like any other, and the log records the
power used.

## Cautions

- **The power is a choice to check**, not a constant: run the spread
  table on your own record.
- **Zero flows** need the offset (`log_offset`, 0.01 m3/s by default) to
  be small next to the low flows but not so small that the log of
  near-zero flows dominates.
- **The Box-Cox objective does not replace event checks.** It counts the
  record fairly; the floods still deserve their own look ([Getting the
  floods right](https://jonpayneea.github.io/PDMS7/articles/floods.md)).
