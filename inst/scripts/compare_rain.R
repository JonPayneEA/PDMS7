# ============================================================ #
# Tool:         compare_rain
# Description:  Which rain series best explains a river's flow, judged from the data alone,
#               before any model: the water balance, the double-mass curve, how closely the
#               river's quick response follows each series, and storms each series missed
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-24
# Tier:         1
# Inputs:       CSV files: flow (m3/s), potential evaporation and each rain series (mm per
#               step), each a date-time column and a value column
# Outputs:      A folder: summary.md, rain_ranking.csv and plots, each with a note on how to
#               read it
# Dependencies: pdmS7 (0.40.0 or later)
# ============================================================ #
#
# How to use it
#   1. Copy the script to your own folder, so you can fill in its settings:
#        file.copy(system.file("scripts", "compare_rain.R", package = "pdmS7"), "compare_rain.R")
#        file.edit("compare_rain.R")
#   2. Fill in the settings below: the catchment area, the time step, and the files.
#   3. Run the whole script (Ctrl+Shift+S in RStudio). It takes a minute or two.
#   4. Read summary.md in the output folder.
#
# What it does
#   Every rain series is set against the same flow, five ways. None needs a model, so the
#   comparison is not coloured by how well a model can make up for poor rain.
#     1. Gaps: how much of the record each series is missing.
#     2. Water balance: the runoff ratio (flow / rain) and the losses against potential
#        evaporation. A series that gives more flow than rain, or losses evaporation cannot
#        explain, has the wrong total.
#     3. Double-mass: each series' cumulative rain against the others'. A series whose curve
#        bends changed part way through (a gauge moved, replaced or failing).
#     4. Quick response: how closely the rise in river flow follows each series, and at what
#        lag. The series the river answers to best catches the storms that matter for floods.
#     5. Flood by flood: on one common set of floods, how often each series had less rain
#        than the flood's quick flow (a storm it missed), and how steady each series' flood
#        runoff ratios are. Good rain gives steady ratios; poor rain makes them jump about.
#   The ranking at the end puts the evidence together. It is a guide, not a verdict: read
#   the reasons, and look at the plots.

library(pdmS7)
library(data.table)

# ---- Settings: fill these in -------------------------------------------------------------

area_km2 <- NA            # catchment area, km2: fill in, such as 52.3
step_hours <- 0.25        # time step: 0.25 for 15-minute data, 1 for hourly
data_folder <- "data"     # where the files below are, relative to the working directory
output_folder <- "rain_comparison"

flow_file <- "flow.csv"   # river flow, m3/s
pet_file <- "pet.csv"     # potential evaporation, mm per step

# Every rain series to compare, each with a short name. Catchment averages and single gauges
# alike; add or remove lines as needed.
rain_files <- c(
  thiessen = "rain_thiessen.csv",
  multiquadric = "rain_multiquadric.csv",
  gauge_A = "gauge_a.csv",
  gauge_B = "gauge_b.csv",
  gauge_C = "gauge_c.csv"
)

# ---- Read and line up the data ------------------------------------------------------------

say <- function(...) cat(sprintf(...), "\n", sep = "")
if (!is.numeric(area_km2) || !is.finite(area_km2) || area_km2 <= 0) {
  stop("Fill in area_km2 at the top of the script: the catchment area in km2.", call. = FALSE)
}
if (!dir.exists(data_folder)) {
  stop("No folder ", normalizePath(data_folder, mustWork = FALSE), ": set data_folder at the ",
       "top of the script to the folder holding the CSV files.", call. = FALSE)
}
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)
here <- function(f) file.path(data_folder, f)
say("Reading %d rain series, the flow and the evaporation", length(rain_files))
raw <- c(list(flow = read_hydro_series(here(flow_file)), pe = read_hydro_series(here(pet_file))),
         lapply(rain_files, function(f) read_hydro_series(here(f))))
grid <- do.call(align_series, c(raw, list(dt = step_hours)))
flow <- convert_units(grid$flow, "auto", step_hours, "flow")
pe <- fill_gaps(convert_units(grid$pe, "mm_per_step", step_hours, "pet"), "interpolate",
                grid$time, "pe")
