# Verify a calibration project

Checks that the log is complete and unaltered and that its evidence
still stands:

## Usage

``` r
verify_project(project, rerun = FALSE)
```

## Arguments

- project:

  Path of a calibration project folder.

- rerun:

  If `TRUE`, repeat every run. Each takes about as long as one model
  run.

## Value

A data.table with one row per check: `check`, `entry`, `ok` and
`detail`.

## Details

- **numbering**: entries are numbered 1, 2, 3 with no gaps, and each
  file name matches its content;

- **chain**: each entry holds the MD5 of the one before, so an edit,
  deletion or insertion breaks the chain at that point;

- **data**: every registered file exists and matches its MD5;

- **series**: every saved series file matches its MD5;

- **rerun** (optional): every run is repeated and its output compared
  with the recorded checksum. A mismatch reports which software has
  changed since the entry was written.

Alteration of the newest entry is caught by the next entry, by sign-off,
or by version control; keep projects under version control or on a
managed drive.

## See also

[calibration_log](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`read_project()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
