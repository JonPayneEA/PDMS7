# Build the calibration report

Writes a report generated entirely from the log: never edit it by hand,
rebuild it. The HTML file is self-contained, with its figures embedded,
so it can be emailed or attached to a review. A Markdown copy with
separate figure files suits projects kept under version control.

## Usage

``` r
build_report(
  project,
  output = file.path(project, "report"),
  rerun = TRUE,
  sensitivity = NULL,
  sensitivity_range = 0.5,
  sensitivity_steps = 9L
)
```

## Arguments

- project:

  Path of a calibration project folder.

- output:

  Folder to write to; created if needed.

- rerun:

  If `TRUE`, the integrity section reruns every logged run.

- sensitivity:

  `TRUE`, `FALSE`, or `NULL` for on when the latest candidate has been
  validated, which is when a Steward reviews the project.

- sensitivity_range, sensitivity_steps:

  Range of the multiplicative variation and the number of points per
  parameter.

## Value

The path of `report.html`, invisibly.

## Details

Sections, in reading order: project and roles; integrity (any failure is
flagged at the top); data and scoring windows; model structure; the
calibration path, as a tree of runs and a table of every run with its
changes, scores, verdict and reasoning; the candidate, with hydrographs,
flow-duration curves and a scatter for both windows; parameter
sensitivity; sign-off history; and an appendix with the final
configuration and the entry checksums.

Sensitivity varies each nonzero numeric parameter of the candidate, one
at a time, by factors from `1 - sensitivity_range` to
`1 + sensitivity_range`, and scores the headline metric on the
calibration window. A flat curve means the data do not determine that
parameter. It costs `sensitivity_steps` model runs per parameter.

## See also

[calibration_log](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`verify_project()`](https://jonpayneea.github.io/PDMS7/reference/verify_project.md)
