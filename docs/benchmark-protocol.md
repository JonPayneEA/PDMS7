# PDM and LSTM benchmark protocol

Version 0.2, 2026-11-02. Decisions closed; three facts to confirm before
sign-off (section 12).

This protocol fixes how PDM and the LSTM models are compared before
anyone sees a test result. Its purpose is simple: if the comparison is
challenged, the answer is this document, dated and agreed in advance. It
takes effect when an Owner is named and a Steward signs it off. No test
period is scored before then.

## 1. Principle

Both models get the same data, the same periods and a stated, comparable
search effort. Both are scored by the same code on the same masked
observations. A basin enters or leaves the comparison for data reasons
decided in advance, never because of its result.

The comparison is in simulation mode. Neither model sees observed flow
at run time: PDM’s updating and state correction are off, and the LSTM
takes no lagged discharge input. Forecast skill with assimilation is a
different question and is outside this protocol.

## 2. Phases

| Phase | Data                                 | Step       | Purpose                                                                                                    |
|-------|--------------------------------------|------------|------------------------------------------------------------------------------------------------------------|
| 1     | CAMELS-GB (Coxon et al., 2020)       | Daily      | Prove the protocol, the scoring code and both teams’ processes on open data, against a published benchmark |
| 2     | Environment Agency gauged catchments | 15 minutes | The operationally relevant comparison                                                                      |

Phase 1 copies the design of Lees et al. (2021), so that both teams can
check their setup against published results: the retrained LSTM against
the published LSTM, and PDM against the four FUSE conceptual models in
that study. Phase 1 results do not change any phase 2 decision; phase 2
decisions still open (section 11) are closed and versioned before phase
2 data are scored.

## 3. Basins

**Phase 1.** The 669 CAMELS-GB catchments used by Lees et al. (2021),
listed in an appendix. The 518 catchments with FUSE results in that
study form a fixed subset for the comparison with the published
conceptual models. No further exclusions are made, except a basin where
a model cannot run for a data reason found before scoring, recorded with
the reason.

**Phase 2.** Selection criteria, fixed now; the list follows before
calibration starts:

- at least 15 years of 15-minute flow;
- no more than 10 per cent missing in any period;
- no significant regulation or abstraction, from the hydrometric
  register’s flags;
- catchment area from 10 to 1,000 km2;
- a deliberate spread of baseflow index, so that both
  groundwater-dominated and flashy catchments are represented.

In both phases, no basin is removed after test results exist.

## 4. Data

- **Time step:** daily in phase 1, as CAMELS-GB; 15 minutes, UTC, in
  phase 2.
- **Forcing:** both models receive the same precipitation and PET
  series, in mm per interval, from the same source and processing chain.
  In phase 1 these are the CAMELS-GB series. Gaps are infilled once, by
  one method, before either model sees the data.
- **LSTM inputs:** the dynamic forcings and static catchment attributes
  used by Lees et al. (2021), listed in an appendix. PDM uses
  precipitation, PET and catchment area only. This is a legitimate
  difference between a regional and a per-basin model, not a fairness
  breach, but it is stated in every report.
- **Observed flow:** in m3/s, mean flow over each interval, matching
  PDM’s `q_m3s`. Missing observations stay missing and are never
  infilled for scoring.

## 5. Periods

Periods are chronological and do not overlap. The same dates apply to
every basin and both models.

| Period     | Phase 1 dates                       | PDM use               | LSTM use                           |
|------------|-------------------------------------|-----------------------|------------------------------------|
| Warm-up    | The year before training            | Simulated, not scored | Sequence look-back                 |
| Training   | As Lees et al. (2021)               | Calibration           | Weight training                    |
| Validation | As Lees et al. (2021)               | Calibration           | Early stopping and hyperparameters |
| Test       | 1998 to 2008, as Lees et al. (2021) | Scored once           | Scored once                        |

PDM is calibrated on the training and validation years combined, so that
both models see the same years before the test and neither sees more.
Because PDM then has no held-out years, its structure and calibration
method are fixed in advance (section 6) and not chosen from results.

