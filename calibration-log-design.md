# Calibration log: design

Status: agreed design, 2026-11-01. This records the decisions taken before the code was
written; the reference documentation describes the code as built.

## Purpose

Manual calibration is judgement. A calibration can be defended later only if the record of
that judgement cannot be quietly rewritten. The calibration log is therefore two things at
once:

- an **audit trail**: append-only, attributed, tamper-evident, and reproducible; and
- a **working record**: quick to write, with free-text reasoning as a first-class field,
  and a readable report generated from it.

A separate, opt-in **run log** records every model run, calibrated or not, so that the
parameter set behind any operational result can be traced to the calibration that produced
it.

## Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Audit trail or notebook | Both: an append-only record with notes and a generated report |
| 2 | Storage | A project folder of plain YAML files; no database |
| 3 | Events | Ten entry types, below |
| 4 | Identity | Declared name and role, stamped with the operating-system login; a Steward cannot sign off their own work |
| 5 | Scoring | A fixed project scorecard set at data registration; every trial scored on every metric |
| 6 | Data | Copied into the project by default (`copy = FALSE` references by path and checksum) |
| 7 | Simulated series | Checksums for every run; full series kept for candidate, validation and sign-off |
| 8 | Report | Self-contained HTML built with base R, plus Markdown |
| 9 | Interface | R functions, with a Shiny app over the same functions covering every action |
| 10 | Run log | Opt-in, through an option or environment variable |
| 11 | Approval | Runs flagged as approved, unapproved or superseded; never blocked |
| 12 | Delivery | Five phases: core, report, run log, app, article |

## Roles

Roles follow the Owner, Steward and Custodian taxonomy of the F&W governance framework.

| Role | Acts in the log |
|---|---|
| Custodian | Starts the project, registers data, selects the structure, runs trials and automatic calibrations, writes notes, proposes a candidate, validates it |
| Steward | Signs off and reopens |
| Delegated Steward | As Steward; the entry records the delegation |
| Owner | Named in `project_start` as accountable; takes no action in the log |

A Steward or Delegated Steward may not sign off a project in which they wrote a trial,
automatic calibration, candidate or validation entry. Names and logins are both compared,
ignoring case and surrounding spaces. The package refuses a self-sign-off.

## Identity

Each person declares a name and role once, through `options(pdmS7.user = , pdmS7.role = )`
or the environment variables `PDMS7_USER` and `PDMS7_ROLE`. Every entry records the declared
name, the role and `Sys.info()[["user"]]`. This is an honour system; a mismatch between name
and login is visible in the report. A platform identity can later replace the declared name
without changing the format.

## Project folder

```
<project>/
  pdms7-project.yml        format version and project identifier; written once
  entries/
    0001-project_start.yml
    0002-data_registered.yml
    0003-structure_selected.yml
    0004-trial.yml
    ...
  data/
    0002/forcing.csv       copies made at registration (unless copy = FALSE)
    0002/observed.csv
  series/
    0009.csv               simulated and observed flow for candidate and validation
  report/                  generated; never edited by hand
```

Entries are numbered in the order written and are never edited or deleted. A lock directory
(`entries/.lock`, created atomically) serialises writers, so two people can work in one
project on a shared drive.

## Entry schema

Every entry carries:

| Field | Content |
|---|---|
| `format` | Entry format version, currently 1 |
| `id` | Four-digit sequence, the same as the file name prefix |
| `type` | One of the ten types |
| `timestamp` | UTC, ISO 8601 |
| `author` | `name`, `role`, `login` |
| `software` | pdmS7 version, R version, platform, engine |
| `previous` | MD5 of the previous entry file, or `none` for the first |

Then, by type:

| Type | Further fields |
|---|---|
| `project_start` | `project`: identifier, catchment, gauge, purpose, area_km2, owner, steward, description |
| `data_registered` | Each series' source path, stored path, MD5 and summary (rows, period, step, missing values, longest gap); `scorecard`: warm-up, calibration and validation windows, metrics, headline, log offset, soil fraction |
| `structure_selected` | Full configuration; reasoning |
| `trial` | Parent entry; changes from the parent; full configuration; calibration scores; output MD5; verdict (better, worse, inconclusive); reasoning |
| `auto_calibration` | Parent; bounds; objective; starts; seed; control; the start table; resulting configuration; calibration scores; output MD5; reasoning |
| `note` | Text; optional entry it refers to |
| `candidate` | The trial or calibration entry proposed; reasoning; calibration scores; series file and its MD5 |
| `validation` | The candidate; validation scores, alongside calibration scores; series file and MD5; reasoning |
| `test` | The validated candidate; test scores beside the calibration and validation scores; series file and MD5; reasoning |
| `sign_off` | The candidate and validation; final configuration; capacity (steward or delegated steward); review checklist; statement |
| `reopen` | Reason |

