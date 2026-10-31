# Fast, fair calibration

This guide covers three changes made for benchmarking PDM against LSTM models across many
basins: multi-start calibration, a compiled simulation engine, and a guard on the Smith
groundwater solver. Read it before planning a large calibration run.

The short version: a 29-year, 15-minute calibration of 60 basins with 20 starts each now
takes about a day on 16 cores, down from about 7,500 hours on 64 cores in pure R. Your code
does not change; the speed comes automatically for the default model.

## Why this matters

A benchmark is only fair if both models are calibrated properly. `calibrate_pdm()` uses
L-BFGS-B, a local optimiser. From a single starting point it can settle in a local optimum
and under-calibrate PDM, which would flatter the model it is compared with. Multi-start
calibration addresses that. Running many starts over many basins at 15-minute resolution was
not feasible in R, which is why the compiled engine came next.

## Quick start

### Daily data

```r
library(pdmS7)

config <- pdm_presets("standard")
config$dt <- 24          # model interval in hours: 24 for daily data
config$area_km2 <- 100   # your catchment area

# forcing: data.frame with rain and pet in mm per interval
# observed: discharge in m3/s, aligned to the forcing rows
fit <- calibrate_pdm(
  config, forcing, observed,
  lower = c(fc = 0.5, recharge.kg = 5, groundwater.kb = 5000),
  upper = c(fc = 2, recharge.kg = 60, groundwater.kb = 20000),
  warmup = 365, objective = "nse",
  starts = 20L, seed = 42
)

fit$parameters      # best parameter set
fit$objective       # best objective (1 - NSE here)
fit$start_results   # one row per start
```

### 15-minute data

Set `dt` to 0.25 hours. Everything else is the same.

```r
config <- pdm_presets("standard")
config$dt <- 0.25
config$area_km2 <- 100

fit <- calibrate_pdm(
  config, forcing, observed,
  lower = c(fc = 0.5, recharge.kg = 5, groundwater.kb = 5000),
  upper = c(fc = 2, recharge.kg = 60, groundwater.kb = 20000),
  warmup = 35064, objective = "nse",   # one year of 15-minute steps
  starts = 20L, seed = 42
)
```

For a plain simulation, `sim_pdm()` takes the interval in minutes:

```r
out <- sim_pdm(forcing$rain, forcing$pet, config, timestep_min = 15L)
```

## Multi-start calibration

### How it works

1. Each parameter is rescaled to the unit interval between its `lower` and `upper` bound, so
   parameters with very different units are treated evenly.
2. Start 1 is always the parameter values already in `config`. The remaining `starts - 1`
   starting points are drawn uniformly at random inside the bounds.
3. L-BFGS-B runs from every start, with the same `control` settings.
4. The start with the lowest objective wins. Its parameters, configuration and model are
   returned, exactly as a single-start run returns them.

Because start 1 is the configured point, the best of several starts can never be worse than
a single start from the same configuration.

### Arguments

| Argument | Default | Meaning |
|---|---|---|
| `starts` | `1L` | Number of starts. `1L` behaves exactly as earlier versions. |
| `seed` | `NULL` | Seeds the random starting points, so a run can be repeated. Your session's random number state is restored afterwards. Ignored when `starts` is 1. |

All other arguments are unchanged: `lower`, `upper`, `warmup`, `objective` (rmse, nse or
log_rmse), `flow` (q_m3s or q_end_m3s), `log_offset`, `control` and `soil_fraction`.

### What comes back

The result has the same fields as before, describing the best start, plus `start_results`:

| Column | Meaning |
|---|---|
| `start` | Start number. 1 is the configured point. |
| `objective` | Final objective for that start, on the scale named by `objective_name` (for nse it is 1 - NSE). 1e+30 means no valid evaluation. |
| `convergence` | The `stats::optim` code. 0 is normal convergence; 1 means the iteration limit was reached; 51 and 52 are L-BFGS-B warnings and stops, usually a line search that could make no further progress. |
| `evaluations` | Number of model simulations used by that start, including the gradient calls `optim` leaves out of its own count. |
| `best` | TRUE for the start that was returned. |
| one column per parameter | The fitted value from that start. Always within the bounds. |

### Reading the results

- **Several starts reaching the same objective** suggests the optimum is well defined.
- **A wide spread of objectives** means the surface has local optima, and a single start
  would have been unreliable.
