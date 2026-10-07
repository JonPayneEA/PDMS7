# Pdm presets

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
pdm_presets(name = NULL)
```

## Arguments

- name:

  Character preset name; NULL lists available presets.

## Value

A character vector of names when name is NULL; otherwise a configuration
list.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
pdm_presets()
#>  [1] "standard"              "paper_cubic"           "figure5"              
#>  [4] "rectangular"           "triangular"            "exponential"          
#>  [7] "lognormal"             "demand"                "split"                
#> [10] "linear_groundwater"    "quadratic_groundwater" "general_power"        
#> [13] "exponential_routing"  
```
