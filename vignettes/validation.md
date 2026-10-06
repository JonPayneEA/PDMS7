# Validation record — 0.2.0

Local verification: 2026-10-05; R 4.3.3, S7 0.2.2, Linux x86_64.

| Gate | Observed result |
|---|---|
| testthat numerical/interface suite | 1,210 expectations passed; zero failures, warnings or skips |
| covr package coverage | 98.22335%, above the Tier 3 70% floor |
| lintr, with current package loaded | Zero findings |
| Baseline equivalence | All 13 presets match version 0.1.0 on the retained 33-interval forcing sequence |
| renv | Runtime and development dependencies recorded; consistent status |
| roxygen2 | Help and namespace regenerated successfully |
| R CMD build | Source archive built successfully |
| R CMD check | Installation, loading and dependency checks passed; full completion was not established in this interrupted environment. Rerun before promotion. |
| Remote CI / Windows | Configured, not executed here |

Tests exercise all five capacity distributions; density/storage quadrature and
inverse round trips; exact and adaptive routing; Smith cubic recurrence;
85 compatible distribution/recharge/groundwater combinations; conservation,
extreme forcing, time conversion, UTC timestamps, warm-up, restart, invalid input,
YAML configuration, all presets, calibration and forecast updating. Preset
equivalence is a regression check, not independent scientific validation.

The formatting pass was followed by a full coverage/test run; the final
documentation-only change removes redundant roxygen inheritance warnings.
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
approval, a completed package check and catchment acceptance remain required.
See `tier3-review.md`. This is a **Tier 3 candidate**, not operational approval.
