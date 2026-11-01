# Model equations

This page is the reference: every equation pdmS7 implements, with Moore
(2007) equation numbers for the PDM; the snow model follows equations
2.1 to 2.8 of the Institute of Hydrology PACK report. Notes mark where
the implementation interprets or corrects the source. For what the
equations *mean*, start with [How the PDM
works](https://jonpayneea.github.io/PDMS7/articles/pdm-explained.md) and
[How the snow model
works](https://jonpayneea.github.io/PDMS7/articles/snowpack-explained.md).

## Units and symbols

All depths are millimetres averaged over the catchment; time is in hours
internally.

| Symbol             | Meaning                                                           | Unit           |
|--------------------|-------------------------------------------------------------------|----------------|
| $p$, $e$, $d$, $v$ | Rain, actual evaporation, recharge and runoff depths per interval | mm             |
| $s$                | Catchment-average soil water                                      | mm             |
| $c$                | A local store’s capacity                                          | mm             |
| $C$                | Common filling level of the stores                                | mm             |
| $F(c)$             | Fraction of the catchment with capacity no greater than $c$       | fraction       |
| $X$, $u$, $q$      | Routing storage, inflow rate and outflow rate                     | mm; mm/h; mm/h |
| $\Delta t$         | Model interval                                                    | h              |
| $A$                | Catchment area                                                    | km²            |

Rain and potential evaporation are interval totals, not rates. `q_m3s`
is the mean flow over the interval; `q_end_m3s` is the flow at its end.

## PDM

### Soil moisture: the capacity distribution (Eq. 2-3, 7, 9, 18-20)

For a filling level $C$, the fraction of the catchment that is saturated
is $F(C)$, and the mean water stored across the catchment is

$$s(C) = \int_{0}^{C}\left\lbrack 1 - F(c) \right\rbrack\, dc,\qquad s_{\max} = E\lbrack c\rbrack.$$

[`capacity_cdf()`](https://jonpayneea.github.io/PDMS7/reference/capacity_cdf.md)
returns $F(C)$;
[`storage_from_capacity()`](https://jonpayneea.github.io/PDMS7/reference/storage_from_capacity.md)
evaluates $s(C)$ and
[`capacity_from_storage()`](https://jonpayneea.github.io/PDMS7/reference/capacity_from_storage.md)
inverts it;
[`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md)
returns $s_{\max}$, the mean capacity, which is not the largest local
capacity.

With $a = c_{\min}$, $z = c_{\max}$ and $w = z - a$, the five capacity
families are:

| Family (`type`)                     | CDF inside its support                                                      | Mean capacity                                   |
|-------------------------------------|-----------------------------------------------------------------------------|-------------------------------------------------|
| Pareto (`pareto`)                   | $1 - \left\lbrack (z - c)/w \right\rbrack^{b}$                              | $a + w/(b + 1)$                                 |
| Rectangular (`rectangular`)         | $(c - a)/w$                                                                 | $(a + z)/2$                                     |
| Symmetric triangular (`triangular`) | $2(c - a)^{2}/w^{2}$ below the midpoint; $1 - 2(z - c)^{2}/w^{2}$ above     | $(a + z)/2$                                     |
| Exponential (`exponential`)         | $1 - \exp( - c/\mu)$ for $c \geq 0$                                         | $\mu$                                           |
| Lognormal (`lognormal`)             | $\Phi\left( \left( \log c - \mu_{L} \right)/\sigma_{L} \right)$ for $c > 0$ | $\exp\left( \mu_{L} + \sigma_{L}^{2}/2 \right)$ |

$\Phi$ is the standard normal CDF. CDFs are zero below and one above a
bounded support. Pareto with $b = 0$ is a point mass at $c_{\max}$. The
printed Appendix A formulas for the rectangular and triangular families
assume $c_{\min} = 0$; pdmS7 uses the general forms above. The
triangular and lognormal storage functions are inverted exactly (cubic
solution, and Newton iteration from a bracket); see `source-notes.md`.

### Evaporation, recharge and runoff (Eq. 5-8, 10, 15-17)

Rain is first multiplied by the rainfall factor:
$p = f_{c}\, p_{input}$. With soil storage $s$ at the start of the
interval and potential evaporation $e_{p}$:

$$e_{req} = e_{p}\left\lbrack 1 - \left( 1 - \frac{s}{s_{\max}} \right)^{b_{e}} \right\rbrack.\qquad\text{(Eq. 8)}$$

Evaporation is allocated first and recharge second, so neither can
overdraw the store:

$$e = \min\left( e_{req},\, s + p \right),\qquad d = \min\left( d_{req},\,\max(0,\, s + p - e) \right).$$

The net depth $n = p - e - d$ fills the stores. When $n > 0$,

$$C = s^{- 1}\left( s_{old} \right),\quad s_{new} = s(C + n),\quad v = n - \left( s_{new} - s_{old} \right).\qquad\text{(Eq. 15-17)}$$

Whatever cannot be stored becomes direct runoff $v$. When $n \leq 0$
storage falls and runoff is zero.

### Recharge (Eq. 10-13)

**Standard** recharge drains soil water above a threshold $s_{t}$:

$$d_{req} = \frac{\max\left( 0,\, s - s_{t} \right)^{b_{g}}}{k_{g}}\,\Delta t.\qquad\text{(Eq. 10)}$$

$k_{g}$ has units h·mm$^{b_{g} - 1}$, which are hours only when
$b_{g} = 1$.

**Demand** recharge depends on the groundwater deficit. With $X_{\max}$
the groundwater storage giving outflow $q_{sat}$,
$g = \min\left( 1,\max\left( 0,\left( X_{\max} - X \right)/X_{\max} \right) \right)$
and $d_{sat} = q_{sat}\Delta t$:

$$d_{req} = \left\lbrack d_{sat} + \left( s_{\max} - d_{sat} \right)\min\left( 1,(g/\alpha)^{\beta} \right) \right\rbrack\frac{s}{s_{\max}}.\qquad\text{(Eq. 11-13)}$$

This is written as a depth per interval, so it depends on the time step,
and it needs $q_{sat}\Delta t \leq s_{\max}$ and a single groundwater
store.

**Split** recharge has no soil drainage: direct runoff is divided,
$\alpha v$ to the surface store and $(1 - \alpha)v$ to groundwater.

### Routing (Eq. 21-27)

Each routing store obeys

$$\frac{dX}{dt} = u - q(X).\qquad\text{(Eq. 21-23)}$$

| Option      | Outflow law                                                                    | Notes                                                       |
|-------------|--------------------------------------------------------------------------------|-------------------------------------------------------------|
| Linear      | $q = X/k_{b}$                                                                  | Exact solution                                              |
| Quadratic   | $q = X^{2}/k_{b}$                                                              | Exact solution                                              |
| Cubic       | $q = X^{3}/k_{b}$                                                              | Adaptive integration; optional Smith recurrence (Eq. 24-25) |
| Power       | $q = kX^{m}$                                                                   | Adaptive integration (Eq. 21-23)                            |
| Cascade     | ${\dot{X}}_{1} = u - X_{1}/k_{1}$, ${\dot{X}}_{2} = X_{1}/k_{1} - X_{2}/k_{2}$ | Exact two-store solution (Eq. 26-27)                        |
| Exponential | $q = \exp(\gamma + aX)$                                                        | $X$ is a signed log-storage coordinate, not a tank          |

Inflow is constant within an interval. The Smith recurrence is accurate
only for steps up to about an hour; see [Choosing model
components](https://jonpayneea.github.io/PDMS7/articles/model-options.md).

### Delay and discharge

After an outlet delay $t_{d}$ (fractional delays split water between
neighbouring intervals), the mean flow is

$$Q_{mean} = \frac{A}{3.6}\,\frac{V_{fast} + V_{slow}}{\Delta t} + q_{c},$$

where $V$ are the routed depths in mm over the interval and $q_{c}$ is a
constant external adjustment in m³/s that does not draw on the model’s
stores.

### Water balance

$$\epsilon = \text{old storage} + p - e - \text{natural outflow} - \text{new storage},$$

with storage including the soil, routing stores and water in the delay
queue. pdmS7 reports $\epsilon$ for every step; it is zero to rounding.

### Forecast updating (Eq. 28-42)

State correction (Eq. 28-30) distributes the flow error at the forecast
origin between the surface and groundwater stores, with gains, in
proportional, super-proportional or non-proportional form; ARMA error
prediction (Eq. 31-42) forecasts the error series in additive or log
form, with pdmS7’s `ar` equal to $- \phi$ in Moore’s notation. See
[Forecast
updating](https://jonpayneea.github.io/PDMS7/articles/forecast-updating.md).

## PACK snow model

### Rain or snow

With corrected precipitation $p$, temperature $T$ and snow threshold
$T_{s}$:

$$p_{snow} = \begin{cases}
{p,} & {T < T_{s}} \\
{0,} & {T \geq T_{s}}
\end{cases},\qquad p_{rain} = p - p_{snow}.$$

New snow enters the dry store $W$ and restores full cover.

### Melt

With snow-covered fraction $F$, melt factor $f$, melt threshold $T_{m}$
and internal step $h$:

$$m = \min\left( W + p_{snow},\; Ff\max\left( 0,T - T_{m} \right)\, h \right),\qquad W_{new} = W + p_{snow} - m.$$

### Liquid water and drainage

Rain on covered ground and meltwater enter the wet store $S$:

$$S\prime = S + Fp_{rain} + m,\qquad S_{c} = r\,\left( S\prime + W_{new} \right).$$

$$D = \begin{cases}
{0,} & {T < T_{c}} \\
{\min\{ S\prime,\; h\left\lbrack k_{1}S\prime + k_{2}\max\left( S\prime - S_{c},0 \right) \right\rbrack\},} & {T \geq T_{c}}
\end{cases}$$

$$S_{new} = S\prime - D,\qquad p_{effective} = D + (1 - F)\, p_{rain}.$$

Cold weather stops drainage but does not refreeze liquid water.

### Snow cover (PACK Figure 2.2)

With total water content $\theta = W + S$ and $\theta_{c}$ the content
for complete cover:

$$F_{0}(\theta) = \min\left( 1,\frac{\log(1 + \theta)}{\log\left( 1 + \theta_{c} \right)} \right).$$

After fresh snow, cover returns to $F_{0}$ along a path anchored at the
previous content $\theta_{a}$ and cover $F_{a}$, over the final fraction
$\alpha$ of the fresh-snow excursion $N$:

$$F(\theta) = \max\left\lbrack F_{0}(\theta),\; F_{a} + \left( 1 - F_{a} \right)\min\left( 1,\frac{\theta - \theta_{a}}{\alpha N} \right) \right\rbrack\quad{\text{for}\mspace{6mu}}\theta > \theta_{a}.$$

The report gives prose and a diagram rather than full event logic;
pdmS7’s reading is recorded in `source-notes.md`.

### Internal steps and balance

Each interval is divided into

$$N_{sub} = \left\lceil \max\left( \frac{60\,\Delta t}{\text{max\_step\_min}},\;\Delta t\,\left( k_{1} + k_{2} \right),\; 1 \right) \right\rceil$$

steps to keep the drainage calculation stable. The snow balance residual
is

$$\epsilon_{snow} = (W + S)_{old} + p_{corrected} - p_{effective} - (W + S)_{new}.$$

When PACK feeds the PDM, the PDM’s $f_{c}$ still multiplies the
effective rain; set it to 1 to avoid correcting precipitation twice.

## Sources

- Moore, R. J. (2007). The PDM rainfall-runoff model. *Hydrology and
  Earth System Sciences*, 11, 483-499.
  [doi:10.5194/hess-11-483-2007](https://doi.org/10.5194/hess-11-483-2007).
- Institute of Hydrology. *PACK: A Pragmatic Snowmelt Model for
  Real-time Use.* [NORA
  15304](https://nora.nerc.ac.uk/id/eprint/15304/1/N015304CR.pdf),
  equations 2.1-2.8, Figure 2.2 and Table 2.1.
- `source-notes.md` in the package source records every interpretation
  and correction.
