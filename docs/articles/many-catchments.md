# Calibrating many catchments

Calibrating one catchment is craft. Calibrating sixty is logistics:
every basin must be treated the same way, the computing must be
budgeted, failures must be caught without stopping the rest, and the
results must be judged as a set. A large-sample comparison, such as PDM
against a machine learning model across many gauges, is only as fair as
this consistency.

This article runs a small version live: eight synthetic catchments, each
with known “true” parameters. Real data cannot tell you whether
calibration found the truth; synthetic data can, so they show where
calibration succeeds and where it cannot. The full-scale recipe is at
the end.

## The catchments

Each basin has its own area, climate and parameters, drawn from
plausible ranges. Its “observed” flow is the true model’s output with 4
per cent gauging noise.

``` r
set.seed(2024)
n <- 24 * 60
make_basin <- function(i) {
  time <- seq(as.POSIXct("2023-10-01", tz = "UTC"), by = 3600, length.out = n)
  wet <- stats::runif(1, 0.04, 0.09)
  scale <- stats::runif(1, 2, 4)
  forcing <- data.frame(
    time = time, pet = stats::runif(1, 0.04, 0.09),
    rain = ifelse(stats::runif(n) < wet, stats::rgamma(n, 0.7, scale = scale), 0)
  )
  truth <- pdm_presets("standard")
  truth$area_km2 <- round(stats::runif(1, 10, 200))
  truth$fc <- stats::runif(1, 0.9, 1.2)
  truth$distribution$cmax <- stats::runif(1, 80, 250)
  truth$recharge$kg <- exp(stats::runif(1, log(20), log(300)))
  k <- sort(stats::runif(2, 1, 12))
  truth$surface$k1 <- k[1]
  truth$surface$k2 <- k[2]
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s *
    exp(stats::rnorm(n, 0, 0.04))
  list(id = sprintf("B%02d", i), forcing = forcing, observed = observed, truth = truth)
}
basins <- lapply(1:8, make_basin)
```

One basin has a data fault, as real collections do: a run of negative
evaporation from a corrupted file.

``` r
basins[[6]]$forcing$pet[100:110] <- -0.05
```

## One protocol for every basin

The protocol is a function, so every basin gets exactly the same
treatment: the same structure, bounds, windows, starts and seed. Each
basin gets its own calibration-log project, so every calibration is
recorded and can be reviewed and signed off like a manual one. A failure
is caught and returned, not allowed to stop the batch.

``` r
lower <- c(fc = 0.7, distribution.cmax = 50, recharge.kg = 5, surface.k1 = 0.5,
           surface.k2 = 0.5)
upper <- c(fc = 1.4, distribution.cmax = 400, recharge.kg = 600, surface.k1 = 20,
           surface.k2 = 20)

calibrate_basin <- function(basin, root) {
  folder <- file.path(root, basin$id)
  tryCatch({
    start_calibration_project(folder, catchment = basin$id, gauge = basin$id,
                              purpose = "Large-sample benchmark",
                              area_km2 = basin$truth$area_km2, owner = "Deputy Director",
                              steward = "Sam Steward")
    register_data(folder, basin$forcing, basin$observed,
                  calibration = c("2023-10-11", "2023-11-14"),
                  validation = c("2023-11-15", "2023-11-29"))
    start <- pdm_presets("standard")
    start$area_km2 <- basin$truth$area_km2
    select_structure(folder, start, "Benchmark protocol: standard PDM for every basin.")
    fit <- log_auto_calibration(folder, parent = 3, lower = lower, upper = upper,
                                objective = "nse", starts = 3, seed = 1,
                                control = list(maxit = 25),
                                reasoning = "Benchmark protocol: 3 starts, fixed bounds.")
    propose_candidate(folder, fit$id, "Benchmark protocol: best of the automatic starts.")
    validate_candidate(folder, "Benchmark protocol.")
    list(id = basin$id, folder = folder, fit = fit$id, error = NA_character_)
  }, error = function(e) {
    list(id = basin$id, folder = folder, fit = NA_character_, error = conditionMessage(e))
  })
}
```

The first ten days of each record are warm-up, the next five weeks
calibration and the last two weeks validation. Real records are far
longer; the shape of the protocol is the same.

## What it will cost

Budget before running. One model run of these two-month records takes:

``` r
model <- pdm_from_config(basins[[1]]$truth)
per_run <- system.time(for (i in 1:20) run_pdm(model, basins[[1]]$forcing))[["elapsed"]] / 20
signif(per_run, 2)
#> [1] 0.0037
```

