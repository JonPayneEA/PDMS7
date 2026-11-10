# pdmS7 0.19.0

- **Progress during long calibrations.** `calibrate_project()` said almost nothing between
  registering the data and the end, which on a long record is hours, so there was no telling
  whether it was running. It now reports its plan at the start; each structure step and each
  calibration stage as it begins; each structure's calibration and validation scores and the
  time it took; and, after each structure step, the time left at the pace so far. During any
  search, `calibrate_pdm()` reports every minute or so how many model runs the current start
  has made (out of how many, for DDS) and how long each takes.
- **Comparisons on several cores** cannot write to the console, so each structure's progress
  goes to `progress.log` in the project folder, and the console says so.
- `options(pdmS7.progress_every = 0)` turns the minute-by-minute lines off; any other number
  sets their interval in seconds.
- **Report fix.** The candidate's "Calibration window" hydrograph and flow-duration figures
  showed the validation window: the figures were drawn after the loop that made them, and
  every one saw its last window. Each window's figures now show that window.
- **Report: the held-back wettest years** each get a hydrograph of observed and simulated
  flow, once the test has scored them, beside the table of their peaks.
- **Report: the largest events.** A table and a figure of the ten largest events of the
  record by observed peak, in whichever window they fall, with each one's window, peak error,
  timing error and event NSE, and its rain.

# pdmS7 0.18.1

Fixes from a review of 0.18.0.

- **`calibrate_project()` without a validation window** now stops before the search when test
  years are registered, or the wettest years are held back (the default on a long record). The
  test scores a validated candidate, so before it failed only after the whole calibration had
  run. Give `validation`, or `wettest_years = 0`.
- **A rerun of `calibrate_project()`** on a project that has a candidate now finishes whichever
  of the validation, the test and (with `report = TRUE`) the report are missing, instead of
  returning at once. A run interrupted after proposing its candidate can be finished, and a
  report added later.
- **`recommend_structure()`** broke ties on the size of the median peak error, so errors of
  -50% and +50% cancelled to a perfect zero and beat a structure steadily within 10%. It now
  takes the median of the absolute errors. `calibration_checks()` reports it in its summary as
  `median_abs_peak_error`.
- **`pdm_hindcast()`** spread its forecast origins from the first to the last row of the
  window, so a window with gaps, such as one leaving out held-back years, was forecast inside
  them too. Origins now fall only on rows of the window.

# pdmS7 0.18.0

- **`calibrate_project(recommend = TRUE)`** chooses the structure before calibrating. The
  structure given is the starting point; `recommend_structure()` then chooses the recharge
  rule, the soil store distribution and the groundwater store in turn, each by a structure
  comparison on the record, and the stages start from the calibration of the structure it
  recommends. Every comparison and every choice, with its reason, is in the project's log. It
  needs a validation window and costs one calibration per option compared.
- **`stages` and `bounds` of `calibrate_project()`** may be functions of a configuration, such
  as `function(config) pdm_stages(config, events = TRUE)`, so that they suit whichever
  structure is chosen. New `overrides` and `exclude` arguments set the search ranges for the
  default stages and bounds and for every structure compared.
- **`recommend_structure()`** gains `overrides` and `exclude`, passed to
  `compare_structures()`.

# pdmS7 0.17.1

- **New article, "Tailoring calibration to the largest events in the app".** It follows one
  project through the Events tab of `calibration_app()`, with screenshots: loading the largest
  events, reading their peak and timing errors, moving the surface stores and the time delay,
  saving the setting as a trial with a verdict and reasons, checking the recessions, refitting
  the other parameters from the trial on the Trial tab, and proposing and validating the
  result. The scripts that build the project and take the screenshots are in
  `tools/app-screenshots`.
- **Events tab fix.** A slider rounds the run's value to its step, so `b` = 0.439941 showed as
  0.44. The tab took that rounding for a change: it reran the whole record, as for any change
  to `b`, and a saved trial recorded a change to `b` nobody made. A slider now counts as moved
  only when it is more than half a step from the run's value. The event plots are also drawn
  at a higher resolution, so their labels can be read.

# pdmS7 0.17.0

- **`water_balance()`** checks the water balance before calibrating, for the whole record and
  for each water year (from October). Over a year a catchment stores little, so its loss, rain
  minus flow, is mostly evaporation, and two limits follow: flow cannot exceed rain, and the
  loss cannot much exceed the potential evaporation. Years beyond either limit are flagged, and
  so are years whose runoff ratio stands apart from the rest. A lasting change, such as a new
  rating from one year on, can leave no single year apart, so the years are also split at each
  boundary in turn and the largest change in the mean runoff ratio is flagged when it exceeds
  25%; years already flagged on their own are left out of that test, so one bad year is not
  mistaken for a change. Steps with missing flow are left out of all three totals, and part
  years are reported but not judged. It also returns a double-mass curve and the baseflow
  index. `plot()` and `autoplot()` draw each year against the Budyko limits and Fu's curve,
  the ratios year by year, and the double-mass curve.
- **The checks article** has a new section, "Year by year: the water balance", in which a new
  rating from one year on is found by the change test and seen in the double-mass curve. Its
  record now covers five whole water years, and its text on flagged parameters and peak
  errors is written from the results rather than fixed, so it stays true if the example
  changes.

# pdmS7 0.16.0

Standard visuals, part 2 of 4: calibration and event plots.

