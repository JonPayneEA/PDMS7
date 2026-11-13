# Future directions

Written 2026-11-13, after version 0.25.0, from the Beggearn Huish calibrations (v6 to v8 and the
surface-caps experiment). Each direction says why it is needed, what it is, what it depends on,
and the first step. The [roadmap](roadmap.md) holds the package's longer plan.

## What Beggearn Huish showed

- **Every structure ended with parameters at a bound.** The split share `recharge.alpha` sat at
  0.05 and the surface stores at their caps (12 h and 24 h) in every fit: the model sends 95% of
  its runoff through the groundwater store and lets that store route the floods. The
  exponential store won (validation NSE 0.898 against 0.831 for the cubic) because it drains fast
  when full and slowly when low.
- **Lifting the surface caps raised NSE but harmed the floods.** With `surface.k1` up to 48 h
  the surface route took a share only to act as another slow store; the median peak error on the
  ten largest floods doubled (11% to 24%) and threshold hits fell.
- **The peaks are on time; the recessions are not.** The modelled peaks line up with the
  observed ones, but after the largest floods the model recedes too fast for several days. The
  river has a multi-day timescale that neither run holds alongside the peaks.
- **The fast zone was rejected outright.** Its share went to the lower bound, 0.01.
- **One flood does not add up.** Event 82 (23 April to 20 May 2012): 214 mm of rain, 212 mm of
  flow, so almost nothing evaporated over four weeks of spring with a full soil store. The rain
  record is not short of rain (April 2012 was six times the median April), and the model's soil
  was full. So the rain, the potential evaporation or the flow is wrong for that event.

## 1. Input checks: rain, evaporation and flow together

**Why.** A calibration fits whatever it is given. Event 82 shows that a single bad event can pull
the fit, and that the fault can sit in any of the three inputs. The checks so far look at the
rain alone, and mostly year by year.

**What.** `check_rainfall()`, or more accurately an input check, returning a table of flags (date
range, check, severity, detail) with plots, shown in the report's Data section, logged with the
data, and fed to `screen_events()` so flagged events leave the flood scoring.

1. *The record:* stuck loggers, impossible intensities, unit and resolution errors, filled gaps.
2. *Totals:* monthly totals against the record's own climatology; annual totals against SAAR.
3. *Change over time:* a change-point test (Pettitt) on annual rain and runoff ratio; the
   rain-to-flow lag year by year, for clock drift and summer-time errors.
4. *Events:* rises in flow with almost no rain (missed storms); runoff-ratio outliers for the
   season and wetness; an event balance of rain less evaporation against outflow, flagging
   events whose outflow comes implausibly close to the rain, as event 82 does.
5. *Flow:* peaks above the highest gauging, and volumes resting on an extrapolated rating.
6. *Independent rain:* HadUK-Grid monthly and H19 radar against the catchment rain, as ratios
   against their own usual value for the catchment, not against one: radar has biases of its
   own. Two independent sources disagreeing with the gauges in the same month make a strong
   case.
7. *Gauges, when available:* `gauge_response()` on each gauge, gauge-against-gauge double mass,
   dry gauges.

**Depends on.** Catchment-average series for HadUK-Grid and H19 (direction 2); gauge series from
the EA Hydrology Data Explorer, with quality codes and coordinates; the highest gauged flow at
each station.

**First step.** Agree the layout of the catchment-average tables (below), then build checks 1 to
5, which need only the series already held.

**Decided.** Groups 1 to 5 first; independent rain and gauges as optional inputs that switch on
further checks when supplied.

## 2. Catchment-average series in Databricks

**Why.** HadUK-Grid is already in Databricks and H19 can be moved there. Sixteen years of
15-minute radar is vast as grids and about 600,000 numbers as a catchment average. Averaging
beside the data, and exporting small tables, keeps pdmS7 free of grid handling and works the
same for every catchment.

**What.** A Databricks job that averages each source over each catchment boundary and writes a
Silver or Gold table, one row per catchment, source and time step:

| Column | Meaning |
|---|---|
| `catchment` | station or catchment identifier |
| `source` | `haduk_monthly`, `h19`, `gauge:<id>`, `thiessen` |
| `time` | start of the step, UTC |
| `step` | step length, e.g. `15 min`, `1 month` |
| `rain_mm` | catchment-average depth for the step |
| `quality` | share of the catchment with valid data for the step |

**Depends on.** Catchment boundaries (direction 3).

**First step.** Fix the layout above with the Databricks side, then write the zonal averaging,
in Python or SQL to match the existing work.

## 3. Catchment boundaries, and an internal hydrological terrain model

