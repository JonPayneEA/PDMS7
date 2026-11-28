# Calibration mask and peak tolerance: design

Status: draft for approval. No code is written until this is agreed.

## The problem

Flood forecasting needs the peaks. The peaks are also where the flow record is least sure: the
rating is extrapolated above the highest gauging, water may bypass the section above bankfull,
and the gaugings that would test it are fewest there. Weighting the peaks down by their
uncertainty, as `flow_weights()` does for the Box-Cox objective, makes the calibration fit the
flows that matter least. That trade is wrong for flood work.

Two different things are mixed in "uncertain data", and they need different treatment:

- **Wrong data**: flow known not to be what the river did. Infilled or edited spans, flow off the
  applied rating, stage spikes, an event the calibration rain missed altogether. No model should
  be asked to fit these. They are left out.
- **Uncertain data**: flow that is probably close but carries a known error band, chiefly the
  peaks. These stay in, at full weight. Whether an error inside the band should count depends on
  how the forecast will be used.

So the design has two parts: a **mask**, which removes wrong data, and a **peak tolerance**, which
decides how errors inside the rating's band are scored.

## Part 1: the mask

### What it removes

| Source | What is masked | Where it comes from |
|---|---|---|
| Flow quality codes | Steps flagged Suspect or Estimated, if the user asks | the flow file's quality column (reach.validate sets the flags; pdmS7 only reads them) |
| Flow off the applied rating | Each run of departing steps | `reach.rate::check_flow_record()`, `off_curve` |
| Missed events | The whole window of an event the calibration series missed | `compare_rain.R`, `missed_events.csv`, for the series being calibrated |
| Periods given by hand | Any `{from, to, reason}` | `site.yml` |

What it never removes:

- a flow because it is high;
- a flow above the top of the rating;
- a flow above bankfull.

Those are uncertain, not wrong, and part 2 deals with them. A test will hold this rule: the mask
built from a record whose only fault is flow above the top of the rating must mask nothing.

### How it is applied

The mask is a logical vector, one value a step, `TRUE` to score. It is passed to
`calibrate_pdm()` as a new argument, `mask`, and to the other calibrations that share its
objectives (`calibrate_pdm_multi()`, `pdm_stages()`).

The mask is not applied by setting masked flows to `NA`. Events are found on the observed flow
(`find_events()`), and holes in the flow would break the events or move them. Instead:

- the model runs on every step, so its stores carry through masked spans;
- events are found on the whole record, as now;
- each objective scores only the steps the mask keeps;
- an event whose peak step is masked is dropped from the events objective whole, as a peak-less
  event would score its recession as if it were the flood.

Masked steps after the warm-up are reported, by source, in steps and as a share of the
calibration window. If the mask removes more than a quarter of the window, the run warns: the
calibration may rest on too little.

### Validation

The validation window is scored twice: raw, and with the mask. The raw score is the honest one
to compare across calibrations. The masked score shows how much of the shortfall was in data the
model was never meant to fit.

## Part 2: the peak tolerance

### When errors inside the band should count

`forecast_use` in `site.yml` already records how the forecasts will be used.

- **`stage`**: the PDM forecasts flow, which is turned back into stage through the same rating it
  was calibrated on. A rating that reads 15% low at the peaks gives the model 15% low peaks to
  fit; the forecast flow is then 15% low; and the same rating turns it back into the right stage.
  The rating's error cancels. The model should fit the rated flow exactly, errors and all.
  **Tolerance 0.**
- **`hydrodynamic_rated`**: the flow goes into a hydrodynamic model that was itself fitted to
  rated flow, so it shares the rating's error, and it cancels there too. **Tolerance 0.**
- **`hydrodynamic_own`**: the flow goes into a hydrodynamic model with its own hydraulics, which
  needs the flow right in its own terms. A model that fits rated peaks exactly copies the rating's
  error into the flood map. Here an error within the band says nothing about whether the model is
  wrong. **Tolerance: the rating's band.**

So the tolerance is zero for two of the three uses. It changes the calibration only where the
forecast's use needs true flow rather than rated flow.

### How the tolerance is scored

The rating's band gives, for each observed flow `q`, a range `[q * (1 + l(q)), q * (1 + u(q))]`
that the true flow is likely to lie in, with `l` negative and `u` positive. The band is that of
`reach.rate::rating_uncertainty()`: combined where the shared gauging error is given, otherwise
sampling only. It widens with flow, and most of all above the highest gauging.

The tolerance treats a simulated flow inside the band as a perfect fit, and one outside it as out
by its distance from the band's nearer edge. This is a dead band, the epsilon-insensitive loss:

