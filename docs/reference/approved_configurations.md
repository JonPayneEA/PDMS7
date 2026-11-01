# List the configurations approved in a register

A register names the calibration projects whose signed-off
configurations count as approved: either a YAML file with a `projects:`
list of folders (relative to the file), or a character vector of
folders. Every sign-off in those projects is listed with its
fingerprint. A sign-off is `current` when it is the project's latest
decision, and `superseded` when the project was later reopened or signed
off again.

## Usage

``` r
approved_configurations(
  register = .setting("pdmS7.register", "PDMS7_REGISTER")
)
```

## Arguments

- register:

  Path of a register YAML file, or project folders. Defaults to the
  `pdmS7.register` option or `PDMS7_REGISTER`.

## Value

A data.table: `project`, `path`, `entry`, `fingerprint`, `status`,
`signed_off_by`, `signed_off_at`. Unreadable projects are listed with
status `unreadable`.

## Details

Set `options(pdmS7.register = "path/to/register.yml")` or the
environment variable `PDMS7_REGISTER`, and the run log marks every run
as `approved`, `superseded` or `unapproved`. Runs are never blocked.

## See also

[`pdm_fingerprint()`](https://jonpayneea.github.io/PDMS7/reference/pdm_fingerprint.md),
[`read_run_log()`](https://jonpayneea.github.io/PDMS7/reference/read_run_log.md),
[calibration_log](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
