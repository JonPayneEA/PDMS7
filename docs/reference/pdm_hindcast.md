# Hindcast forecasts from many origins

Reruns past forecasts. From each forecast origin the model forecasts the
next `horizon_h` hours, using the rain that actually fell as the
forecast rain, so the scores measure the model and its updating, not a
rainfall forecast. A forecast LSTM can be given the same origins and
scored by the same
[`hindcast_scores()`](https://jonpayneea.github.io/PDMS7/reference/hindcast_scores.md).

## Usage

``` r
pdm_hindcast(
  model,
  forcing,
  observed,
  state = NULL,
  window = NULL,
  every_h = 6,
  horizon_h = 48,
  ar = NULL,
  response_flow = NULL,
  fit_window = NULL,
  state_correction = NULL,
  lower_limit = 0
)
```

## Arguments

- model:

  A FlodePdmModel.

- forcing:

  Data frame with `rain` and `pet`, mm per step; optional `time`.

- observed:

  Observed flow in m3/s, aligned with `forcing`; NA where missing.

- state:

  Starting state; by default steady state at the first observed flow.

- window:

  Row numbers in which forecast origins may lie, typically the
  validation or test window. Default: every row after the first 10 per
  cent.

- every_h:

  Hours between forecast origins.

- horizon_h:

  Forecast horizon in hours.

- ar:

  Named list of AR coefficient vectors, Deltares convention. `NULL`
  gives the default pair described above;
  [`list()`](https://rdrr.io/r/base/list.html) gives none.

- response_flow:

  Reference flow in m3/s for the response time. Default: the 90th
  percentile of observed flow, a typical high flow.

- fit_window:

  Optional row numbers on which to fit AR(3) coefficients, method
  `fitted`.

- state_correction:

  `NULL` for none, or a
  [`state_updater()`](https://jonpayneea.github.io/PDMS7/reference/state_updater.md)
  to add method `state`.

- lower_limit:

  Lowest allowed updated flow, m3/s.

## Value

A list: `forecasts`, a data.table with `origin` (row), `time` (if
`forcing` has one), `lead` (steps), `lead_h`, `method`, `forecast` and
`observed`; `ar`, the coefficient sets used; `response_time`, the
[`pdm_response_time()`](https://jonpayneea.github.io/PDMS7/reference/pdm_response_time.md)
result; and `dt`.

## Details

**Methods.** Every hindcast includes:

|                    |                                                                             |
|--------------------|-----------------------------------------------------------------------------|
| Method             | Forecast                                                                    |
| `none`             | The simulation, without updating                                            |
| `persistence`      | The last observed flow, held for every lead: the baseline to beat           |
| each entry of `ar` | The simulation plus the AR projection of recent error, as in IMFS           |
| `fitted`           | As above, with AR(3) coefficients fitted to the errors in `fit_window` only |
| `state`            | State correction at the origin (Moore 2007, Eq. 28-30), then run forward    |

By default `ar` holds the Environment Agency 2024 default set and a
default-family set whose principal decay is the model's own time to peak
at `response_flow`, from
[`pdm_response_time()`](https://jonpayneea.github.io/PDMS7/reference/pdm_response_time.md).
The 2024 default is defined for 15-minute steps; on other steps it is
still applied, as given, with a message.

Errors are observed minus simulated flow, in m3/s, additive, as in IMFS.
The AR projection at an origin needs the last three errors; if any of
those observations is missing, that origin has no AR forecast. Updated
flows below `lower_limit` are raised to it.

**No leaks.** The simulation runs continuously without updating, so the
forecast from an origin uses observations up to that origin only. AR
coefficients come from outside the scored period: the fixed sets, or
`fit_window`, which should be the calibration window. Fitting on the
scored window would let the AR learn the errors it then corrects.

## See also

[`hindcast_scores()`](https://jonpayneea.github.io/PDMS7/reference/hindcast_scores.md),
[`plot_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/plot_hindcast.md),
[`pdm_response_time()`](https://jonpayneea.github.io/PDMS7/reference/pdm_response_time.md),
[`ar_from_response_time()`](https://jonpayneea.github.io/PDMS7/reference/ar_from_response_time.md)

## Examples

``` r
set.seed(1)
n <- 24 * 40
forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0), pet = 0.05)
truth <- pdm_model(area_km2 = 40, fc = 1.1)
observed <- run_pdm(truth, forcing, initial_state_from_flow(truth, 2, 0.7))$output$q_m3s
#> Warning: A steady start at 2 m3/s with baseflow_fraction 0.70 needs 504 mm of soil storage, more than the store's capacity of 214.3 mm; the soil is capped and the run starts out of balance. Start at a lower flow or a smaller baseflow_fraction, or use start = "soil".
model <- pdm_model(area_km2 = 40)
hc <- pdm_hindcast(model, forcing, observed, window = (24 * 20 + 1):n, horizon_h = 24)
#> Warning: A steady start at 1.976 m3/s with baseflow_fraction 0.70 needs 497.9 mm of soil storage, more than the store's capacity of 214.3 mm; the soil is capped and the run starts out of balance. Start at a lower flow or a smaller baseflow_fraction, or use start = "soil".
#> The EA 2024 AR default is defined for 15-minute steps; this model uses 1 h steps
head(hindcast_scores(hc))
#>     method lead_h lead_ratio     n       nse       rmse        mae
#>     <char>  <num>      <num> <int>     <num>      <num>      <num>
#> 1: ea_2024      1  0.3382447    80 0.9993394 0.05756167 0.02319460
#> 2: ea_2024      2  0.6764894    80 0.9966174 0.13362834 0.05746344
#> 3: ea_2024      3  1.0147341    80 0.9906801 0.21385742 0.09760162
#> 4: ea_2024      4  1.3529788    80 0.9797317 0.30079061 0.14399671
#> 5: ea_2024      5  1.6912236    80 0.9645740 0.37917730 0.17578950
#> 6: ea_2024      6  2.0294683    79 0.9521745 0.46560654 0.20206155
#>             bias     skill
#>            <num>     <num>
#> 1:  0.0026038381 0.9916308
#> 2:  0.0071191902 0.9814958
#> 3:  0.0065991271 0.9680622
#> 4: -0.0004104198 0.9513987
#> 5:  0.0013508577 0.9423080
#> 6: -0.0010823713 0.9455827
```