- **The same objective from different parameter values** points to equifinality: the data
  cannot separate those parameters. Narrow the bounds or fix one of them.
- **`convergence` of 1** means the start hit `maxit`. Raise `control = list(maxit = ...)`
  if the best start shows it.
- **`convergence` of 51 or 52** often means the optimiser could not improve further, for
  example on a flat surface or at a perfect fit. Check the objective before treating it as a
  failure.

### How many starts?

Twenty is a cautious default, not a rule. Run a pilot on three to five representative basins
with 20 starts, then check where the best objective first appears:

```r
tab <- fit$start_results
data.frame(start = tab$start, objective = tab$objective, best_so_far = cummin(tab$objective))
```

If the best value is usually reached within the first five starts, five is enough, and the
full run costs a quarter as much.

### Reproducibility

With a fixed `seed`, the same inputs give the same result every time. Use a different seed
per basin when running in parallel, so the basins do not share starting points by accident:

```r
seed = 1000L + basin_index
```

### Running basins in parallel

Parallelism is left to the caller. Run one basin per worker; each worker runs its starts in
sequence. This works on Windows as well as Linux:

```r
library(parallel)

cl <- makeCluster(detectCores() - 1L)
clusterEvalQ(cl, library(pdmS7))
clusterExport(cl, c("basins", "lower", "upper"))

fits <- parLapply(cl, seq_along(basins), function(i) {
  b <- basins[[i]]
  calibrate_pdm(
    b$config, b$forcing, b$observed, lower, upper,
    warmup = b$warmup, objective = "nse",
    starts = 20L, seed = 1000L + i
  )
})
stopCluster(cl)
```

Here `basins` is a list with one entry per catchment, each holding `config`, `forcing`,
`observed` and `warmup`.

## The compiled engine

### What it does

Each time step of PDM is a few dozen arithmetic operations. In R, the work around them cost
far more: building S7 objects, validating them, and creating a one-row data.table at every
step. A profile put the groundwater maths itself at under 10 per cent of the run time.

The compiled engine runs the whole time loop in C++. It covers the default configuration:

- Pareto capacity distribution
- standard recharge
- two-store cascade surface routing
- power-law groundwater routing, including cubic, with either solver

`run_pdm()` checks the model and uses the compiled loop when every component is one of these.
Anything else, such as split recharge, exponential routing or snow, runs on the original R
loop exactly as before. You do not choose; it happens automatically. `sim_pdm()` and
`calibrate_pdm()` both go through `run_pdm()`, so they speed up too.

### Is the output the same?

Yes, bit for bit. The C++ code repeats the R arithmetic in the same order, including two
details of R's own behaviour: `x^2` is computed as `x * x`, and `sum()` accumulates in extended
precision. `tests/testthat/test-engine.R` compares every output column, the final state and
the water balance between the two engines across eight model configurations, restarts and
timestamped forcing, and requires them to be identical.

To run the original R loop, for checking or debugging:

```r
options(pdmS7.engine = "r")     # R loop
options(pdmS7.engine = "auto")  # back to the default
```

### The calibration path

During calibration only the scored flow series is needed. `calibrate_pdm()` uses an internal
path that returns just that series and skips the 24-column flux table. At 15 minutes this
halves the time per evaluation. The values are the same as `run_pdm()` would give.

### Measured speed

On a 4-core Xeon at 2.1 GHz with R 4.3.3:

| Run | Time per simulation |
|---|---|
| 10,600 daily steps, R loop | 23.5 s |
| 10,600 daily steps, compiled | 0.055 s |
| 29 years of 15-minute steps, compiled | 2.5 s |
| 29 years of 15-minute steps, compiled, calibration path | 1.2 s |

A full daily calibration with three parameters took 60 s and 938 evaluations. The R loop
would have needed about six hours. Full details are in the
[timing report](docs/benchmarks/solver-timing.md).

### Installing

The package now contains C++ code, so building from source needs a compiler. On Windows that
means Rtools matched to your R version; on macOS, the Xcode command line tools; on Linux, the
usual build tools. The cpp11 package is needed at build time only; nothing extra is loaded
when the package runs.

```r
install.packages("cpp11")
install.packages("pdmS7_0.3.1.tar.gz", repos = NULL, type = "source")
```

## Choosing a groundwater solver

