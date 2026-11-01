# Fingerprint a model configuration

An MD5 checksum of every component, parameter, area and time step of a
model. Two models share a fingerprint exactly when they would produce
the same simulation, however they were built: from a configuration list,
a YAML file, a preset or code. The run log and the approval register use
it to recognise a signed-off parameter set.

## Usage

``` r
pdm_fingerprint(x)
```

## Arguments

- x:

  A `FlodePdmModel` or a configuration list accepted by
  [`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md).

## Value

A 32-character MD5 string.

## Examples

``` r
pdm_fingerprint(pdm_presets("standard"))
#> [1] "63ffbc4eaec1be4bd83a1d7d6c2d3155"
identical(pdm_fingerprint(pdm_presets("standard")),
          pdm_fingerprint(pdm_from_config(pdm_presets("standard"))))
#> [1] TRUE
```