- **Event plots.** Event tables from `find_events()`, `screen_events()`, `event_scores()` and
  `calibration_checks()` now carry the class `pdm_events`, and `plot()` and `autoplot()` draw
  three standard plots:
  - `balance`: each event's rain against its quick flow on log scales, with a dashed line at
    the runoff-ratio limit and grey lines at 0.5 and 0.1. An event above the limit shed more
    quick flow than the rain that fell, so the rain, the area or the flow is wrong for it.
  - `peaks`: simulated against observed peaks, with the 1:1 line and a 20% band.
  - `timing`: each peak's timing error against its size.
  Screened events are drawn hollow; events from `calibration_checks()` are coloured by window.
- **Checks plots.** `plot()` and `autoplot()` on `calibration_checks()` draw where each
  parameter sits within its search range, on the scale the search used, with any at a bound
  flagged; or the project's events as above.
- **The calibration path.** `calibration_path()` gathers a project's automatic calibrations in
  order: each stage's scores, every start's result, and the candidate's scores in each window.
  It prints a summary, and `plot()` and `autoplot()` draw the scores after each stage, each
  start's objective, and the candidate in each window.
- **"Automatic calibration from start to finish" updated.** Step 1 is now preparing and
  registering the data, with a flow diagram of the preparation functions; step 2 checks the data
  and the events; step 5 shows the check plots; a new section runs the same calibration in one
  call with `calibrate_project()` and plots its stages and parameters.
- **New article: "Checking the data and the events".** Every check in the order to run
  them: annual totals and the runoff ratio, each event's rain against its quick flow,
  screening, parameters at a limit, peaks and timing, and the stages. A copy of the record with
  a mistyped area and an under-recording rain gauge shows each check firing.
- **Renderer.** Hollow points, labelled axis positions, an x range, and score plots whose
  axis need not start at zero; the ggplot2 legends of mixed point and line plots merge.

# pdmS7 0.15.0

The helper functions of the Beggearn Huish calibration script, tested and in the package.

- **Data preparation.** `read_hydro_series()` reads hydrometric exports: split year, month and
  day columns in any of their spellings, one time column in the common formats, or a date and a
  time column, in any time zone; it refuses a file whose timestamps repeat. `align_series()`
  puts several series on one grid over the period they share. `convert_units()` converts mm per
  hour or day, metres, litres a second and megalitres a day, and with `"auto"` works the unit
  out from plausible annual totals. `fill_gaps()` fills by a named rule (stop, zero,
  interpolate up to a longest gap, none) and `zero_negatives()` sets negative values to zero.
  `check_inputs()` reports the period, gaps, negatives, annual totals and runoff ratio, and
  flags anything implausible.
- **Preparation in the log.** Each of those functions notes what it did on the series it
  returns (`preparation_notes()`), and `register_data()` writes the notes into the
  registration entry; the report shows them in its Data section. Data registered without
  notes register exactly as before.
- **`calibrate_project()`** runs a whole logged calibration in one call: project, registration,
  structure, staged calibration, candidate, validation when a window is registered and test
  when one is. A finished project is left as it is; an unfinished one is moved aside.
- **`candidate_model()`** returns the model of a project's candidate.
- **`event_run()`** runs a project's model over a separate event file: from the record's own
  state when the event lies inside the registered record, otherwise from steady state at its
  first flow, with missing evaporation taken from the record. It prints the event's scores
  and `plot()` draws its hydrograph.
- **`calibration_checks()`** returns a `pdm_calibration_checks` list whose print method shows
  the parameters at a bound and the largest events in each window.
- **Article.** The data preparation article has a new section running the same steps with these
  functions.

# pdmS7 0.14.0

Standard visuals, part 1 of 4: the house style and the run diagnostics.

- **House style.** Every standard plot uses the Okabe-Ito colours, which stay distinct with the
  common forms of colour blindness, and gives each colour one meaning: observed flow black,
  the model blue, rain sky blue, a second run or a change vermillion, the calibration and
  validation windows light grey and light orange, thresholds dashed reddish purple.
  `pdm_colours()` returns them by role for your own figures, and `pdm_palette()` gives a fixed
  order for series of equal standing. The previous palette's green and red become almost
  identical to a reader with red-green colour blindness.
- **Base R and ggplot2.** Each standard plot builds one description of what to draw, and two
  renderers draw it: `plot()` in base R and `autoplot()` in ggplot2, so the two always agree.
  ggplot2 is a suggested package: `plot()` always works, and the `autoplot()` methods register
  when ggplot2 is installed. `theme_pdm()` is the ggplot2 theme.
- **Figure sizes.** `pdm_save()` writes PNG, PDF or SVG at standard sizes: `screen`, `report`
  and `report_half` (A4), `slide` (16:9) and `journal_single` and `journal_double`.
- **Run diagnostics.** `pdm_series()` gathers a simulation with its observed flow, rain,
  windows, thresholds and an optional second run; `project_series()` builds it for any model
  entry of a calibration project. `plot()` and `autoplot()` draw a hydrograph with rain hanging
  from the top, flow duration curves, cumulative volume, or residuals with their 30-day
  running mean, over the whole record, a window or any period.
- **Restyled plots.** `plot_hindcast()`, `plot_recession()` and `plot_workbench()` use the
  house style, and each gains `plot()` and `autoplot()` methods on its object.
  `hindcast_scores()` now returns a `pdm_hindcast_scores` data.table so that they dispatch. The
  workbench draws a trial in vermillion (it was orange) and observed flow in black;
  `plot_hindcast()`'s `legend` argument is kept but the legend now sits below the plot.