Cubic groundwater routing has two solvers:

- **`adaptive`** (the default): step-doubling Runge-Kutta. Accurate at every time step tested.
- **`smith`**: a closed-form approximation, about a quarter faster.

Smith's error grows with the square of the time step, and is worse for faster stores (smaller
`kb`). Maximum error as a percentage of peak flow:

| Step | kb 1,000 | kb 10,000 | kb 50,000 |
|---|---|---|---|
| 15 minutes | 0.06 | 0.02 | 0.007 |
| 1 hour | 1.0 | 0.26 | 0.11 |
| 3 hours | 5.5 | 2.2 | 1.0 |
| 24 hours | 100 | 100 | 62 |

Use adaptive unless you need the last quarter of speed at a 15-minute step. Never use Smith
for daily data. `pdm_model()` warns, once per R session, when Smith is combined with a step
above 1 hour. Only the `paper_cubic` preset selects Smith; every other preset uses adaptive.
`inst/benchmarks/smith_step_error.R` reproduces the table.

## Budgeting a large run

Total time is:

```
basins x starts x evaluations per start x seconds per evaluation / cores
```

For 60 basins, 20 starts and 938 evaluations per start, that gives:

| Cores | Daily | 15-minute |
|---|---|---|
| 4 | 5.0 hours | 92 hours |
| 16 | 1.2 hours | 23 hours |
| 64 | 0.3 hours | 5.8 hours |

The 15-minute figures assume the same number of evaluations as the daily test. Real basins
will differ. Before booking compute, run the pilot described above and use the evaluation
counts from its `start_results`.

## Recommended workflow

1. **Prepare the forcing.** Rain and PET in mm per interval, discharge in m3/s, all on the
   same intervals. Set `config$dt` to the interval in hours.
2. **Choose the warm-up.** A year is a reasonable start. Warm-up steps are simulated but not
   scored.
3. **Set bounds.** Keep them physically plausible. Bounds that are too wide waste evaluations;
   bounds that are too narrow can exclude the optimum.
4. **Pilot.** Three to five basins, 20 starts, fixed seeds. Check the spread in
   `start_results` and how many starts were needed.
5. **Run.** All basins in parallel, one basin per worker, a distinct seed per basin.
6. **Check.** For each basin, look at `convergence`, the spread of objectives, and whether any
   fitted parameter sits on a bound.
7. **Validate.** Score the calibrated model on an independent period before comparing it with
   the LSTM.

## Limitations

- Multi-start calibration reduces the risk of a local optimum; it does not guarantee the global
  one.
- Uniform random starts cover the parameter space less evenly than a space-filling design such
  as a Latin hypercube. With 20 starts and three or four parameters this rarely matters.
- The compiled engine covers the default configuration only. Other components run at R speed.
- Evaluation counts depend on the basin, the objective, the bounds and the number of
  parameters.

## For maintainers: extending the engine

To port another component:

1. Add its step to `src/pdm_engine.cpp`, mirroring the R expression in the same evaluation
   order. Use `rpow()` for `^` and the long-double helpers for `sum()`.
2. Pass its parameters through `.engine_run()` in `R/engine.R`.
3. Add its class to `.engine_supported()`. Matching is by exact class, so subclasses stay on
   the R loop until they are added deliberately.
4. Add a configuration using it to `engine_models()` in `tests/testthat/test-engine.R`. The
   test requires identical output from both engines.
5. Run `cpp11::cpp_register()` if a function signature changed, then `roxygen2::roxygenise()`.

Any change to the model equations in R must be repeated in C++. The equivalence tests will
fail until both agree.

## Files

| File | Purpose |
|---|---|
| `R/configuration_part2.R` | `calibrate_pdm()`, including multi-start |
| `R/engine.R` | Engine dispatch, the calibration path and the Smith warning |
| `src/pdm_engine.cpp` | Compiled time loop |
| `R/model_2.R` | `run_pdm()`, which chooses the engine |
| `tests/testthat/test-calibrate_multistart.R` | Multi-start tests |
| `tests/testthat/test-engine.R` | Engine equivalence and Smith warning tests |
| `inst/benchmarks/time_solvers.R` | Timing benchmark |
| `inst/benchmarks/smith_step_error.R` | Smith error by time step |
| `docs/benchmarks/solver-timing.md` | Timing report |
