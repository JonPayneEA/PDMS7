# pdmS7 — configurable PDM for Flode conventions

Version 0.3.1 targets **Tier 3 engineering checks** for pseudo-operational use.
It remains a standalone package, with `reach.hydro` as its proposed Flode home.
Human maintainer attribution, independent review and catchment validation are
outstanding; this is not a declaration of operational approval.

The model implements Moore (2007), [doi:10.5194/hess-11-483-2007](https://doi.org/10.5194/hess-11-483-2007),
with all five Appendix A capacity distributions, three recharge schemes, six
routing choices, calibration, restartable states, and forecast updating.

## Install

R >= 4.3 is required. For users of the installable source archive:

```r
install.packages(c("S7", "data.table", "yaml", "logger"))
install.packages("pdmS7_0.3.1.tar.gz", repos = NULL, type = "source")
```

For developers, extract the full project, open R in `pdmS7/`, and use
`renv::restore()`. The lockfile also records the testing and documentation tools.
Do not copy the previous machine's `renv/library` directory.

## Illustrated vignettes

**Plain Markdown copies are included in the project:**

- [PDM explained](docs/vignettes/pdm-explained.md)
- [PACK snowpack explained](docs/vignettes/snowpack-explained.md)
- [Example workflow](docs/vignettes/example-workflow.md)

Start with [the guide index and PACK file map](docs/vignettes/README.md).
Diagrams are included in `docs/vignettes/figures/`; no documentation build is
needed to read the `.md` guides. The PACK implementation is in `R/pack_model.R`,
`R/pack_step.R` and `R/sim_pack.R`, with defaults in `inst/config/pack.yml`.

The source archive includes built HTML vignettes. After installation:

```r
browseVignettes("pdmS7")
vignette("pdm-explained", package = "pdmS7")
vignette("snowpack-explained", package = "pdmS7")
vignette("example-workflow", package = "pdmS7")
```

Editable R Markdown sources live in `vignettes/`. They explain the equations,
component functions, units and assumptions in plain English, with process diagrams
and executable examples. The workflow uses synthetic forcing and observations;
it demonstrates calibration, held-out validation and checkpoint restart, not
field performance. Rebuild with `R CMD build pdmS7` after restoring development
dependencies. No numerical APIs changed in this documentation release.

The full project download also provides standalone HTML readers in
`read-vignettes/`, with embedded figures and native MathML for modern browsers.
These readers work offline. The normal knitr-built package pages use the
markdown renderer's online KaTeX assets for maths display.

## Quick start

```r
library(pdmS7)

config <- read_pdm_config(
  system.file("config", "standard.yml", package = "pdmS7")
)
config$area_km2 <- 44  # supply your catchment area

datetime <- seq(
  as.POSIXct("2026-10-01 00:00:00", tz = "UTC"),
  by = "hour", length.out = 4
)
flow_dt <- sim_pdm(
  rainfall_mm = c(0, 10, 5, 0),
  pet_mm = rep(0.05, 4),
  params = config,
  timestep_min = 60L,
  datetime = datetime
)
flow_dt[, c("datetime", "qsim_cms", "soil_moisture_mm"), with = FALSE]
attr(flow_dt, "water_balance")
```

Rainfall and PET are **depths in mm per interval**, not rates. `timestep_min` is
an integer number of minutes. Discharge is m³/s. Timestamps are converted to
UTC while preserving instants; missing or irregular supplied timestamps are
errors. If no timestamps are supplied, the `datetime` column contains UTC `NA`
values, not invented dates.

## Configuration

`pdm_presets()` lists 13 templates. The templates live in
`inst/config/presets.yml`, and `inst/config/standard.yml` is a standalone example.
YAML is declarative: unknown keys and `!expr` expressions are rejected.

```r
config <- pdm_presets("standard")
config$distribution <- list(type = "lognormal", meanlog = log(100) - 0.5, sdlog = 1)
config$recharge <- list(type = "demand", alpha = 0.5, beta = 1, qsat = 1)
config$groundwater <- list(type = "quadratic", kb = 1000)
model <- pdm_from_config(config)
```

| Component | Choices and parameters |
|---|---|
| Capacity | `pareto(cmin,cmax,b)`; `rectangular(cmin,cmax)`; `triangular(cmin,cmax)`; `exponential(mean)`; `lognormal(meanlog,sdlog)` |
| Recharge | `standard(kg,bg,st)`; `demand(alpha,beta,qsat)`; `split(alpha)` |
| Either routing pathway | `linear(kb)`; `quadratic(kb)`; `cubic(kb,solver)`; `power(k,m,solver,rtol,atol)`; `cascade(k1,k2)`; `exponential(a,gamma)` |
| Catchment controls | `be`, `fc`, `td`, `qc`, `area_km2`, `dt` |

`parameter_catalog()` gives units, valid domains, equations and provenance.
The Figure 5 Pareto parameters are `cmin=0`, `cmax=140`, `b=0.4` (Smax=100 mm).
Other full parameter sets are **illustrative templates, not calibrated catchment
sets**. No published Beverley Brook calibration is implied.

The new `sim_pdm()` interface converts minutes to the **hours** used by the paper
and the component APIs. A configuration list's `dt` is replaced by
`timestep_min / 60`; a supplied model must already match that interval. Coefficients
such as `kg`, `kb`, `k1`, `k2`, `td` retain their documented hour-based units.

## S7 objects and compatibility

```r
model <- pdm_model(
  distribution = FlodeParetoCapacity(cmin = 0, cmax = 140, b = 0.4),
  recharge = FlodeStandardRecharge(kg = 24, bg = 1, st = 0),
  surface = FlodeCascadeRouting(k1 = 2, k2 = 4),
  groundwater = cubic_routing(kb = 10000)
)
S7::S7_inherits(model, FlodePdmModel)
```

All canonical classes carry the `Flode` prefix. Previous constructor names such
as `ParetoCapacity`, `PDMModel` and `PDMState` remain aliases. The legacy
`run_pdm(model, forcing, state)` API retains `rain`/`pet` inputs and its list of
results, including a data.frame with `q_m3s` and `q_end_m3s` columns.

The unchanged mathematical component names mirror the paper and conventional
probability APIs (e.g. `capacity_cdf`). Their units are documented in help and the
parameter catalog. No implicit unit conversion is introduced into these APIs.

**Saved 0.1.0 S7 objects:** rebuild from the saved configuration under 0.2.0;
canonical class identity has changed. Newly saved states restart within 0.2.0.
Do not change model structure or timestep without transforming/reinitializing
states. No compatibility claim is made for 0.1.0 serialized state objects.

## Water balance, warm-up and restart

`qsim_cms` is interval-average flow; `qsim_end_cms` is endpoint flow. Compare
observations with the correct series. Balance diagnostics use interval volumes,
including water pending in delay queues. Signed `qc` is an external outlet
addition/removal, excluded from the internal storage balance.

```r
first_dt <- sim_pdm(c(0, 10), c(0.05, 0.05), config, 60L, warmup_steps = 1L)
second_dt <- sim_pdm(c(5, 0), c(0.05, 0.05), config, 60L,
  state = attr(first_dt, "final_state"))
# Warm-up rows are retained and flagged; exclude is_warmup rows when scoring.
```

`initial_state()` allows explicit soil/routing states. `spin_up()` repeats a
representative forcing period; inspect state convergence. Store checkpoint
objects with `saveRDS()` and `readRDS()`, using a caller-configured path.

## Calibration and updating

The legacy calibration API is retained:

```r
config <- pdm_presets("standard")
# fit <- calibrate_pdm(config, forcing, observed_cms,
#   lower = c(distribution.b = 0.05, surface.k1 = 0.1),
#   upper = c(distribution.b = 3, surface.k1 = 10),
#   warmup = 24, objective = "rmse", flow = "q_m3s")
```

These bounds are illustrative. Missing observations are excluded; missing forcing
is rejected. Inspect convergence and validate on independent periods. Debug logs
for rejected parameter trials use `logger::log_debug()`; ordinary simulations
produce no operational console messages. A calling script can configure logger
thresholds/appenders. Runtime code has no tidyverse dependency.

`correct_state()` implements proportional, super-proportional, and
non-proportional endpoint state correction, with explicit external correction
volume. It requires `td=0`. `fit_error_updater()` and `update_forecast()` implement
additive or logarithmic ARMA correction. Use training history available at the
forecast origin, never future observations. AR coefficients use R's sign
convention (`ar=-phi` in the paper).

## Snow and multi-objective calibration

`sim_pack()` implements PACK's dry/wet stores, two drainage outlets, temperature
thresholds and areal depletion. `sim_snow_pdm()` couples its effective rainfall
to PDM and returns both restart states. Defaults transcribe the supplied image's
parameter file, with **hourly rate units assumed**; the report's daily typical
set is separately available. See the [snow guide](docs/snow-model.md) for equations,
parameter mapping, the unit uncertainty and numerical interpretations.

`calibrate_pdm_multi()` can vary snow and PDM parameters jointly, returning
an approximate Pareto front and a weighted compromise. Metrics include NSE/KGE
loss, RMSE, log-RMSE, volume bias and peak-magnitude error. Explicit scales and
weights control trade-offs. See the [calibration guide](docs/multi-objective.md).

River-network routing and additional state assimilation are deferred in the
[roadmap](docs/roadmap.md). Existing updating APIs remain available.

## Limitations that matter in pseudo-operations

- Maintainer name/email and Steward/peer approval have not been supplied.
- Presets need catchment calibration, held-out validation and forcing-quality checks.
- This remains an independent implementation, not proprietary UKCEH PDM software.
- Demand recharge follows the paper's interval-depth formula and can depend
  strongly on timestep. Check timestep sensitivity.
- Exponential routing uses a signed log-storage coordinate; it is not a finite
  nonnegative tank. Groundwater abstractions/well-level extensions are not included.
- Fractional `td` uses a conservative outlet-delay convention. Delayed observation
  state smoothing is not implemented.
- Evaporation is capped before recharge when available water is insufficient.
  Requested and actual losses are both reported.

See [source notes](docs/source-notes.md) for equations, apparent Appendix A
corrections, numerical methods and exact scope.

## Development and verification

From the project root after restoring dependencies:

```r
roxygen2::roxygenise()
testthat::test_local()
cov <- covr::package_coverage()
stopifnot(covr::percent_coverage(cov) >= 70)
pkgload::load_all()
stopifnot(length(lintr::lint_package()) == 0)
renv::status()
rcmdcheck::rcmdcheck(args = c("--no-manual"), error_on = "warning")
```

The shared Flode CI workflow is pinned to the style repository commit recorded
in [the review](docs/tier3-review.md), with `tier: 3`. CI configuration is provided;
remote CI has not been run in a hosted repository. The review distinguishes
completed local checks from outstanding human governance requirements.
