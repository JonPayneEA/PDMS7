# Calibration app

A Shiny app over the calibration log, for staff who prefer not to
script. Every button calls the same exported function a script would
([`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`log_trial()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`sign_off_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
and the rest), so a project started in the app can be continued in R and
the other way round, and the same rules apply: roles, reasoning, scoring
windows, integrity checks and the bar on signing off your own work.

## Usage

``` r
calibration_app(project = NULL)
```

## Arguments

- project:

  Optional path of a calibration project to open.

## Value

A Shiny app object; printing it, as at the console, runs it.

## Details

Tabs:

- **Setup**: start a project, register data, select a model structure.

- **Trial**: choose a parent run, adjust parameters, preview the
  hydrograph and scorecard against the parent (drag to zoom,
  double-click to reset), then save with a verdict and reasoning. Notes
  and automatic calibration are here too. Nothing is logged until saved.

- **History**: the calibration path, every run, a side-by-side
  comparison of any two runs, and proposing and validating a candidate.

- **Report**: integrity checks, and building and downloading the report.

- **Sign-off**: for a Steward or Delegated Steward, with the review
  checklist; and reopening.

The app runs on your own machine and reads data files from local or
shared-drive paths. Enter your name and role at the top; they are
recorded in every entry, with your login.

## Examples

``` r
if (interactive() && requireNamespace("shiny", quietly = TRUE)) {
  calibration_app()
}
```
