# Larger floods: extrapolation and the rating

A model calibrated on a river’s record is fitted to the floods in that
record. It is used for the floods that are not: the ones that matter
most. A calibration can score well on every window and still go wrong
once flows pass anything it was fitted to. Three things cause most of
the trouble.

- **Large floods are rare.** The parameters that control them, chiefly
  the soil store’s capacity and the fast routing, are barely tested by
  the record. Many settings fit it equally well and then disagree above
  it.
- **The optimiser uses every freedom it has.** A store that only fills
  in a big flood costs nothing to get wrong if no big flood occurs
  during calibration, so its fitted value is close to arbitrary.
- **The largest observed flows are themselves extrapolated.** Above the
  highest flow ever gauged, the rating curve is a line drawn beyond its
  data. The size of those flows is uncertain, even though their order is
  not.

No calibration method removes these. pdmS7 makes them visible, in the
record, before anyone signs off.

## What pdmS7 does

| Check                           | How                                                                                                                                                                                                          | When                                               |
|---------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------|
| **Wettest years held back**     | The two wettest water years (October to September) in the calibration and validation windows, ranked by their highest flow, are left out of every calibration, trial and validation score.                   | Chosen at registration; scored once, with the test |
| **Spread of equally good fits** | Each automatic calibration keeps the parameter sets it tried that score within a tolerance of its best (0.02 NSE by default), up to 50 spread-out sets. The test runs every one through the held-back years. | Kept at calibration; reported at the test          |
| **Rating flag**                 | Given the highest gauged flow, registration counts the flows above it in each window, and the test marks each held-back peak that lies above it.                                                             | Recorded at registration and test                  |

Holding back the largest floods is the differential split-sample test of
Klemeš (1986): fit on one kind of conditions, test on another. Ranking
years by their highest flow survives rating error, because a rating
rises with stage: it may get a flood’s size wrong, but not whether it
was bigger than another. The rating flag does not change the fit. It
tells the reviewer where the observed numbers deserve less trust.

## The example

Ten water years of daily data from a made-up 60 km2 catchment. Two
storms, in 2013-14 and 2018-19, are far larger than anything else in the
record. The model’s soil store holds up to 250 mm, and only those two
storms come close to filling it. The observations carry 5 per cent
noise.

``` r
set.seed(21)
n <- 365 * 10
time <- seq(as.POSIXct("2010-10-01", tz = "UTC"), by = 86400, length.out = n)
rain <- ifelse(runif(n) < 0.45, rgamma(n, 0.7, scale = 7), 0)
rain[c(1200, 1201, 2950, 2951, 2952)] <- c(70, 55, 60, 75, 40)
forcing <- data.frame(time = format(time, "%Y-%m-%dT%H:%M:%SZ"), rain = rain,
                      pet = 1.2 + sin(2 * pi * (seq_len(n) - 100) / 365))
truth <- pdm_presets("standard")
truth$dt <- 24
truth$area_km2 <- 60
truth$distribution$cmax <- 250
truth$surface$k1 <- 30
truth$fc <- 1.05
model <- pdm_from_config(truth)
observed <- run_pdm(model, forcing[, -1], initial_state_from_flow(model, 1.5, 0.7))$output$q_m3s *
  exp(rnorm(n, 0, 0.05))
years <- wettest_years(time, observed, n = 2)
years[, c("water_year", "start", "peak_m3s", "held")]
#>    water_year                start peak_m3s  held
#> 1     2018-19 2018-10-01T00:00:00Z 54.42164  TRUE
#> 2     2013-14 2013-10-01T00:00:00Z 44.29610  TRUE
#> 3     2019-20 2019-10-01T00:00:00Z 16.11405 FALSE
#> 4     2016-17 2016-10-01T00:00:00Z 15.46620 FALSE
#> 5     2015-16 2015-10-01T00:00:00Z 13.87150 FALSE
#> 6     2010-11 2010-10-01T00:00:00Z 12.38833 FALSE
#> 7     2011-12 2011-10-01T00:00:00Z 11.23948 FALSE
#> 8     2014-15 2014-10-01T00:00:00Z 10.96564 FALSE
#> 9     2012-13 2012-10-01T00:00:00Z 10.94225 FALSE
#> 10    2017-18 2017-10-01T00:00:00Z 10.73377 FALSE
```