names_r <- names(rain_files)
rains <- lapply(names_r, function(n) convert_units(grid[[n]], "mm_per_step", step_hours, "rain"))
names(rains) <- names_r
years <- as.numeric(difftime(max(grid$time), min(grid$time), units = "days")) / 365.25
colours <- grDevices::hcl.colors(max(3L, length(names_r)), "Dark 3")[seq_along(names_r)]
png_of <- function(name, draw, width = 1600, height = 900) {
  grDevices::png(file.path(output_folder, name), width = width, height = height, res = 150)
  on.exit(grDevices::dev.off())
  draw()
}

# Steps where every series has a value: each comparison uses the same steps, so a series is
# not judged on a different stretch of the record from the others.
common <- Reduce(`&`, lapply(rains, is.finite)) & is.finite(flow)
say("%.1f years of data; %.0f%% of steps have every series and the flow", years,
    100 * mean(common))

# ---- 1. Gaps ------------------------------------------------------------------------------

missing_pct <- vapply(rains, function(r) 100 * mean(!is.finite(r)), numeric(1))

# ---- 2. Water balance ---------------------------------------------------------------------

say("Water balance")
# Gaps are set to zero only for the balance, on the common steps; elsewhere the flow is set
# missing, so no series gains or loses rain from another's gaps.
balance_of <- function(r) {
  rr <- ifelse(common, r, 0)
  q <- ifelse(common, flow, NA_real_)
  water_balance(data.frame(time = grid$time, rain = rr, pet = pe), q, area_km2)
}
balances <- lapply(rains, balance_of)
balance <- data.frame(
  rain = names_r,
  rain_mm_per_year = round(vapply(balances, function(b) b$record$rain_mm, 0) /
                             (sum(common) * step_hours / 8766)),
  runoff_ratio = round(vapply(balances, function(b) b$record$runoff_ratio, 0), 3),
  loss_over_pet = round(vapply(balances, function(b) b$record$loss_over_pet, 0), 3),
  flagged_years = vapply(balances, function(b) sum(nzchar(b$years$flags) &
                                                     b$years$flags != "incomplete"), 0L))
# A balance is implausible when the flow exceeds the rain (runoff ratio above 1) or the losses
# exceed what evaporation can take (loss over potential evaporation above 1). Distance beyond
# either limit counts against a series.
balance$balance_problem <- round(pmax(balance$runoff_ratio - 1, 0) +
                                   pmax(balance$loss_over_pet - 1, 0), 3)

# HOW TO READ rain_by_year.png
# One group of bars per water year (October to September), one bar per rain series: the rain
# each series gives the catchment that year.
# Good: the series agree within a few per cent every year, or differ by the same amount every
#   year (a steady difference is a matter of scale, which the water balance then judges).
# Worry if: one series drops or jumps in some years only. A gauge failed, moved or was
#   replaced then; check its record for those years.
png_of("rain_by_year.png", function() {
  periods <- balances[[1]]$years$period
  totals <- vapply(balances, function(b) b$years$rain_mm, numeric(length(periods)))
  if (is.null(dim(totals))) totals <- matrix(totals, nrow = 1)
  graphics::par(mar = c(5, 4.5, 2, 1))
  graphics::barplot(t(totals), beside = TRUE, names.arg = periods, col = colours, border = NA,
                    las = 2, ylab = "Rain (mm)", main = "Rain by water year, each series",
                    ylim = c(0, 1.3 * max(totals, na.rm = TRUE)), legend.text = names_r,
                    args.legend = list(bty = "n", x = "top", ncol = min(5, length(names_r))))
})

# HOW TO READ runoff_ratio_by_series.png
# The runoff ratio (flow / rain) year by year, one line per series, with a red line at 1.
# Good: a level line well below 1. Typical ratios: 0.3 to 0.5 in the lowlands, 0.6 to 0.9 in
#   wet uplands, lower on chalk.
# Worry if: a line crosses 1 (that series gives less rain than flowed out: it under-catches,
#   or misses storms); a line steps up or down part way (that series changed); the lines
#   cross each other, swapping order (the series disagree in different years in different
#   ways, so no one scaling fixes them).
png_of("runoff_ratio_by_series.png", function() {
  periods <- balances[[1]]$years$period
  ratio <- vapply(balances, function(b) b$years$runoff_ratio, numeric(length(periods)))
  if (is.null(dim(ratio))) ratio <- matrix(ratio, nrow = 1)
  graphics::par(mar = c(5, 4.5, 2, 1))
  graphics::matplot(seq_along(periods), ratio, type = "b", pch = 19, lty = 1, lwd = 2,
                    col = colours, xaxt = "n", xlab = "", ylab = "Runoff ratio (flow / rain)",
                    ylim = c(0, 1.3 * max(1.1, max(ratio, na.rm = TRUE))),
                    main = "Runoff ratio by water year, each series")
  graphics::axis(1, at = seq_along(periods), labels = periods, las = 2)
  graphics::abline(h = 1, col = "#B3261E")
  graphics::legend("top", names_r, col = colours, lwd = 2, pch = 19, bty = "n",
                   ncol = min(5, length(names_r)))
})