# pdmS7 0.13.0

- **Events workbench.** `event_workbench()` gathers a run's `n` largest events (10 by
  default) in the calibration or validation window, screened with `screen_events()`.
  `workbench_try()` reruns them with parameters changed and scores each one;
  `plot_workbench()` draws them before and after. A change to the surface stores or the time
  delay reruns only the event windows, from saved states, exactly as a full run would; any
  other change reruns the whole record. The calibration app has a new Events tab: choose the
  number of events, move sliders for the surface stores, the time delay and `b`, and save the
  setting as a logged trial; a button draws the recession plot of the record and the model.
  The calibration log article has a new section on it.
- **Structure recommendation.** `recommend_structure()` chooses the recharge rule, then the
  soil store distribution, then the groundwater store, each by a logged structure comparison
  on the validation window. Structures with a parameter at a bound are set aside; those within
  the tie tolerance of the best are equally good; the incumbent is kept when it is among them;
  otherwise the smallest median peak error on the largest validation events wins, then fewer
  parameters. Each step's choice and reason is written to the log as a note. The choosing a
  structure article has a new section on it.
- **Catchment rainfall from gauges and radar.** `merge_rainfall()` builds catchment-average
  rain by Thiessen polygons, multiquadric interpolation of the gauges (Hardy, 1971), or
  conditional merging of gauges and gridded radar (Sinclair and Pegram, 2005) with multiquadric
  surfaces: the gauges set the level, the radar the storm's shape between them.
  `rainfall_cross_validation()` leaves out each gauge in turn and chooses the multiquadric shape
  parameter; `catchment_mask()` finds the grid cells inside a catchment boundary. Radar can be
  passed as a function returning one step's grid, so a long record need not be held in memory.
  On a synthetic storm field, conditional merging matched the true catchment total within 1%
  with a correlation of 0.98, against 0.78 for Thiessen.
- `rainfall_field()` gives one step's rain field on the grid, for mapping a storm.
- **New article: "Catchment rainfall from gauges and radar".** Why rain is the main error, the
  three methods shown on a made-up storm (maps and cross-sections), checks at the gauges, over
  the catchment and through the river, and how to use H19 radar.
- `h19_radar()` reads gridded H19 radar from the archive's daily NetCDF files (either variable
  name, 2010 to 2019 or 2021 on), crops it to an extent and hands `merge_rainfall()` one
  15-minute grid at a time, loading each day once. `terra` and `ncdf4` are suggested packages.
- **New article: "Automatic calibration from start to finish".** The whole calibration in
  plain English, with flow diagrams: the record's windows, the search loop, choosing the
  structure, the four stages, the checks and where each failure leads, the last steps and the
  log. A small calibration runs live through every step.
- **New article: "Getting the floods right".** A plain-English walk through why a good score
  can hide bad floods, and the tools against it: finding and screening events, the acceptance
  checks, the events stage, the workbench, recession analysis, what a record can tell apart
  about structure, and a suggested order of work. Its worked example runs live.
- **Can the record choose the recharge rule?** `inst/benchmarks/recharge_rules.R` calibrates
  nine made-up catchments with standard, split and demand recharge. Validation scores found
  the true rule in all nine, by 0.08 to 0.25 in log NSE, against 0.003 for the groundwater
  store. Whether the baseflow line rises with each event's quick flow separates split recharge
  from the other two without a model. The calibration study article has a new section on it.

# pdmS7 0.12.0

- **Event screening.** `screen_events()` flags events a hydrologist would not trust: a rise
  lost in the baseflow (`small_rise`: the peak rises less than `min_rise` times the baseflow
  beneath it), more quick flow than rain, gaps in the flow window, and peaks above the highest
  gauged flow. Every test works on flow above the baseflow line, so a high, steady baseflow is
  neither counted as event runoff nor mistaken for a rise. The events objective
  (`event_screen`) and `calibration_checks()` (`screen`) leave flagged events out by default,
  except peaks above the highest gauging, which are flagged but kept; in a project the
  registered highest gauged flow is used.
- **Events rerun on their own.** `event_states()` runs the record once and saves the model's
  state at the start of each event's window; `run_events()` reruns only the windows, from those
  states. With the same model the result is exact. After changing the surface stores or the
  time delay, a lead-in five times the sum of the surface time constants brings event peaks
  within 0.1% of a full run; changing the soil or groundwater stores needs the states saved
  again, and `run_events()` refuses it. This is the groundwork for an events workbench and
  for tracing trade-offs between whole-record and event fit.
- **Recession analysis.** `recession_analysis()` plots how fast flow falls against how high it
  is, from dry, falling steps long enough after rain, and fits the slope of that relation with
  a bootstrap interval over whole recessions. The slope identifies the groundwater store (1
  linear, 1.5 quadratic, 1.67 cubic, 2 exponential) and the exponent of a power store.
  On made-up catchments it recovered every store where recharge stops between events (split
  recharge), but standard recharge, which keeps feeding groundwater through recessions,
  lowered the slopes by 0.1 to 0.9. So the slope is read straight only where recharge stops;
  otherwise compare the record's slope with each fitted model's, which `plot_recession()`
  draws together.
- **Can the record choose the groundwater store?** `inst/benchmarks/recession_stores.R`
  calibrates sixteen made-up catchments with all four stores. The slope read from the record
  found the true store in 8, the closest simulated slope in 9, and the best validation score
  in all 16, but by a median margin of 0.003 in log NSE, below the 0.02 tie tolerance in 15.
  The calibration study article has a new section on it: compare stores, call those within
  the tolerance equally good, and keep the cubic store unless one is clearly better.

