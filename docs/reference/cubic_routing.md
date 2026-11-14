# Cubic routing

Component of the configurable Moore (2007) rainfall-runoff framework.
The store releases `q = S^3 / kb` (mm/h), so in the compiled core and in
[`power_routing()`](https://jonpayneea.github.io/PDMS7/reference/power_routing.md)
`k = 1 / kb`.

## Usage

``` r
cubic_routing(kb = 10000, solver = "adaptive")
```

## Arguments

- kb:

  Positive reciprocal rate coefficient: hour mm^(m-1).

- solver:

  Character scalar: adaptive or smith. The Smith approximation requires
  m = 3.

## Value

An S7 component object.

## Details

**Solvers.** `"adaptive"` integrates `dS/dt = u - S^3 / kb` over each
step by RK4 with step doubling to a tight tolerance. `"smith"` uses
Smith's closed-form step (Moore, 2007, Eq. 24; PDM for PCs), kept for
compatibility with published and PDM for PCs results. It is an
approximation, not an exact solution: it linearises the outflow about
the storage at the start of the step, so its error grows with the step
and with how far the storage moves within it. From an empty store it
releases nothing in the first step (with `S0 = 0`, `u = 1` mm/h,
`kb = 1` and a one-hour step it ends at 1 mm, where the continuous
equation gives 0.823 mm and releases 0.177 mm). It converges to the
continuous solution as the step shrinks. Use the adaptive solver unless
matching PDM for PCs matters more than accuracy, and prefer short steps
with Smith.

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
cubic_routing(kb = 10000)
#> <pdmS7::FlodePowerRouting>
#>  @ k     : num 1e-04
#>  @ m     : num 3
#>  @ solver: chr "adaptive"
#>  @ rtol  : num 1e-08
#>  @ atol  : num 1e-10
```
