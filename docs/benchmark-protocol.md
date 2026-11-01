# PDM and LSTM benchmark protocol

Draft for agreement. Version 0.1, 2026-10-31.

This protocol fixes how PDM and the LSTM models are compared before
anyone sees a test result. Its purpose is simple: if the comparison is
challenged, the answer is this document, dated and agreed in advance.
Items in square brackets are open decisions. They must be closed, and
the protocol versioned, before the test period is scored.

## 1. Principle

Both models get the same data, the same periods and a stated, comparable
search effort. Both are scored by the same code on the same masked
observations. A basin enters or leaves the comparison for data reasons
decided in advance, never because of its result.

The comparison is in simulation mode. Neither model sees observed flow
at run time: PDM’s updating and state correction are off, and the LSTM
takes no lagged discharge input. Forecast skill with assimilation is a
different question and needs its own protocol.

## 2. Basins

- The basin list is fixed in an appendix before calibration starts: \[60
  basins, list to follow\].
- Selection criteria are recorded with the list: \[record length, data
  completeness, no significant regulation or abstraction, catchment area
  range\].
- A basin is excluded only for data reasons found before scoring: for
  example, a gauge record with more than \[10\] per cent missing in the
  test period, or forcing that cannot be infilled. The reason is
  recorded. No basin is removed after test results exist.

## 3. Data

- **Time step:** 15 minutes, UTC, for both models.
- **Forcing:** both models receive the same rainfall and PET series, in
  mm per interval, from the same source and processing chain. Gaps are
  infilled once, by one method, before either model sees the data.
- **Static inputs:** the LSTM may also use catchment attributes; PDM
  uses only catchment area. This is a legitimate difference between a
  regional and a per-basin model, not a fairness breach, but it is
  stated in every report: \[list of LSTM static attributes\].
- **Observed flow:** in m3/s, mean flow over each interval, matching
  PDM’s `q_m3s`. Missing observations stay missing. They are never
  infilled for scoring.

## 4. Periods

Periods are chronological and do not overlap. The same dates apply to
every basin and both models.

| Period                  | Dates                                         | PDM use               | LSTM use                           |
|-------------------------|-----------------------------------------------|-----------------------|------------------------------------|
| Warm-up                 | \[1 year before calibration\]                 | Simulated, not scored | Sequence look-back                 |
| Calibration or training | \[YYYY to YYYY\]                              | Parameter estimation  | Weight training                    |
| Tuning                  | \[YYYY to YYYY\]                              | Not used              | Early stopping and hyperparameters |
| Test                    | \[YYYY to YYYY\], about the final \[7\] years | Scored once           | Scored once                        |

The test period is scored once, after both models are frozen. Any rerun
after test results are known is reported as such, with the reason.

PDM does not need a tuning period. It may be calibrated on calibration
and tuning combined, so that it sees the same span of data as the LSTM:
\[decide; recommended: yes\].

## 5. PDM configuration

- **Package:** pdmS7 at a recorded commit, compiled engine, adaptive
  groundwater solver.
- **Structure:** Pareto capacity, standard recharge, two-store surface
  cascade, cubic groundwater, no snow. The same structure for every
  basin.
- **Parameters and bounds:** \[list in an appendix\]. Bounds are set
  from catchment knowledge before calibration and are not changed after
  test results exist.
- **Objective:** 1 minus NSE on `q_m3s`, warm-up excluded.
- **Search effort:** \[k\] L-BFGS-B starts per basin, with k set by the
  pilot (`inst/examples/pilot_calibration.R`); maximum 200 iterations
  per start; seed 1000 plus the basin’s index in the appendix list.
- **Diagnostics recorded per basin:** `start_results` in full, with
  every start’s objective, convergence code, evaluation count and fitted
  parameters; parameters within 1 per cent of a bound; wall time.

## 6. LSTM configuration

- **Architecture and inputs:** \[specify\]. Fixed before training.
- **Loss:** \[NSE-based loss, per-basin normalised, or as agreed\].
  State it if it differs from PDM’s objective.