# pdmS7 0.11.0

- **Calibrating for events.** NSE over a long record counts time steps, not events, so a
  model can score well with its flood peaks late and low. Four additions guard against it:
  - `calibrate_pdm(objective = "events")` scores only the largest events, found with
    `find_events()`: 1 - pooled event NSE, plus the mean absolute peak error, plus the mean
    absolute timing error in response times, weighted by `event_weights`
    (`nse = 1, peak = 0.5, timing = 0.5`). `event_share` (0.5) sets the share of events,
    largest first, that count.
  - `pdm_stages(events = TRUE)` adds a fourth stage after the polish, which refits the surface
    stores, `b` and the time delay `td` (0 to `td_max` hours) on that objective with DDS
    (`event_budget` runs per start), leaving the water balance as stage 3 set it.
  - `pdm_stages(thresholds = ...)` puts a threshold term on the last stage, which then also
    searches with DDS. Stages may now carry their own `method`, `control`, threshold settings
    and `extra_bounds` (for parameters outside the bounds table, such as `td`).
  - `calibration_checks()` reports parameters that ended at a bound of their search range
    (a lower bound of zero excepted), and the median peak and timing errors and event NSE of
    the largest events in each window.
- `log_auto_calibration()` accepts `objective = "events"` and records its weights and share.
- The "Automatic calibration, explained" article has a new section, "Calibrating for events".

# pdmS7 0.10.0

- **Negative PE is allowed, as condensation.** Potential evaporation products such as MOSES PE
  go slightly negative when condensation exceeds evaporation. Both engines, R and C, now accept
  negative `pet` (rain must still be nonnegative). A negative value is not scaled by soil
  wetness (Eq. 8): its whole depth joins the soil store, however dry the soil, since dew forms
  on surfaces whatever the soil moisture, and a full store passes it on as runoff, like rain.
  `run_pdm()`, `register_data()`, `sim_pdm()` and the calibration functions all accept it;
  missing PE is still refused. Results with nonnegative PE do not change.

# pdmS7 0.9.1

- `find_events()` has been checked against the authors' reference code for DMCA-ESR, run in
  Octave, on three synthetic records (two hourly, one daily): identical response times and all
  663 event windows identical. The help page and the events article record the check.
- **Fix: comparisons finishing within the same second no longer merge.** `compare_structures()`
  named each comparison by its time to the second, so two on one project in the same second
  shared a name, and reading either back returned both. A suffix now keeps them apart.

# pdmS7 0.9.0

- **Events from the records.** `find_events()` finds rainfall-runoff events in continuous rain
  and flow records objectively, with the DMCA-based event separation routine of Giani et al.
  (2022): no baseflow separation, one setting (`rain_min`), any time step that resolves the
  delay between rain and flow. Each event has rain and flow windows, rain depth, peak, and with
  an area, quick flow and runoff ratio.
- `response_time_dmca()` estimates a catchment's response time from rain and flow alone (Giani
  et al., 2021). Ten years of 15-minute data take under a second, about twenty-five times
  faster than the R reference, which `options(pdmS7.engine = "r")` still selects.
- **The event method is in the C core**, beside the model: `pdm_dmca_rho()`,
  `pdm_find_events()`, `pdm_event_summary()` and `pdm_event_scores()` in `src/pdm_core.h`, so
  Python, Scala and other languages find the same events as R. It matches the R reference
  exactly in event positions and within 1e-14 in every number. Golden files for three records
  (hourly, daily, and hourly with gaps) are in `inst/golden/`, checked from R, from plain C
  (`tools/core/check_golden.c`) and from Python (`tools/core/events_example.py`).
- `event_scores()` scores a model event by event: peak error, peak timing, volume error and NSE
  over each flow window. `batch_events()` does it for every basin of a batch, labels each event
  with its window, and compares each basin's observed and simulated response times.
- New article: "Events in large samples: finding them and scoring models on them".
- `synthetic_basins()` at a sub-daily step no longer writes overlapping calibration and
  validation windows, which registration refused.
- **Fix: `ar_from_response_time()` refuses unstable AR sets.** The default family's first
  coefficient is set for 15-minute steps; at longer steps a decay of under about 4.9 steps
  gave a root of 1 or more, so the projected error grew without limit. At hourly steps that
  is any catchment with a time to peak under 4.9 hours. `pdm_hindcast()` used such sets by
  default without a word; it now leaves them out with a warning. Hindcasts of fast catchments
  at steps longer than 15 minutes change.
- The AR article compares the model's time to peak with the records' response time
  (`response_time_dmca()`) as the family's timescale. They forecast alike at 15 minutes; at
  hourly steps the records' shorter timescale gives an unstable set more often and is no
  better where both work, so the time to peak stays the recommendation.

# pdmS7 0.8.1

- **New article: "What limits automatic calibration: a study".** On 30 synthetic catchments,
  four searches are set against the score of the true parameters; the search reaches the best
  fit the record allows. Profiles show that `kb` cannot be recovered from flow records: across
  a hundredfold range it barely changes the flow, because the slow recharge hides it. It
  matters only in a drought long enough to stop recharge, where equally good calibrations can
  disagree by a factor of more than three in low flow.
