# Robust calibration: an overview

The PDM stays as published. What can still be improved is everything
around it: what the calibration counts as a good fit, which parameters
it bothers to fit, how a model is judged, whether it holds when
conditions change, and how sure we are of it. Six articles take these in
turn, each on the same made-up catchment, so that every answer can be
checked against the truth.

| Question                                            | Article                                                                                            | Functions                                                                                                                                                                                                                                                  |
|-----------------------------------------------------|----------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Does the calibration count every error fairly?      | [Counting every error fairly](https://jonpayneea.github.io/PDMS7/articles/fair-errors.md)          | `objective = "boxcox"`, [`boxcox_flow()`](https://jonpayneea.github.io/PDMS7/reference/boxcox_flow.md), [`flow_weights()`](https://jonpayneea.github.io/PDMS7/reference/flow_weights.md)                                                                   |
| Which parameters can the record determine?          | [Global sensitivity](https://jonpayneea.github.io/PDMS7/articles/global-sensitivity.md)            | [`pdm_sensitivity()`](https://jonpayneea.github.io/PDMS7/reference/pdm_sensitivity.md)                                                                                                                                                                     |
| Which model forecasts best?                         | [Choosing a model as a forecaster](https://jonpayneea.github.io/PDMS7/articles/forecast-choice.md) | [`compare_forecasts()`](https://jonpayneea.github.io/PDMS7/reference/compare_forecasts.md)                                                                                                                                                                 |
| Will the calibration hold in other years?           | [Stress tests](https://jonpayneea.github.io/PDMS7/articles/stress-tests.md)                        | [`split_sample_test()`](https://jonpayneea.github.io/PDMS7/reference/split_sample_test.md), [`parameter_drift()`](https://jonpayneea.github.io/PDMS7/reference/split_sample_test.md)                                                                       |
| How sure are we of the parameters and the forecast? | [Bayesian calibration](https://jonpayneea.github.io/PDMS7/articles/bayesian-calibration.md)        | [`calibrate_bayes()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_bayes.md), [`posterior_band()`](https://jonpayneea.github.io/PDMS7/reference/posterior_band.md), priors                                                                       |
| Is a probability forecast honest?                   | [Ensemble verification](https://jonpayneea.github.io/PDMS7/articles/ensemble-verification.md)      | [`ensemble_scores()`](https://jonpayneea.github.io/PDMS7/reference/ensemble_scores.md), [`crps_ensemble()`](https://jonpayneea.github.io/PDMS7/reference/crps_ensemble.md), [`brier_score()`](https://jonpayneea.github.io/PDMS7/reference/brier_score.md) |

## How they fit together

**Before calibrating**, a global sensitivity analysis on the structure’s
full bounds shows which parameters the record can determine. Fix the
rest at a regional or default value: fewer free parameters, fewer
equally good answers, calibrations that agree.

**Calibrating**, the Box-Cox objective counts every hour’s error alike
instead of letting a few floods decide, and rating weights let flows the
gauge measures poorly count for less. Choose the power so the errors are
the same size at every flow; the first article shows how.

**Choosing between candidates**, judge them as forecasters: hindcast
skill at the lead times the service uses, and threshold warnings, not
the score of a simulation of the whole record.

**Checking the choice**, calibrate on dry years and score wet ones, and
calibrate period by period to catch a change in the catchment or the
record that a single calibration would hide.

**Quantifying the uncertainty**, a Bayesian calibration samples every
set consistent with the record and the priors; with priors from a model
of parameters from catchment descriptors, it also serves catchments with
short records, or none. Its predictive band, and any ensemble forecast
built on it, should then be checked for honesty with the ensemble
scores.

## What these do not cover

They treat the rainfall as given. Parameters absorb the habits of the
rainfall they were fitted on, so the largest single improvement is to
calibrate on the same catchment rainfall product, built the same way,
that is used to forecast ([Catchment rainfall from gauges and
radar](https://jonpayneea.github.io/PDMS7/articles/rainfall.md)).
