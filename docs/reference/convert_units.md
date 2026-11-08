# Convert rain, evaporation or flow to the units pdmS7 uses

pdmS7 takes rain and potential evaporation as depths in mm per time
step, and flow in m3/s. `convert_units()` converts from the usual
alternatives:

## Usage

``` r
convert_units(
  x,
  from,
  dt,
  quantity = c("rain", "pet", "flow"),
  plausible = NULL
)
```

## Arguments

- x:

  Numeric series.

- from:

  Units of `x`, or `"auto"`.

- dt:

  Time step in hours.

- quantity:

  `rain`, `pet` or `flow`.

- plausible:

  For `"auto"` with rain or evaporation: the plausible annual total, mm.

## Value

`x` converted, noted.

## Details

|               |                                                                         |
|---------------|-------------------------------------------------------------------------|
| Quantity      | Units accepted                                                          |
| `rain`, `pet` | `mm_per_step`, `mm_per_hour` (an intensity), `mm_per_day`, `m_per_step` |
| `flow`        | `m3s`, `ls` (litres a second), `mld` (megalitres a day)                 |

With `from = "auto"`, the unit is worked out: for rain and evaporation,
the annual total each depth unit implies is compared with a plausible
range, and exactly one must fit; for flow, a mean above 100 is read as
litres a second. The guess is noted, with the totals it was based on, so
a reviewer can check it. Prefer naming the unit when you know it.

## See also

[`fill_gaps()`](https://jonpayneea.github.io/PDMS7/reference/fill_gaps.md),
[`check_inputs()`](https://jonpayneea.github.io/PDMS7/reference/check_inputs.md)

## Examples

``` r
convert_units(c(0, 2, 4), "mm_per_hour", dt = 0.25, quantity = "rain")
#> [1] 0.0 0.5 1.0
#> attr(,"pdm_prep")
#>    step                                        detail
#> 1 units rain from mm_per_hour to mm per step (x 0.25)
convert_units(c(1200, 1500), "ls", dt = 0.25, quantity = "flow")
#> [1] 1.2 1.5
#> attr(,"pdm_prep")
#>    step                         detail
#> 1 units flow from ls to m3/s (x 0.001)
```
