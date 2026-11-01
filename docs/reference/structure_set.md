# Model structures to compare

A named list of configurations for
[`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md),
each one change from a base structure, so that each comparison answers
one question: does a different soil store, recharge rule or groundwater
store fit this catchment better?

## Usage

``` r
structure_set(names = NULL, base = pdm_presets("standard"))
```

## Arguments

- names:

  Structures to include; by default all eight.

- base:

  Configuration whose area, time step, delay, rainfall factor and other
  settings carry over. Its components are not used: every structure
  starts from the standard PDM's components, so each name means the same
  structure whatever the base.

## Value

A named list of configuration lists.

## Details

|                                                         |                                                                           |
|---------------------------------------------------------|---------------------------------------------------------------------------|
| Name                                                    | Change from the base                                                      |
| `standard`                                              | None: Pareto store, standard recharge, cascade surface, cubic groundwater |
| `rectangular`, `triangular`, `exponential`, `lognormal` | Soil capacity distribution                                                |
| `split`                                                 | Split recharge                                                            |
| `demand`                                                | Demand recharge                                                           |
| `exponential_groundwater`                               | Exponential groundwater store                                             |

Pick a subset by name, or add your own configurations to the list; any
combination is allowed if you have a reason to test it.

## Examples

``` r
names(structure_set())
#> [1] "standard"                "rectangular"            
#> [3] "triangular"              "exponential"            
#> [5] "lognormal"               "split"                  
#> [7] "demand"                  "exponential_groundwater"
structure_set(c("standard", "lognormal"))$lognormal$distribution
#> $type
#> [1] "lognormal"
#> 
#> $meanlog
#> [1] 4.1
#> 
#> $sdlog
#> [1] 0.8
#> 
```
