# Save a pdmS7 figure at a standard size

Writes a figure to PNG, PDF or SVG, chosen by the file's extension, at
one of the standard sizes:

## Usage

``` r
pdm_save(
  plot,
  file,
  preset = "screen",
  width = NULL,
  height = NULL,
  dpi = NULL,
  ...
)
```

## Arguments

- plot:

  What to draw.

- file:

  Output path ending in `.png`, `.pdf` or `.svg`.

- preset:

  One of the presets above.

- width, height:

  Size in inches, overriding the preset.

- dpi:

  Resolution for PNG, overriding the preset.

- ...:

  Passed to [`plot()`](https://rdrr.io/r/graphics/plot.default.html)
  when `plot` is an object, such as `type = "duration"`.

## Value

`file`, invisibly.

## Details

|                  |               |            |       |                            |
|------------------|---------------|------------|-------|----------------------------|
| Preset           | Size (inches) | Resolution | Text  | Use                        |
| `screen`         | 8 x 4.5       | 110 dpi    | 11 pt | screens, articles, the app |
| `report`         | 6.3 x 3.6     | 300 dpi    | 10 pt | full width of an A4 report |
| `report_half`    | 3.1 x 2.6     | 300 dpi    | 8 pt  | half width of an A4 report |
| `slide`          | 10 x 5.6      | 200 dpi    | 14 pt | 16:9 slides                |
| `journal_single` | 3.35 x 2.6    | 600 dpi    | 8 pt  | one journal column         |
| `journal_double` | 6.9 x 3.6     | 600 dpi    | 9 pt  | two journal columns        |

`plot` may be a ggplot (from `autoplot()`), any object with a
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) method, such as
a
[`pdm_series()`](https://jonpayneea.github.io/PDMS7/reference/pdm_series.md),
or a function of no arguments that draws in base graphics.

## See also

[`pdm_colours()`](https://jonpayneea.github.io/PDMS7/reference/pdm_colours.md),
[`theme_pdm()`](https://jonpayneea.github.io/PDMS7/reference/theme_pdm.md)

## Examples

``` r
s <- pdm_series(simulated = sin(1:200 / 10) + 2, observed = sin(1:200 / 10 + 0.2) + 2)
f <- tempfile(fileext = ".png")
pdm_save(s, f, preset = "report")
file.exists(f)
#> [1] TRUE
```