**Why.** The averaging needs a boundary for each critical gauge, and the model's `area_km2`
turns flow into depth, so an area a few per cent out shifts the whole water balance. The
published boundaries (NRFA, FEH) come from IHDTM, a 50 m grid that is licensed, not open, and
misses divides on flat, urban and engineered ground. Databricks holds the EA LIDAR Composite DTM
at 2 m, which is open.

**What.** An internal hydrologically conditioned terrain model, under its own name:

1. The EA LIDAR Composite DTM, with OS Terrain 50 to fill gaps.
2. Resampled to 10 m: fine enough for drains and flat divides, coarse enough for a river basin.
3. Known rivers burned in, from OS Open Rivers or the EA Detailed River Network, so flow
   follows the mapped channels through culverts and under bridges.
4. Remaining barriers breached and spurious pits removed, breaching in preference to filling.
5. Flow direction and accumulation; catchments delineated from each gauge, the outlet snapped to
   the conditioned channel.
6. Validation against every NRFA station's published area and boundary, and the derived
   channels against the mapped rivers. Where they differ by more than about 5%, find out why
   before trusting either.

Processing by river basin with a buffer, not by fixed tiles, keeps flow paths whole. Flow
direction and accumulation are stored once per basin, so a new gauge's boundary takes seconds.
WhiteboxTools or pysheds in Python do steps 3 to 5.

**What it will not give.** The FEH descriptors that need soil and other data (BFIHOST, SPRHOST,
FARL). It gives boundaries, areas and channel networks; slope descriptors can be derived.

**Governance.** A shared data product others will build on: versioned, with its inputs and their
survey dates, the river network it was burned with, and its validation report against NRFA.

**First step.** The basins holding the critical gauges, validated against NRFA there; national
coverage once the conditioning has proved itself. For Beggearn Huish, the comparison also checks
the 36.7 km2 in the model, one of the suspects for event 82.

## 4. A medium store for multi-day recessions

**Why.** After the largest floods the model recedes too fast for days. Lifting the surface caps
supplied that timescale but drained the peaks. The record wants three timescales together: the
flood peak, a recession over days, and baseflow.

**What.** Use the multi-zone PDM for a slow zone as well as a fast one: a share of the catchment
whose surface store has a time constant of days, so the multi-day recession comes from its own
area without taking water from the peaks. It follows the same rule as the fast zone: kept only if
better on validation by more than the tie tolerance, and not pinned at a bound.

**Depends on.** Direction 1 clearing event 82 first, so a data fault is not mistaken for a
missing store.

**First step.** A slow-zone option alongside `two_zone_config()`, tested on a made-up catchment
with a known medium store, then on Beggearn Huish.

## 5. Scoring individual storms

**Why.** With one event per flood, Beggearn Huish's "floods" are wet spells of three to eleven
weeks with several near-equal spikes. The median timing error of 7.9 h is an artefact: when the
model's highest spike is the neighbour of the observed one, the error is hours though every
spike is on time.

**What.** A smaller `separation` for scoring peaks and timing, so each storm is judged on its
own, set as a project option and used by the events stage, the report and
`compare_calibrations()`. The water-balance checks keep whole floods.

**First step.** Pass `separation` and `trough` through `pdm_stages()`; compare Beggearn Huish's
timing errors at 3, 1.5 and 1 response times.

## 6. Smaller items

- **The exponential store in PDM for PCs files.** `write_pdm_inp()` refuses it until its code
  and parameter layout in a `*.inp` file are confirmed. Needs an example file with an exponential
  store, or the page of the PDM for PCs manual that gives them.
- **The structure diagram when every option is at a bound.** Greying every box hides the choice.
  Keep the normal colours, mark each box "at a bound" in words, and say that none could be set
  aside.
- **Per-gauge inputs to the model.** If `gauge_response()` on the raw gauges shows one gauge
  driving the spike, feed a zone from that gauge's area. Only on that evidence.
- **Multi-input transfer functions.** A DBM-style transfer function with one input per gauge, to
  estimate each gauge's share of the fast and slow responses jointly (Young, 2003; to be checked
  before it is cited elsewhere). After the correlation checks, and only if they show something.
- **Calibration speed, held back by choice.** Calibrating at hourly and validating at 15 minutes,
  and forward-difference gradients, would each cut the cost substantially but change the results.
  Not without a before-and-after comparison.

## Order of work

1. The table layout (direction 2), agreed with the Databricks side.
2. Input checks 1 to 5 (direction 1), and the highest gauged flow for Beggearn Huish.
3. Boundaries for the critical gauges (direction 3), then the HadUK-Grid and H19 averages.
4. Independent rain checks; event 82 settled.
5. The slow zone (direction 4) and storm-by-storm scoring (direction 5).
