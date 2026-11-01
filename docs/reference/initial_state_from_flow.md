# Initial state in equilibrium with an observed flow

A warm start that replaces an arbitrary soil fraction with a state
consistent with the flow observed at the start of the run. It assumes
the catchment is in a steady state at that moment, as it approximately
is in a dry-weather recession:

## Usage

``` r
initial_state_from_flow(
  model,
  observed_m3s,
  baseflow_fraction,
  soil_fraction = 0.5
)
```

## Arguments

- model:

  A FlodePdmModel.

- observed_m3s:

  Observed flow at the start of the run, m3/s; finite and at least `qc`.

- baseflow_fraction:

  Share of the natural flow that is baseflow, in `[0, 1]`.

- soil_fraction:

  Soil storage as a fraction of capacity, used only with split recharge,
  in `[0, 1]`.

## Value

A validated FlodePdmState with step 0.

## Details

- natural flow is `observed_m3s` minus `qc`, converted to mm/h, and
  divided into baseflow (`baseflow_fraction`) and surface flow (the
  rest);

- each routing store, or both stores of a cascade, is set to deliver its
  share in equilibrium, using
  [`storage_for_flow()`](https://jonpayneea.github.io/PDMS7/reference/storage_for_flow.md);

- the soil store is set so that recharge equals baseflow. With standard
  recharge this is S = st + (kg \* qb)^(1 / bg); with demand recharge it
  is the soil storage at which the demand formula gives qb. With split
  recharge the soil store does not drain to groundwater, so the steady
  state does not determine it and `soil_fraction` of capacity is used.
  The soil store is capped at capacity;

- the outlet delay queues hold the water already in transit at that
  flow.

The state's instantaneous flow then equals `observed_m3s`. The first
simulated interval is a mean over the interval, so it departs from the
observation as the stores respond to the forcing; with no rain the
surface store recedes.

`baseflow_fraction` has no default: it varies widely between catchments.
For UK gauged catchments the baseflow index (BFI) published by the
National River Flow Archive is a reasonable value. An exponential store
has no steady state at zero flow, so its share of the flow must be
positive.

The compiled core does the same calculation (`pdm_state_from_flow()` in
src/pdm_core.h).

## References

Moore (2007), doi:10.5194/hess-11-483-2007.

## Examples

``` r
model <- pdm_model(area_km2 = 44)
state <- initial_state_from_flow(model, observed_m3s = 0.8, baseflow_fraction = 0.6)
run_pdm(model, data.frame(rain = c(0, 0), pet = c(0, 0)), state)$output$q_m3s
#> [1] 0.7944496 0.7681147
```
