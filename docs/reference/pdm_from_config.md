# Pdm from config

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
pdm_from_config(config)
```

## Arguments

- config:

  Named model configuration list; unknown keys are rejected.

## Value

A validated FlodePdmModel.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
pdm_from_config(pdm_presets('standard'))
#> <pdmS7::FlodePdmModel>
#>  @ distribution: <pdmS7::FlodeParetoCapacity>
#>  .. @ cmin: num 0
#>  .. @ cmax: num 140
#>  .. @ b   : num 0.4
#>  @ recharge    : <pdmS7::FlodeStandardRecharge>
#>  .. @ kg: num 24
#>  .. @ bg: num 1
#>  .. @ st: num 0
#>  @ surface     : <pdmS7::FlodeCascadeRouting>
#>  .. @ k1: num 2
#>  .. @ k2: num 4
#>  @ groundwater : <pdmS7::FlodePowerRouting>
#>  .. @ k     : num 1e-04
#>  .. @ m     : num 3
#>  .. @ solver: chr "adaptive"
#>  .. @ rtol  : num 1e-08
#>  .. @ atol  : num 1e-10
#>  @ be          : num 1
#>  @ fc          : num 1
#>  @ td          : num 0
#>  @ qc          : num 0
#>  @ area_km2    : num 1
#>  @ dt          : num 1
```