# ---- 3. Double-mass ------------------------------------------------------------------------

say("Double-mass curves")
# Each series against the others: cumulative rain of the series against cumulative rain of
# the median of all the series, step by step, both as shares of their totals. Wet and dry
# spells fall on every series alike and cancel; what is left is a change in one series. The
# bend is the largest gap between its curve and the diagonal, in per cent.
reference <- apply(as.data.frame(rains), 1, stats::median)
cum_share <- function(x) {
  x <- ifelse(common, x, 0)
  cumsum(x) / sum(x)
}
ref_share <- cum_share(reference)
cumulative <- lapply(rains, function(r) data.frame(reference = ref_share, rain = cum_share(r)))
bend_pct <- vapply(cumulative, function(d) round(100 * max(abs(d$rain - d$reference)), 1), 0)

# HOW TO READ double_mass_by_series.png
# Each series' cumulative rain against the cumulative rain of the median of all the series,
# both as shares of their totals, one line per series. The dashed diagonal is a series that
# keeps step with the others throughout.
# Good: every line on the diagonal. The weather falls on every gauge alike, so it cancels out
#   here: only a change in one series shows.
# Worry if: a line bends away and keeps the new slope. That series changed at the bend: a
#   gauge moved, replaced, overgrown, or its logger failing. The bend's size is in the legend;
#   a few per cent or more deserves a look at that series' record around the bend.
png_of("double_mass_by_series.png", function() {
  graphics::par(mar = c(4.5, 4.5, 2, 1))
  graphics::plot(c(0, 1), c(0, 1), type = "n",
                 xlab = "Cumulative rain of the median series (share of total)",
                 ylab = "Cumulative rain of each series (share of total)",
                 main = "Double-mass curves, each series against the others")
  graphics::abline(0, 1, lty = 2, col = "grey50")
  for (i in seq_along(cumulative)) {
    d <- cumulative[[i]]
    k <- unique(round(seq(1, nrow(d), length.out = 2000)))
    graphics::lines(d$reference[k], d$rain[k], col = colours[i], lwd = 2)
  }
  graphics::legend("topleft", sprintf("%s (bend %.1f%%)", names_r, bend_pct), col = colours,
                   lwd = 2, bty = "n")
})

# ---- 4. Quick response ---------------------------------------------------------------------

say("How closely the river follows each series")
response <- gauge_response(as.data.frame(rains), flow, grid$time, dt = step_hours,
                           area_km2 = area_km2)
fwrite(response$summary, file.path(output_folder, "quick_response.csv"))

# HOW TO READ quick_response.png
# One line per rain series: how closely the rise in river flow follows that series' rain
# (correlation, up) at each lag (across, hours after the rain). The peak of each line is the
# series' best lag. quick_response.csv adds, flood by flood, which series explained the rise
# best (event_wins), whether a series sees the big storms as big (size_r), and how often it
# saw almost no rain when the others saw a storm (dry_events).
# Good: one series peaks clearly highest and wins most floods: the river answers to it. All
#   lags positive and a few hours.
# Worry if: a series peaks at a negative lag (rain cannot follow the flow it causes: its
#   clock is wrong); one series' lag differs from the rest by a whole hour or more (a clock or
#   time-zone error); a series has several dry events (a blocked funnel or a logger down). The
#   series are correlated with each other, which blurs the differences: read the order and
#   the gaps between the lines, not the values alone.
png_of("quick_response.png", function() plot(response))

# ---- 5. Flood by flood ---------------------------------------------------------------------

say("Flood by flood")
# One common set of floods, found on the average of all the series, so no series picks its
# own. For each flood, each series' rain over the flood's rain window, against the flood's
# quick flow (the water above the baseflow, from the flow alone).
average <- rowMeans(as.data.frame(rains), na.rm = TRUE)
average[!is.finite(average)] <- 0
floods <- screen_events(find_events(average, ifelse(is.finite(flow), flow, NA_real_),
                                    grid$time, dt = step_hours, area_km2 = area_km2),
                        flow, exclude = c("small_rise", "gaps"))