- **Hyperparameter search:** on the tuning period only, with the search
  space and number of trials recorded.
- **Search effort:** \[n\] training seeds. The reported model is \[the
  ensemble mean, or the median seed\]; the spread across seeds is
  reported alongside.
- **Output handling:** negative predicted flows are set to zero before
  scoring, and the number of intervals affected is reported.

## 7. Search effort and compute

The two models search in different ways, so effort cannot be equalised
exactly. It is reported instead: PDM starts and objective evaluations
against LSTM seeds, trials and epochs, with core-hours or GPU-hours for
each. A reader can then judge whether either model was under-resourced.

## 8. Metrics

All metrics are computed on the test period by
[`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md)
from pdmS7, for both models, using the same observation mask. One
scoring function removes one class of argument. The function returns
losses; the report converts them where noted.

| Metric               | [`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md) name | Reported as      | What it shows                               |
|----------------------|-------------------------------------------------------------------------------------------|------------------|---------------------------------------------|
| NSE                  | `nse_loss`                                                                                | 1 minus the loss | Overall fit, dominated by high flows        |
| KGE                  | `kge_loss`                                                                                | 1 minus the loss | Correlation, variability and bias together  |
| RMSE of log flows    | `log_rmse` (offset \[0.01\] m3/s)                                                         | As returned      | Low-flow behaviour                          |
| Volume bias          | `abs_bias`                                                                                | As returned      | Water balance                               |
| Peak magnitude error | `peak_relative_error`                                                                     | As returned      | Size of the largest flow in the test period |

KGE’s three terms (correlation, variability ratio, bias ratio) explain
where a fit fails, but
[`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md)
does not return them separately. If wanted, they are computed from the
same masked series by one shared function, written and agreed before
scoring: \[decide\].

Peak timing is not assessed: the package has no timing metric, and
adding one is deferred. Event-based peak analysis, if wanted, needs an
agreed event definition and belongs in a protocol revision.

## 9. Comparison and reporting

- **Per basin:** every metric for both models in one table, including
  basins where PDM wins.
- **Across basins:** median and interquartile range of each metric, and
  cumulative distribution plots.
- **Paired comparison:** per-basin differences, the count of basins each
  model wins on each metric, and a Wilcoxon signed-rank test as a
  descriptive summary, not a verdict.
- **Diagnostics:** PDM basins with parameters on a bound or no converged
  start are flagged, not dropped. Results are reported with and without
  them.
- **Stratification:** results by \[catchment area, baseflow index,
  flashiness\] if agreed in advance. Strata chosen after seeing results
  are labelled as exploratory.

## 10. Reproducibility

Recorded with the results: package commit, R version, operating system,
seeds, the frozen configuration for each basin, the LSTM code version
and weights, and the scored series. The outputs are archived with this
protocol.

## 11. Changes to this protocol

Each change is versioned with its date and reason. A change made after
any test result is known is reported in the results, with the comparison
under the original protocol where possible.

## Open decisions

| Item                              | Section | Owner | Recommendation                               |
|-----------------------------------|---------|-------|----------------------------------------------|
| Basin list and selection criteria | 2       | \[ \] | Fix before the pilot finishes                |
| Missing-data exclusion threshold  | 2       | \[ \] | 10 per cent in the test period               |
| LSTM static attributes            | 3       | \[ \] | List explicitly                              |
| Period dates                      | 4       | \[ \] | Final 7 years as test                        |
| PDM on calibration plus tuning    | 4       | \[ \] | Yes, to match the data span                  |
| PDM bounds                        | 5       | \[ \] | From catchment knowledge, before calibration |
| PDM starts, k                     | 5       | \[ \] | From the pilot                               |
| LSTM loss, seeds, ensemble rule   | 6       | \[ \] | Ensemble mean, spread reported               |
| Log offset                        | 8       | \[ \] | 0.01 m3/s, or 1 per cent of mean flow        |
| KGE terms reported separately     | 8       | \[ \] | Yes, from one shared function                |
| Strata                            | 9       | \[ \] | Agree before scoring                         |
