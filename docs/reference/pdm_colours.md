# The pdmS7 colours

Every standard pdmS7 plot uses the Okabe-Ito colours, which stay
distinct with the common forms of colour blindness, and gives each
colour one meaning:

## Usage

``` r
pdm_colours(roles = NULL, alpha = 1)

pdm_palette(n)
```

## Arguments

- roles:

  Roles to return; by default all.

- alpha:

  Opacity, from 0 to 1.

- n:

  Number of colours.

## Value

A named character vector of hex colours.

## Details

|               |                |                                          |
|---------------|----------------|------------------------------------------|
| Role          | Colour         | Drawn as                                 |
| `observed`    | black          | measured flow                            |
| `simulated`   | blue           | the model                                |
| `rain`        | sky blue       | bars hanging from the top                |
| `alternative` | vermillion     | a second run, or a change ("after")      |
| `calibration` | grey           | a light band over the calibration window |
| `validation`  | orange         | a light band over the validation window  |
| `threshold`   | reddish purple | dashed lines at warning thresholds       |
| `flag`        | vermillion     | markers on anything flagged              |
| `reference`   | grey           | guide lines                              |

Use `pdm_colours()` in your own figures so they match. `pdm_palette()`
gives colours in a fixed order for plots with several series of equal
standing, such as methods or catchments.

## See also

[`theme_pdm()`](https://jonpayneea.github.io/PDMS7/reference/theme_pdm.md),
[`pdm_save()`](https://jonpayneea.github.io/PDMS7/reference/pdm_save.md)

## Examples

``` r
pdm_colours()
#>    observed   simulated        rain alternative calibration  validation 
#>   "#000000"   "#0072B2"   "#56B4E9"   "#D55E00"   "#999999"   "#E69F00" 
#>   threshold        flag   reference        text        grid 
#>   "#CC79A7"   "#D55E00"   "#999999"   "#333333"   "#E5E5E5" 
pdm_colours(c("observed", "simulated"))
#>  observed simulated 
#> "#000000" "#0072B2" 
pdm_palette(4)
#>         blue   vermillion bluish_green       orange 
#>    "#0072B2"    "#D55E00"    "#009E73"    "#E69F00" 
```