floods <- floods[floods$use & is.finite(floods$quickflow_mm) & floods$quickflow_mm > 0, ]
event_rain <- vapply(rains, function(r) {
  vapply(seq_len(nrow(floods)), function(e) {
    w <- floods$rain_start[e]:floods$rain_end[e]
    if (any(!is.finite(r[w]))) NA_real_ else sum(r[w])
  }, 0)
}, numeric(nrow(floods)))
if (is.null(dim(event_rain))) event_rain <- matrix(event_rain, ncol = length(rains))
ratio <- floods$quickflow_mm / event_rain
missed <- colSums(ratio > 1 | event_rain < 0.5, na.rm = TRUE)
missed_pct <- round(100 * missed / colSums(is.finite(ratio)), 1)
# Steadiness: the spread of the log of the flood runoff ratios, over floods the series saw
# some rain for (the others count as missed storms above). Floods differ, so the ratios always
# vary; poor rain adds its own scatter on top.
seen <- ratio
seen[!is.finite(seen) | event_rain < 0.5] <- NA
spread <- round(apply(log(seen), 2, stats::sd, na.rm = TRUE), 3)
flood_table <- data.frame(rain = names_r, floods = colSums(is.finite(ratio)),
                          missed_storms = as.integer(missed), missed_pct = missed_pct,
                          ratio_spread = spread)

# HOW TO READ flood_runoff_ratios.png
# One box per rain series: the runoff ratios of the same floods (quick flow over that series'
# rain for the flood). The red line is 1: above it, the flood had more quick flow than the
# series recorded rain, so the series missed or under-caught that storm.
# Good: a narrow box well below 1, with few points above the line.
# Worry if: a box is wide (the series sees some storms well and others badly), or many
#   points sit above 1 (storms that passed the gauges by). Convective summer storms are where
#   single gauges fail most: a catchment average from several gauges usually does better.
png_of("flood_runoff_ratios.png", function() {
  graphics::par(mar = c(5, 4.5, 2, 1))
  graphics::boxplot(as.data.frame(seen), names = names_r, col = colours, log = "y", las = 2,
                    ylab = "Flood runoff ratio (quick flow / rain), log scale",
                    main = sprintf("Runoff ratios of the same %d floods, each series",
                                   nrow(floods)))
  graphics::abline(h = 1, col = "#B3261E")
})

# ---- The ranking ---------------------------------------------------------------------------

rs <- response$summary[match(names_r, response$summary$gauge), ]
ranking <- data.frame(
  rain = names_r,
  missing_pct = round(missing_pct, 2),
  rain_mm_per_year = balance$rain_mm_per_year,
  runoff_ratio = balance$runoff_ratio,
  loss_over_pet = balance$loss_over_pet,
  balance_problem = balance$balance_problem,
  flagged_years = balance$flagged_years,
  double_mass_bend_pct = bend_pct,
  response_r = round(rs$r, 3),
  lag_h = rs$lag_h,
  flood_wins = rs$event_wins,
  storm_size_r = round(rs$size_r, 3),
  dry_events = rs$dry_events,
  missed_storms_pct = flood_table$missed_pct,
  flood_ratio_spread = flood_table$ratio_spread)
# Two measures against the other series, since a catchment's true rain is never known: how
# far a series' total sits from the median of all the series, and how far its lag sits from
# their median lag. One series well apart from the rest is the likelier to be wrong; when
# most of the series are poor, read these with care.
med_total <- stats::median(ranking$rain_mm_per_year)
ranking$total_apart_pct <- round(100 * abs(ranking$rain_mm_per_year - med_total) / med_total, 1)
ranking$lag_apart_h <- abs(ranking$lag_h - stats::median(ranking$lag_h))
# Each measure ranks the series, best first; the overall rank is the mean. Higher is better
# for the response correlation, the flood wins and the storm size correlation; lower for the
# rest.
better_low <- c("missing_pct", "balance_problem", "flagged_years", "double_mass_bend_pct",
                "dry_events", "missed_storms_pct", "flood_ratio_spread", "total_apart_pct",
                "lag_apart_h")
