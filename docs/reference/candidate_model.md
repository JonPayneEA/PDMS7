# The model of a project's candidate

The model of a project's candidate

## Usage

``` r
candidate_model(project, entry = NULL)
```

## Arguments

- project:

  A calibration project folder.

- entry:

  Model entry; by default the current candidate.

## Value

A PDM model, as
[`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md)
builds it.

## See also

[`read_entry()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md),
[`project_series()`](https://jonpayneea.github.io/PDMS7/reference/pdm_series.md)

## Examples

``` r
if (FALSE) { # \dontrun{
model <- candidate_model("projects/beggearn_huish")
} # }
```