```
s' = q                      if q(1 + l) <= s <= q(1 + u)
s' = s - q u                if s > q(1 + u)
s' = s - q l                if s < q(1 + l)
```

Every objective then scores `s'` against `q`, in place of `s`. Because the change is made to the
simulation before scoring, it works for every objective unchanged: RMSE, NSE, the logs, Box-Cox,
thresholds, and the events objective's peak and timing terms.

`peak_tolerance` in `site.yml` sets it:

- `auto`, the default: 0 for `stage` and `hydrodynamic_rated`, the band for `hydrodynamic_own`;
- `0`: none, whatever the use;
- a number: that many times the band, for a sensitivity test (`0.5`, `1`, `2`).

With `peak_tolerance` above 0 and no band to hand, the run stops and says so; it never assumes a
band.

### The risks, and what guards against them

- **Flat ground for the search.** Inside the band every parameter set that keeps the peaks within
  it scores alike, so the optimiser can wander. In practice the band is narrow at the low and
  middle flows, which pin the model down, and wide only at the few peaks. The run reports the
  share of each peak's error the band absorbed, so a calibration resting on the band shows
  itself.
- **A band that is too wide.** A band from few gaugings can be very wide above the top of the
  rating. The tolerance is capped at a share of the flow (`peak_tolerance_cap`, 0.5 by default),
  and the cap is reported where it binds.
- **The band is itself uncertain.** That is why `peak_tolerance` takes a factor: run at 0.5, 1
  and 2, and the calibration should not change much. If it does, the peaks decide the
  calibration and the rating needs work before the model does.

## Where the settings come from

`compare_rain.R` already writes `calibration_inputs.yml`, which `site.yml` reads with
`rain_comparison:`. Two keys would be added there:

- `mask`: the missed events' windows for each series recommended, and the flow record's
  off-curve runs, each `{from, to, reason}`;
- `rating_band`: the band as a table of flow, `lower` and `upper`, from `rating_uncertainty()`.

`site.yml` gains, under section 3:

```yaml
peak_tolerance: auto        # auto, 0, or a factor of the rating's band
peak_tolerance_cap: 0.5     # the most the tolerance may be, as a share of the flow
mask_quality: []            # flow quality codes to mask, such as [Suspect, Estimated]
mask_periods: []            # periods to leave out by hand: [{from, to, reason}]
```

`calibrate_site.R` builds the mask and the band from these, passes them to the calibration, and
reports both at the head of its summary.

## Functions

| Function | Does |
|---|---|
| `calibration_mask(time, ..., warmup)` | Builds the mask from periods, quality codes and events; returns the mask and a table of what was masked and why |
| `peak_band(observed, band, factor, cap)` | Turns the band table into each step's lower and upper share, scaled and capped |
| `tolerate(sim, observed, band)` | The dead band above: returns `s'` |
| `calibrate_pdm(..., mask = NULL, band = NULL)` | Scores only masked-in steps, `tolerate()`d where `band` is given; both `NULL` leaves it as it is now |

All four take plain vectors and data frames. The PDM itself is unchanged.

## Tests

Expected values from closed forms or hand counts, as everywhere:

- **The dead band**: `tolerate()` on simulated flows inside, on and beyond each edge returns
  exactly the observed, the observed, and the simulated less the edge.
- **No tolerance is no change**: `band = NULL` or a factor of 0 returns the same objective, to the
  last digit, as today's `calibrate_pdm()`.
- **The mask scores only what it keeps**: with half the steps masked, RMSE equals the hand-worked
  RMSE over the other half.
- **An event with its peak masked is dropped** from the events objective, and one masked only
  in its recession is kept.
- **The rule that peaks are never masked**: a record whose only fault is flow above the top of the
  rating gives an empty mask.
- **The forecast uses**: `auto` gives a zero band for `stage` and `hydrodynamic_rated`, the band
  for `hydrodynamic_own`.
- **A synthetic check, reported but not a pass mark**: on `new_site(practice = TRUE)`, whose
  rating reads 15% low above the highest gauging, `hydrodynamic_own` with a band covering that
  error should recover the true peaks no worse, and usually better, than no tolerance.

## Out of scope

- Weighting flows by their uncertainty: rejected, for the reason at the top.
- Masking or changing the rain itself: a clock fault or a gauge failure is fixed upstream, and
  the missed-event windows are masked on the flow side only.
- Any change to the PDM.

## Open questions for you

1. Should Suspect and Estimated flows be masked by default, or only when asked? The draft says
   only when asked, since reach.validate's flags vary by station.
2. Is a quarter of the calibration window the right point to warn that too much is masked?
3. For `hydrodynamic_own`, should the default factor be 1 times the band, or less, given that the
   band itself is an estimate?
