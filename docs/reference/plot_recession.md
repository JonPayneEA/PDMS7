# Plot a recession analysis

The recession points and bins on logarithmic axes, with the fitted line
and, for reference, lines of the slopes of the linear, cubic and
exponential stores through the middle of the bins. A second analysis,
such as one of simulated flow, is drawn over the first.

## Usage

``` r
plot_recession(x, y = NULL, main = "Recession analysis")
```

## Arguments

- x:

  A result of
  [`recession_analysis()`](https://jonpayneea.github.io/PDMS7/reference/recession_analysis.md).

- y:

  Optional second result to compare, drawn in orange.

- main:

  Plot title.

## Value

`x`, invisibly.

## Examples

``` r
# See recession_analysis().
```
