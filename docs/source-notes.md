# Source traceability and numerical conventions

## Primary sources

1. Moore, R. J. (2007). The PDM rainfall-runoff model. *Hydrology and Earth System
   Sciences* 11, 483–499. https://doi.org/10.5194/hess-11-483-2007
2. Moore, R. J. and Bell, V. A. (2002). Incorporation of groundwater losses and
   well level data in rainfall-runoff models illustrated using the PDM. *HESS* 6,
   25–38. https://doi.org/10.5194/hess-6-25-2002
   Used only for the routing solutions explicitly referred to by Moore (2007).
3. S7 documentation: https://cran.r-project.org/web/packages/S7/vignettes/S7.html and
   https://cran.r-project.org/web/packages/S7/vignettes/packages.html

This is independently written code based on the mathematical model. The source
papers themselves are not redistributed in the package. The package's MIT
license applies to its original code and documentation, not to the source papers.

## Equations and implementation

| Paper | Implementation |
|---|---|
| Eq. 2–3 | `capacity_cdf`, saturated area fraction (multiply by catchment area for area) |
| Eq. 7, 9 | `storage_from_capacity`, `capacity_mean` |
| Eq. 5–7, 15–17 | `soil_step`; runoff = net depth − change in basin storage |
| Eq. 8 | Start-of-interval actual evaporation request, configurable exponent |
| Eq. 10 | Standard recharge above `st`, exponent `bg` |
| Eq. 11–13 | Demand recharge with derived `Sgmax`; deficit clipped to [0,1] |
| p486 third formulation | Split direct runoff by `alpha`; no soil drainage |
| Eq. 18–20, Appendix A | Five capacity families and inverse storage transforms |
| Eq. 21–23 | Power routing dS/dt = u − k S^m |
| Eq. 24–25 | Optional cubic Smith recurrence and endpoint flow |
| Eq. 26–27 | Exact two-store state-space routing; exposed transfer coefficients |
| Table 1 | Parameter catalog, rainfall factor, delay, constant flow |
| Eq. 28–30 | Manual state correction with gains and explicit correction flux |
| Eq. 31–42 | ARMA additive/log forecast correction; ar = −phi |
| 2002 Appendix A.2, A.4, A.10 | Exact linear, quadratic, general recession solutions |
| 2002 Appendix A.6–A.7 | Exact exponential/log-storage routing |

### Capacity distributions

All families implement S(C) = E[min(c,C)] = integral from 0 to C of (1−F(c)) dc.
The total basin capacity is E[c], not the maximum point capacity.

- Pareto on [cmin,cmax]: F(c)=1−((cmax−c)/(cmax−cmin))^b.
  Below cmin, S(C)=C; above cmax, S(C)=Smax.
  `b=0` is a point mass at cmax, handled separately in the CDF. Its ordinary
  density is undefined, so requesting a PDF raises an error.
- Rectangular: uniform on [cmin,cmax], equal to Pareto b=1. Mean is
  (cmin+cmax)/2 and F(c)=(c−cmin)/(cmax−cmin) within the support.
- Triangular: symmetric with midpoint mode. First branch density is
  4(c−cmin)/(cmax−cmin)^2; second branch is
  4(cmax−c)/(cmax−cmin)^2.
- Exponential: mean `mean`, F(c)=1−exp(−c/mean); S(C)=mean*(1−exp(−C/mean)).
- Lognormal: log(c) is normal with mean `meanlog` and SD `sdlog`.
  With z=(log(C)−meanlog)/sdlog and M=exp(meanlog+sdlog²/2),
  S(C)=M*Phi(z−sdlog)+C*Phi(−z). This truncated-moment identity is used
  instead of the inconsistent erfc expression printed in Appendix A.

At S=Smax for an unbounded distribution, C=Inf is an exact limiting state; any
additional positive net rain becomes runoff. At zero storage C=0. Triangular
and lognormal inverses use bracketed root finding, avoiding unconstrained
Newton iterations near distribution tails. CDF/integral operations are vectorised;
`soil_step` operates on one state and one net depth.

### Apparent typographical errors in Appendix A

The PDF was inspected visually as well as extracted as text. The following are
mathematical corrections, not a claimed publisher-issued erratum:

- Rectangular F(c) omits the cmin shift and gives inconsistent mean/storage
  expressions for nonzero cmin. The implementation uses the normalized uniform
  law and its survival integral, consistent with Pareto b=1.