better_high <- c("response_r", "flood_wins", "storm_size_r")
ranks <- cbind(sapply(better_low, function(m) rank(ranking[[m]], ties.method = "average")),
               sapply(better_high, function(m) rank(-ranking[[m]], ties.method = "average")))
if (is.null(dim(ranks))) ranks <- matrix(ranks, nrow = 1)
ranking$mean_rank <- round(rowMeans(ranks), 2)
ranking <- ranking[order(ranking$mean_rank), ]
fwrite(ranking, file.path(output_folder, "rain_ranking.csv"))

# Plain-English warnings for each series.
warnings_for <- function(i) {
  x <- ranking[i, ]
  c(if (x$runoff_ratio > 1) "more flow than rain: it under-catches or misses storms",
    if (x$loss_over_pet > 1) "losses beyond what evaporation can take: too much rain",
    if (x$double_mass_bend_pct > 2) sprintf("it bends %.0f%% from the other series",
                                            x$double_mass_bend_pct),
    if (x$lag_h < 0) "the river rises before its rain: check its clock",
    if (x$dry_events > 1) sprintf("%d floods it saw almost no rain for", x$dry_events),
    if (x$missed_storms_pct > 5) sprintf("%.0f%% of floods had more quick flow than its rain",
                                          x$missed_storms_pct),
    if (x$missing_pct > 5) sprintf("%.0f%% of its record is missing", x$missing_pct),
    if (x$total_apart_pct > 10) sprintf("its total is %.0f%% from the median of the series",
                                        x$total_apart_pct),
    if (x$lag_apart_h >= 1) sprintf("its lag is %g h from the others': check its clock",
                                    x$lag_apart_h))
}
lags <- stats::setNames(ranking$lag_h, ranking$rain)
best <- ranking$rain[1]
lines <- c(
  "# Which rain series best explains the flow", "",
  sprintf("%.1f years of %s data; %d rain series; %d floods compared.", years,
          if (step_hours < 1) sprintf("%g-minute", step_hours * 60) else
            sprintf("%g-hour", step_hours), length(names_r), nrow(floods)),
  "Judged from the data alone, before any model. How to read each plot: the HOW TO READ",
  "notes in compare_rain.R, beside the line that draws it.", "",
  sprintf("**Best by the data: %s.** The ranking, best first (mean rank over twelve",
          best), "measures):", "",
  sprintf(paste("%d. **%s** (mean rank %.1f): runoff ratio %.2f, quick-response correlation",
                "%.2f, first for %d of %d floods."), seq_len(nrow(ranking)), ranking$rain,
          ranking$mean_rank, ranking$runoff_ratio, ranking$response_r, ranking$flood_wins,
          sum(response$summary$event_wins)),
  "", "## Warnings", "",
  unlist(lapply(seq_len(nrow(ranking)), function(i) {
    w <- warnings_for(i)
    sprintf("- %s: %s.", ranking$rain[i], if (length(w)) paste(w, collapse = "; ") else
      "none")
  })),
  if (diff(range(lags)) >= 1) {
    c("", sprintf(paste("The river answers to the series at lags from %g to %g hours. Series",
                        "a whole hour or more apart often mean a clock or time-zone error in",
                        "one."), min(lags), max(lags)))
  },
  "", "## What next", "",
  "- The ranking is a guide. A series that ranks well but carries a warning may still be the",
  "  best choice once the fault is fixed (a clock corrected, a gap filled).",
  "- A catchment average from several gauges usually beats any single gauge for floods,",
  "  because storms miss single gauges. If a single gauge ranks first, ask why: it may sit",
  "  where the storms that drive floods fall, or the averages may be built on poor gauges.",
  "- Next, calibrate the PDM on the best two or three and compare their validation scores:",
  "  calibrate_site.R with each as the first rain series, into separate output folders.",
  "", "Tables: `rain_ranking.csv`, `quick_response.csv`. Plots: `rain_by_year.png`,",
  "`runoff_ratio_by_series.png`, `double_mass_by_series.png`, `quick_response.png`,",
  "`flood_runoff_ratios.png`.")
writeLines(lines, file.path(output_folder, "summary.md"))
print(ranking[, c("rain", "mean_rank", "runoff_ratio", "total_apart_pct", "response_r",
                  "lag_h", "flood_wins", "missed_storms_pct", "flood_ratio_spread")],
      row.names = FALSE)
say("\nWritten to %s. Read summary.md.", normalizePath(output_folder))
