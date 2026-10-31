# Cubic groundwater solver timing

These figures were measured on one machine and apply to it alone: an x86_64 virtual machine
(Intel Xeon at 2.10 GHz, 4 logical cores), R 4.3.3, run on 2026-10-31. Other hardware will
differ in absolute terms. The ratios are more portable than the seconds.

Reproduce with `Rscript inst/benchmarks/time_solvers.R` from the package root.

## Method

- Input: 10,600 synthetic daily steps, fixed seed 20261031. Rainfall is intermittent gamma
  (40 per cent wet days); PET is a seasonal curve. Basin area 100 km2.
- Model: `pdm_presets("standard")` with cubic groundwater, timestep 1440 minutes.
- Timing: `sim_pdm()` with `solver = "adaptive"` and `solver = "smith"`. One untimed warm-up
  run, then three timed repeats each. The table reports the median.
- Calibration count: one `calibrate_pdm()` run, default control (`maxit = 200`), three
  parameters (`fc`, `recharge.kg`, `groundwater.kb`), synthetic observations from a perturbed
  parameter set. **This run used the first 1,000 steps, not the full 10,600.** A first attempt
  on the full series ran for over an hour without finishing and was stopped. The evaluation
  count is a property of the optimiser, but it may differ on a longer series.

## Results

| Solver | Repeats (s) | Median s per simulation |
|---|---|---|
| adaptive | 22.147, 22.652, 21.862 | 22.147 |
| smith | 20.565, 20.609, 21.330 | 20.609 |

- Speed-up of Smith over adaptive: 1.1 times.
- Maximum absolute flow difference between the solvers: 40.64 m3/s. The maximum adaptive flow
  on the same series is 63.35 m3/s.
- Calibration: 97 objective evaluations, 1,775 s, convergence code 0, 1,000 steps.

## Extrapolation to 60 basins x 20 starts

That is 60 x 20 x 97 = 116,400 objective evaluations. Two bases follow, because the
calibration run disagrees with the simulation timing.

**Basis A: evaluation cost equals a `sim_pdm()` run on 10,600 steps** (the figures above).

| Cores | adaptive (hours) | smith (hours) |
|---|---|---|
| 1 | 716 | 666 |
| 4 | 179 | 167 |
| 16 | 45 | 42 |
| 64 | 11.2 | 10.4 |

**Basis B: evaluation cost as observed inside the calibration.** The calibration spent
1,775 s / 97 = 18.3 s per evaluation on only 1,000 steps. Scaled linearly to 10,600 steps that
is about 194 s per evaluation, which gives roughly 6,300 core-hours for the full job, or about
98 hours on 64 cores. This is a derived estimate, not a measurement, and assumes cost grows
linearly with series length.

## Reading the results

1. **The solver is not the bottleneck.** Smith saves about 7 per cent. Per-step cost is about
   2 ms for either solver, which points at interpreter and object overhead in the R time loop,
   not at the groundwater integration. Replacing the adaptive solver will not change the
   economics of a 60-basin multi-start run.
2. **Calibration evaluations cost far more than a plain simulation.** At 18.3 s per 1,000 steps
   against 2.1 s per 1,000 steps for `sim_pdm()`, the gap is roughly nine-fold. I have not
   established why. The optimiser may probe parameter corners where the adaptive solver takes
   many sub-steps, but that is a hypothesis and was not tested. Profile one evaluation before
   committing compute to the full job.
3. **Smith and adaptive disagree materially on this series.** A 40.6 m3/s maximum difference
   against a 63.3 m3/s peak is not a rounding effect. The existing tests cover Smith only on
   small cases. If Smith is considered as a faster option, validate it against adaptive on
   realistic forcing first. No model code was changed here.

## Decision

C++ porting of the routing code and a peak timing objective stay deferred, as recorded in
`NEWS.md`. Item 1 argues that a routing port alone would not pay for itself, and item 2 needs
explaining before any port is scoped.