- The rectangular runoff expression appears to omit the square on its initial
  C* term. Computing runoff from continuity avoids this error.
- The triangular density's lower branch is printed with `cmax−c`, inconsistent
  with its increasing CDF; the derivative requires `c−cmin`.
- The triangular final overflow branch has an inconsistent inequality; overflow
  is handled by the capacity support and continuity.
- The printed normal CDF definition and lognormal erfc storage/runoff equations
  contain inconsistent limits/factors/signs. The standard normalized normal CDF
  and the independently derived truncated-moment identity above are used.

Quadrature tests check normalized densities, their means, storage integrals, and
inverse transforms. These checks validate the corrected probability laws rather
than reproducing the apparent misprints.

### Routing

Inputs to routing are constant **rates** within an interval. `route_step` returns
`storage`, discharged depth `outflow`, interval mean `q_mean`, and instantaneous
endpoint `q_end`. Its conservation contract is
`sum(old storage) + inflow*dt = sum(new storage) + outflow`.
Tiny negative discharged depths caused by floating-point cancellation are set
to zero; any resulting roundoff is visible in the water-balance diagnostic.

For the cascade, both continuous reservoir states are propagated jointly;
routing the first reservoir's mean output through the second would not be the
exact same solution. The repeated-time-constant limit is handled explicitly.
The published transfer coefficients apply to endpoint flows; using these endpoint
samples as discharged interval depths would not conserve water. Both endpoint
and integrated outputs are therefore exposed.

The default power solver uses exact linear and quadratic solutions, exact
zero-input recession for any positive exponent, and adaptive RK4 step doubling
otherwise. The accepted nonlinear solution is constrained to lie between the
initial storage and equilibrium. The nominal defaults are rtol=1e−8 and
atol=1e−10 mm. The Smith option reproduces Eq. 24, including its limit at S=0;
it is a first-order local approximation and can be inaccurate for large steps.
Its endpoint discharge is Eq. 25, while its interval volume is from continuity.
The default numerical solver is not claimed to reproduce the proprietary PDM
implementation bit-for-bit.

Exponential routing uses q=exp(gamma+a*S). S is a signed relative coordinate;
it can decrease below zero with positive flow, as in the referenced model. A
finite nonnegative-tank interpretation would require changing that model. The
implementation rejects numerical overflow/underflow of flow and zero-flow
initialisation through `storage_for_flow`.

### Discrete boundary policies and time delay

Moore specifies requested loss rates but not a complete discrete allocation rule
when evaporation plus drainage exceed available water. This framework caps AET
first, then recharge, using start storage plus interval rainfall. It reports both
requests and realised fluxes. This is a documented implementation choice; reduce
`dt` and check sensitivity where caps are frequent.

Eq. 13 is a **depth** formulation: D=[qsat*dt+(Smax−qsat*dt)*f]*S/Smax.
It is implemented literally, so this demand scheme can be strongly time-step
dependent. It is not reinterpreted as a dt-invariant rate law. `qsat` labels the
recharge at groundwater saturation; the formula can give larger recharge when
groundwater is depleted. Sgmax is a demand scale, not a hard upper bound on the
routing store. Negative demand from Sg>Sgmax is prevented by clipping the deficit
ratio to zero.

Table 1 names td but does not specify where/how the delay is discretized. Here
td delays both natural outlet pathways after routing, before adding qc. A delay
of (n+f)*dt delivers fractions (1−f) and f at offsets n and n+1. This conserves
volumes for interval-constant flow, includes water in transit in the balance,
and uses the same interpolation for endpoint flow samples. Initially queues are
empty. State-correction gains operate on unlagged endpoint flows, so state
correction is deliberately unavailable for td>0.

### Parameter provenance and exclusions

The 2007 paper has one parameter-definition table, a Figure 5 soil example, and
suggested structural/exponent/gain values. It does not publish complete calibrated
catchment sets. Presets are templates, not recovered calibration results. All
numeric domains are mathematical/implementation validity constraints, not
statistical priors or literature calibration ranges.

The historical travel-time/inverse-Gaussian unit hydrograph discussed on p494
is background to earlier PDM development, not a current routing component in
Table 1; it is not implemented. Neither are spatially distributed PDM variants,
well-level transformations, pumped groundwater abstraction, underflow/spring
extensions, snow, a Kalman filter, variable-step forcing, or automatic delayed
observation smoothing. These are not silently approximated by another option.