- The search results are stored as `inst/extdata/search_study.csv`;
  `inst/benchmarks/search_methods.R` regenerates them, including the staged search with the
  polish confined as before version 0.8.0.
- With the free polish of version 0.8.0, staged DDS fits less well than staged L-BFGS-B in all
  30 synthetic catchments (29 with the old confined polish); `calibrate_pdm()`'s help says so.

# pdmS7 0.8.0

- **Staged calibration's polish searches the full bounds.** `pdm_stages()` used to confine
  stage 3 to a quarter of each range either side of stage 2's values. Stage 1 fits with the
  surface stores at their starting values, and where the true stores are much slower it can
  settle on the wrong slow stores; the confined polish could not undo that. On 30 synthetic
  catchments it left two far short of their true parameters' score (NSE 0.904 against 0.995
  in one). With the full bounds, every catchment comes within 0.001 of the truth's score.
  `band` still confines the polish when asked. Staged results change.
- **DDS.** `calibrate_pdm(method = "dds")` adds dynamically dimensioned search (Tolson and
  Shoemaker, 2007), a derivative-free global search; `control$maxit` is its budget of model
  runs per start. It accepts threshold objectives, and `calibrate_batch()`,
  `calibrate_staged()`, `compare_structures()`, `log_auto_calibration()` and the app offer it.
  On the smooth NSE of the standard structure, L-BFGS-B remains the better choice: given the
  same number of model runs, DDS fitted less well in 29 of 30 synthetic catchments.
- **The large-sample article checks each calibration against the truth.** Calibrations reach
  the true parameters' score in almost every catchment, so a parameter that still comes back
  wrong (`kb` above all) cannot be recovered from the record, whatever the search. The article
  now calibrates all parameters at once.
- `inst/benchmarks/search_methods.R` compares the searches on the large synthetic sample.

# pdmS7 0.7.0

- **Large samples.** `synthetic_basins()` writes a sample of synthetic catchments, each with its
  own climate and true parameters, as basin folders ready for `calibrate_batch()`, with each
  truth saved beside it. New article: "A large sample: what automatic calibration recovers".
- `calibrate_batch()`'s default structure takes each basin's time step from its data, so daily
  and 15-minute basins need no structure of their own.
- Parallel workers in `calibrate_batch()` and `compare_structures()` now use the main session's
  library paths, so a package installed outside the default library (by `R CMD build`, renv or
  a user library) works with `cores > 1`; workers used to fail with "there is no package
  called 'pdmS7'".
- `read_projects()` and `batch_results()` report `wettest_score`, the headline over the
  held-back wettest years.

# pdmS7 0.6.0

- **The standard preset has a realistic water balance.** It used to drain its soil to
  groundwater within a day (`kg` = 24 h), so the soil stayed nearly empty and evaporated about
  2 per cent of potential. It now has a soil capacity up to 300 mm (`cmax`) and `kg` = 4000 h:
  evaporation about half of potential, baseflow index near 0.6. `pdm_model()`'s defaults and
  the parameter catalog match. Results from the preset or default models change; calibrations
  of real data, which set their own parameters, do not.
- `initial_state_from_flow()` warns when a steady start would need more soil storage than the
  store holds; the soil is then capped and the run starts out of balance. This used to happen
  silently.
- `calibrate_staged()` takes `start` and `baseflow_fraction`, like `calibrate_pdm()`.

# pdmS7 0.5.0

- **Extrapolation checks in calibration projects.** Calibrations are fitted to the floods in the
  record and used for larger ones; this release makes that visible before sign-off.
  - `register_data()` holds back the two wettest water years (October to September) in the
    calibration and validation windows by default. No calibration, trial or validation scores
    them; `test_candidate()` reveals them once, with the test window, under the same rules. Set
    `wettest_years` to change the number, or 0 to hold none back. Holding years back needs a
    `time` column and enough record to leave three years, so short records now need
    `wettest_years = 0`.
  - Each automatic calibration keeps the parameter sets it tried that score within
    `tie_tolerance` (default 0.02) of its best headline, up to 50 spread-out sets. The test
    reports, for each held year, the observed peak, the candidate's peak and the range across
    those sets.
  - `register_data(highest_gauged_m3s =)` records the highest check gauging. Flows above it,
    where the rating is extrapolated, are counted window by window at registration and flagged
    in the test. The fit is unchanged.
  - The report, the app and `calibrate_batch()` (through `basin.yml`) carry all three. Sign-off
    needs the test when years are held back, even without a test window.
  - Projects registered before 0.5.0 hold nothing back and reproduce as before.
- **Synthetic rivers.** `synthetic_catchment()` builds a calibration problem with a known
  answer: stochastic rain drives a PDM with a lowland water balance, named storms can be added,
  and a simulated gauge records the flow with persistent (AR(1)) error and an optional rating
  bias above the highest gauged flow. `synthetic_rain()` generates rain and PET at any step by
  four methods: Neyman-Scott and Bartlett-Lewis rectangular pulses, a Markov chain with gamma
  amounts, and seasonal block resampling of a real record. `fit_rain()` fits the first three to
  a gauge record, including one read with reach.io; `rain_statistics()` gives the pulse models'
  exact statistics; `rain_parameters()` the illustrative built-in values.
- `wettest_years()` ranks the water years of any record by peak flow.
- `calibrate_pdm(archive =)` keeps every trial's parameters and a score of your choosing.
- New articles: "Larger floods: extrapolation and the rating", built on a synthetic river
  whose true peaks are known, and "Synthetic rivers: try everything on a known answer".
