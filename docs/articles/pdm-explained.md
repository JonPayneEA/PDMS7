# PDM explained: from rainfall to river flow

## The idea in plain English

PDM treats a catchment as many small soil stores with different
capacities. Shallow stores fill first. As rain continues, more of the
catchment becomes saturated and produces runoff. The model then delays
that water through fast and slow routing stores before reporting river
flow.

It does **not** map individual fields or hillslopes. A probability
distribution describes how storage capacity varies across the catchment.
The S7 components let you exchange that distribution, the recharge rule
and the routing rule without rewriting the simulation.

![Default pathway: soil runoff feeds fast routing; recharge feeds
groundwater. Split recharge instead divides runoff between both
paths.](pdm-explained_files/figure-html/pdm-diagram-1.png)

Default pathway: soil runoff feeds fast routing; recharge feeds
groundwater. Split recharge instead divides runoff between both paths.

## Units and symbols

| Symbol | Meaning | Unit |
|----|----|----|
| $`p`$, $`e`$, $`d`$, $`v`$ | Rain, actual evaporation, recharge and runoff **depths per interval** | mm |
| $`s`$ | Catchment-average soil water | mm |
| $`c`$ | A local store’s capacity | mm |
| $`C`$ | Common filling level used by the capacity distribution | mm |
| $`F(c)`$ | Fraction of catchment with capacity no greater than $`c`$ | fraction |
| $`X`$, $`u`$, $`q`$ | Routing storage, inflow rate and outflow rate | mm; mm/h; mm/h |
| $`\Delta t`$ | Model interval | hours internally |
| $`A`$ | Catchment area | km² |

