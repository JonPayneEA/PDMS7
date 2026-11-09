# The path of a calibration through its stages

Gathers the automatic calibrations of a project in the order they ran,
with each stage's scores, every start's result, and the candidate's
scores in each window, for three standard plots:

## Usage

``` r
calibration_path(project)

# S3 method for class 'pdm_calibration_path'
plot(x, type = c("stages", "starts", "windows"), ...)

# S3 method for class 'pdm_calibration_path'
autoplot(object, type = c("stages", "starts", "windows"), ...)
```

## Arguments

- project:

  A calibration project folder.

- x, object:

  A `pdm_calibration_path`.

- type:

  One of the plots above.

- ...:

  Not used.

## Value

`calibration_path()`: a `pdm_calibration_path` list with `stages` (one
row per automatic calibration entry), `starts` (one row per start) and
`windows` (the candidate's scores by window, or `NULL`).
[`plot()`](https://rdrr.io/r/graphics/plot.default.html): `x`,
invisibly. `autoplot()`: a ggplot.

## Details

|           |                                                                        |
|-----------|------------------------------------------------------------------------|
| `type`    | Shows                                                                  |
| `stages`  | NSE, log NSE and volume error after each stage                         |
| `starts`  | each start's objective in each stage, the best filled                  |
| `windows` | the candidate's scores in the calibration, validation and test windows |

## See also

[`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md),
[`calibration_checks()`](https://jonpayneea.github.io/PDMS7/reference/calibration_checks.md)

## Examples

``` r
if (FALSE) { # \dontrun{
path <- calibration_path("projects/beggearn_huish")
plot(path)
plot(path, type = "windows")
} # }
```
