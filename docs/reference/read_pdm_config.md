# Read pdm config

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
read_pdm_config(path)
```

## Arguments

- path:

  Character scalar identifying a YAML file. Executable expressions are
  rejected.

## Value

A validated named configuration list.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
read_pdm_config(system.file('config', 'standard.yml', package = 'pdmS7'))
#> $distribution
#> $distribution$type
#> [1] "pareto"
#> 
#> $distribution$cmin
#> [1] 0
#> 
#> $distribution$cmax
#> [1] 140
#> 
#> $distribution$b
#> [1] 0.4
#> 
#> 
#> $recharge
#> $recharge$type
#> [1] "standard"
#> 
#> $recharge$kg
#> [1] 24
#> 
#> $recharge$bg
#> [1] 1
#> 
#> $recharge$st
#> [1] 0
#> 
#> 
#> $surface
#> $surface$type
#> [1] "cascade"
#> 
#> $surface$k1
#> [1] 2
#> 
#> $surface$k2
#> [1] 4
#> 
#> 
#> $groundwater
#> $groundwater$type
#> [1] "cubic"
#> 
#> $groundwater$kb
#> [1] 10000
#> 
#> $groundwater$solver
#> [1] "adaptive"
#> 
#> 
#> $be
#> [1] 1
#> 
#> $fc
#> [1] 1
#> 
#> $td
#> [1] 0
#> 
#> $qc
#> [1] 0
#> 
#> $area_km2
#> [1] 1
#> 
#> $dt
#> [1] 1
#> 
```
