# Catchment response time from rain and flow records

Estimates a catchment's response time, the average lag between the
centre of mass of rain and the centre of mass of the flow it produces,
from the records alone, by detrending moving-average cross-correlation
analysis (DMCA; Giani et al., 2021). No model and no baseflow separation
are needed.

## Usage

``` r
response_time_dmca(rain, flow, dt = 1, max_response_h = 150)
```

## Arguments

- rain:

  Rain per step (mm). Missing values count as zero.

- flow:

  Flow per step, in any units. Missing values count as zero in the
  cumulative series, as in the published method, so long gaps distort
  the estimate.

- dt:

  Time step, hours.

- max_response_h:

  Longest response time searched, hours. The default, 150 hours, follows
  the published example for hourly data.

## Value

A list: `response_h` (hours), `response_steps`, `window` (the
moving-average window, `2 * response_steps + 1`, in steps) and `curve`,
a data frame of `response_h` and `rho`, the DMCA correlation at each
half-window searched.

## Details

Rain and flow are each accumulated, and each cumulative series has its
centred moving average of window `2h + 1` steps subtracted, leaving its
fluctuations. The correlation between the two fluctuation series is
computed for every half-window `h`; the response time is the `h` at
which it is most negative. Rain and flow may be in any units: the
correlation does not depend on scale.

The data must resolve the delay: with daily data, a catchment that
responds within a day shows a response time of one step or less. A
minimum at the largest window searched means the search was too short,
and a warning says so.

## References

Giani, G., Rico-Ramirez, M. A. and Woods, R. A. (2021). A practical,
objective, and robust technique to directly estimate catchment response
time. Water Resources Research, 57, e2020WR028201.
doi:10.1029/2020WR028201

## See also

[`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md),
[`pdm_response_time()`](https://jonpayneea.github.io/PDMS7/reference/pdm_response_time.md)
for a model's own response

## Examples

``` r
set.seed(1)
rain <- ifelse(runif(3000) < 0.05, rexp(3000, 0.5), 0)
# Flow is the rain delayed by 10 steps and smoothed.
flow <- stats::filter(c(rep(0, 10), rain[1:2990]), rep(1 / 5, 5), sides = 1)
flow[is.na(flow)] <- 0
response_time_dmca(rain, flow)$response_h
#> [1] 14
```
