# Flow thresholds from the record: QMED and flow duration markers

Where a catchment has no warning thresholds, the record itself gives
flows worth scoring a model against. `flow_markers()` computes them, in
a table that
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
takes as `thresholds`;
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
uses `QMED`, `Q1` and `Q5` itself when no thresholds are given.

## Usage

``` r
flow_markers(
  observed,
  dt,
  time = NULL,
  markers = c("QMED", "Q1", "Q5"),
  complete = 0.9
)
```

## Arguments

- observed:

  Observed flow, m3/s; missing values allowed.

- dt:

  Time step, hours.

- time:

  Optional times of the flows (POSIXct), for water years.

- markers:

  Markers to compute, from `QMED`, a multiple such as `0.5QMED`, or
  `Q<p>` with `p` a percentage between 0 and 100, such as `Q1` or
  `Q0.5`.

- complete:

  Smallest fraction of a water year's steps that must be observed for
  its maximum to count towards QMED.

## Value

A data frame with `name`, `value` (m3/s), `unit` (`flow`) and `note`,
and the number of complete years as attribute `years`.

## Details

|                        |                                                  |                          |
|------------------------|--------------------------------------------------|--------------------------|
| Marker                 | Flow                                             | Crossed                  |
| `QMED`                 | Median annual maximum: the 2-year flood          | One year in two          |
| `0.5QMED`, multiples   | Fraction of QMED; 0.5 is near a UK POT threshold | A few times a year       |
| `Q1`, `Q5`, any `Q<p>` | Exceeded `p` per cent of the time                | Above Q1 3.6 days a year |

QMED follows the Flood Estimation Handbook: the median of the annual
maxima of water years, October to September, each year counted only if
at least `complete` of its steps are observed. From 15-minute or hourly
data the maxima are near-instantaneous peaks, as the Handbook intends;
from daily means QMED is lower. With fewer than 10 years the median is
uncertain, and a warning says so; fewer than 2 complete years give no
QMED. Without times, years are taken as blocks of 365.25 days from the
start of the record.

Exceedance markers count time, not floods: a long wet winter spends many
days above Q5 without a notable flood. QMED and its multiples count
peaks.

## Examples

``` r
set.seed(1)
n <- 24 * 365 * 3
q <- exp(stats::filter(rnorm(n, 0, 0.05), 0.995, method = "recursive"))
flow_markers(q, dt = 1)
#> Warning: QMED from 3 complete water years is uncertain; the Flood Estimation Handbook prefers 10 or more.
#>   name   value unit                          note
#> 1 QMED 4.31252 flow Median of 3 water-year maxima
#> 2   Q1 3.44444 flow  Flow exceeded 1% of the time
#> 3   Q5 2.36809 flow  Flow exceeded 5% of the time
flow_markers(q, dt = 1, markers = c("0.5QMED", "Q10"))
#> Warning: QMED from 3 complete water years is uncertain; the Flood Estimation Handbook prefers 10 or more.
#>      name   value unit                                note
#> 1 0.5QMED 2.15626 flow 0.5 x Median of 3 water-year maxima
#> 2     Q10 1.88455 flow       Flow exceeded 10% of the time
```
