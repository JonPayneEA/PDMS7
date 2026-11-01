# Read a calibration project

`read_project()` gives the project details, status and a
one-row-per-entry table. `project_trials()` lists every run (structure,
trial and automatic calibration) with its parent, changes, scores,
verdict and reasoning. `read_projects()` summarises several projects in
one table, for example every project in a team folder.

## Usage

``` r
read_project(project)

project_trials(project)

read_projects(projects)
```

## Arguments

- project:

  Path of a calibration project folder.

- projects:

  Paths of calibration project folders.

## Value

`read_project()`: a list with `path`, `id`, `status` (`open`,
`signed_off` or `reopened`), `project` (the `project_start` fields),
`scorecard` (the latest) and `entries` (a data.table).
`project_trials()` and `read_projects()`: data.tables.

## See also

[calibration_log](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
[`verify_project()`](https://jonpayneea.github.io/PDMS7/reference/verify_project.md)
