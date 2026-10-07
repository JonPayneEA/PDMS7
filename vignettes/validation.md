# Validation record — 0.3.1

Local verification: 2026-10-06; R 4.3.3, S7 0.2.2, Linux x86_64.

| Gate | Observed result |
|---|---|
| testthat numerical/interface suite | 1,277 expectations passed; zero failures, warnings or skips |
| covr package coverage | 98.17937% measured on 0.3.0; numerical code unchanged in this documentation-only release |
| lintr, with current package loaded | Zero findings |
| Baseline equivalence | Original PDM engine unchanged from 0.2.0; the 0.2.0 record verified all 13 presets against 0.1.0 |
| renv | Runtime and development dependencies recorded; consistent status |
| roxygen2 | Help and namespace regenerated successfully |
| R CMD build | Source archive built successfully |
| R CMD check backend | Status: OK; no errors, warnings or notes; no-manual; vignette checks enabled |
| Vignettes | Three built, their extracted R code rerun, and outputs rebuilt successfully |
| Standalone HTML | Three offline readers; embedded figures and native MathML; no remote script/image/style dependencies |
| Remote CI / Windows | Configured, not executed here |

Tests exercise all five capacity distributions; density/storage quadrature and
inverse round trips; exact and adaptive routing; Smith cubic recurrence;
85 compatible distribution/recharge/groundwater combinations; conservation,
extreme forcing, time conversion, UTC timestamps, warm-up, restart, invalid input,
YAML configuration, all presets, calibration and forecast updating. Preset
equivalence is a regression check, not independent scientific validation.

Snow tests cover independently calculated accumulation, melt and two-outlet
drainage, drainage inhibition, threshold equality, partial cover, fresh-snow
memory, conservative substeps, rain-only equivalence and coupled restart.
Calibration tests verify analytical metrics, Pareto dominance/ties, bounds,
reproducibility, random-state preservation and joint snow/PDM fitting.

The normal package check stalled at online repository lookup. The successful
check used the same R CMD check backend (`tools:::.check_packages`) with a local
repository index made from installed dependency metadata. All code, help,
example, installation and test checks ran; no check categories were disabled
except PDF manual generation. This does not verify CRAN network
availability, a fresh remote dependency restore, or Windows compatibility.
Subsequent changes only adjust whitespace, package description and documentation/
catalog metadata. Check logs accompany the full project under docs/verification.
The source archive excludes development files. Use the full project ZIP for
CI, renv, lint settings and this record.

## Reproduce

Open the full project in R, then run:

```r
renv::restore()
roxygen2::roxygenise()
testthat::test_local()
coverage <- covr::package_coverage()
stopifnot(covr::percent_coverage(coverage) >= 70)
pkgload::load_all()
stopifnot(length(lintr::lint_package()) == 0)
renv::status()
rcmdcheck::rcmdcheck(args = "--no-manual", error_on = "warning")
```

These checks do not establish real-catchment forecasting skill or equivalence
to proprietary PDM software. Maintainer attribution, independent peer/Steward
approval and catchment acceptance remain required. Confirm the assumed image
parameter units and review the snow event conventions before operational use.
See `tier3-review.md`. This is a **Tier 3 candidate**, not operational approval.
