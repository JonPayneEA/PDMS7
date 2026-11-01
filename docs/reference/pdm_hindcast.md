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
model <- pdm_model(area_km2 = 40)
hc <- pdm_hindcast(model, forcing, observed, window = (24 * 20 + 1):n, horizon_h = 24)
#> The EA 2024 AR default is defined for 15-minute steps; this model uses 1 h steps
head(hindcast_scores(hc))
#>     method lead_h lead_ratio     n       nse        rmse         mae
#>     <char>  <num>      <num> <int>     <num>       <num>       <num>
#> 1: ea_2024      1 0.06052198    80 0.9999924 0.004511309 0.002255966
#> 2: ea_2024      2 0.12104396    80 0.9999373 0.012976216 0.005777511
#> 3: ea_2024      3 0.18156594    80 0.9998191 0.021984528 0.010380429
#> 4: ea_2024      4 0.24208792    80 0.9996562 0.030315441 0.016242178
#> 5: ea_2024      5 0.30260990    80 0.9994347 0.038895785 0.022749255
#> 6: ea_2024      6 0.36313188    79 0.9990558 0.050678973 0.029958054
#>             bias     skill
#>            <num>     <num>
#> 1: -0.0002889751 0.9982776
#> 2: -0.0008250368 0.9960394
#> 3: -0.0015710318 0.9942598
#> 4: -0.0032247819 0.9929409
#> 5: -0.0046550755 0.9916079
#> 6: -0.0069163093 0.9895494
```
