# Create FlodeStateUpdater

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
FlodeStateUpdater(
  scheme = character(0),
  gb = integer(0),
  gs = integer(0),
  gg = integer(0),
  beta1 = integer(0),
  beta2 = integer(0),
  soil_proportional = logical(0)
)
```

## Arguments

- scheme:

  State correction rule: proportional, super_proportional, or
  non_proportional.

- gb:

  Nonnegative dimensionless baseflow correction gain.

- gs:

  Nonnegative dimensionless surface-flow correction gain.

- gg:

  Nonnegative soil-storage correction gain in hours; zero disables soil
  correction.

- beta1:

  Positive surface-flow weighting in super-proportional correction.

- beta2:

  Groundwater weighting, at least one, in super-proportional correction.

- soil_proportional:

  Logical scalar; use the baseflow proportion for soil correction if
  TRUE.

## Value

An S7 component object.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
FlodeStateUpdater('proportional', 1, 1, 0, 10, 1.1, TRUE)
#> <pdmS7::FlodeStateUpdater>
#>  @ scheme           : chr "proportional"
#>  @ gb               : num 1
#>  @ gs               : num 1
#>  @ gg               : num 0
#>  @ beta1            : num 10
#>  @ beta2            : num 1.1
#>  @ soil_proportional: logi TRUE
```
