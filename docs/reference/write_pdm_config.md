# Write a PDM configuration to a YAML file

Writes a configuration list so that
[`read_pdm_config()`](https://jonpayneea.github.io/PDMS7/reference/read_pdm_config.md)
reads back exactly the same numbers.
[`yaml::write_yaml()`](https://rdrr.io/pkg/yaml/man/write_yaml.html)
rounds to seven significant figures by default, which can change a
calibrated model; this function writes each number with the fewest
digits that reproduce it exactly.

## Usage

``` r
write_pdm_config(config, path)
```

## Arguments

- config:

  A configuration list accepted by
  [`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md).

- path:

  File to write.

## Value

`path`, invisibly.

## Examples

``` r
path <- tempfile(fileext = ".yml")
config <- pdm_presets("standard")
config$fc <- 1 / 3
write_pdm_config(config, path)
identical(read_pdm_config(path)$fc, 1 / 3)
#> [1] TRUE
```
