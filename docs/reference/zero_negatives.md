# Set negative values to zero

Negative rain is a data error. Negative evaporation is not always one
(MOSES PE goes slightly negative when condensation exceeds evaporation,
and pdmS7 takes it as it is), so use this on evaporation only if your
source should never be negative. The count, smallest value and total are
noted.

## Usage

``` r
zero_negatives(x, label = "series")
```

## Arguments

- x:

  Numeric series.

- label:

  Name of the series in the note.

## Value

`x` with negative values set to zero, noted.

## See also

[`fill_gaps()`](https://jonpayneea.github.io/PDMS7/reference/fill_gaps.md),
[`preparation_notes()`](https://jonpayneea.github.io/PDMS7/reference/preparation_notes.md)

## Examples

``` r
zero_negatives(c(0.2, -0.01, 0.5), label = "rain")
#> [1] 0.2 0.0 0.5
#> attr(,"pdm_prep")
#>        step                                                            detail
#> 1 negatives rain: 1 negative values (smallest -0.01, total -0.01) set to zero
```
