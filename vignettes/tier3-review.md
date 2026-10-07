# Tier 3 engineering review

Target: standalone PDM package for pseudo-operational use; proposed Flode module
`reach.hydro`. This is a Tier 3 **candidate**, not an approved operational tool.

Reference: [JonPayneEA/flode_code_styles](https://github.com/JonPayneEA/flode_code_styles)
at commit `028eae437bddce685a8e436312d31f290c3de715`, read 2026-10-05.
The shared workflow is pinned to that commit. No code was pushed or published.

## Scope and interpretation

The original PDM distributions/recharge/routing options, parameter domains and
conservation conventions remain those of version 0.1.0. Version 0.3.0 adds optional
PACK snow processing and multi-objective calibration. The snow guide documents
the assumed image parameter units and explicit choices where the report leaves
discrete event logic unspecified; these need independent scientific review.
The refactor adds the team's data.table/UTC interface, S7 naming, YAML settings,
roxygen documentation, testthat layout, lint configuration, reproducible tooling,
and shared CI. Existing APIs remain available; see README migration notes for
serialized S7 objects.

Runtime dependencies are S7 (required typed model components), data.table
(tabular assembly/CSV input), yaml (declarative configuration), logger
(structured standalone logging), and R's stats. No tidyverse runtime
packages are used. Development tools may depend transitively on tidyverse
packages; they are not used for model data processing.

Scientific notation in component APIs follows the paper (e.g. cmax, kg, dt).
Units are explicit in help and the catalog. The new primary simulation API uses
rainfall_mm, pet_mm, timestep_min and qsim_cms. Legacy data.frame results and
constructor names are retained for compatibility, rather than silently changing
old callers' output semantics.

## Human governance blockers

1. The user has not supplied a responsible human maintainer name and EA email.
   Headers say so explicitly. DESCRIPTION retains the prior clearly synthetic
   `pdm@example.org` contact solely to keep the development artifact installable;
   **replace it before any merge or operational handover**. It is not a real
   operational support contact or an assertion of EA authorship.
2. Independent review and Steward promotion have not taken place. This package
   has not been merged into Flode.
3. No catchment observations or acceptance criteria were supplied. Parameters
   require calibration, held-out validation and a forcing-quality assessment.
4. Remote CI is configured but has not executed. The environment used for local
   checks does not demonstrate Windows deployment compatibility.

## Technical verification

The final local verification results are recorded in `validation.md`. Distinguish
measured local results from the CI configuration and the human review blockers.

## Reproduction

Extract the full project, start R at its root, and restore `renv.lock`.
Run roxygen2, testthat, covr, lintr, renv status, and the package check as shown
in README. The 70% line-coverage floor and zero-lint policy are enabled in CI.
The lockfile records the tested R version; other supported R versions should
be exercised through the supplied shared CI matrix.
