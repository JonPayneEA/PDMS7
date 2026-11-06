# Changelog

## pdmS7 0.9.1

- [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md)
  has been checked against the authors’ reference code for DMCA-ESR, run
  in Octave, on three synthetic records (two hourly, one daily):
  identical response times and all 663 event windows identical. The help
  page and the events article record the check.

## pdmS7 0.9.0

- **Events from the records.**
  [`find_events()`](https://jonpayneea.github.io/PDMS7/reference/find_events.md)
  finds rainfall-runoff events in continuous rain and flow records
  objectively, with the DMCA-based event separation routine of Giani et
  al. (2022): no baseflow separation, one setting (`rain_min`), any time
  step that resolves the delay between rain and flow. Each event has
  rain and flow windows, rain depth, peak, and with an area, quick flow
  and runoff ratio.
- [`response_time_dmca()`](https://jonpayneea.github.io/PDMS7/reference/response_time_dmca.md)
  estimates a catchment’s response time from rain and flow alone (Giani
  et al., 2021). Ten years of 15-minute data take under a second, about
  twenty-five times faster than the R reference, which
  `options(pdmS7.engine = "r")` still selects.
- **The event method is in the C core**, beside the model:
  `pdm_dmca_rho()`, `pdm_find_events()`, `pdm_event_summary()` and
  `pdm_event_scores()` in `src/pdm_core.h`, so Python, Scala and other
  languages find the same events as R. It matches the R reference
  exactly in event positions and within 1e-14 in every number. Golden
  files for three records (hourly, daily, and hourly with gaps) are in
  `inst/golden/`, checked from R, from plain C
  (`tools/core/check_golden.c`) and from Python
  (`tools/core/events_example.py`).
- [`event_scores()`](https://jonpayneea.github.io/PDMS7/reference/event_scores.md)
  scores a model event by event: peak error, peak timing, volume error
  and NSE over each flow window.
  [`batch_events()`](https://jonpayneea.github.io/PDMS7/reference/batch_events.md)
  does it for every basin of a batch, labels each event with its window,
  and compares each basin’s observed and simulated response times.
- New article: “Events in large samples: finding them and scoring models
  on them”.
- [`synthetic_basins()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_basins.md)
  at a sub-daily step no longer writes overlapping calibration and
  validation windows, which registration refused.
- **Fix:
  [`ar_from_response_time()`](https://jonpayneea.github.io/PDMS7/reference/ar_from_response_time.md)
  refuses unstable AR sets.** The default family’s first coefficient is
  set for 15-minute steps; at longer steps a decay of under about 4.9
  steps gave a root of 1 or more, so the projected error grew without
  limit. At hourly steps that is any catchment with a time to peak under
  4.9 hours.
  [`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md)
  used such sets by default without a word; it now leaves them out with
  a warning. Hindcasts of fast catchments at steps longer than 15
  minutes change.
- The AR article compares the model’s time to peak with the records’
  response time
  ([`response_time_dmca()`](https://jonpayneea.github.io/PDMS7/reference/response_time_dmca.md))
  as the family’s timescale. They forecast alike at 15 minutes; at
  hourly steps the records’ shorter timescale gives an unstable set more
  often and is no better where both work, so the time to peak stays the
  recommendation.

## pdmS7 0.8.1

- **New article: “What limits automatic calibration: a study”.** On 30
  synthetic catchments, four searches are set against the score of the
  true parameters; the search reaches the best fit the record allows.
  Profiles show that `kb` cannot be recovered from flow records: across
  a hundredfold range it barely changes the flow, because the slow
  recharge hides it. It matters only in a drought long enough to stop
  recharge, where equally good calibrations can disagree by a factor of
  more than three in low flow.
- The search results are stored as `inst/extdata/search_study.csv`;
  `inst/benchmarks/search_methods.R` regenerates them, including the
  staged search with the polish confined as before version 0.8.0.
- With the free polish of version 0.8.0, staged DDS fits less well than
  staged L-BFGS-B in all 30 synthetic catchments (29 with the old
  confined polish);
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)’s
  help says so.

## pdmS7 0.8.0

- **Staged calibration’s polish searches the full bounds.**
  [`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md)
  used to confine stage 3 to a quarter of each range either side of
  stage 2’s values. Stage 1 fits with the surface stores at their
  starting values, and where the true stores are much slower it can
  settle on the wrong slow stores; the confined polish could not undo
  that. On 30 synthetic catchments it left two far short of their true
  parameters’ score (NSE 0.904 against 0.995 in one). With the full
  bounds, every catchment comes within 0.001 of the truth’s score.
  `band` still confines the polish when asked. Staged results change.
- **DDS.** `calibrate_pdm(method = "dds")` adds dynamically dimensioned
  search (Tolson and Shoemaker, 2007), a derivative-free global search;
  `control$maxit` is its budget of model runs per start. It accepts
  threshold objectives, and
  [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md),
  [`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md),
  [`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md),
  [`log_auto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  and the app offer it. On the smooth NSE of the standard structure,
  L-BFGS-B remains the better choice: given the same number of model
  runs, DDS fitted less well in 29 of 30 synthetic catchments.
- **The large-sample article checks each calibration against the
  truth.** Calibrations reach the true parameters’ score in almost every
  catchment, so a parameter that still comes back wrong (`kb` above all)
  cannot be recovered from the record, whatever the search. The article
  now calibrates all parameters at once.
- `inst/benchmarks/search_methods.R` compares the searches on the large
  synthetic sample.

## pdmS7 0.7.0

- **Large samples.**
  [`synthetic_basins()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_basins.md)
  writes a sample of synthetic catchments, each with its own climate and
  true parameters, as basin folders ready for
  [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md),
  with each truth saved beside it. New article: “A large sample: what
  automatic calibration recovers”.
- [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)’s
  default structure takes each basin’s time step from its data, so daily
  and 15-minute basins need no structure of their own.
- Parallel workers in
  [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  and
  [`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md)
  now use the main session’s library paths, so a package installed
  outside the default library (by `R CMD build`, renv or a user library)
  works with `cores > 1`; workers used to fail with “there is no package
  called ‘pdmS7’”.
- [`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  and
  [`batch_results()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  report `wettest_score`, the headline over the held-back wettest years.

## pdmS7 0.6.0

- **The standard preset has a realistic water balance.** It used to
  drain its soil to groundwater within a day (`kg` = 24 h), so the soil
  stayed nearly empty and evaporated about 2 per cent of potential. It
  now has a soil capacity up to 300 mm (`cmax`) and `kg` = 4000 h:
  evaporation about half of potential, baseflow index near 0.6.
  [`pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/pdm_model.md)’s
  defaults and the parameter catalog match. Results from the preset or
  default models change; calibrations of real data, which set their own
  parameters, do not.
- [`initial_state_from_flow()`](https://jonpayneea.github.io/PDMS7/reference/initial_state_from_flow.md)
  warns when a steady start would need more soil storage than the store
  holds; the soil is then capped and the run starts out of balance. This
  used to happen silently.
- [`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)
  takes `start` and `baseflow_fraction`, like
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md).

## pdmS7 0.5.0

- **Extrapolation checks in calibration projects.** Calibrations are
  fitted to the floods in the record and used for larger ones; this
  release makes that visible before sign-off.
  - [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
    holds back the two wettest water years (October to September) in the
    calibration and validation windows by default. No calibration, trial
    or validation scores them;
    [`test_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
    reveals them once, with the test window, under the same rules. Set
    `wettest_years` to change the number, or 0 to hold none back.
    Holding years back needs a `time` column and enough record to leave
    three years, so short records now need `wettest_years = 0`.
  - Each automatic calibration keeps the parameter sets it tried that
    score within `tie_tolerance` (default 0.02) of its best headline, up
    to 50 spread-out sets. The test reports, for each held year, the
    observed peak, the candidate’s peak and the range across those sets.
  - `register_data(highest_gauged_m3s =)` records the highest check
    gauging. Flows above it, where the rating is extrapolated, are
    counted window by window at registration and flagged in the test.
    The fit is unchanged.
  - The report, the app and
    [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
    (through `basin.yml`) carry all three. Sign-off needs the test when
    years are held back, even without a test window.
  - Projects registered before 0.5.0 hold nothing back and reproduce as
    before.
- **Synthetic rivers.**
  [`synthetic_catchment()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_catchment.md)
  builds a calibration problem with a known answer: stochastic rain
  drives a PDM with a lowland water balance, named storms can be added,
  and a simulated gauge records the flow with persistent (AR(1)) error
  and an optional rating bias above the highest gauged flow.
  [`synthetic_rain()`](https://jonpayneea.github.io/PDMS7/reference/synthetic_rain.md)
  generates rain and PET at any step by four methods: Neyman-Scott and
  Bartlett-Lewis rectangular pulses, a Markov chain with gamma amounts,
  and seasonal block resampling of a real record.
  [`fit_rain()`](https://jonpayneea.github.io/PDMS7/reference/fit_rain.md)
  fits the first three to a gauge record, including one read with
  reach.io;
  [`rain_statistics()`](https://jonpayneea.github.io/PDMS7/reference/rain_statistics.md)
  gives the pulse models’ exact statistics;
  [`rain_parameters()`](https://jonpayneea.github.io/PDMS7/reference/rain_parameters.md)
  the illustrative built-in values.
- [`wettest_years()`](https://jonpayneea.github.io/PDMS7/reference/wettest_years.md)
  ranks the water years of any record by peak flow.
- `calibrate_pdm(archive =)` keeps every trial’s parameters and a score
  of your choosing.
- New articles: “Larger floods: extrapolation and the rating”, built on
  a synthetic river whose true peaks are known, and “Synthetic rivers:
  try everything on a known answer”.
- The benchmark protocol is at version 0.3: a PDM-only extrapolation
  check on the wettest years, outside the head-to-head comparison, which
  holds no years back.

## pdmS7 0.4.1

- **Calibration starts from the first observed flow.** Every trial of
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md),
  and every run in a calibration project, starts in steady state at the
  first observed flow, so a slow groundwater store is full when scoring
  begins and cannot bias its own parameters.
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  gains `start` (`"flow"`, the default, or `"soil"` for the earlier
  start), `baseflow_fraction` and `start_flow`.
  [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  records the rule; projects registered earlier keep the soil start, so
  their recorded runs still reproduce. Calibrations will differ from
  those of 0.4.0 where the warm-up was short.

- Locks on the calibration log and on shared CSV files recover from a
  dead session’s lock without the race that could delete a fresh one.

- The run log and batch status refuse to append rows under a header with
  different columns.

- [`validate_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  re-checks the candidate under the lock.

- [`calibration_app()`](https://jonpayneea.github.io/PDMS7/reference/calibration_app.md)
  restores the identity options when it closes.

- The C++ binding unpacks parameters in one place.

- Six new pages on the website: “Where to start” (reading paths by
  role), “Preparing your data” (from EA sources through reach.io to
  model files, with a checklist), “Reviewing a calibration: a Steward’s
  guide”, a glossary, troubleshooting, and further reading. The home
  page states the package’s purpose, “Get started” opens the reading
  paths, and the roadmap is rewritten.

- The benchmark protocol is at version 0.2, with its decisions closed.

- Every source file is commented: the R package, the compiled core, the
  golden checker and the tests (each test states what it guards). A code
  review accompanies it, in `code-review.md` and under Guides on the
  website: no errors in the hydrology; two medium and seventeen low
  findings, ranked, with remedies for decision.

- [`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md)
  reports “No forecast origins fit in the window” for a window too
  narrow for any origin, instead of an internal error.

## pdmS7 0.4.0

- New
  [`pdm_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/pdm_hindcast.md)
  reruns past forecasts from many origins, using the rain that fell,
  with no updating, persistence, AR post-processing as in IMFS (the
  Environment Agency 2024 default, a default-family set from the model’s
  response time, and optionally a set fitted to the calibration period)
  and state correction.
  [`hindcast_scores()`](https://jonpayneea.github.io/PDMS7/reference/hindcast_scores.md)
  scores each lead time: NSE, RMSE, bias, skill against persistence,
  threshold POD, FAR and CSI, and lead time over time to peak, so
  catchments and models line up on one axis. It also scores another
  model’s forecasts given as a table.
  [`plot_hindcast()`](https://jonpayneea.github.io/PDMS7/reference/plot_hindcast.md)
  plots any score against lead time.

- New
  [`pdm_response_time()`](https://jonpayneea.github.io/PDMS7/reference/pdm_response_time.md)
  measures a model’s time to peak, recession and centroid lag from a
  pulse of rain, with an optional check against an FEH time to peak.

- New
  [`ar_ea_default()`](https://jonpayneea.github.io/PDMS7/reference/ar_from_response_time.md)
  and
  [`ar_from_response_time()`](https://jonpayneea.github.io/PDMS7/reference/ar_from_response_time.md)
  give AR coefficients in the Deltares convention used by IMFS and
  reach.postproc; the second follows
  [`reach.postproc::default_family_ar_parameters()`](https://rdrr.io/pkg/reach.postproc/man/default_family_ar_parameters.html)
  exactly.

- New
  [`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)
  and
  [`pdm_stages()`](https://jonpayneea.github.io/PDMS7/reference/pdm_stages.md)
  calibrate in stages: water balance and slow stores on log NSE with a
  volume penalty, then the fast stores on NSE, then a joint polish
  within narrowed bounds.
  [`log_staged_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)
  writes one `auto_calibration` entry per stage, each recording its
  stage; `calibrate_batch(staged = TRUE)` does the same per basin and
  resumes from the last finished stage.

- [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  gains `objective = "log_nse"` and `volume_weight`, a penalty on the
  absolute volume error.

- [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  handles snow basins: with `snow: true` in `basin.yml` and a
  `temperature` column, PACK at fixed parameters turns precipitation
  into rain and melt, the PDM is calibrated on that, and a log note
  records the PACK settings and the raw forcing’s checksum.

- New articles, “Testing forecasts with hindcasts” and “AR and ARMA
  error correction, explained”. “Automatic calibration” and “Calibrating
  many catchments” cover staged calibration and snow basins.

- Internal: the calibration functions are split into smaller helpers; no
  results change.

- The introductory articles are rewritten in plain English with figures
  of the model running: “How the PDM works” (buckets, dry and wet
  ground, the saturated area, the two paths to the river, the water
  balance, and what each setting does), “How the snow model works” (a
  winter, rain on snow, snow cover, settings, and snow with the PDM) and
  “Your first model run” (from data files to a calibrated, saved model).
  Each ends with a short equations appendix; the new “Model equations”
  page holds the full reference.

- New
  [`write_pdm_config()`](https://jonpayneea.github.io/PDMS7/reference/write_pdm_config.md)
  writes a configuration that
  [`read_pdm_config()`](https://jonpayneea.github.io/PDMS7/reference/read_pdm_config.md)
  reads back exactly; general YAML writers round numbers to seven
  significant figures.

- “Calibrating many catchments” is rewritten as a plain-English,
  step-by-step guide to
  [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md),
  run live with an interruption and a failure. “Automatic calibration”
  is rewritten in plain English.

- New
  [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  runs one calibration protocol on every basin in a folder (each with
  `forcing.csv`, `flow.csv` and `basin.yml`), giving each basin its own
  calibration-log project, in parallel with `cores`. It can be stopped
  and restarted at any point: each basin carries on from its last
  completed step and finished steps are never repeated. Failures are
  recorded with their reason without stopping the batch.
  [`batch_status()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  shows progress from `batch-status.csv`;
  [`batch_results()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  collects the projects.

- Three new articles: “Scoring a simulation” (every score, with the
  contingency table, event matching, events against steps and the
  performance diagram), “Automatic calibration” (bounds, log-scale
  search, the two optimisers and threshold objectives) and “Inside the
  logs” (project folders, entry files, the checksum chain, the run log
  and the register). The site’s articles are regrouped into Calibration,
  Records and review, and Forecasting.

- New
  [`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md)
  calibrates several model structures alike, in parallel with `cores`,
  logs each as a structure and an automatic calibration linked by a
  comparison id, and ranks them on the validation window, with optional
  two-way cross-validation.
  [`structure_comparison()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md)
  rebuilds a ranking from the log.
  [`structure_set()`](https://jonpayneea.github.io/PDMS7/reference/structure_set.md)
  gives the standard PDM and seven one-change variants;
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
  gives default bounds from `inst/calibration-bounds.csv`. The report
  and the app (a new Structures tab) show comparisons.

- [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  and
  [`log_auto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  gain `log_scale`, searching named parameters uniformly in log(value).

- [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  gains an optional `test` window, scored once by the new
  [`test_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  entry after every choice is made, and required before sign-off when
  registered.

- New article, “Choosing a model structure”.

- New article, “Calibrating many catchments”: one logged protocol
  applied to a batch of basins, budgeting, catching failures, judging
  scores as a distribution, checking whether multi-start runs agreed,
  and how well calibration recovers known parameters.

- New
  [`read_entry()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  returns one calibration-log entry in full, and
  [`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  gains `validation_score`, the candidate’s headline score on the
  validation window.

- New threshold verification.
  [`pdm_threshold_scores()`](https://jonpayneea.github.io/PDMS7/reference/pdm_threshold_scores.md)
  scores one or more thresholds at once: events (episodes above a
  threshold, merged across short gaps and matched within a timing
  tolerance) give probability of detection, false alarm ratio, critical
  success index and frequency bias, plus crossing time, peak timing,
  peak, duration and volume errors for each hit; a step-by-step count
  adds probability of false detection, equitable threat score and Peirce
  skill score.

- [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  gains `thresholds` (flows, or levels converted through a registered
  `rating` table and never extrapolated) and event settings. Every
  logged run is scored at every threshold, and a threshold score such as
  `csi:Flood Warning` may be the headline. The report adds a threshold
  table and a performance diagram.

- [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  gains `method = "nelder_mead"`, a derivative-free optimiser kept
  within the bounds, and an optional threshold term in the objective
  (`thresholds`, `threshold_weight`, `threshold_score`), or
  `objective = "threshold"` alone.
  [`log_auto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  passes registered thresholds by name and records the method, objective
  and number of model runs. The default method and objective are
  unchanged.

- New article, “Logging a manual calibration”: a complete project from
  start to sign-off, integrity checks and tampering, the report, and
  tracing operational runs with the run log.

- New
  [`calibration_app()`](https://jonpayneea.github.io/PDMS7/reference/calibration_app.md):
  a Shiny app over the calibration log for staff who prefer not to
  script. Setup (start, register data, select structure), Trial (adjust
  parameters, preview the hydrograph and scorecard against the parent,
  save with a verdict and reasoning; notes; automatic calibration),
  History (path, every run, compare two runs, propose and validate a
  candidate), Report (integrity, build and download) and Sign-off. Every
  button calls the exported function a script would, so the same rules
  apply. shiny is a suggested package, needed only for the app.

- New opt-in run log. With `options(pdmS7.run_log = "runs.csv")` or
  `PDMS7_RUN_LOG` set, every
  [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md)
  call, and so
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
  and
  [`sim_snow_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_snow_pdm.md),
  appends one row: who, when, an optional tag, the model’s
  [`pdm_fingerprint()`](https://jonpayneea.github.io/PDMS7/reference/pdm_fingerprint.md),
  a checksum of the forcing, period, versions, run time, and success or
  the error message. Calibration evaluations, spin-up cycles and the
  calibration log’s own reruns are not logged. With a register of
  calibration projects set (`pdmS7.register` or `PDMS7_REGISTER`), each
  run is marked `approved`, `superseded` (its project was reopened) or
  `unapproved`; runs are never blocked. New
  [`read_run_log()`](https://jonpayneea.github.io/PDMS7/reference/read_run_log.md),
  [`approved_configurations()`](https://jonpayneea.github.io/PDMS7/reference/approved_configurations.md)
  and
  [`pdm_fingerprint()`](https://jonpayneea.github.io/PDMS7/reference/pdm_fingerprint.md).
  Logging is off by default and a logging failure never stops a run.

- New calibration log: an append-only, tamper-evident record of a
  calibration project.
  [`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`select_structure()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`log_trial()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`log_auto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`log_note()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`propose_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`validate_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md),
  [`sign_off_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  and
  [`reopen_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  each write one YAML entry recording who, when, which data and
  parameters, the scores and the reasoning. Entries are chained by MD5,
  data are copied and checksummed, and every run records a checksum of
  its output.
  [`verify_project()`](https://jonpayneea.github.io/PDMS7/reference/verify_project.md)
  detects edits, gaps, changed data and runs that no longer reproduce. A
  Steward cannot sign off their own calibration.
  [`read_project()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md),
  [`project_trials()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  and
  [`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  read the record. Design: `calibration-log-design.md`.

- New
  [`build_report()`](https://jonpayneea.github.io/PDMS7/reference/build_report.md)
  writes a calibration report generated from the log: a self-contained
  HTML file with embedded figures, and a Markdown copy. It shows
  integrity status first, then data and scoring windows, model
  structure, the calibration path as a tree and a table, the candidate’s
  hydrographs, flow-duration curves and scorecard for both windows,
  parameter sensitivity on a shared scale, sign-off history, and the
  final configuration. It uses base graphics only.

- New
  [`pdm_scorecard()`](https://jonpayneea.github.io/PDMS7/reference/pdm_scorecard.md):
  NSE, log NSE, KGE and its components, RMSE, signed and absolute volume
  error, peak error, and the Yilmaz et al. (2008) flow-duration-curve
  signatures.

- Five new illustrated articles on the package website: choosing model
  components, starting states, calibration, forecast updating, and the C
  core. Articles, guides and the function reference are grouped by topic
  in the site navigation. DESCRIPTION gains `URL` and `BugReports`.

- [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  gains opt-in multi-start calibration through `starts` and `seed`.
  Start 1 is the configured point; extra starts are drawn uniformly
  inside the bounds, all are optimised, and the best objective is
  returned. The result gains `start_results`, a table of per-start
  objective, convergence code, evaluation count and fitted parameters.
  The default `starts = 1L` runs the same single optimisation as earlier
  versions.

- [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md),
  and so
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
  and
  [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md),
  now run a compiled time loop for every capacity distribution;
  standard, split and demand recharge; and cascade, power-law and
  exponential stores on either route. It is about 430 times faster.
  Output agrees with the R loop to rounding: bit-identical on R 4.3,
  with last-place differences on R 4.5 and later, where calibrated
  parameters can differ from earlier versions by about 1e-13 relative.
  `options(pdmS7.engine = "r")` forces the R loop, which remains the
  reference implementation. Building from source now needs a compiler
  (Rtools on Windows); cpp11 is a build-time dependency only.

- Added `inst/benchmarks/time_solvers.R` and a report at
  `docs/benchmarks/solver-timing.md` timing both solvers and both
  engines on daily and 15-minute series.

- [`pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/pdm_model.md)
  (and so
  [`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md)
  and
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md))
  warns, once per session, when the Smith cubic solver is used with a
  step above 1 hour. Its error grows with the square of the step and
  reaches 60 to 100 per cent of peak flow at a daily step. Results are
  unchanged; the default adaptive solver is unaffected.
  `inst/benchmarks/smith_step_error.R` reproduces the evidence.

- The compiled time loop now sits behind a language-neutral C interface
  (`src/pdm_core.h`, interface version 2), so other languages can call
  the same model code. `src/pdm_engine.cpp` is a thin R wrapper over it,
  and results are unchanged. The core validates its own inputs and
  leaves the caller’s state untouched on error. `tools/core/README.md`
  covers building it without R.

- Golden test files in `inst/golden/` hold inputs and expected outputs
  from the R reference, for checking any binding of the core.
  `tools/core/check_golden.c` checks them from plain C.

- The triangular capacity distribution is now inverted exactly (cube
  root or the trigonometric solution of a cubic) and the lognormal by
  safeguarded Newton iteration, in place of
  [`uniroot()`](https://rdrr.io/r/stats/uniroot.html) with a 1e-10
  tolerance. Storage round trips improve from about 2e-11 to 1e-14 mm;
  model outputs for these two distributions change by at most about
  3e-11.

- Fixed: the rectangular distribution’s
  [`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md)
  used (cmin + cmax) / 2 while its other methods used the Pareto b = 1
  form, which can differ in the last place. A soil store filled exactly
  to capacity could then fail with “Soil storage exceeds capacity_mean”.
  Both now use the Pareto form, so
  [`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md)
  can change in the last place.

- The PACK snowpack also runs in the compiled core, about 540 times
  faster than its R loop and bit-identical to it on R 4.3.
  [`sim_pack()`](https://jonpayneea.github.io/PDMS7/reference/sim_pack.md)
  and
  [`sim_snow_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_snow_pdm.md)
  use it automatically. The core gains `pdm_pack_run()` for snow alone
  and `pdm_snow_run()` for snow feeding PDM.

- New
  [`initial_state_from_flow()`](https://jonpayneea.github.io/PDMS7/reference/initial_state_from_flow.md):
  a warm start in steady state with the flow observed at the start of a
  run. Routing stores deliver their share of the flow, the soil store is
  set so that recharge equals baseflow, and delay queues hold the water
  in transit. It replaces an arbitrary soil fraction for short test runs
  and forecasts. Also in the core as `pdm_state_from_flow()`.

- Forecast updating also runs in the compiled core:
  [`correct_state()`](https://jonpayneea.github.io/PDMS7/reference/correct_state.md)
  (state correction, Moore 2007 Eq. 28-30) and
  [`update_forecast()`](https://jonpayneea.github.io/PDMS7/reference/update_forecast.md)
  (ARMA error prediction, Eq. 31-42), with `pdm_correct_state()` and
  `pdm_update_forecast()` for other languages. Results are bit-identical
  to the R code. Fitting the ARMA coefficients stays in R.

- The compiled core is now plain C99 (`src/pdm_core.c`), so other
  languages need only a C compiler to build it. Results are
  bit-identical to the previous C++ version.

- Fixed: the compiled engine rejected an initial state whose values were
  all stored as integers, for example one read with
  [`read.csv()`](https://rdrr.io/r/utils/read.table.html). The R loop
  accepted it.

- A peak timing objective is deferred.

## pdmS7 0.3.1

- Added three executable vignettes: PDM equations and functions, PACK
  snow accounting and defaults, and a synthetic
  calibration/validation/restart workflow.
- Added reproducible process diagrams, soil/cover curves and workflow
  hydrographs.
- No changes to the numerical model APIs or equations.

## pdmS7 0.3.0

- Added optional PACK S7 snow components, conservative substep
  accounting, areal depletion, fresh-snow memory and coupled PDM
  restart.
- Added the image parameter preset (explicit hourly-unit assumption) and
  a distinct report-typical preset, with full parameter mapping and
  source notes.
- Added multi-objective metrics, weighted multi-start calibration,
  evaluated Pareto trade-offs, configurable scales and joint snow/PDM
  parameter paths.
- Documented river networks and additional state assimilation as future
  work.

## pdmS7 0.2.0

### Flode Tier 3 engineering target

- Introduced `Flode`-prefixed S7 classes with existing class names
  retained as aliases.
- Added
  [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
  with explicit depth units, integer minute steps, data.table output,
  UTC timestamps, and warm-up flags.
- Added safe YAML loading and an illustrative configuration file.
- Replaced CSV input with `fread()` and tabular assembly with
  `rbindlist()`.
- Added state-object validation and structured debug logging.
- Converted numerical regression checks to testthat and added interface
  tests.
- Added roxygen source documentation, renv, lintr, and pinned shared
  Flode CI.
- Retained the earlier simulation functions and output column names for
  compatibility.

This release targets the Tier 3 technical checks. It is not formally
approved for operations: human maintainer attribution, independent
review, and catchment validation remain required. Version 0.1.0
serialized S7 objects should be rebuilt from their saved configuration
because the canonical class names have changed.