- The benchmark protocol is at version 0.3: a PDM-only extrapolation check on the wettest
  years, outside the head-to-head comparison, which holds no years back.

# pdmS7 0.4.1

- **Calibration starts from the first observed flow.** Every trial of `calibrate_pdm()`, and
  every run in a calibration project, starts in steady state at the first observed flow, so a
  slow groundwater store is full when scoring begins and cannot bias its own parameters.
  `calibrate_pdm()` gains `start` (`"flow"`, the default, or `"soil"` for the earlier start),
  `baseflow_fraction` and `start_flow`. `register_data()` records the rule; projects registered
  earlier keep the soil start, so their recorded runs still reproduce. Calibrations will differ
  from those of 0.4.0 where the warm-up was short.
- Locks on the calibration log and on shared CSV files recover from a dead session's lock
  without the race that could delete a fresh one.
- The run log and batch status refuse to append rows under a header with different columns.
- `validate_candidate()` re-checks the candidate under the lock.
- `calibration_app()` restores the identity options when it closes.
- The C++ binding unpacks parameters in one place.

- Six new pages on the website: "Where to start" (reading paths by role), "Preparing your
  data" (from EA sources through reach.io to model files, with a checklist), "Reviewing a
  calibration: a Steward's guide", a glossary, troubleshooting, and further reading. The home
  page states the package's purpose, "Get started" opens the reading paths, and the roadmap is
  rewritten.
- The benchmark protocol is at version 0.2, with its decisions closed.
- Every source file is commented: the R package, the compiled core, the golden checker and the
  tests (each test states what it guards). A code review accompanies it, in `code-review.md`
  and under Guides on the website: no errors in the hydrology; two medium and seventeen low
  findings, ranked, with remedies for decision.
- `pdm_hindcast()` reports "No forecast origins fit in the window" for a window too narrow for
  any origin, instead of an internal error.

# pdmS7 0.4.0

- New `pdm_hindcast()` reruns past forecasts from many origins, using the rain that fell, with
  no updating, persistence, AR post-processing as in IMFS (the Environment Agency 2024 default,
  a default-family set from the model's response time, and optionally a set fitted to the
  calibration period) and state correction. `hindcast_scores()` scores each lead time: NSE,
  RMSE, bias, skill against persistence, threshold POD, FAR and CSI, and lead time over time to
  peak, so catchments and models line up on one axis. It also scores another model's forecasts
  given as a table. `plot_hindcast()` plots any score against lead time.
- New `pdm_response_time()` measures a model's time to peak, recession and centroid lag from a
  pulse of rain, with an optional check against an FEH time to peak.
- New `ar_ea_default()` and `ar_from_response_time()` give AR coefficients in the Deltares
  convention used by IMFS and reach.postproc; the second follows
  `reach.postproc::default_family_ar_parameters()` exactly.
- New `calibrate_staged()` and `pdm_stages()` calibrate in stages: water balance and slow
  stores on log NSE with a volume penalty, then the fast stores on NSE, then a joint polish
  within narrowed bounds. `log_staged_calibration()` writes one `auto_calibration` entry per
  stage, each recording its stage; `calibrate_batch(staged = TRUE)` does the same per basin
  and resumes from the last finished stage.
- `calibrate_pdm()` gains `objective = "log_nse"` and `volume_weight`, a penalty on the
  absolute volume error.
- `calibrate_batch()` handles snow basins: with `snow: true` in `basin.yml` and a
  `temperature` column, PACK at fixed parameters turns precipitation into rain and melt, the
  PDM is calibrated on that, and a log note records the PACK settings and the raw forcing's
  checksum.
- New articles, "Testing forecasts with hindcasts" and "AR and ARMA error correction,
  explained". "Automatic calibration" and "Calibrating
  many catchments" cover staged calibration and snow basins.
- Internal: the calibration functions are split into smaller helpers; no results change.

- The introductory articles are rewritten in plain English with figures of the model
  running: "How the PDM works" (buckets, dry and wet ground, the saturated area, the two
  paths to the river, the water balance, and what each setting does), "How the snow model
  works" (a winter, rain on snow, snow cover, settings, and snow with the PDM) and "Your
  first model run" (from data files to a calibrated, saved model). Each ends with a short
  equations appendix; the new "Model equations" page holds the full reference.
- New `write_pdm_config()` writes a configuration that `read_pdm_config()` reads back
  exactly; general YAML writers round numbers to seven significant figures.
- "Calibrating many catchments" is rewritten as a plain-English, step-by-step guide to
  `calibrate_batch()`, run live with an interruption and a failure. "Automatic calibration"
  is rewritten in plain English.
- New `calibrate_batch()` runs one calibration protocol on every basin in a folder (each
  with `forcing.csv`, `flow.csv` and `basin.yml`), giving each basin its own calibration-log
  project, in parallel with `cores`. It can be stopped and restarted at any point: each
  basin carries on from its last completed step and finished steps are never repeated.
  Failures are recorded with their reason without stopping the batch. `batch_status()`
  shows progress from `batch-status.csv`; `batch_results()` collects the projects.
- Three new articles: "Scoring a simulation" (every score, with the contingency table,
  event matching, events against steps and the performance diagram), "Automatic
  calibration" (bounds, log-scale search, the two optimisers and threshold objectives) and
  "Inside the logs" (project folders, entry files, the checksum chain, the run log and the
  register). The site's articles are regrouped into Calibration, Records and review, and
  Forecasting.