The test period is scored once, after both models are frozen. Any rerun
after test results are known is reported as such, with the reason.

## 6. PDM configuration

- **Package:** pdmS7 at a recorded commit, compiled engine, adaptive
  groundwater solver.
- **Structure:** Pareto capacity, standard recharge, two-store surface
  cascade, cubic groundwater, no snow. The same structure for every
  basin.
- **Parameters and bounds:**
  [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
  of that structure, from `inst/calibration-bounds.csv` at the recorded
  commit, with the search scales given there. Bounds are not changed
  after test results exist.
- **Calibration method and effort:** fixed by the pilot below, before
  any test score exists.
- **Runs:**
  [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md),
  one calibration-log project per basin, seeds derived from the basin’s
  identifier.
- **Diagnostics recorded per basin:** every start’s objective,
  convergence code, evaluation count and fitted parameters; parameters
  within 1 per cent of a bound; wall time. The calibration log holds all
  of these.

### Pilot

- **Basins:** 20 phase 1 basins, chosen to span the range of baseflow
  index, listed in an appendix before the pilot runs.
- **Data:** calibrate on the training years only; score on the
  validation years. The test years are not used.
- **Settings compared:** calibration of all parameters at once
  (objective 1 minus NSE) and staged calibration
  ([`calibrate_staged()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_staged.md)
  with the default stages), each at 3, 5, 10 and 20 starts.
- **Rule:** the chosen setting is the cheapest, in total objective
  evaluations, whose median validation NSE over the 20 basins is within
  0.01 of the best setting’s. The pilot results and the choice are
  recorded before the final calibration runs.

The final run then applies the chosen setting to every basin, on
training and validation years.

## 7. LSTM configuration

- **Architecture, inputs and loss:** as Lees et al. (2021). If the team
  uses NeuralHydrology, the configuration file is archived with the
  results and fixes all three.
- **Hyperparameter search:** on the validation years only, with the
  search space and number of trials recorded.
- **Seeds:** 8, as in Lees et al. (2021).
- **Reported model:** the ensemble mean of the 8 seeds, with the spread
  across seeds alongside. The median single seed is also reported, so
  that averaging, which smooths errors a single PDM run keeps, can be
  judged.
- **Output handling:** negative predicted flows are set to zero before
  scoring, and the number of intervals affected is reported.

## 8. Search effort and compute

The two models search in different ways, so effort cannot be equalised
exactly. It is reported instead: PDM starts and objective evaluations
against LSTM seeds, trials and epochs, with core-hours or GPU-hours for
each. A reader can then judge whether either model was under-resourced.

## 9. Metrics

All metrics are computed on the test period by
[`pdm_scorecard()`](https://jonpayneea.github.io/PDMS7/reference/pdm_scorecard.md)
from pdmS7, for both models and the lower benchmark, using the same
observation mask. One scoring function removes one class of argument.

| Metric                   | [`pdm_scorecard()`](https://jonpayneea.github.io/PDMS7/reference/pdm_scorecard.md) name | What it shows                                                                        |
|--------------------------|-----------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| NSE (headline)           | `nse`                                                                                   | Overall fit, dominated by high flows                                                 |
| KGE (headline)           | `kge`                                                                                   | Correlation, variability and bias together                                           |
| KGE terms                | `kge_r`, `kge_alpha`, `kge_beta`                                                        | Where a KGE shortfall comes from                                                     |
| NSE of log flows         | `log_nse`                                                                               | Low-flow behaviour                                                                   |
| RMSE, RMSE of log flows  | `rmse`, `log_rmse`                                                                      | Error in flow units, and in low flows                                                |
| Volume error             | `volume_error`, `abs_volume_error`                                                      | Water balance                                                                        |
| Peak error               | `peak_error`                                                                            | Size of the largest flow in the test period                                          |
| Flow-duration signatures | `fdc_high`, `fdc_mid`, `fdc_low`                                                        | High-flow volume, mid-segment slope and low-flow volume biases (Yilmaz et al., 2008) |

- **Log offset:** 1 per cent of each basin’s mean observed flow over the
  training years, so that log scores weigh small and large rivers alike.
- **Lower benchmark:** for each basin, the mean observed flow for each
  day of the year over the training years, scored in the same way
  (Seibert et al., 2018). A model is judged against this floor as well
  as against the other model.
- Peak timing is not assessed at a daily step.

## 10. Comparison and reporting

- **Per basin:** every metric for both models and the lower benchmark in
  one table, including basins where PDM wins.
- **Across basins:** median and interquartile range of each metric, and
  cumulative distribution plots.
- **Paired comparison:** per-basin differences, the count of basins each
  model wins on each metric, and a Wilcoxon signed-rank test as a
  descriptive summary, not a verdict.
- **Published reference (phase 1):** on the 518-basin subset, PDM beside
  the published FUSE results and the retrained LSTM beside the published
  LSTM.
- **Diagnostics:** PDM basins with parameters on a bound or no converged
  start are flagged, not dropped. Results are reported with and without
  them.
- **Strata, fixed now:** baseflow index, catchment area and aridity,
  each in thirds with cut points from all phase 1 basins set before
  scoring; and region as reported by Lees et al. (2021). Any other split
  is labelled exploratory.

## 11. Phase 2 decisions to close before phase 2

Period dates; the basin list; the forcing product; the LSTM architecture
for 15-minute data; and whether the phase 1 pilot’s choice carries over
or a phase 2 pilot is run. Each is closed and the protocol versioned
before any phase 2 test score exists.

## 12. Facts to confirm before sign-off

These are not decisions; they are copied from Lees et al. (2021) and
checked against the paper:

1.  the training, validation and test dates, to the day;
2.  the LSTM dynamic inputs and static attributes;
3.  the list of 669 catchments and the 518-catchment subset.

## 13. Reproducibility

Recorded with the results: package commit, R version, operating system,
seeds, the frozen configuration for each basin, the LSTM code version,
configuration and weights, and the scored series. The outputs are
archived with this protocol.

## 14. Agreement and changes

The protocol is recorded in a calibration-log project: an Owner is named
when the project starts, each version is registered with its checksum,
and a Steward signs it off. Calibration projects run under it cite the
version they follow. Each change is versioned with its date and reason.
A change made after any test result is known is reported in the results,
with the comparison under the original protocol where possible.

## References

- Coxon, G. et al. (2020). CAMELS-GB: hydrometeorological time series
  and landscape attributes for 671 catchments in Great Britain. Earth
  System Science Data, 12, 2459–2483.
- Klemeš, V. (1986). Operational testing of hydrological simulation
  models. Hydrological Sciences Journal, 31, 13–24.
- Lees, T. et al. (2021). Benchmarking data-driven rainfall–runoff
  models in Great Britain: a comparison of long short-term memory
  (LSTM)-based models with four lumped conceptual models. Hydrology and
  Earth System Sciences, 25, 5517–5534.
- Seibert, J. et al. (2018). Upper and lower benchmarks in hydrological
  modelling. Hydrological Processes, 32, 1120–1125.
- Yilmaz, K. K. et al. (2008). A process-based diagnostic evaluation of
  a hydrologic model. Water Resources Research, 44, W09417.

## Version history

| Version | Date       | Change                                                                                                                                                                                                                                                                                                                                                                            |
|---------|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 0.1     | 2026-10-31 | Draft for agreement                                                                                                                                                                                                                                                                                                                                                               |
| 0.2     | 2026-11-02 | Decisions closed: two phases; phase 1 on CAMELS-GB matching Lees et al. (2021); PDM calibrated on training plus validation; pilot to fix PDM method and effort; LSTM as Lees et al. with 8 seeds; [`pdm_scorecard()`](https://jonpayneea.github.io/PDMS7/reference/pdm_scorecard.md) metrics, relative log offset and a day-of-year lower benchmark; four strata; simulation only |
