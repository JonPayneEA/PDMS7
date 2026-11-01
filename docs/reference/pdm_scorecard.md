# Score a simulation against observed flow

Computes every score used by the calibration log. Unlike
[`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md),
which returns losses to minimise, these are diagnostics in their natural
form, signed where the sign tells the calibrator which way to move.

## Usage

``` r
pdm_scorecard(simulated, observed, log_offset = 0.01)
```

## Arguments

- simulated, observed:

  Numeric aligned nonnegative discharge vectors, m3/s. Missing
  observations are excluded; simulations at scored rows must be finite.

- log_offset:

  Positive offset added before logarithms, m3/s.

## Value

Named numeric vector, in the order of the table above.

## Details

|                    |                                                                      |      |
|--------------------|----------------------------------------------------------------------|------|
| Score              | Meaning                                                              | Best |
| `nse`              | Nash-Sutcliffe efficiency                                            | 1    |
| `log_nse`          | NSE of log(flow + log_offset), weighting low flows                   | 1    |
| `kge`              | Kling-Gupta efficiency (Gupta et al. 2009)                           | 1    |
| `kge_r`            | Correlation                                                          | 1    |
| `kge_alpha`        | Ratio of standard deviations, simulated over observed                | 1    |
| `kge_beta`         | Ratio of means, simulated over observed                              | 1    |
| `rmse`             | Root mean square error, m3/s                                         | 0    |
| `log_rmse`         | RMSE of log(flow + log_offset)                                       | 0    |
| `volume_error`     | Signed volume error as a fraction: positive is too wet               | 0    |
| `abs_volume_error` | Absolute volume error as a fraction                                  | 0    |
| `peak_error`       | Signed error in the highest flow as a fraction                       | 0    |
| `fdc_high`         | Volume bias of the flow-duration curve above 2 per cent exceedance   | 0    |
| `fdc_mid`          | Bias in the slope of the curve between 20 and 70 per cent exceedance | 0    |
| `fdc_low`          | Bias in the low-flow segment above 70 per cent exceedance            | 0    |

The three flow-duration-curve signatures follow Yilmaz et al. (2008), as
fractions rather than percentages; logarithms use `log_offset` so zero
flows are allowed. A score that is undefined for the data, such as KGE
for a constant simulation, is `NA`.

## References

Gupta et al. (2009), doi:10.1016/j.jhydrol.2009.08.003; Yilmaz et al.
(2008), doi:10.1029/2007WR006716.

## Examples

``` r
obs <- c(1, 3, 8, 5, 3, 2, 1.5, 1.2, 1, 0.9)
pdm_scorecard(obs * 1.1, obs)
#>              nse          log_nse              kge            kge_r 
#>     0.9748630840     0.9819843080     0.8585786438     1.0000000000 
#>        kge_alpha         kge_beta             rmse         log_rmse 
#>     1.1000000000     1.1000000000     0.3427827300     0.0947600996 
#>     volume_error abs_volume_error       peak_error         fdc_high 
#>     0.1000000000     0.1000000000     0.1000000000               NA 
#>          fdc_mid          fdc_low 
#>     0.0004822624    -0.0009495880 
```