- New `compare_structures()` calibrates several model structures alike, in parallel with
  `cores`, logs each as a structure and an automatic calibration linked by a comparison id,
  and ranks them on the validation window, with optional two-way cross-validation.
  `structure_comparison()` rebuilds a ranking from the log. `structure_set()` gives the
  standard PDM and seven one-change variants; `calibration_bounds()` gives default bounds
  from `inst/calibration-bounds.csv`. The report and the app (a new Structures tab) show
  comparisons.
- `calibrate_pdm()` and `log_auto_calibration()` gain `log_scale`, searching named
  parameters uniformly in log(value).
- `register_data()` gains an optional `test` window, scored once by the new
  `test_candidate()` entry after every choice is made, and required before sign-off when
  registered.
- New article, "Choosing a model structure".
- New article, "Calibrating many catchments": one logged protocol applied to a batch of
  basins, budgeting, catching failures, judging scores as a distribution, checking whether
  multi-start runs agreed, and how well calibration recovers known parameters.
- New `read_entry()` returns one calibration-log entry in full, and `read_projects()` gains
  `validation_score`, the candidate's headline score on the validation window.
- New threshold verification. `pdm_threshold_scores()` scores one or more thresholds at
  once: events (episodes above a threshold, merged across short gaps and matched within a
  timing tolerance) give probability of detection, false alarm ratio, critical success index
  and frequency bias, plus crossing time, peak timing, peak, duration and volume errors for
  each hit; a step-by-step count adds probability of false detection, equitable threat
  score and Peirce skill score.
- `register_data()` gains `thresholds` (flows, or levels converted through a registered
  `rating` table and never extrapolated) and event settings. Every logged run is scored at
  every threshold, and a threshold score such as `csi:Flood Warning` may be the headline.
  The report adds a threshold table and a performance diagram.
- `calibrate_pdm()` gains `method = "nelder_mead"`, a derivative-free optimiser kept
  within the bounds, and an optional threshold term in the objective (`thresholds`,
  `threshold_weight`, `threshold_score`), or `objective = "threshold"` alone.
  `log_auto_calibration()` passes registered thresholds by name and records the method,
  objective and number of model runs. The default method and objective are unchanged.
- New article, "Logging a manual calibration": a complete project from start to sign-off,
  integrity checks and tampering, the report, and tracing operational runs with the run
  log.
- New `calibration_app()`: a Shiny app over the calibration log for staff who prefer not
  to script. Setup (start, register data, select structure), Trial (adjust parameters,
  preview the hydrograph and scorecard against the parent, save with a verdict and
  reasoning; notes; automatic calibration), History (path, every run, compare two runs,
  propose and validate a candidate), Report (integrity, build and download) and Sign-off.
  Every button calls the exported function a script would, so the same rules apply.
  shiny is a suggested package, needed only for the app.
- New opt-in run log. With `options(pdmS7.run_log = "runs.csv")` or `PDMS7_RUN_LOG` set,
  every `run_pdm()` call, and so `sim_pdm()` and `sim_snow_pdm()`, appends one row: who,
  when, an optional tag, the model's `pdm_fingerprint()`, a checksum of the forcing, period,
  versions, run time, and success or the error message. Calibration evaluations, spin-up
  cycles and the calibration log's own reruns are not logged. With a register of
  calibration projects set (`pdmS7.register` or `PDMS7_REGISTER`), each run is marked
  `approved`, `superseded` (its project was reopened) or `unapproved`; runs are never
  blocked. New `read_run_log()`, `approved_configurations()` and `pdm_fingerprint()`.
  Logging is off by default and a logging failure never stops a run.
- New calibration log: an append-only, tamper-evident record of a calibration project.
  `start_calibration_project()`, `register_data()`, `select_structure()`, `log_trial()`,
  `log_auto_calibration()`, `log_note()`, `propose_candidate()`, `validate_candidate()`,
  `sign_off_project()` and `reopen_project()` each write one YAML entry recording who,
  when, which data and parameters, the scores and the reasoning. Entries are chained by
  MD5, data are copied and checksummed, and every run records a checksum of its output.
  `verify_project()` detects edits, gaps, changed data and runs that no longer reproduce.
  A Steward cannot sign off their own calibration. `read_project()`, `project_trials()` and
  `read_projects()` read the record. Design: `calibration-log-design.md`.
- New `build_report()` writes a calibration report generated from the log: a
  self-contained HTML file with embedded figures, and a Markdown copy. It shows integrity
  status first, then data and scoring windows, model structure, the calibration path as a
  tree and a table, the candidate's hydrographs, flow-duration curves and scorecard for both
  windows, parameter sensitivity on a shared scale, sign-off history, and the final
  configuration. It uses base graphics only.
- New `pdm_scorecard()`: NSE, log NSE, KGE and its components, RMSE, signed and absolute
  volume error, peak error, and the Yilmaz et al. (2008) flow-duration-curve signatures.
- Five new illustrated articles on the package website: choosing model components, starting
  states, calibration, forecast updating, and the C core. Articles, guides and the function
  reference are grouped by topic in the site navigation. DESCRIPTION gains `URL` and
  `BugReports`.
- `calibrate_pdm()` gains opt-in multi-start calibration through `starts` and `seed`.
  Start 1 is the configured point; extra starts are drawn uniformly inside the bounds, all
  are optimised, and the best objective is returned. The result gains `start_results`, a
  table of per-start objective, convergence code, evaluation count and fitted parameters.
  The default `starts = 1L` runs the same single optimisation as earlier versions.