After `sign_off` the project is closed. Only `reopen` may follow; a reopened project accepts
entries again, and a later sign-off supersedes the earlier one.

## Integrity

- **Chain.** Each entry stores the MD5 of the file before it. Checksums of entries, data
  and series ignore carriage returns, so a Windows checkout that converts line endings
  does not break the chain. `verify_project()` recomputes
  the chain and reports any gap, insertion or alteration. Alteration of the newest entry is
  caught by the next entry, by a sign-off, or by version control.
- **Data.** Every run first checks the registered files against their MD5s.
- **Outputs.** Every run records the MD5 of its simulated flow, rounded to 10 significant
  figures so that last-digit differences between R versions do not register.
  `verify_project(rerun = TRUE)` reruns every entry and compares; a mismatch names what has
  changed in the software since the entry was written.
- **Numbers.** Parameters are written with the fewest digits that reproduce the double
  exactly, so a configuration read back from the log is the configuration that was run.

## Scorecard

Scores are fixed when data are registered and computed for every run: NSE, log NSE, KGE and
its three components (correlation, variability ratio, mean ratio), RMSE, log RMSE, absolute
and signed volume error, peak error, and the three flow-duration-curve signatures of Yilmaz
et al. (2008): high-flow volume bias (exceedance below 2 per cent), mid-segment slope bias
(20 to 70 per cent) and low-flow volume bias (above 70 per cent). One metric is named the
headline, NSE by default, for sorting and charts. The verdict on a trial is the person's
own.

Trials and automatic calibrations are scored on the calibration window only. The validation
window is scored once, by the `validation` entry, so that it stays an honest test.

Every run simulates continuously from the first registered row from `initial_state(model,
soil_fraction)`; rows before the calibration window are the warm-up.

## Threshold scores

Agreed 2026-11-01, after phases 1 to 5.

| # | Question | Decision |
|---|---|---|
| 13 | What is an event | An episode above the threshold; exceedances closer than a minimum gap merge; a simulated crossing within a timing tolerance of an observed one is a hit, matched one to one, closest first |
| 14 | Threshold units | Flow (m3/s) or level (m), per threshold; levels convert through a registered rating table, interpolated in log flow, never extrapolated |
| 15 | Matching settings | One set per registration: tolerance 6 h, gap 24 h, minimum duration 0 by default. Event scores need no correct negatives; the chance-corrected scores (POFD, ETS, PSS) are step-based only |
| 16 | Weight in calibration | A threshold score may be the headline. Automatic calibration may add a weighted threshold term to a continuous objective, using derivative-free Nelder-Mead, since event counts change in steps |

Threshold scores join each run's scores as `metric:threshold`, for example
`csi:Flood Warning`, so they are logged, verified, reported and ranked like any other.

## Structure comparison and the test window

Agreed 2026-11-01.

| # | Question | Decision |
|---|---|---|
| 17 | Which structures | A list to choose from; by default the standard PDM and seven one-change variants |
| 18 | Parameters and bounds | A shipped bounds table per component, with overrides and exclusions; log-scale search for parameters spanning orders of magnitude |
| 19 | Ranking | On the validation window, with the calibration score and the change shown; optional two-way cross-validation |
| 20 | Final check | An optional test window, scored once by a `test` entry (the eleventh type) after every choice; required before sign-off when registered; a poor result does not block sign-off |

Each compared structure is logged as ordinary `structure_selected` and `auto_calibration`
entries sharing a comparison id, so no further entry type is needed and the ranking can be
rebuilt from the log. Structures are fitted in parallel workers that write nothing; the
entries are written afterwards, in order, by the session that started the comparison.

## Run log and register

With `options(pdmS7.run_log = )` or `PDMS7_RUN_LOG` set, `run_pdm()` appends one CSV row per
call under a lock. Each row carries the model's fingerprint, an MD5 of its canonical
components and parameters, so a model built in code and the signed-off YAML match. A
register (`pdmS7.register` or `PDMS7_REGISTER`) is a YAML file listing project folders, or
the folders themselves; its sign-offs are re-read at most once a minute. Calibration
evaluations, spin-up cycles and the calibration log's own reruns are not logged.

## Delivery

1. Project log core, scorecard and integrity checks.
2. Report: HTML and Markdown, with hydrographs, flow-duration curves, trial tree, progress
   chart and optional parameter sensitivity.
3. Run log and approval register.
4. Shiny app: setup, trials, history, report and sign-off. Shiny is a suggested package
   only.
5. Website article: logging a manual calibration.

A pull request follows phase 2 and another follows phase 4.
