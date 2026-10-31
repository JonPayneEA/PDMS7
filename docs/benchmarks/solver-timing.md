# Solver and engine timing

These figures were measured on one machine and apply to it alone: an x86_64 virtual machine
(Intel Xeon at 2.10 GHz, 4 logical cores), R 4.3.3, run on 2026-10-31. Other hardware will
differ in absolute terms. The ratios are more portable than the seconds.

Reproduce with `Rscript inst/benchmarks/time_solvers.R` from the package root.

## Method

- Input: synthetic forcing from fixed seeds. Daily: 10,600 steps. 15-minute: 29 years, which
  is 1,016,856 steps. Rainfall is intermittent gamma (40 per cent wet intervals); PET is a
  seasonal curve. Basin area 100 km2.
- Model: `pdm_presets("standard")` (Pareto capacity, standard recharge, two-store cascade,
  cubic groundwater, no snow).
- Timing: `sim_pdm()` with `solver = "adaptive"` and `solver = "smith"`. One untimed warm-up
  run, then three timed repeats each. Tables report the median.
- Engines: the compiled engine (the default for this model since this change) and the R loop
  (`options(pdmS7.engine = "r")`), which remains the reference implementation. The two give
  bit-identical output; `tests/testthat/test-engine.R` checks this on eight model
  configurations.
- Calibration: one `calibrate_pdm()` run on the full daily series, default control
  (`maxit = 200`), three parameters (`fc`, `recharge.kg`, `groundwater.kb`), synthetic
  observations from a perturbed parameter set.

## Results

| Run | Repeats (s) | Median s per simulation | Microseconds per step |
|---|---|---|---|
| daily, compiled, adaptive | 0.195, 0.048, 0.055 | 0.055 | 5.2 |
| daily, compiled, smith | 0.018, 0.018, 0.016 | 0.018 | 1.7 |
| daily, R loop, adaptive | 23.51, 23.92, 21.80 | 23.51 | 2,220 |
| 15-minute, compiled, adaptive | 3.275, 2.240, 2.539 | 2.539 | 2.5 |
| 15-minute, compiled, smith | 1.911, 2.383, 1.396 | 1.911 | 1.9 |
| 15-minute, compiled, adaptive, flow only | 1.225, 1.135, 1.178 | 1.178 | 1.2 |

"Flow only" is the path `calibrate_pdm()` uses: it returns the scored flow series without
building the 24-column flux table.

- **Engine speed-up:** about 430 times on the daily series (23.5 s against 0.055 s).
- **Solver agreement:** daily, the maximum absolute difference between adaptive and Smith is
  40.64 m3/s against a 63.35 m3/s peak. At 15 minutes it is 0.0041 m3/s against a 24.95 m3/s
  peak.
- **Calibration:** 938 objective evaluations, including the finite-difference gradient calls
  that `optim` leaves out of its own count of 134. It took 59.7 s, with convergence code 0.
  The R loop would have needed about six hours for the same run.

## Extrapolation to 60 basins x 20 starts

That is 60 x 20 x 938 = 1,125,600 evaluations. The daily column uses the measured calibration
time per evaluation. The 15-minute column uses the measured flow-only time and assumes the same
number of evaluations per calibration; it is derived, not measured.

| Cores | Daily (hours) | 15-minute (hours) |
|---|---|---|
| 1 | 19.9 | 368 |
| 4 | 4.98 | 92.1 |
| 16 | 1.24 | 23.0 |
| 64 | 0.311 | 5.76 |

Under the R loop the 15-minute job would have taken about 7,500 hours on 64 cores. An earlier
version of this report also used `optim`'s function count directly, which understated
calibration cost about sevenfold.

## Reading the results

1. **The R loop was the bottleneck, not the solver.** A profile of `run_pdm()` put most of the
   time in per-step S7 object handling, validation and data.table construction; the RK4
   integration was under 10 per cent. The compiled engine removes that overhead.
2. **15-minute calibration is now practical.** About a day on 16 cores, or under six hours on
   64, for 60 basins with 20 starts each.
3. **Smith is unsafe at a daily step and accurate at 15 minutes.** Its linearisation holds over
   a short interval and fails over 24 hours. At 15 minutes it agrees with adaptive to about
   0.02 per cent of peak flow and is roughly a quarter faster. Adaptive remains the default.
4. **Evaluation counts depend on the problem.** 938 evaluations here; real basins and other
   parameter sets will differ. Read `start_results$evaluations` from a pilot run before
   budgeting.

## Decision

The compiled engine covers the default configuration only. Other distributions, recharge
schemes and routing types still run in R and can be ported one at a time against the same
equivalence tests. A peak timing objective stays deferred.
