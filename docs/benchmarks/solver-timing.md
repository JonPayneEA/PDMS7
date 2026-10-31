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
- Calibration: `optim` reported 97 function evaluations, 1,775 s, convergence code 0,
  1,000 steps. That count leaves out the finite-difference gradient calls (two per parameter
  per gradient). Each of the 97 iterations also computed one gradient, so the true number of
  simulations was about 97 x (1 + 2 x 3) = 679. The time agrees: 1,775 s / 679 = 2.6 s per
  simulation of 1,000 steps, which matches a separate profile of `run_pdm()` at 1.9 to 2.8 s
  across the corners of the bounds. `calibrate_pdm()` now counts every objective call in
  `start_results$evaluations`, so a re-run will report the true figure directly.

## Extrapolation to 60 basins x 20 starts

That is 60 x 20 x 679 = about 814,800 simulations. The 15-minute column scales the 10,600-step
daily timing linearly to 29 years of 15-minute steps (about 1,017,000 steps, 96 times longer);
it is derived, not measured.

| Cores | Daily, adaptive (hours) | Daily, smith (hours) | 15-minute, adaptive (hours) |
|---|---|---|---|
| 1 | 5,010 | 4,660 | 481,000 |
| 4 | 1,250 | 1,170 | 120,000 |
| 16 | 313 | 292 | 30,100 |
| 64 | 78 | 73 | 7,520 |

An earlier version of this report used the 97 count directly and understated these figures
about sevenfold.

## Profile of one simulation

`Rprof` on `run_pdm()` over 1,000 daily steps puts nearly all the time in per-step R overhead:
S7 property access and object construction (`@`, `new_object`), validation (`.check`,
`.validate_state`, `isTRUE`), and building a data.table on every step
(`data.table::data.table`, `as.data.table.list`, about 30 per cent). The groundwater
integration itself (`.rk4`) is under 10 per cent. Cost does not depend much on parameter
values: 1.9 to 2.8 s per 1,000 steps across all eight corners of the calibration bounds.

## Reading the results

1. **The solver is not the bottleneck.** Smith saves about 7 per cent and the RK4 integration
   is under a tenth of the profile. The time goes on interpreter and object overhead in the R
   time loop, at about 2 ms per step.
2. **15-minute calibration is not feasible in R.** About 7,500 hours on 64 cores. Trimming the
   R loop (one table at the end, lighter validation) might gain two or three times. Only a
   compiled time loop can close a gap of this size.
3. **Smith and adaptive disagree materially on this series.** A 40.6 m3/s maximum difference
   against a 63.3 m3/s peak is not a rounding effect. The existing tests cover Smith only on
   small cases. If Smith is considered as a faster option, validate it against adaptive on
   realistic forcing first. No model code was changed here.

## Decision

A peak timing objective stays deferred. Porting the time loop to compiled code is now
justified by items 1 and 2 and is the next step.