A calibration of five parameters with three starts uses roughly 1,000 to
2,000 model runs, so the batch should take about 39 seconds. Measure
runs per start on a pilot before committing a large computer:
`inst/examples/pilot_calibration.R` does this, and the [calibration
article](https://jonpayneea.github.io/PDMS7/articles/calibration.md)
explains the formula.

## Running the batch

``` r
options(pdmS7.user = "Ann Hydrologist", pdmS7.role = "custodian")
root <- file.path(tempdir(), "benchmark")
elapsed <- system.time(results <- lapply(basins, calibrate_basin, root = root))[["elapsed"]]
round(elapsed)
#> [1] 30
for (r in results) if (!is.na(r$error)) cat(r$id, "failed:", r$error, "\n")
#> B06 failed: pet must contain finite nonnegative numbers
```

The faulty basin was refused at registration, with the reason, and the
other seven ran. Its project holds its start entry, so the failure is on
record too; fix the data and register again.

On a server the same function runs basins in parallel. Each worker
writes only its own project folder, so there is no contention, and each
needs the user declared:

``` r
cl <- parallel::makeCluster(parallel::detectCores() - 1L)
parallel::clusterEvalQ(cl, {
  library(pdmS7)
  options(pdmS7.user = "Ann Hydrologist", pdmS7.role = "custodian")
})
results <- parallel::parLapply(cl, basins, calibrate_basin, root = root)
parallel::stopCluster(cl)
```

## The results as a set

[`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
gathers every project into one table, with the candidate’s headline
score on both windows.

``` r
ok <- Filter(function(r) is.na(r$error), results)
folders <- vapply(ok, function(r) r$folder, character(1))
summary <- read_projects(folders)
summary[, .(project, status, runs, headline, calibration = round(candidate_score, 3),
            validation = round(validation_score, 3))]
#>    project status  runs headline calibration validation
#>     <char> <char> <int>   <char>       <num>      <num>
#> 1:     B01   open     2      nse       0.988      0.987
#> 2:     B02   open     2      nse       0.977      0.980
#> 3:     B03   open     2      nse       0.982      0.983
#> 4:     B04   open     2      nse       0.994      0.997
#> 5:     B05   open     2      nse       0.966      0.973
#> 6:     B07   open     2      nse       0.982      0.967
#> 7:     B08   open     2      nse       0.997      0.994
```

``` r
par(mfrow = c(1, 2), mar = c(4, 4.2, 1, 1))
range_nse <- range(c(summary$candidate_score, summary$validation_score))
plot(summary$candidate_score, summary$validation_score, pch = 16, col = pal[1],
     xlim = range_nse, ylim = range_nse, xlab = "Calibration NSE", ylab = "Validation NSE")
abline(0, 1, col = pal[7])
text(summary$candidate_score, summary$validation_score, summary$project, pos = 4,
     cex = 0.7, col = pal[5])
plot(sort(summary$validation_score), seq_len(nrow(summary)) / nrow(summary), type = "s",
     lwd = 2, col = pal[1], xlab = "Validation NSE", ylab = "Share of basins", ylim = c(0, 1))
```

![Left: calibration against validation NSE. Points below the line did
worse on data the calibration never saw. Right: the share of basins
reaching each validation
NSE.](many-catchments_files/figure-html/scores-1.png)

Left: calibration against validation NSE. Points below the line did
worse on data the calibration never saw. Right: the share of basins
reaching each validation NSE.

The distribution across basins, not any single basin, is the result of a
large-sample calibration. Report it whole: the median says how good the
model usually is, the lower tail where it fails.

## Did the starts agree?

Each automatic calibration logged its table of starts. When starts end
at different objectives, the convergence codes say why.

``` r
agreement <- do.call(rbind, lapply(ok, function(r) {
  starts <- read_entry(r$folder, r$fit)$start_results
  objective <- unlist(starts$objective)
  data.frame(basin = r$id, best = signif(min(objective), 3),
             worst = signif(max(objective), 3),
             converged = sum(unlist(starts$convergence) == 0),
             evaluations = sum(unlist(starts$evaluations)))
}))
agreement$agree <- (agreement$worst - agreement$best) < 1e-3
agreement
#>   basin    best  worst converged evaluations agree
#> 1   B01 0.01190 0.0320         0        1199 FALSE
#> 2   B02 0.02300 0.0230         2        1001  TRUE
#> 3   B03 0.01780 0.0535         3         825 FALSE
#> 4   B04 0.00599 0.0587         0        1045 FALSE
#> 5   B05 0.03360 0.0338         0        1056  TRUE
#> 6   B07 0.01830 0.0183         1        1122  TRUE
#> 7   B08 0.00274 0.0827         3         660 FALSE
```

Two different problems show here. Where every start converged (code 0)
yet the objectives differ, as for B03 and B08, the surface has separate
optima, and a single-start calibration could have stopped at the worse
one: those basins need more starts. Where starts stopped at the
iteration limit (code 1), the disagreement only means the budget was too
small; this article caps each start at 25 iterations to run quickly, and
a real run should allow 200 or more. Either way, a batch should flag
such basins automatically rather than trust the best start.

## Did calibration find the truth?

Synthetic basins allow what real ones cannot: comparing each fitted
parameter with the value that generated the data. The two surface time
constants are interchangeable in a cascade, so they are compared as the
faster and the slower of the pair.

``` r
pairs <- do.call(rbind, lapply(ok, function(r) {
  fitted <- read_entry(r$folder, r$fit)$configuration
  truth <- basins[[match(r$id, vapply(basins, function(b) b$id, ""))]]$truth
  value <- function(cfg) {
    k <- sort(c(cfg$surface$k1, cfg$surface$k2))
    c(fc = cfg$fc, cmax = cfg$distribution$cmax, kg = cfg$recharge$kg,
      k_fast = k[1], k_slow = k[2])
  }
  data.frame(basin = r$id, parameter = names(value(truth)), truth = value(truth),
             fitted = value(fitted))
}))
par(mfrow = c(1, 5), mar = c(4, 4, 2, 0.5), mgp = c(2.2, 0.7, 0))
for (p in unique(pairs$parameter)) {
  d <- pairs[pairs$parameter == p, ]
  lim <- range(c(d$truth, d$fitted))
  plot(d$truth, d$fitted, pch = 16, col = pal[1], xlim = lim, ylim = lim, main = p,
       xlab = "True", ylab = "Fitted", log = if (p == "kg") "xy" else "")
  abline(0, 1, col = pal[7])
}
```

![Fitted against true parameter values, each basin a point. Points on
the line are recovered
exactly.](many-catchments_files/figure-html/recovery-1.png)

Fitted against true parameter values, each basin a point. Points on the
line are recovered exactly.

``` r
pairs$error <- pairs$fitted / pairs$truth - 1
aggregate(cbind(median_abs_error = abs(error)) ~ parameter, data = pairs,
          FUN = function(x) round(stats::median(x), 3))
#>   parameter median_abs_error
#> 1      cmax            0.040
#> 2        fc            0.001
#> 3    k_fast            0.061
#> 4    k_slow            0.050
#> 5        kg            0.010
```

The rainfall factor and the recharge constant come back almost exactly:
they control the water balance and the baseflow that every week of
record shows. The soil capacity comes back well except in one basin,
where a large store that two autumn months never fill leaves the data
little to say about its size. The surface time constants are recovered
in most basins, but in one the pair trades off, the fast store fitted
slower and the slow store faster, giving much the same hydrographs.

The lesson for real catchments, where the truth is unknown, is that an
excellent fit does not prove the parameters are right. Longer records
that include a dry summer and a wet winter, the [parameter
sensitivity](https://jonpayneea.github.io/PDMS7/articles/calibration-log.md)
in each project’s report, and a [staged
calibration](https://jonpayneea.github.io/PDMS7/articles/calibration.md)
that fits the water balance on years of daily data all help. Parameters
matter whenever the model is used outside the conditions it was
calibrated on.

## Review at scale

A Steward reviewing sixty basins starts from the summary table, checks
the integrity of every project, and reads the report of each basin in
the lower tail.

``` r
integrity <- vapply(folders, function(f) all(verify_project(f)$ok), logical(1))
table(intact = integrity)
#> intact
#> TRUE 
#>    7
```

``` r
worst <- summary[order(validation_score)][1:5]
for (f in worst$path) build_report(f)
```

Every project can then be signed off one by one, as in [Logging a manual
calibration](https://jonpayneea.github.io/PDMS7/articles/calibration-log.md).
A batch protocol does not remove the Steward; it lets them spend their
time on the basins that need it.

## The full-scale recipe

For 60 basins with 29 years at 15 minutes, the shape is the same; only
the data loading and the budget change. One run of 29 years at 15
minutes takes about a second with the compiled engine ([performance
guide](https://jonpayneea.github.io/PDMS7/performance.md)), so 60 basins
of 20 starts at roughly 1,500 runs each take about 500 hours of
computing: about eight hours on 64 cores. Staged calibration can cut
that several times over.

``` r
load_basin <- function(id, data_root) {
  forcing <- data.table::fread(file.path(data_root, id, "forcing.csv"))
  flow <- data.table::fread(file.path(data_root, id, "flow.csv"))
  config <- read_pdm_config(file.path(data_root, id, "config.yml"))
  list(id = id, forcing = forcing, observed = flow$q_m3s, truth = config)
}
ids <- list.dirs("basins", full.names = FALSE, recursive = FALSE)
basins <- lapply(ids, load_basin, data_root = "basins")
# calibrate_basin() as above, with starts = 20, the real windows and control = list(maxit = 200)
```
