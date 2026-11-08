# The pdmS7 ggplot2 theme

A light theme with horizontal grid lines only, the legend below the plot
and plain titles. Every `autoplot()` method in pdmS7 uses it; add it to
your own ggplot2 figures so they match. Needs the ggplot2 package.

## Usage

``` r
theme_pdm(base_size = 11, base_family = "")
```

## Arguments

- base_size:

  Base font size in points.

- base_family:

  Font family.

## Value

A ggplot2 theme.

## See also

[`pdm_colours()`](https://jonpayneea.github.io/PDMS7/reference/pdm_colours.md)

## Examples

``` r
if (requireNamespace("ggplot2", quietly = TRUE)) {
  ggplot2::ggplot(data.frame(x = 1:10, y = cumsum(rnorm(10))), ggplot2::aes(x, y)) +
    ggplot2::geom_line(colour = pdm_colours("simulated")) +
    theme_pdm()
}
```