- `run_pdm()`, and so `sim_pdm()` and `calibrate_pdm()`, now run a compiled time loop for
  every capacity distribution; standard, split and demand recharge; and cascade, power-law and
  exponential stores on either route. It is about 430 times
  faster. Output agrees with the
  R loop to rounding: bit-identical on R 4.3, with last-place differences on R 4.5 and later,
  where calibrated parameters can differ from earlier versions by about 1e-13 relative.
  `options(pdmS7.engine = "r")` forces the R loop, which remains the reference
  implementation. Building from source now needs a
  compiler (Rtools on Windows); cpp11 is a build-time dependency only.
- Added `inst/benchmarks/time_solvers.R` and a report at `docs/benchmarks/solver-timing.md`
  timing both solvers and both engines on daily and 15-minute series.
- `pdm_model()` (and so `pdm_from_config()` and `sim_pdm()`) warns, once per session, when the
  Smith cubic solver is used with a step above 1 hour. Its error grows with the square of the
  step and reaches 60 to 100 per cent of peak flow at a daily step. Results are unchanged; the
  default adaptive solver is unaffected. `inst/benchmarks/smith_step_error.R` reproduces the
  evidence.
- The compiled time loop now sits behind a language-neutral C interface (`src/pdm_core.h`,
  interface version 2), so other languages can call the same model code. `src/pdm_engine.cpp` is a thin R wrapper over
  it, and results are unchanged. The core validates its own inputs and leaves the caller's
  state untouched on error. `tools/core/README.md` covers building it without R.
- Golden test files in `inst/golden/` hold inputs and expected outputs from the R reference,
  for checking any binding of the core. `tools/core/check_golden.c` checks them from plain C.
- The triangular capacity distribution is now inverted exactly (cube root or the
  trigonometric solution of a cubic) and the lognormal by safeguarded Newton iteration, in
  place of `uniroot()` with a 1e-10 tolerance. Storage round trips improve from about 2e-11 to
  1e-14 mm; model outputs for these two distributions change by at most about 3e-11.
- Fixed: the rectangular distribution's `capacity_mean()` used (cmin + cmax) / 2 while its
  other methods used the Pareto b = 1 form, which can differ in the last place. A soil store
  filled exactly to capacity could then fail with "Soil storage exceeds capacity_mean". Both
  now use the Pareto form, so `capacity_mean()` can change in the last place.
- The PACK snowpack also runs in the compiled core, about 540 times faster than its R loop
  and bit-identical to it on R 4.3. `sim_pack()` and `sim_snow_pdm()` use it automatically.
  The core gains `pdm_pack_run()` for snow alone and `pdm_snow_run()` for snow feeding PDM.
- New `initial_state_from_flow()`: a warm start in steady state with the flow observed at
  the start of a run. Routing stores deliver their share of the flow, the soil store is set so
  that recharge equals baseflow, and delay queues hold the water in transit. It replaces an
  arbitrary soil fraction for short test runs and forecasts. Also in the core as
  `pdm_state_from_flow()`.
- Forecast updating also runs in the compiled core: `correct_state()` (state correction,
  Moore 2007 Eq. 28-30) and `update_forecast()` (ARMA error prediction, Eq. 31-42), with
  `pdm_correct_state()` and `pdm_update_forecast()` for other languages. Results are
  bit-identical to the R code. Fitting the ARMA coefficients stays in R.
- The compiled core is now plain C99 (`src/pdm_core.c`), so other languages need only a C
  compiler to build it. Results are bit-identical to the previous C++ version.
- Fixed: the compiled engine rejected an initial state whose values were all stored as
  integers, for example one read with `read.csv()`. The R loop accepted it.
- A peak timing objective is deferred.

# pdmS7 0.3.1

- Added three executable vignettes: PDM equations and functions, PACK snow
  accounting and defaults, and a synthetic calibration/validation/restart workflow.
- Added reproducible process diagrams, soil/cover curves and workflow hydrographs.
- No changes to the numerical model APIs or equations.

# pdmS7 0.3.0

- Added optional PACK S7 snow components, conservative substep accounting,
  areal depletion, fresh-snow memory and coupled PDM restart.
- Added the image parameter preset (explicit hourly-unit assumption) and a
  distinct report-typical preset, with full parameter mapping and source notes.
- Added multi-objective metrics, weighted multi-start calibration, evaluated
  Pareto trade-offs, configurable scales and joint snow/PDM parameter paths.
- Documented river networks and additional state assimilation as future work.

# pdmS7 0.2.0

## Flode Tier 3 engineering target

- Introduced `Flode`-prefixed S7 classes with existing class names retained as aliases.
- Added `sim_pdm()` with explicit depth units, integer minute steps, data.table
  output, UTC timestamps, and warm-up flags.
- Added safe YAML loading and an illustrative configuration file.
- Replaced CSV input with `fread()` and tabular assembly with `rbindlist()`.
- Added state-object validation and structured debug logging.
- Converted numerical regression checks to testthat and added interface tests.
- Added roxygen source documentation, renv, lintr, and pinned shared Flode CI.
- Retained the earlier simulation functions and output column names for compatibility.

This release targets the Tier 3 technical checks. It is not formally approved
for operations: human maintainer attribution, independent review, and catchment
validation remain required. Version 0.1.0 serialized S7 objects should be rebuilt
from their saved configuration because the canonical class names have changed.