[`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
takes integer **minutes**, while component functions take hours. Rain
and PET are interval totals, not mm/hour rates. `qsim_cms` is an
interval average in m³/s; `qsim_end_cms` is flow at the interval end.
Use the series that matches the observations. A factor or coefficient
calibrated hourly is not automatically a daily coefficient.

## 1. How the soil distribution works

For a filling level $`C`$, the mean water stored across the catchment is

``` math
s(C)=\int_0^C [1-F(c)]\,dc, \qquad s_{\max}=E[c].
```

In words: integrate the fraction of stores that can still hold water at
each depth.
[`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md)
returns $`s_{\max}`$, **not** the largest local capacity.
[`storage_from_capacity()`](https://jonpayneea.github.io/PDMS7/reference/storage_from_capacity.md)
evaluates $`s(C)`$;
[`capacity_from_storage()`](https://jonpayneea.github.io/PDMS7/reference/capacity_from_storage.md)
reverses it.
[`capacity_cdf()`](https://jonpayneea.github.io/PDMS7/reference/capacity_cdf.md)
returns $`F(C)`$, the saturated area fraction.

### Five configurable capacity families

Outside bounded supports, CDFs are zero below the lower limit and one
above the upper limit. Let $`a=c_{\min}`$, $`z=c_{\max}`$ and $`w=z-a`$.

| Family / configuration type | CDF inside its support | Mean capacity |
|----|----|----|
| Pareto / `pareto` | $`1-[(z-c)/w]^b`$ | $`a+w/(b+1)`$ |
| Rectangular / `rectangular` | $`(c-a)/w`$ | $`(a+z)/2`$ |
| Symmetric triangular / `triangular` | $`2(c-a)^2/w^2`$ below midpoint; $`1-2(z-c)^2/w^2`$ above | $`(a+z)/2`$ |
| Exponential / `exponential` | $`1-\exp(-c/\mu)`$ for $`c\geq0`$ | $`\mu`$ |
| Lognormal / `lognormal` | $`\Phi((\log c-\mu_L)/\sigma_L)`$ for $`c>0`$ | $`\exp(\mu_L+\sigma_L^2/2)`$ |

$`\Phi`$ is the standard normal CDF. Pareto with `b=0` is a point mass
at `cmax`, not an ordinary density;
[`capacity_pdf()`](https://jonpayneea.github.io/PDMS7/reference/capacity_pdf.md)
deliberately rejects that case. Infinite filling level is a valid
saturated limit for unbounded families. The implementation corrects
apparent normalization/printing errors in the paper’s Appendix A; see
`docs/source-notes.md` in the full project.

``` r
soil <- FlodeParetoCapacity(cmin = 0, cmax = 140, b = 0.4)
capacity_mean(soil) # 100 mm, not 140 mm
#> [1] 100
storage_from_capacity(soil, c(0, 50, 100, 140))
#> [1]   0.00000  46.12835  82.68969 100.00000
```

![For the example Pareto distribution, mean soil storage grows more
slowly than the common filling level as more stores
saturate.](pdm-explained_files/figure-html/capacity-figure-1.png)

For the example Pareto distribution, mean soil storage grows more slowly
than the common filling level as more stores saturate.

## 2. Evaporation, recharge and runoff

Rain is first multiplied by `fc`. With current soil storage $`s`$ and
PET depth $`e_p`$, the requested actual evaporation is

``` math
e_{\mathrm{req}}=e_p\left[1-\left(1-\frac{s}{s_{\max}}\right)^{b_e}\right].
```

Wet soil supplies more of the potential demand. Requests are evaluated
at the start of the interval. To prevent overdrawing the store, this
implementation allocates available water to evaporation first and
recharge second:

``` math
p=f_c p_{\mathrm{input}},\quad e=\min(e_{\mathrm{req}},s+p),\quad
d=\min(d_{\mathrm{req}},\max(0,s+p-e)).
```

The remaining net depth is $`n=p-e-d`$. When $`n>0`$:

``` math
C=s^{-1}(s_{\mathrm{old}}),\quad
s_{\mathrm{new}}=s(C+n),\quad v=n-(s_{\mathrm{new}}-s_{\mathrm{old}}).
```

Whatever cannot increase storage becomes runoff. For $`n\leq0`$, storage
decreases and runoff is zero. The complete model’s water-limiting rules
prevent negative storage; standalone
[`soil_step()`](https://jonpayneea.github.io/PDMS7/reference/soil_step.md)
clips a requested excessive deficit at zero, so do not interpret an
impossible standalone withdrawal as an actual flux.

``` r
soil_step(soil, storage = 50, net_depth = 20)
#> $storage
#> [1] 65.59771
#> 
#> $runoff
#> [1] 4.402291
```

### Three recharge choices

**Standard:** water drains only above threshold $`s_t`$:

``` math
d_{\mathrm{req}}=\frac{\max(0,s-s_t)^{b_g}}{k_g}\Delta t.
```

`kg` has units consistent with the exponent: h·mm$`^{b_g-1}`$, not
always hours.

**Demand:** groundwater deficit controls soil drainage. Let $`X_{\max}`$
be the groundwater storage giving `qsat`, and clip
$`g=(X_{\max}-X)/X_{\max}`$ to \[0,1\]. Then, with
$`d_{\mathrm{sat}}=q_{\mathrm{sat}}\Delta t`$,

``` math
d_{\mathrm{req}}=\left[d_{\mathrm{sat}}+(s_{\max}-d_{\mathrm{sat}})
\min\left(1,(g/\alpha)^\beta\right)\right]\frac{s}{s_{\max}}.
```

This is an interval-depth rule: it is timestep-sensitive and requires
$`q_{\mathrm{sat}}\Delta t\leq s_{\max}`$. It also requires a single
groundwater store with a positive implied $`X_{\max}`$; it cannot use
the two-store cascade.

**Split:** no separate soil drainage. Divide generated runoff into fast
$`\alpha v`$ and slow $`(1-\alpha)v`$ inputs. This changes the diagram’s
connections, not just a coefficient in the standard drainage equation.

## 3. Routing and the reported discharge

Routing answers “when does generated water reach the outlet?”

``` math
\frac{dX}{dt}=u-q(X).
```

| Routing option | Flow law / structure | Main configuration |
|----|----|----|
| Linear | $`q=X/k_b`$ | `linear(kb)` |
| Quadratic | $`q=X^2/k_b`$ | `quadratic(kb)` |
| Cubic | $`q=X^3/k_b`$ | `cubic(kb, solver)` |
| General power | $`q=kX^m`$ | `power(k, m, solver, rtol, atol)` |
| Cascade | $`dX_1/dt=u-X_1/k_1`$; $`dX_2/dt=X_1/k_1-X_2/k_2`$ | `cascade(k1, k2)` |
| Exponential | $`q=\exp(\gamma+aX)`$ | `exponential(a, gamma)` |

Here the notation `linear(kb)` denotes a configuration choice, not an R
function call; the constructor is `linear_routing(kb)`. The exponential
model’s $`X`$ is a **signed log-storage coordinate**, not an ordinary
nonnegative tank. Power routing uses exact solutions where available and
adaptive integration otherwise; the cubic `smith` option reproduces the
report’s approximate recurrence.
[`route_step()`](https://jonpayneea.github.io/PDMS7/reference/route_step.md)
returns a new state, discharged depth and both mean and endpoint rates.
Inputs are treated as constant rates during each routing interval.

After a common outlet delay `td`, conversion to m³/s is

``` math
Q_{\mathrm{mean}}=\frac{A}{3.6}\frac{V_{\mathrm{fast}}+V_{\mathrm{slow}}}{\Delta t}+q_c.
```

Fractional delays split water conservatively between neighbouring
intervals. Delay queues are part of the stored restart state. `qc` is an
external signed outlet adjustment, not a withdrawal from the model
stores.

## Function map and a short run

| Task | Public functions |
|----|----|
| Configure | [`pdm_presets()`](https://jonpayneea.github.io/PDMS7/reference/pdm_presets.md), [`parameter_catalog()`](https://jonpayneea.github.io/PDMS7/reference/parameter_catalog.md), [`read_pdm_config()`](https://jonpayneea.github.io/PDMS7/reference/read_pdm_config.md), [`load_pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/load_pdm_model.md), [`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md), [`pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/pdm_model.md) |
| Inspect soil | [`capacity_cdf()`](https://jonpayneea.github.io/PDMS7/reference/capacity_cdf.md), [`capacity_pdf()`](https://jonpayneea.github.io/PDMS7/reference/capacity_pdf.md), [`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md), [`storage_from_capacity()`](https://jonpayneea.github.io/PDMS7/reference/storage_from_capacity.md), [`capacity_from_storage()`](https://jonpayneea.github.io/PDMS7/reference/capacity_from_storage.md), [`soil_step()`](https://jonpayneea.github.io/PDMS7/reference/soil_step.md) |
| Inspect pathways | [`recharge_depth()`](https://jonpayneea.github.io/PDMS7/reference/recharge_depth.md), [`routing_flow()`](https://jonpayneea.github.io/PDMS7/reference/routing_flow.md), [`storage_for_flow()`](https://jonpayneea.github.io/PDMS7/reference/storage_for_flow.md), [`route_step()`](https://jonpayneea.github.io/PDMS7/reference/route_step.md), [`transfer_coefficients()`](https://jonpayneea.github.io/PDMS7/reference/transfer_coefficients.md) |
| Run and restart | [`initial_state()`](https://jonpayneea.github.io/PDMS7/reference/initial_state.md), [`pdm_step()`](https://jonpayneea.github.io/PDMS7/reference/pdm_step.md), [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md), [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md), [`spin_up()`](https://jonpayneea.github.io/PDMS7/reference/spin_up.md) |
| Fit and evaluate | [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md), [`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md), [`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md), [`pareto_front()`](https://jonpayneea.github.io/PDMS7/reference/pareto_front.md) |
| Existing updating | [`state_updater()`](https://jonpayneea.github.io/PDMS7/reference/state_updater.md), [`correct_state()`](https://jonpayneea.github.io/PDMS7/reference/correct_state.md), [`error_updater()`](https://jonpayneea.github.io/PDMS7/reference/error_updater.md), [`fit_error_updater()`](https://jonpayneea.github.io/PDMS7/reference/fit_error_updater.md), [`update_forecast()`](https://jonpayneea.github.io/PDMS7/reference/update_forecast.md) |

``` r
config <- pdm_presets("standard")
config$area_km2 <- 44
flow <- sim_pdm(c(0, 10, 5, 0), rep(0.05, 4), config, timestep_min = 60L)
flow[, c("qsim_cms", "soil_moisture_mm", "balance_error_mm"), with = FALSE]
#>       qsim_cms soil_moisture_mm balance_error_mm
#>          <num>            <num>            <num>
#> 1: 0.002762403         47.89167     7.105427e-15
#> 2: 0.352909552         54.39355     0.000000e+00
#> 3: 1.776898979         56.54137     1.421085e-14
#> 4: 3.198890757         54.15721     0.000000e+00
attr(flow, "water_balance")
#>     residual_mm max_abs_step_mm 
#>    2.131628e-14    1.421085e-14
```

Presets other than identified paper examples are illustrative, not
calibrated catchments.
[`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
initializes half-full soil by default; explicit states or an adequate
spin-up period may be needed.
[`spin_up()`](https://jonpayneea.github.io/PDMS7/reference/spin_up.md)
repeats forcing; it does not automatically prove convergence. Do not
change structure/timestep while reusing a checkpoint.

The existing updating functions alter model states or forecast errors;
state correction needs zero outlet delay and reports added/removed
water. They are not a river-network or ensemble-assimilation system.
Those extensions remain future work.

## What the balance check does, and does not, prove

The per-step residual is

``` math
\epsilon=\text{old storage}+p-e-\text{natural outflow}-\text{new storage}.
```

“Storage” includes soil, routing states and water in delay queues. A
near-zero residual checks accounting. It does **not** establish good
forecasts, correct forcing, a calibrated parameter set, or operational
approval.

### Source

Moore, R. J. (2007), *The PDM rainfall-runoff model*, HESS 11, 483–499,
[doi:10.5194/hess-11-483-2007](https://doi.org/10.5194/hess-11-483-2007).
Equations above describe this library’s implementation; its source notes
identify the Appendix A corrections and additional numerical
conventions.
