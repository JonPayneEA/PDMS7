# AR coefficients for forecast updating

Two sources of third-order AR coefficients for error post-processing, in
the Deltares sign convention used by
[`error_updater()`](https://jonpayneea.github.io/PDMS7/reference/error_updater.md)
and by the Environment Agency's IMFS: the error at step t is a1 times
the error at t - 1, plus a2 times that at t - 2, plus a3 times that at
t - 3.

## Usage

``` r
ar_from_response_time(decay_h, dt, first_coefficient = 1.765)

ar_ea_default()
```

## Arguments

- decay_h:

  Principal decay time in hours, typically
  `pdm_response_time()$time_to_peak_h`.

- dt:

  Model time step in hours.

- first_coefficient:

  The fixed first coefficient of the family.

## Value

A named numeric vector `a_1`, `a_2`, `a_3` with attribute `roots`.

## Details

`ar_ea_default()` gives the Environment Agency 2024 default set, defined
for 15-minute steps.

`ar_from_response_time()` builds a member of the continuous default
family from one timescale, the principal decay time. It follows the
published construction of
[`reach.postproc::default_family_ar_parameters()`](https://rdrr.io/pkg/reach.postproc/man/default_family_ar_parameters.html):
the first coefficient is fixed at 1.765; a rapid negative root decays in
a third of a step; the principal root is exp(-1 / decay) with the decay
in steps; the remaining root makes the three sum to the first
coefficient. As in reach.postproc, equating a catchment's time to peak
with the decay of its forecast errors is an approximation, a starting
estimate to be checked against past events, not a derived result. Check
any set with
[`reach.postproc::assess()`](https://rdrr.io/pkg/reach.postproc/man/assess.html)
before operational use.

## See also

[`pdm_response_time()`](https://jonpayneea.github.io/PDMS7/reference/pdm_response_time.md),
[`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md)

## Examples

``` r
ar_ea_default()
#>       a_1       a_2       a_3 
#>  1.765000 -0.726250 -0.040656 
ar_from_response_time(9, dt = 0.25)
#>         a_1         a_2         a_3 
#>  1.76500000 -0.72875763 -0.04078111 
#> attr(,"roots")
#> [1]  0.97260448  0.84218259 -0.04978707
```
