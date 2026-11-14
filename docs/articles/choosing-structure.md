# How the model structure is chosen

The structure of a model, its soil store, recharge rule and routing, is
a modelling decision like any other, and a reviewer may ask why this
one. “It is the standard” is an answer; “we calibrated the alternatives
alike and this one did best on data the calibration never saw” is a
better one.
[`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md)
gives that answer, and logs it.

This article first explains how
[`recommend_structure()`](https://jonpayneea.github.io/PDMS7/reference/recommend_structure.md)
chooses the soil store, recharge rule and groundwater store, step by
step. It then compares eight structures on a synthetic catchment whose
true structure is known, and carries the chosen one through validation
and a final test. The [component
guide](https://jonpayneea.github.io/PDMS7/articles/model-options.md)
explains what each component does.

## How the structure is chosen

[`recommend_structure()`](https://jonpayneea.github.io/PDMS7/reference/recommend_structure.md)
chooses the structure one component at a time, as a hydrologist would,
and writes down why. `calibrate_project(recommend = TRUE)` calls it
before the staged calibration. Each step changes one component and holds
the others at what the steps before chose:

| Step | Component               | Options compared                                        |
|------|-------------------------|---------------------------------------------------------|
| 1    | Recharge rule           | standard, split, demand                                 |
| 2    | Soil store distribution | Pareto, rectangular, triangular, exponential, lognormal |
| 3    | Groundwater store       | cubic, quadratic, linear, exponential                   |

**Why this order.** It follows what a record can tell apart. On made-up
catchments whose true structure is known ([What automatic calibration
recovers](https://jonpayneea.github.io/PDMS7/articles/large-sample.md)),
the recharge rule was identified every time, by margins of 0.08 or more
in log NSE, and the groundwater store only by margins too small to
trust. Deciding the clearest question first means the later, harder
choices are made on a structure that is already right where the record
can say so.

**What each step does.** Every option is calibrated alike, by
[`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md):
the same objective, starts, seed and iteration limit, bounds from
[`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
for its own components, on the calibration window. Each is then scored
on the validation window, which no calibration saw. One rule then makes
the choice:

1.  **Set aside any option bent to fit.** An option that ended with a
    parameter at a bound of its search range is not describing the
    catchment; the search pushed it as far as it could go. It is set
    aside, unless every option did. (Split recharge cannot end at a
    share of 0 or 1, which would switch a flow path off: its search
    range is 0.05 to 0.95.)
2.  **Find the equally good.** Every remaining option within the tie
    tolerance of the best validation score counts as equally good: 0.02
    in NSE unless the project registered another. A smaller difference
    is a tie, not a result; another seed or another winter could reorder
    them.
3.  **Keep the current component if it is among them.** The record
    cannot justify a change. This makes the recommendation conservative:
    where the record is silent, as it usually is about the groundwater
    store, the standard structure stays.
4.  **Otherwise, break the tie on the floods.** Among the equally good,
    the option with the smallest median peak error on the largest
    validation events wins, then the one with fewer parameters.

**An example.** On one catchment the groundwater step compared:

| Option          | Parameters | Calibration NSE | Validation NSE |
|-----------------|------------|-----------------|----------------|
| exponential     | 8          | 0.9362          | 0.9172         |
| quadratic       | 7          | 0.9387          | 0.9171         |
| linear          | 7          | 0.9165          | 0.8923         |
| cubic (current) | 7          | 0.8826          | 0.8369         |

The exponential and quadratic stores are equally good, 0.0001 apart. The
current cubic store is not among them, 0.08 behind, so rule 3 does not
keep it. Rule 4 chose the exponential store for its smaller median peak
error on the largest validation floods. Had their peak errors been
equal, the quadratic store would have won on fewer parameters.

Every comparison is logged, and each step’s choice and reason is written
as a note, so the recommendation is part of the audit trail:

``` r
rec <- recommend_structure(project, reasoning = "First choice of structure.")
rec                           # one line per step: choice and reason
rec$steps$recharge$table      # the comparison, with at_bound and equally_good
```

**Zones, if asked.** With `zones = c(1, 2)` in
[`calibrate_project()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_project.md),
a fourth step compares the structure chosen as one zone with the same
structure plus a small fast zone, by the same rule ([Choosing model
components](https://jonpayneea.github.io/PDMS7/articles/model-options.html#several-zones);
worked through in [The two-zone
PDM](https://jonpayneea.github.io/PDMS7/articles/two-zone-pdm.md)). Use
it where one PDM cannot give a sharp spike and a slower flood hydrograph
at once: the signs are a split recharge share at its lower bound and
surface stores at their caps in every fit.

**What it does not choose.** The surface routing stays a cascade of two
linear stores, the standard and almost always adequate. The groundwater
extension is not tried automatically: it needs abstraction data or a
reason to expect losses, and its parameters cannot be pinned down from
flow alone. Add it to the configuration when the catchment calls for it
([Choosing model
components](https://jonpayneea.github.io/PDMS7/articles/model-options.html#the-groundwater-extension)).

The rest of this article runs a full comparison by hand, on a made-up
catchment, and carries the chosen structure through validation and a
final test.

## The catchment

The “true” catchment has a lognormal soil store. The calibrator is not
told.

``` r
set.seed(11)
n <- 24 * 75
time <- seq(as.POSIXct("2023-10-01", tz = "UTC"), by = 3600, length.out = n)
forcing <- data.frame(
  time = time, pet = 0.06,
  rain = ifelse(stats::runif(n) < 0.07, stats::rgamma(n, 0.7, scale = 3), 0)
)
truth <- structure_set("lognormal")$lognormal
truth$area_km2 <- 60
truth$fc <- 1.1
truth$distribution$meanlog <- 4.8
truth$distribution$sdlog <- 0.5
truth$recharge$kg <- 2000
truth$surface$k1 <- 3
truth$surface$k2 <- 10
# The river is already flowing when the record starts: steady state, not empty stores.
truth_model <- pdm_from_config(truth)
observed <- run_pdm(truth_model, forcing,
                    initial_state_from_flow(truth_model, 1, 0.7))$output$q_m3s *
  exp(stats::rnorm(n, 0, 0.04))
```

The project registers three windows: calibration, validation, and a
final **test** window. Ranking structures on the validation window uses
it up as an independent check, so the test window is kept back, scored
once, at the end, by nothing but
[`test_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md).

``` r
options(pdmS7.user = "Ann Hydrologist", pdmS7.role = "custodian")
project <- file.path(tempdir(), "structure-choice")
start_calibration_project(project, catchment = "Example Brook", gauge = "99002",
                          purpose = "Structure selection", area_km2 = 60,
                          owner = "Deputy Director", steward = "Sam Steward")
reg <- register_data(project, forcing, observed,
                     calibration = c("2023-10-08", "2023-11-20"),
                     validation = c("2023-11-21", "2023-12-05"),
                     test = c("2023-12-06", "2023-12-14"), wettest_years = 0)
```

## The candidates

[`structure_set()`](https://jonpayneea.github.io/PDMS7/reference/structure_set.md)
gives the standard PDM and seven variants, each one change from it, so
each comparison answers one question.

``` r
structures <- structure_set()
data.frame(
  structure = names(structures),
  soil = vapply(structures, function(s) s$distribution$type, ""),
  recharge = vapply(structures, function(s) s$recharge$type, ""),
  groundwater = vapply(structures, function(s) s$groundwater$type, ""),
  row.names = NULL
)
#>                 structure        soil recharge groundwater
#> 1                standard      pareto standard       cubic
#> 2             rectangular rectangular standard       cubic
#> 3              triangular  triangular standard       cubic
#> 4             exponential exponential standard       cubic
#> 5               lognormal   lognormal standard       cubic
#> 6                   split      pareto    split       cubic
#> 7                  demand      pareto   demand       cubic
#> 8 exponential_groundwater      pareto standard exponential
```

Each structure calibrates the parameters of its own components, within
bounds from a table shipped with the package. Parameters that span
orders of magnitude are searched on a log scale, so that a recharge
constant of 10 hours gets as much attention as one of 1,000.

``` r
calibration_bounds(structures$lognormal)[, c("path", "lower", "upper", "scale")]
#>                   path lower   upper  scale
#> 1 distribution.meanlog   2.3       6 linear
#> 2   distribution.sdlog   0.1       2 linear
#> 3          recharge.kg   1.0    5000    log
#> 4           surface.k1   0.5      72    log
#> 5           surface.k2   0.5      72    log
#> 6       groundwater.kb 100.0 1000000    log
```

Bounds can be overridden for a catchment you know, with `overrides`, or
a parameter held fixed with `exclude`. The rainfall factor `fc` is held
at its configured value unless an override gives it bounds. This made-up
catchment’s rain is known to be 10 per cent low, so the comparison below
unlocks it.

## The comparison

Every structure gets the same objective, starts, seed and iteration
limit. With `cores`, the structures run in parallel; here they run in
turn.

``` r
elapsed <- system.time(
  ranking <- compare_structures(project, structures, starts = 2, control = list(maxit = 30),
                                overrides = list(fc = c(0.6, 1.6)),
                                reasoning = "Which structure suits this catchment?")
)[["elapsed"]]
round(elapsed)
#> [1] 48
ranking[, .(rank, structure, parameters, calibration = round(calibration, 4),
            validation = round(validation, 4), change = round(change, 4), starts_agree)]
#>     rank               structure parameters calibration validation  change
#>    <int>                  <char>      <int>       <num>      <num>   <num>
#> 1:     1               lognormal          7      0.9962     0.9952 -0.0010
#> 2:     2                   split          7      0.9861     0.9942  0.0082
#> 3:     3                standard          7      0.9958     0.9895 -0.0062
#> 4:     4 exponential_groundwater          8      0.9957     0.9879 -0.0078
#> 5:     5             rectangular          6      0.9950     0.9844 -0.0107
#> 6:     6             exponential          6      0.9916     0.9795 -0.0121
#> 7:     7                  demand          9      0.9445     0.9276 -0.0169
#> 8:     8              triangular          6      0.9198     0.8929 -0.0270
#>    starts_agree
#>          <lgcl>
#> 1:        FALSE
#> 2:         TRUE
#> 3:         TRUE
#> 4:        FALSE
#> 5:        FALSE
#> 6:        FALSE
#> 7:        FALSE
#> 8:        FALSE
```

``` r
k <- nrow(ranking)
par(mar = c(4, 12, 0.6, 0.6))
plot(NA, xlim = range(c(ranking$calibration, ranking$validation)), ylim = c(0.5, k + 0.5),
     yaxt = "n", xlab = "NSE", ylab = "")
axis(2, at = k:1, labels = ranking$structure, las = 1, cex.axis = 0.85)
segments(ranking$calibration, k:1, ranking$validation, k:1, col = pal[7])
points(ranking$calibration, k:1, pch = 1, col = pal[1], cex = 1.3)
points(ranking$validation, k:1, pch = 16, col = pal[1], cex = 1.3)
```

![Calibration (open) and validation (filled) NSE for each structure,
best on validation at the
top.](choosing-structure_files/figure-html/plot-1.png)

Calibration (open) and validation (filled) NSE for each structure, best
on validation at the top.

## Reading the ranking

The true structure, `lognormal`, ranks first. It would be wrong to
conclude much from that alone: 2 structures lie within 0.005 NSE of the
top on validation, a spread of 9.7^{-4}. A difference that small is a
tie, not a result; another seed or another few weeks of data could
reorder them.

At the other end, `demand` and `triangular` trail the top by more than
0.05 NSE on validation. A gap that size is a conclusion the data do
support: on this catchment, those structures should not be chosen.

Three things to read in any comparison:

- **The spread at the top.** Differences smaller than the noise between
  starts or between years are ties. Longer records, including a dry
  summer, separate soil stores; a few weeks cannot.
- **The change from calibration to validation.** A structure that gains
  in calibration and loses in validation is fitting noise with its extra
  parameters.
- **Whether the starts agreed.** Where they did not, as for lognormal,
  exponential_groundwater, rectangular, exponential, demand, triangular,
  the structure may have been under-calibrated; give it more starts or
  iterations before ruling it out.

Faced with a tie, prefer the simplest structure, the one with fewest
parameters, among those within a stated margin of the best. Stating the
margin in advance keeps the choice honest.

``` r
margin <- 0.005
tied <- ranking[validation >= ranking$validation[1] - margin]
choice <- tied[order(parameters, rank)][1]
choice[, .(structure, parameters, validation = round(validation, 4), calibration_entry)]
#>    structure parameters validation calibration_entry
#>       <char>      <int>      <num>            <char>
#> 1: lognormal          7     0.9952              0012
```

## Validation and the final test

The chosen calibration becomes the candidate, is validated, and then,
with structure and parameters fixed, is tested once on the window nobody
has looked at.

``` r
propose_candidate(project, entry = choice$calibration_entry,
                  reasoning = paste("Simplest structure within", margin,
                                    "NSE of the best on validation."))
validate_candidate(project, "Validation as in the comparison.")
final <- test_candidate(project, "Final check on held-back data.")
round(c(calibration = final$calibration_scores$nse,
        validation = final$validation_scores$nse, test = final$test_scores$nse), 4)
#> calibration  validation        test 
#>      0.9962      0.9952      0.9939
```

The test score is the honest estimate of how the chosen model will do on
new data, because nothing was chosen with it. A Steward cannot sign off
a project with a test window until the test has been run, and sees all
three scores side by side in the report.

## Cross-validation

With a short record, one validation window is a thin basis for a
ranking. `cross_validate = TRUE` also calibrates each structure on the
validation window and scores it on the calibration window, and ranks on
the mean of the two held-out scores. It doubles the cost.

``` r
compare_structures(project, structures, starts = 4, cross_validate = TRUE, cores = 8,
                   reasoning = "Short record: rank on both held-out windows.")
```

## In the app and at scale

The app’s **Structures** tab runs the same comparison: tick the
structures, set the starts and cores, and press the button. Every
comparison is logged,
[`structure_comparison()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md)
rebuilds its ranking from the log at any time, and the report includes
it.

Across many catchments, the question becomes which structure wins most
often, and by how much. Combine this article with [Calibrating many
catchments](https://jonpayneea.github.io/PDMS7/articles/many-catchments.md):

``` r
winners <- vapply(folders, function(f) {
  r <- compare_structures(f, structures, starts = 10, cores = 8, reasoning = "Benchmark")
  r$structure[1]
}, character(1))
table(winners)
```
