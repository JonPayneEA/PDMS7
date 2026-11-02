# Where to start

pdmS7 is a probability-distributed rainfall-runoff model (Moore, 2007)
built for one purpose: to calibrate conceptual models fairly, record
that calibration so it can be defended, and compare the result with
machine-learning models on equal terms. Different readers need different
parts. Pick the role closest to yours and read the articles in order.
The [Glossary](https://jonpayneea.github.io/PDMS7/articles/glossary.md)
explains any term along the way.

## I calibrate models (Custodian)

1.  [How the PDM
    works](https://jonpayneea.github.io/PDMS7/articles/pdm-explained.md):
    what the model does, in plain English.
2.  [Preparing your
    data](https://jonpayneea.github.io/PDMS7/articles/data-preparation.md):
    from EA sources to model files, with a checklist.
3.  [Your first model
    run](https://jonpayneea.github.io/PDMS7/articles/example-workflow.md):
    data to a calibrated, saved model.
4.  [Starting a
    run](https://jonpayneea.github.io/PDMS7/articles/starting-states.md)
    and [Choosing model
    components](https://jonpayneea.github.io/PDMS7/articles/model-options.md).
5.  [Scoring a
    simulation](https://jonpayneea.github.io/PDMS7/articles/scoring.md):
    what each score shows.
6.  [Automatic calibration,
    explained](https://jonpayneea.github.io/PDMS7/articles/auto-calibration.md),
    including staged calibration.
7.  [Logging a manual
    calibration](https://jonpayneea.github.io/PDMS7/articles/calibration-log.md):
    the record a Steward will review.
8.  [Choosing a model
    structure](https://jonpayneea.github.io/PDMS7/articles/choosing-structure.md),
    when the standard PDM may not suit.

For many catchments at once, add [Calibrating many
catchments](https://jonpayneea.github.io/PDMS7/articles/many-catchments.md).
[Troubleshooting](https://jonpayneea.github.io/PDMS7/articles/troubleshooting.md)
covers the common errors.

## I review and sign off calibrations (Steward)

1.  [Reviewing a calibration: a Steward’s
    guide](https://jonpayneea.github.io/PDMS7/articles/steward-guide.md):
    what to look at and what should make you stop.
2.  [Scoring a
    simulation](https://jonpayneea.github.io/PDMS7/articles/scoring.md):
    enough to read the report’s scores.
3.  [Logging a manual
    calibration](https://jonpayneea.github.io/PDMS7/articles/calibration-log.md):
    how the record is built.
4.  [Inside the
    logs](https://jonpayneea.github.io/PDMS7/articles/log-structure.md):
    what the checksums prove.

## I am accountable for a model’s use (Owner)

1.  This page and the [Steward’s
    guide](https://jonpayneea.github.io/PDMS7/articles/steward-guide.md),
    for what sign-off means.
2.  [The benchmark
    protocol](https://jonpayneea.github.io/PDMS7/benchmark-protocol.md),
    if the model is part of the comparison with machine learning.
3.  [Calibration log
    design](https://jonpayneea.github.io/PDMS7/calibration-log-design.md),
    for the governance decisions behind the log.

## I forecast

1.  [How the PDM
    works](https://jonpayneea.github.io/PDMS7/articles/pdm-explained.md).
2.  [Forecast
    updating](https://jonpayneea.github.io/PDMS7/articles/forecast-updating.md):
    state correction and error prediction.
3.  [AR and ARMA error correction,
    explained](https://jonpayneea.github.io/PDMS7/articles/ar-error-correction.md):
    what the IMFS coefficients mean.
4.  [Testing forecasts with
    hindcasts](https://jonpayneea.github.io/PDMS7/articles/hindcasts.md):
    skill by lead time against persistence.
5.  [Scoring a
    simulation](https://jonpayneea.github.io/PDMS7/articles/scoring.md),
    for the threshold scores POD, FAR and CSI.

## I build the LSTM side of the comparison

1.  [The benchmark
    protocol](https://jonpayneea.github.io/PDMS7/benchmark-protocol.md):
    data, periods, effort and scoring, fixed in advance.
2.  [Scoring a
    simulation](https://jonpayneea.github.io/PDMS7/articles/scoring.md):
    the scoring function both models are judged by.
3.  [Testing forecasts with
    hindcasts](https://jonpayneea.github.io/PDMS7/articles/hindcasts.md):
    how forecasts from any model are scored.
4.  [How the PDM
    works](https://jonpayneea.github.io/PDMS7/articles/pdm-explained.md),
    to know what the LSTM is up against.

## I develop or maintain the package

1.  [Model
    equations](https://jonpayneea.github.io/PDMS7/articles/model-equations.md):
    every equation, with Moore’s numbering.
2.  [The C
    core](https://jonpayneea.github.io/PDMS7/articles/compiled-core.md):
    speed, equivalence tests and use from other languages.
3.  The Guides menu: validation, source notes, benchmark timing and the
    roadmap.
4.  [Further
    reading](https://jonpayneea.github.io/PDMS7/articles/further-reading.md).
