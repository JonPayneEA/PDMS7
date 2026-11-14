# Reviewing a calibration: a Steward's guide

A Custodian calibrates; a Steward decides whether the result is fit to
use. The calibration log records every step the Custodian took, but it
cannot tell you whether those steps were sound. That is the Steward’s
judgement. This guide sets out what to look at, in what order, and what
should make you stop.

You need no R to follow it. Everything here is in the report from
[`build_report()`](https://jonpayneea.github.io/PDMS7/reference/build_report.md),
which opens in a browser, or on the Report tab of
[`calibration_app()`](https://jonpayneea.github.io/PDMS7/reference/calibration_app.md).
[Logging a manual
calibration](https://jonpayneea.github.io/PDMS7/articles/calibration-log.md)
shows how a project is built; [Inside the
logs](https://jonpayneea.github.io/PDMS7/articles/calibration-log.html#inside-the-logs)
explains the files.

## Your role

| Role              | Does                                                                               |
|-------------------|------------------------------------------------------------------------------------|
| Owner             | Accountable for the model’s use. Named in the project; takes no action in the log. |
| Steward           | Reviews and signs off, or sends it back. May not sign off work they took part in.  |
| Delegated Steward | As Steward, under a recorded delegation.                                           |
| Custodian         | Builds the calibration: data, structure, trials, candidate, validation.            |

The package refuses a sign-off from anyone who wrote a trial,
calibration, candidate or validation in the project, checking both the
declared name and the computer login.

## Reading the report, in order

The report follows the order of the work. Review it in the same order:
an error early on invalidates everything after it.

### 1. Integrity

The first section says whether the record is intact: every entry’s
checksum chain, every data file against the checksum taken when it was
registered, and every saved series.

- **Green:** the record is as written. Carry on.
- **Red:** stop. Something was edited after the event, or a data file
  has changed. Ask the Custodian why before reading further.

For a stronger check, run `verify_project(project, rerun = TRUE)`, or
ask the Custodian to. It repeats every model run and confirms each
reproduces its recorded output. A mismatch names what changed in the
software since the run.

### 2. Data

The Data section summarises each registered series: rows, period, step,
missing values and the longest gap. Check:

- **The periods.** Calibration, validation and, if registered, test
  windows are separate, in that order, and long enough: a few years of
  calibration at least, and a validation period that includes floods.
- **Missing flow.** More than about 10 per cent missing in a window
  weakens its scores. A long gap in the middle of the only big flood is
  worse than many short ones.
- **Where the data came from.** The source paths and checksums tie the
  calibration to a specific extract. For data from reach.io, the
  Hydrometric Data Register gives its provenance.
- **Warning thresholds.** If thresholds are registered, are they the
  current ones, in the right units, and is the rating used for level
  thresholds the current rating?

[Preparing your
data](https://jonpayneea.github.io/PDMS7/articles/data-preparation.md)
lists the checks the Custodian should have run.

### 3. Structure

Is the model structure reasonable for the catchment, and is the
reasoning recorded? If a structure comparison was run, the report ranks
the structures on the validation window: a structure chosen despite
ranking low needs a stated reason.

If the structure was recommended step by step, *How the structure was
chosen* draws the decisions: one row per component, every option with
its validation score, the choice filled, the equally good outlined, and
options set aside with a parameter at a bound in grey. Under the figure,
each step’s reason in words. Check that each choice follows the rule it
states: a step that kept its starting option should say the others were
within the tie tolerance; a step that changed should say by how much the
new option was better.

*Run totals* gives the model runs and the elapsed time of each step and
stage. It says what the search cost, and a step with far fewer runs than
its neighbours is worth asking about.

### 4. Calibration path

The path shows every trial and automatic calibration, linked to the run
it started from, with the headline score of each. Look for:

- **A path that explains the candidate.** You should be able to follow
  how the Custodian got from the starting structure to the candidate. A
  candidate that appears from nowhere, or a long run of unexplained
  trials, needs questioning.
- **Reasoning.** Each trial records why it was tried and what the
  Custodian concluded. Thin reasoning is not a failure in itself, but it
  makes the calibration harder to defend later.
- **Parameters on a bound.** An automatic calibration that ends with a
  parameter at the edge of its range was stopped by the fence, not by
  the data. The calibrated value may be fine; it may equally be
  compensating for a data problem.
- **Starts that disagree.** If the automatic starts end at very
  different parameters with similar scores, the data do not pin those
  parameters down. The model may still forecast well, but its parameter
  values should not be read as catchment properties.
- **Stages.** In a staged calibration, check that the first stage got
  the water balance right (volume error close to zero) before the fast
  stores were fitted.

### 5. Candidate and validation

This is the heart of the review. The report shows calibration and
validation scores side by side, with hydrographs and flow-duration
curves for each window.

| Sign                                                                      | Suggests                                                                |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------|
| Validation NSE well below calibration NSE (a drop of more than about 0.1) | Over-fitting, or a change in the catchment or the gauge between periods |
| Volume error over about 10 per cent in either window                      | A water-balance problem: rain, PET, area or rating                      |
| Good overall scores, poor high-flow signature (`fdc_high`)                | The model misses the floods that matter for warnings                    |
| Systematically late or early peaks on the hydrograph                      | Surface store time constants, or a time-stamp error in the data         |
| Poor low-flow signature (`fdc_low`) only                                  | Matters for drought work, less for flood forecasting                    |
| Threshold CSI low, or many false alarms                                   | Not fit for a warning service at that threshold, whatever the NSE       |

Judge the scores against the purpose. An NSE of 0.75 may be perfectly
adequate for a slow chalk river used for drought planning and inadequate
for a flashy catchment with a warning service. Look at the hydrographs:
a single number hides where the errors are.

### 6. The test window and the held-back years

If a test window was registered, it is scored once, after every choice
is made, and sign-off requires it. A poor test result does not block
sign-off, but it must be explained. A test result much worse than
validation suggests the validation window was used, perhaps without
intending it, to make choices.

Most projects also hold back the two wettest water years, and the test
scores them too. Look past the scores, which ordinary days dominate, to
the table of peaks:

- **The candidate’s peak against the observed peak.** A large miss on
  floods the model never saw means the calibration does not extrapolate.
- **The range across equally good fits.** A wide range means the record
  cannot pin down the parameters that control large floods, and the
  candidate’s peak is partly luck.
- **The rating flag.** A peak above the highest gauged flow is itself
  uncertain. Ask whether a miss is the model’s or the rating’s.

If the Data section shows that the calibration window contains many
flows above the highest gauging, ask why. [Larger floods: extrapolation
and the
rating](https://jonpayneea.github.io/PDMS7/articles/extrapolation.md)
explains the table.

## Signing off

The sign-off asks you to confirm four things. Only tick each one if you
did it:

| Item               | You confirm                                                              |
|--------------------|--------------------------------------------------------------------------|
| `integrity`        | The integrity section is clean, or every failure is explained            |
| `data`             | The data are the right data, adequately complete, with the right periods |
| `calibration_path` | The path explains the candidate and the reasoning is adequate            |
| `validation`       | The validation (and test) results are fit for the stated purpose         |

Then write a statement in your own words: what the calibration is fit
for, and any limits on its use. “Accepted for flood forecasting; peaks
above 50 m3/s are underestimated by about 10 per cent, so treat
forecasts above that with caution” is far more useful to the next reader
than “Approved.”

``` r
sign_off_project(project, statement = "Accepted for flood forecasting; ...",
                 checklist = c(integrity = TRUE, data = TRUE, calibration_path = TRUE,
                               validation = TRUE))
```

Once signed off, the project accepts no more entries. Runs with exactly
the signed-off configuration are then marked as approved in the run log.

## Sending it back

If the calibration is not fit for use, do not sign it off. Write a note
in the log saying what must change, so the reason is part of the record:

``` r
log_note(project, "Not signed off: validation volume error is 18 per cent. Check the rating
change in 2019 before recalibrating.")
```

If a signed-off calibration later turns out to be wrong, reopen it with
[`reopen_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
and a reason. The original sign-off stays in the record; a later
sign-off supersedes it.

## A short checklist

1.  Integrity green, or every failure explained.
2.  Periods separate and sensible; missing data acceptable; thresholds
    current.
3.  Structure reasoned; any comparison supports the choice.
4.  The path explains the candidate; no unexplained parameters on
    bounds.
5.  Validation close to calibration; volume error small; hydrographs
    credible; thresholds adequate for warning use.
6.  Test window scored, and any shortfall explained.
7.  A statement that says what the model is fit for, and what it is not.
