# Score threshold crossings

Verifies a simulation against observed flow at one or more thresholds,
such as flood alert and flood warning flows, as a forecaster would: did
the model cross the threshold when the river did, and how far out was
it?

## Usage

``` r
pdm_threshold_scores(
  simulated,
  observed,
  thresholds,
  dt_hours = 1,
  tolerance_h = 6,
  gap_h = 24,
  min_duration_h = 0
)
```

## Arguments

- simulated, observed:

  Aligned discharge vectors, m3/s.

- thresholds:

  Named numeric vector of threshold flows, m3/s.

- dt_hours:

  Time step, hours.

- tolerance_h, gap_h, min_duration_h:

  Matching tolerance, minimum gap between separate events, and minimum
  event duration, hours.

## Value

A data.table with one row per threshold: `threshold`, `flow_m3s`, then
the scores.

## Details

**Events.** An event is an episode above the threshold. Exceedances
separated by less than `gap_h` are merged, so flow flickering about the
threshold is one event, and events shorter than `min_duration_h` are
ignored. A simulated event whose first crossing lies within
`tolerance_h` of an observed event's crossing is a hit; pairs are
matched one to one, closest first, with ties going to the earlier
observed event. Unmatched observed events are misses and unmatched
simulated events false alarms. Missing observations count as below the
threshold.

|                        |                                                                  |      |
|------------------------|------------------------------------------------------------------|------|
| Score                  | Meaning                                                          | Best |
| `pod`                  | Probability of detection: hits / observed events                 | 1    |
| `far`                  | False alarm ratio: false alarms / simulated events               | 0    |
| `csi`                  | Critical success index: hits / (hits + misses + false alarms)    | 1    |
| `bias`                 | Frequency bias: simulated events / observed events               | 1    |
| `crossing_error_h`     | Mean crossing time error over hits, simulated minus observed     | 0    |
| `abs_crossing_error_h` | Mean absolute crossing time error                                | 0    |
| `peak_timing_error_h`  | Mean simulated minus observed time of each event's peak          | 0    |
| `peak_error`           | Mean relative error of each event's peak flow                    | 0    |
| `duration_error_h`     | Mean simulated minus observed time above the threshold           | 0    |
| `volume_error`         | Relative error of the total volume above the threshold over hits | 0    |

Crossing and peak timing errors are positive when the simulation is
late. Event scores need no correct negatives, which events do not
define. **Steps**: the same contingency is also counted step by step
(`pod_step`, `far_step`, `csi_step`, `bias_step`) with the scores that
need correct negatives: probability of false detection (`pofd_step`),
equitable threat score (`ets_step`) and Peirce skill score (`pss_step`).

Scores with an empty denominator, such as POD when nothing was observed
above the threshold, are `NA`.

## References

Jolliffe and Stephenson (2012), Forecast Verification, 2nd edition,
Wiley.

## Examples

``` r
obs <- c(1, 2, 6, 8, 5, 2, 1, 1, 3, 7, 4, 1)
sim <- c(1, 1, 3, 7, 9, 4, 2, 1, 1, 2, 2, 1)
pdm_threshold_scores(sim, obs, c(alert = 4, warning = 7.5), tolerance_h = 1, gap_h = 1)
#>    threshold flow_m3s   pod   far   csi  bias observed_events simulated_events
#>       <char>    <num> <num> <num> <num> <num>           <num>            <num>
#> 1:     alert      4.0   0.5     0   0.5   0.5               2                1
#> 2:   warning      7.5   1.0     0   1.0   1.0               1                1
#>     hits misses false_alarms crossing_error_h abs_crossing_error_h
#>    <num>  <num>        <num>            <num>                <num>
#> 1:     1      1            0                1                    1
#> 2:     1      0            0                1                    1
#>    peak_timing_error_h peak_error duration_error_h volume_error pod_step
#>                  <num>      <num>            <num>        <num>    <num>
#> 1:                   1      0.125               -1    0.1428571      0.5
#> 2:                   1      0.125                0    2.0000000      0.0
#>    far_step csi_step bias_step  pofd_step    ets_step    pss_step
#>       <num>    <num>     <num>      <num>       <num>       <num>
#> 1:        0      0.5       0.5 0.00000000  0.40000000  0.50000000
#> 2:        1      0.0       1.0 0.09090909 -0.04347826 -0.09090909
```
