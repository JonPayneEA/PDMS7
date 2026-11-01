# Read a calibration project

`read_project()` gives the project details, status and a
one-row-per-entry table. `project_trials()` lists every run (structure,
trial and automatic calibration) with its parent, changes, scores,
verdict and reasoning. `read_entry()` returns one entry in full, for
example an automatic calibration's table of starts. `read_projects()`
summarises several projects in one table, for example every basin of a
large-sample calibration, with the candidate's headline score on the
calibration and validation windows.

## Usage

``` r
read_project(project)

project_trials(project)

read_entry(project, id)

read_projects(projects)
```

## Arguments

- project:

  Path of a calibration project folder.

- id:

  An entry id, such as 4 or "0004".

- projects:

  Paths of calibration project folders.

## Value

`read_project()`: a list with `path`, `id`, `status` (`open`,
`signed_off` or `reopened`), `project` (the `project_start` fields),
`scorecard` (the latest) and `entries` (a data.table). `read_entry()`:
the entry as a list. `project_trials()` and `read_projects()`:
data.tables.

## See also

[calibration_log](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`verify_project()`](https://jonpayneea.github.io/PDMS7/reference/verify_project.md)
