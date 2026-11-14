# Roadmap

Updated 2026-11-02, after version 0.4.0. The [future
directions](https://jonpayneea.github.io/PDMS7/future-directions.md),
written after the Beggearn Huish calibrations, set out the next work on
input checks, catchment boundaries and model structure.

## Next

1.  **Phase 1 of the benchmark.** CAMELS-GB at a daily step, under the
    [benchmark
    protocol](https://jonpayneea.github.io/PDMS7/benchmark-protocol.md):
    confirm the facts copied from Lees et al. (2021), sign the protocol
    off, run the pilot that fixes PDM’s calibration method and effort,
    then calibrate and score.
2.  **Benchmark tooling.** A worked benchmark script that runs the
    protocol end to end; a specified exchange format for LSTM output
    with a reader that checks it against the observation mask; the
    day-of-year lower benchmark; and a `protocol` entry in the
    calibration log so that each protocol version is registered and
    signed off before any test score exists.
3.  **A real-catchment pilot.** Three to five EA catchments through the
    full logged process, to find what synthetic examples cannot, and an
    article built from the results.

## Then

- **Hindcasts in the calibration log.** A `hindcast` entry, so forecast
  skill by lead time is reviewed and signed off with the calibration,
  and shown in the report and the app.
- **AR assessment.** Stability and decay-time checks for any AR set,
  flagged in every hindcast.
- **Event-based forecast scores.** Peak timing and peak error by lead
  time, for floods only.
- **Phase 2 of the benchmark.** EA gauged catchments at 15 minutes, once
  phase 2’s decisions are closed.

## Later

- **Uncertainty.** Parameter spread from the multi-start archive, and
  ensemble bounds on forecasts.
- **River-network routing.** Reach travel times, tributaries, reservoirs
  and transfers. Within-catchment surface and groundwater routing
  remains available.
- **Further assimilation.** Uncertainty-aware updates of snow, soil and
  routing stores, ensemble filters and explicit assimilation water
  budgets. PACK’s survey-based state updating is not yet implemented.
- **Further science.** Evolutionary Pareto search, abstractions and
  returns, and multi-zone snow and catchment models.

Each needs its own acceptance criteria, conservation tests and
independent validation.

## Done since 0.3

Configuration fingerprints and the run log; the calibration log with
Steward sign-off; threshold scores, including crossing and peak timing
at thresholds; structure comparison; batch calibration; staged
calibration; snow basins in batches; response times; hindcasts with
lead-time scores and IMFS-style AR post-processing; the benchmark
protocol’s decisions.
