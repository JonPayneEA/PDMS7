# Parameter catalog

Component of the configurable Moore (2007) rainfall-runoff framework.

## Usage

``` r
parameter_catalog()
```

## Value

A data.frame of parameters, units, domains, examples, equation
references, and provenance.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
head(parameter_catalog())
#>   component parameter paper_symbol units        domain example
#> 1     model        fc           fc     1           >=0       1
#> 2     model        td           td     h           >=0       0
#> 3     model        qc           qc  m3/s finite signed       0
#> 4     model  area_km2            A   km2            >0       1
#> 5     model        dt      Delta t     h            >0       1
#> 6     model        be           be     1            >0       1
#>                                        reference          provenance
#> 1                                        Table 1        illustrative
#> 2 Table 1; output-lag convention in source notes        illustrative
#> 3                                        Table 1        illustrative
#> 4                          Eq 3; unit conversion       user supplied
#> 5                        Eq 5; constant interval       user supplied
#> 6                     Eq 8; usual values 1 and 2 paper common choice
```