[`wettest_years()`](https://jonpayneea.github.io/PDMS7/reference/wettest_years.md)
is what
[`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
uses. The two held-back years have peaks of 54 and 44 m3/s; no other
year exceeds 16.

## Registering the data

Suppose the station’s highest check gauging is 30 m3/s. Everything above
that comes from an extended rating.

``` r
project <- file.path(tempdir(), "wet-brook")
unlink(project, recursive = TRUE)
start_calibration_project(project, catchment = "Wet Brook", gauge = "00001",
                          purpose = "Flood forecasting", area_km2 = 60,
                          owner = "Area Manager", steward = "Sam Steward")
#> INFO [2026-11-02 19:30:56] Started calibration project wet-brook in /tmp/RtmpxtPzir/wet-brook
reg <- register_data(project, forcing, observed,
                     calibration = c("2011-01-01", "2016-09-30"),
                     validation = c("2016-10-01", "2019-09-30"),
                     test = c("2019-10-01", "2020-09-27"),
                     highest_gauged_m3s = 30,
                     reasoning = "Ten years; rating checked to 30 m3/s.")
#> INFO [2026-11-02 19:30:56] Registered data 0002: 3650 rows
check <- reg$rating_check$windows
data.frame(window = names(check), steps_above = sapply(check, `[[`, "steps_above"),
           highest_m3s = round(sapply(check, `[[`, "highest_m3s"), 1))
#>                  window steps_above highest_m3s
#> calibration calibration           0        13.9
#> validation   validation           0        15.5
#> test               test           0        16.1
#> wettest         wettest           4        54.4
```

The rating check, recorded in the entry, shows the problem at once.
Every flow above the gauged limit lies in the held-back years. The
highest flow left for calibration and validation is 15.5 m3/s, about
half the limit. Without the hold-out, the calibration would have been
fitted to 4 days of extrapolated flow, and nothing in the record would
have said so.

## Calibrating

An ordinary automatic calibration of every parameter, from the standard
starting point.

``` r
start <- pdm_presets("standard")
start$dt <- 24
start$area_km2 <- 60
select_structure(project, start, "Standard structure.")
#> INFO [2026-11-02 19:30:56] Structure 0003: nse 0.9846
b <- calibration_bounds(start)
fit <- log_auto_calibration(
  project, parent = 3, lower = setNames(b$lower, b$path), upper = setNames(b$upper, b$path),
  log_scale = b$path[b$scale == "log"], starts = 3, seed = 2, control = list(maxit = 40),
  reasoning = "All parameters, three starts."
)
#> INFO [2026-11-02 19:31:38] Calibration 0004: nse 0.9953
good <- fit$equally_good
c(nse = fit$scores$nse, trials_within_tolerance = good$within, sets_kept = length(good$sets))
#>                     nse trials_within_tolerance               sets_kept 
#>               0.9953297            2220.0000000              50.0000000
```

The calibration NSE is 0.995. Of the parameter sets the search tried,
2220 scored within 0.02 of the best; 50 spread-out ones are kept. How
far apart are they?

``` r
sets <- do.call(rbind, lapply(good$sets, function(s) unlist(s$parameters)))
spread <- t(apply(sets, 2, range))
data.frame(truth = sapply(colnames(sets), function(p) pdmS7:::.path_get(truth, p)),
           lowest = signif(spread[, 1], 3), highest = signif(spread[, 2], 3))
#>                      truth  lowest  highest
#> fc                    1.05   0.997     1.07
#> distribution.cmax   250.00 139.000   635.00
#> distribution.b        0.40   0.132     1.18
#> recharge.kg          24.00  19.400    39.10
#> surface.k1           30.00   1.680    53.90
#> surface.k2            4.00   4.000    53.60
#> groundwater.kb    10000.00 582.000 12300.00
```

The soil capacity `cmax` spans 139 to 635 mm among fits that all
reproduce the calibration record almost equally well. The record cannot
tell them apart, because in those years the soil never comes near full.
This is the arbitrary parameter the introduction warned of, and it is
exactly the one a large flood depends on.

## The test

Validation and the test follow the usual rules. The test also reveals
the held-back years.

``` r
propose_candidate(project, fit$id, "Best automatic fit.")
validation <- validate_candidate(project, "Validation holds up.")
#> INFO [2026-11-02 19:31:38] Validation 0006: nse 0.9951
test <- test_candidate(project, "Final check, including the wettest years.")
#> INFO [2026-11-02 19:31:40] Test 0007: nse 0.9959
#> INFO [2026-11-02 19:31:40] Wettest years 0007: nse 0.9974
c(validation = validation$validation_scores$nse, test_window = test$test_scores$nse,
  wettest_years = test$wettest$scores$nse)
#>    validation   test_window wettest_years 
#>     0.9950786     0.9959219     0.9974215
peaks <- do.call(rbind, lapply(test$wettest$years, as.data.frame))
peaks[, -1] <- lapply(peaks[, -1], function(x) if (is.numeric(x)) round(x, 1) else x)
peaks
#>   water_year observed_peak_m3s simulated_peak_m3s spread_low_m3s
#> 1    2018-19              54.4               52.5           41.1
#> 2    2013-14              44.3               41.9           35.0
#>   spread_high_m3s above_gauged
#> 1              53         TRUE
#> 2              42         TRUE
```

Every score looks fine, including over the wettest years, where NSE is
dominated by the many ordinary days. The peaks tell the real story.

- The candidate’s peaks are 3 and 5 per cent low.
- The equally good sets span 22 and 16 per cent of the observed peak.
- In both years the observed peak lies above every one of them. The
  range shows how far fits the record cannot tell apart disagree. It is
  not a confidence interval, and the truth can lie outside it.
- Both observed peaks lie above the highest gauging, so on a real river
  even the “observed” values would be uncertain.

``` r
y <- reg$scorecard$wettest$years[[1]]
peak <- y$first_row - 1 + which.max(observed[y$first_row:y$last_row])
rows <- (peak - 15):(peak + 45)
simulate <- function(parameters) {
  cfg <- fit$configuration
  for (p in names(parameters)) cfg <- pdmS7:::.path_set(cfg, p, parameters[[p]])
  m <- pdm_from_config(cfg)
  run_pdm(m, forcing[, -1], initial_state_from_flow(m, observed[1], 0.7))$output$q_m3s[rows]
}
ensemble <- sapply(good$sets, function(s) simulate(s$parameters))
candidate <- simulate(list())
plot(time[rows], observed[rows], type = "n", ylim = c(0, max(ensemble, observed[rows]) * 1.05),
     xlab = "", ylab = "Flow (m3/s)", main = paste("Largest flood, water year", y$water_year))
polygon(c(time[rows], rev(time[rows])), c(apply(ensemble, 1, min), rev(apply(ensemble, 1, max))),
        col = adjustcolor(pal[2], 0.25), border = NA)
abline(h = 30, lty = 2, col = pal[7])
lines(time[rows], candidate, col = pal[2], lwd = 2)
points(time[rows], observed[rows], pch = 16, cex = 0.5, col = pal[1])
legend("topright", c("observed", "candidate", "equally good sets", "highest gauging"),
       col = c(pal[1], pal[2], adjustcolor(pal[2], 0.4), pal[7]), pch = c(16, NA, 15, NA),
       lty = c(NA, 1, NA, 2), lwd = c(NA, 2, NA, 1), bty = "n")
```

![](extrapolation_files/figure-html/hydrograph-1.png)

## Reading the result

The scores answer “does the model reproduce this river?”. The held-back
peaks answer the question a forecaster asks: “would it have got the big
one right?”. Read the table in three parts.

- **The candidate against the observed peak.** A large miss on floods
  the model never saw is the plainest sign that the calibration does not
  extrapolate.
- **The width of the range.** A wide range means the record cannot pin
  down the parameters that control large floods. The candidate’s own
  peak is then partly luck, good or bad.
- **The rating flag.** Where the observed peak lies above the highest
  gauging, a miss may be the rating’s error rather than the model’s.
  Treat both as uncertain.

When the range is wide, more calibration effort will not help. The
remedies change what the calibration knows: fix the poorly constrained
parameter from independent evidence (soil data for `cmax`, say), choose
a simpler structure that extrapolates predictably (see [Choosing a model
structure](https://jonpayneea.github.io/PDMS7/articles/choosing-structure.md)),
or extend the rating with new gaugings. Record the decision, with its
reasons, in a note before sign-off.

## Settings

| Argument of [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md) | Default | Meaning                                                                                                   |
|--------------------------------------------------------------------------------------------------|---------|-----------------------------------------------------------------------------------------------------------|
| `wettest_years`                                                                                  | 2       | Years held back. Needs a `time` column and enough record to leave three years. 0 holds none back.         |
| `highest_gauged_m3s`                                                                             | none    | The top of the reliable rating. Flows above it are flagged, never changed.                                |
| `tie_tolerance`                                                                                  | 0.02    | How close to the best calibration score, in the headline’s units, a set must be to count as equally good. |

The test needs both the held-back years and a logged automatic
calibration to report a range. A manual trial, or a fit from a structure
comparison, keeps no record of the alternatives, so its range is the
candidate alone, and the report says so. Projects registered before
version 0.5.0 hold nothing back.

## Reference

Klemeš, V. (1986) Operational testing of hydrological simulation models.
*Hydrological Sciences Journal* 31(1), 13-24.
