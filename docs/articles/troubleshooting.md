# Troubleshooting

The common problems, the message pdmS7 gives, and what to do. Each
message on this page is produced by the package itself when the site is
built, so it matches what you will see.

## Data

### Missing or negative inputs

``` r
says(run_pdm(model, data.frame(rain = c(1, NA), pet = 0.05)))
#> [1] "rain must contain finite nonnegative numbers"
says(run_pdm(model, data.frame(rain = c(1, 2), pet = c(0.05, -1))))
#> [1] "pet must contain finite nonnegative numbers"
```

The model cannot run through a gap in rain or PET, and negative values
are data faults. Infill rain by one recorded method; fill PET from a
seasonal curve. [Preparing your
data](https://jonpayneea.github.io/PDMS7/articles/data-preparation.md),
steps 2, 5 and 6.

### Rows that do not line up

``` r
config <- pdm_presets("standard")
says(calibrate_pdm(config, forcing, observed = c(1, 2, 3), lower = c(fc = 0.8),
                   upper = c(fc = 1.2)))
#> [1] "observed length must match forcing"
```

The forcing and the observed flow must have one row each per time step.
Join them on time, not by position, and fill missing time steps with
explicit rows.

### Scores that cannot be computed

``` r
says(calibrate_pdm(config, forcing, observed = rep(2, 6), lower = c(fc = 0.8),
                   upper = c(fc = 1.2), objective = "nse"))
#> [1] "NSE needs variable observations"
```

NSE compares the model with the mean observed flow, so it needs flow
that varies. A window that is almost all missing, or a constant flow,
usually means the wrong file or a broken gauge record.

### Times

If the model’s floods arrive one step early or late on every event, the
rain or the flow is stamped at the start of the step instead of the end,
or is in local time instead of UTC. Plot a few sharp storms: flow cannot
rise before the rain that causes it.

## Calibration

### Bounds and starting values

``` r
says(calibrate_pdm(config, forcing, observed = c(1, 2, 3, 2, 1, 1), lower = c(fc = 1.2),
                   upper = c(fc = 1.5)))
#> [1] "Initial parameters outside bounds"
```

The starting value of each calibrated parameter, from the configuration,
must lie inside its bounds. Widen the bounds or change the starting
configuration.
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
gives default bounds that include the standard presets.

### Parameters ending on a bound

Not an error, but a warning sign. The search was stopped by the fence,
not by the data. Check the data first (wrong area, biased rainfall, a
rating change), then consider whether the bound is physically justified.
Widening a bound to let a parameter run away rarely gives a better
model. The `start_results` table of a calibration shows each start’s
final values.

### Starts that disagree

Several starts ending at different parameters with similar scores mean
the data do not pin those parameters down (equifinality). More starts
will not fix it. Staged calibration
([`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)),
which fits groups of parameters to the parts of the hydrograph they
control, often helps. [Automatic calibration,
explained](https://jonpayneea.github.io/PDMS7/articles/auto-calibration.md).

### A threshold objective with the gradient method

``` r
says(calibrate_pdm(config, forcing, observed = c(1, 2, 3, 2, 1, 1), lower = c(fc = 0.8),
                   upper = c(fc = 1.2), thresholds = c(alert = 2.5), method = "lbfgsb"))
#> [1] "Threshold scores change in steps, which a gradient optimiser cannot follow; use method = \"nelder_mead\" or \"dds\""
```

Threshold scores change in steps, so a gradient method cannot follow
them. Use `method = "nelder_mead"`.

### The search found nothing valid

`No valid calibration evaluation; inspect configuration and bounds`
means every trial failed to run. Usually a combination of components and
bounds that the model rejects, for example demand recharge with a
cascade groundwater store. Run the starting configuration once with
[`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md):
its error says what is wrong.

## Model structure

``` r
says(pdm_model(recharge = DemandRecharge(alpha = 0.5, beta = 1, qsat = 101)))
#> [1] "no error"
says(correct_state(pdm_model(td = 2), initial_state(pdm_model(td = 2)), 1))
#> [1] "State correction requires td=0; delayed observations need a lag-aware smoother"
```

Some components only make sense together. Demand recharge needs a single
groundwater store with room for its rate; state correction needs no
outlet delay (`td = 0`), because with a delay the latest observation
reflects an earlier state. [Choosing model
components](https://jonpayneea.github.io/PDMS7/articles/model-options.md).

## Batches

### A basin failed

[`batch_status()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
shows the step it reached and the reason. Fix the cause, often a data
file, and run the same
[`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
call again: finished basins pass through in moments and the failed one
carries on from where it stopped. Use `only = "B06"` to retry just that
basin. [Calibrating many
catchments](https://jonpayneea.github.io/PDMS7/articles/many-catchments.md).

### A lock left behind

If R was stopped while writing to a project, the next write may report
removing a stale lock. That is expected: the package clears a lock left
by a session that no longer exists.

## The calibration log

### Not enough years to hold back

``` r
time <- seq(as.POSIXct("2020-10-01", tz = "UTC"), by = 86400, length.out = 3 * 365)
says(wettest_years(time, rep(1, length(time)), n = 2))
#> [1] "Only 3 water years have at least half a year of observed flow; holding back 2 would leave fewer than 3. Hold back fewer years, or none with 0"
```

By default
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
holds back the two wettest water years, which needs a record of at least
five years with half of each observed. For a shorter record, set
`wettest_years = 1` or `0` and say why in the registration’s reasoning.
Without a `time` column in the forcing, registration refuses for the
same reason: water years need dates. If holding back the wettest year
leaves the validation window almost empty, lengthen the window; the
message names it. [Larger
floods](https://jonpayneea.github.io/PDMS7/articles/extrapolation.md).

### A data file has changed

`Registered ... file has changed since registration` means a data file
no longer matches the checksum taken when it was registered. Someone
edited or replaced it. Do not carry on: restore the original, or
register the new file as new data with a note explaining why.

### An entry no longer reproduces

`... no longer reproduces its recorded output` means rerunning a logged
configuration gives a different flow. Usually the package or R has
changed since the entry was written.
`verify_project(project, rerun = TRUE)` names what changed. Recalibrate
under the new version, or run the old version to reproduce the record.

### A Steward cannot sign off

``` r
sign_off_project(project, "Accepted.", reviewed)
#> Error: You wrote calibration entries in this project; another Steward must sign off
```

By design. A Steward who took part in the calibration cannot sign it
off. Ask another Steward, or a Delegated Steward. [Reviewing a
calibration](https://jonpayneea.github.io/PDMS7/articles/steward-guide.md).

## Forecasting

``` r
says(pdm_hindcast(model, forcing, observed = c(1, 2, 3, 2, 1, 1), window = 6:6))
#> [1] "No forecast origins fit in the window"
```

A hindcast needs room for forecast origins inside the window, with at
least one step after each. Widen the window or shorten `every_h`.
[Testing forecasts with
hindcasts](https://jonpayneea.github.io/PDMS7/articles/hindcasts.md).

## Still stuck

Check the function’s help page
([`?calibrate_pdm`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
and so on), then the
[Glossary](https://jonpayneea.github.io/PDMS7/articles/glossary.md) for
any unfamiliar term. If the package itself seems wrong, report it with a
small example that reproduces the problem on the [issue
tracker](https://github.com/JonPayneEA/PDMS7/issues).
