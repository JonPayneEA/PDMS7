# ============================================================ #
# Tool:         calibrate_site
# Description:  A starter for calibrating one site from a YAML settings file, for someone new
#               to R and the PDM: checks the data, the water balance and the events, calibrates
#               with the protocol settled on CAMELS-GB, draws the diagnostic plots, tests how
#               errors in the rain and evaporation carry into the flow, and writes a summary
#               in plain English
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-24
# Modified:     2026-11-24 - First version; warnings, lead time, annual maxima, seasons,
#               recessions, gauge response, regional context, storm-by-storm rain errors and
#               parameter uncertainty
# Tier:         1
# Inputs:       A settings file like inst/examples/site.yml, and the CSV files it names
# Outputs:      An output folder: summary.md, then 1_data, 2_water_balance, 3_events,
#               4_calibration (the calibration project and its report), 5_diagnostics and
#               6_input_uncertainty, each with plots (PNG) and tables (CSV)
# Dependencies: pdmS7 (0.39.0 or later); data.table; yaml
# ============================================================ #
#
# How to run it
#   1. Set up a folder, put the CSV files in its data folder, and fill in section 1 of its
#      site.yml:
#        library(pdmS7)
#        new_site("My_River")
#      To practise first on made-up data, ready to run: new_site("Practice", practice = TRUE)
#   2. Load the settings into R, look at them, and run this script:
#        settings <- read_site_settings("My_River/site.yml")
#        settings
#        source(system.file("scripts", "calibrate_site.R", package = "pdmS7"))
#      Change a setting in R as in the file, such as settings$effort <- "quick", and run the
#      script again. Without a settings object it asks for the file; from a terminal:
#        Rscript calibrate_site.R my_site.yml
#   3. Read summary.md in the output folder. It says what each result means and what to do.
#      The results stay in the R session too: wb, events, model, checks, series, scenarios.
#   4. how_to_read_the_plots.md in the output folder says, for each plot drawn, what it
#      shows, what good looks like and what should worry you. The same notes sit beside the
#      lines that draw the plots below: search for "HOW TO READ" and the plot's file name.
#
# The steps
#   1. Data       read, line up and check the series; count gaps
#   2. Water      the water balance year by year: runoff ratios, losses against evaporation,
#      balance    the Budyko plot and the double-mass curve. This is the first check on the
#                 rain: a runoff ratio above 1 means more flow than rain
#   3. Events     each flood's quick flow against its rain; storms the gauges missed; how the
#                 river drains in dry weather (recessions); with single gauges, which one the
#                 river answers to
#   (the first run stops here: read the summary, then set stop_after_checks: false)
#   4. Calibrate  the structure chosen on the record, then a staged search: water balance and
#                 slow stores first, then the fast response, a polish that weighs high and low
#                 flows fairly, and the largest floods
#   5. Diagnose   hydrographs, flow duration, residuals, parameters against their limits, the
#                 largest floods' peaks and timing, and, with effort standard or thorough,
#                 which parameters the record determines and how well the model forecasts.
#                 Then floods and warnings: hits, misses and false alarms at warning
#                 thresholds, the notice a forecast gives, annual maxima against the highest
#                 gauged flow, the seasons, the model's recessions against the river's, and,
#                 with the CAMELS-GB bulk results, the site among similar catchments
#   6. Input      how far the flow moves when the rain or the evaporation is 10% out; a band
#      uncertainty of flows from storm-by-storm rain errors; with effort thorough, a band from
#                 parameter uncertainty (Bayesian); with several rain files, how much they
#                 disagree

suppressPackageStartupMessages({
  library(pdmS7)
  library(data.table)
})
stopifnot(utils::packageVersion("pdmS7") >= "0.39.0")
`%||%` <- function(x, y) if (is.null(x)) y else x
say <- function(...) cat(sprintf(...), "\n", sep = "")
listed <- function(x) if (length(x)) paste(x, collapse = ", ") else "none"

# ---- Settings ---------------------------------------------------------------------------

# Settings already in the session, from settings <- read_site_settings("my_site.yml"), are
# used, checked again in case they were changed. Otherwise the file named on the command
# line, or in PDM_SITE_CONFIG, or chosen when asked.
if (exists("settings", inherits = FALSE) && inherits(settings, "pdm_site_settings")) {
  settings <- read_site_settings(settings)
} else {
  args <- commandArgs(trailingOnly = TRUE)
  settings_file <- if (length(args)) args[1] else Sys.getenv("PDM_SITE_CONFIG")
  if (!nzchar(settings_file) && interactive()) settings_file <- file.choose()
  if (!nzchar(settings_file) || !file.exists(settings_file)) {
    stop("No settings. Set up a folder with new_site(\"My_River\"), put the data in it and ",
         "fill in its site.yml, then settings <- read_site_settings(\"My_River/site.yml\") ",
         "and run this again. To practise first: new_site(\"Practice\", practice = TRUE).",
         call. = FALSE)
  }
  settings <- read_site_settings(settings_file)
}
s <- settings
site <- list(name = s$name, gauge = s$gauge)
area <- s$area_km2
dt <- s$step_hours
rain_files <- s$rain
calibration <- s$calibration
validation <- s$validation
effort <- s$effort
plan <- list(
  quick = list(starts = 2L, budget = 150L, recommend = TRUE, sensitivity = FALSE,
               forecast = FALSE, stress = FALSE, members = 50L, bayes = FALSE),
  standard = list(starts = 3L, budget = 300L, recommend = TRUE, sensitivity = TRUE,
                  forecast = TRUE, stress = FALSE, members = 100L, bayes = FALSE),
  thorough = list(starts = 4L, budget = 600L, recommend = TRUE, sensitivity = TRUE,
                  forecast = TRUE, stress = TRUE, members = 200L, bayes = TRUE)
)[[effort]]
overrides <- if (!is.null(s$rainfall_factor)) list(fc = s$rainfall_factor)
options(pdmS7.user = Sys.getenv("USERNAME", Sys.getenv("USER", "analyst")),
        pdmS7.role = "custodian")
logger::log_threshold(logger::WARN, namespace = "pdmS7")

out <- s$output
folder <- function(name) {
  p <- file.path(out, name)
  dir.create(p, recursive = TRUE, showWarnings = FALSE)
  p
}
png_of <- function(path, draw, width = 1600, height = 900) {
  grDevices::png(path, width = width, height = height, res = 150)
  on.exit(grDevices::dev.off())
  draw()
  invisible(path)
}
summary_lines <- c(sprintf("# %s: calibration summary", site$name), "",
                   sprintf("Settings: %s. Effort: %s. pdmS7 %s, %s.", basename(s$file),
                           effort, utils::packageVersion("pdmS7"), format(Sys.Date())), "")
summary_lines <- c(summary_lines,
                   paste("How to read each plot: `how_to_read_the_plots.md`, in this folder."),
                   "")
note <- function(...) summary_lines <<- c(summary_lines, unlist(list(...)))

# The reading guide: the HOW TO READ notes in this script, collected into one file for the
# plots this run drew, in step order. They are read from the installed script, so the notes
# beside the code and the guide are always the same text.
write_reading_guide <- function() {
  src <- system.file("scripts", "calibrate_site.R", package = "pdmS7")
  if (!nzchar(src)) return(invisible(NULL))
  code <- readLines(src, warn = FALSE)
  steps <- c("1_data" = "1. The data", "2_water_balance" = "2. The water balance",
             "3_events" = "3. Floods and their rain", "5_diagnostics" = "5. Diagnostics",
             "6_input_uncertainty" = "6. Input uncertainty")
  # Only the plots in the step folders themselves; the calibration report keeps its own.
  drawn <- unlist(lapply(names(steps), function(f) {
    file.path(f, list.files(file.path(out, f), "\\.png$"))
  }))
  guide <- c("# How to read the plots", "",
             sprintf("%s. Each plot this run drew, in the order of the steps: what it shows,",
                     site$name),
             "what good looks like, and what should worry you.", "")
  heading <- ""
  for (i in grep("^\\s*# HOW TO READ ", code)) {
    name <- sub("^\\s*# HOW TO READ ", "", code[i])
    where <- drawn[basename(drawn) == name]
    if (!length(where)) next
    j <- i + 1
    while (j <= length(code) && grepl("^\\s*#", code[j]) && !grepl("HOW TO READ", code[j])) {
      j <- j + 1
    }
    text <- sub("^\\s*# ?", "", code[seq.int(i + 1, j - 1)])
    # Description lines join into a paragraph; "Good:", "Worry if:" and the like each start
    # a bullet, and the indented lines after one continue it.
    items <- character(0)
    in_bullet <- FALSE
    for (line in text) {
      if (grepl("^(Good|Worry if|What it shows|Typical):", line)) {
        items <- c(items, sub("^([^:]+):", "- **\\1:**", line))
        in_bullet <- TRUE
      } else if (in_bullet) {
        items[length(items)] <- paste(items[length(items)], trimws(line))
      } else {
        items <- c(items, trimws(line))
      }
    }
    folder <- dirname(where[1])
    if (folder != heading) {
      guide <- c(guide, paste("##", steps[[folder]]), "")
      heading <- folder
    }
    first <- which(grepl("^- ", items))[1]
    paragraph <- if (is.na(first)) items else items[seq_len(first - 1)]
    bullets <- if (is.na(first)) character(0) else items[first:length(items)]
    guide <- c(guide, sprintf("### `%s`", where[1]), "", paste(paragraph, collapse = " "), "",
               if (length(bullets)) c(bullets, ""))
  }
  writeLines(guide, file.path(out, "how_to_read_the_plots.md"))
}
write_summary <- function() {
  writeLines(summary_lines, file.path(out, "summary.md"))
  write_reading_guide()
}
say("pdmS7 single-site calibration: %s (%s km2), effort %s", site$name, area, effort)

# ---- 1. Data ----------------------------------------------------------------------------

say("\n1. Reading and checking the data")
d1 <- folder("1_data")
raw <- c(list(flow = read_hydro_series(s$flow), pe = read_hydro_series(s$pet)),
         lapply(rain_files, read_hydro_series))
if (s$snow) raw$temperature <- read_hydro_series(s$temperature)
gauge_names <- names(s$rain_gauges)
for (n in gauge_names) raw[[paste0("gauge: ", n)]] <- read_hydro_series(s$rain_gauges[[n]])
grid <- do.call(align_series, c(raw, list(dt = dt)))
flow <- convert_units(grid$flow, "auto", dt, "flow")
pe <- fill_gaps(convert_units(grid$pe, "mm_per_step", dt, "pet"), "interpolate", grid$time, "pe")
rains <- lapply(names(rain_files), function(n) {
  r <- convert_units(grid[[n]], "mm_per_step", dt, "rain")
  zero_negatives(fill_gaps(r, "stop", grid$time, "rain"), "rain")
})
names(rains) <- names(rain_files)
if (isTRUE(s$snow)) {
  temperature <- fill_gaps(grid$temperature, "interpolate", grid$time, "temperature")
  rains <- lapply(rains, function(r) {
    sim_pack(r, temperature, pack_presets(), timestep_min = as.integer(round(dt * 60)))$
      effective_rain_mm
  })
}
forcings <- lapply(rains, function(r) data.frame(time = grid$time, rain = r, pet = pe))
forcing <- forcings[[1]]
years <- as.numeric(difftime(max(grid$time), min(grid$time), units = "days")) / 365.25
missing_flow <- 100 * mean(!is.finite(flow))
writeLines(utils::capture.output(print(check_inputs(forcing, flow, area))),
           file.path(d1, "input_checks.txt"))
# HOW TO READ series.png
# Rain on top (bars, mm per step), flow below (m3/s), over the whole record.
# Good: every burst of rain is followed, within hours, by a rise in flow, and the flow falls
#   away smoothly between storms.
# Worry if: the flow is flat for weeks (a stuck gauge); it jumps up or down in one step and
#   stays there (a rating or datum change); a big storm brings no rise, or a rise has no rain
#   (a missed or misplaced storm); long empty stretches (gaps).
png_of(file.path(d1, "series.png"), function() {
  graphics::par(mfrow = c(2, 1), mar = c(2, 4.5, 1, 1))
  graphics::plot(grid$time, forcing$rain, type = "h", col = "#1B6F80", ylab = "Rain (mm/step)",
                 xlab = "")
  graphics::plot(grid$time, flow, type = "l", col = "#13212E", ylab = "Flow (m3/s)", xlab = "")
})
note("## 1. The data", "",
     sprintf("- %.1f years of %s data, from %s to %s.", years,
             if (dt < 1) sprintf("%g-minute", dt * 60) else sprintf("%g-hour", dt),
             format(min(grid$time), "%d %b %Y"), format(max(grid$time), "%d %b %Y")),
     sprintf("- Flow is missing for %.1f%% of the steps.%s", missing_flow,
             if (missing_flow > 10) " That is a lot: check the gauge record for long gaps." else
               " Missing flow is skipped when scoring, so a little does no harm."),
     if (isTRUE(s$snow)) "- Snow: the rain is PACK rain plus melt, from the temperature." else
       NULL,
     "- Look at `1_data/series.png`: rain on top, flow below. Flat lines or sudden steps in",
     "  the flow usually mean gauge problems, not hydrology.", "")

# ---- 2. Water balance -------------------------------------------------------------------

say("2. The water balance, year by year")
d2 <- folder("2_water_balance")
wb <- water_balance(forcing, flow, area)
fwrite(wb$years, file.path(d2, "water_balance_by_year.csv"))
# HOW TO READ budyko.png
# Each water year as a point: across, how dry the climate is (potential evaporation / rain);
# up, the share of the rain that never reached the river (loss / rain, or 1 - runoff ratio).
# The dashed lines are physical limits: a catchment cannot lose more than all its rain (the
# flat line at 1), nor evaporate more than the air can take (the sloping line). The curve is
# where a typical catchment sits; the open circle is the whole record.
# Good: points below both dashed lines, near the curve, close together.
# Worry if: a point sits above a dashed line. That is impossible for a closed catchment, so
#   the data are wrong: rain too high, flow too low, or water leaving underground or by
#   abstraction. Points far below the curve mean more flow than climate explains: rain too
#   low (common in the uplands) or water arriving from outside the catchment.
pdm_save(wb, file.path(d2, "budyko.png"), type = "budyko")
# HOW TO READ years.png
# Two lines across the water years: the runoff ratio (flow / rain) and the loss over
# potential evaporation; the line at 1 is the limit for both. Amber points are flagged
# years, open points incomplete years.
# Good: both lines fairly level, wet years a little higher in runoff ratio, both below 1.
# Worry if: either line crosses 1, or jumps in one year and stays at the new level. A step
#   usually means a new rain gauge, a new rating or a new abstraction, not a change in the
#   weather. Calibrate on the years after a step, or find out why.
pdm_save(wb, file.path(d2, "years.png"), type = "years")
# HOW TO READ double_mass.png
# Cumulative flow against cumulative rain, from the start of the record; the dashed line
# joins its ends.
# Good: the curve stays on the dashed line. Short wiggles are just wet and dry spells.
# Worry if: the curve bends and keeps the new slope. Steeper after the bend means more flow
#   per mm of rain than before, flatter means less: something in the rain or the flow record
#   changed at that point. summary.md names the year of any large shift.
pdm_save(wb, file.path(d2, "double_mass.png"), type = "double_mass")
yr <- wb$years
# HOW TO READ runoff_ratio_by_year.png
# One bar per water year (October to September): the share of the year's rain that left the
# catchment as river flow. The dashed line is the whole record; the red line at 1 is where
# flow would equal rain. Amber bars are years the water balance flags.
# Good: bars of similar height, wetter years a little taller, all well below 1. Typical
#   ratios: 0.3 to 0.5 in the lowlands, 0.6 to 0.9 in wet uplands, lower on chalk.
# Worry if: a bar reaches 1 (more flow than rain: the rain is too low or water comes in from
#   outside); one year stands far from the rest (check that year's rain and flow); the bars
#   step up or down part way through the record (a change in a gauge or the catchment).
png_of(file.path(d2, "runoff_ratio_by_year.png"), function() {
  graphics::par(mar = c(5, 4.5, 2, 1))
  flagged <- nzchar(yr$flags)
  graphics::barplot(yr$runoff_ratio, names.arg = yr$period, las = 2,
                    col = ifelse(flagged, "#E3A51C", "#1B6F80"), border = NA,
                    ylim = c(0, max(1.1, 1.1 * max(yr$runoff_ratio, na.rm = TRUE))),
                    ylab = "Runoff ratio (flow / rain)",
                    main = "Runoff ratio by water year (amber: flagged year)")
  graphics::abline(h = wb$record$runoff_ratio, lty = 2, col = "#13212E")
  graphics::abline(h = 1, col = "#B3261E")
  graphics::legend("topright", bty = "n", lty = c(2, 1), col = c("#13212E", "#B3261E"),
                   c("Whole record", "Flow equals rain"))
})
rec <- wb$record
bfi <- wb$bfi %||% NA_real_
verdict <- if (rec$runoff_ratio > 1) {
  paste("**More flow than rain.** The rain is too low (gauges under-catch in the uplands),",
        "or water arrives from outside the catchment (springs fed from a neighbouring",
        "aquifer). Calibrating on this rain will distort the model. If the catchment is not",
        "groundwater-fed, give a range for rainfall_factor, such as [1.0, 1.5].")
} else if (rec$loss_over_pet > 1) {
  paste("**More water lost than evaporation can take.** The rain may be too high, or water",
        "leaves unseen: abstraction, groundwater flowing under the gauge, or sewers in towns.",
        "The model will make up the difference in its stores; treat the fit with care.")
} else if (rec$runoff_ratio < 0.35 && is.finite(bfi) && bfi > 0.65) {
  paste("**A groundwater-fed catchment losing water.** A low runoff ratio with a high",
        "baseflow index usually means water leaves through the aquifer or is abstracted. The",
        "groundwater extension's abstraction term may be needed (see the pdmS7 article on",
        "groundwater).")
} else {
  paste("**The balance looks plausible.** The flow is a believable share of the rain, and the",
        "losses are within what evaporation can take.")
}
n_flagged <- sum(nzchar(yr$flags))
note("## 2. The water balance", "",
     "The water balance is the first check on the rain, the input with the largest errors.",
     "Over a year, rain = flow + evaporation + change in storage, and storage changes little",
     "from year to year, so the flow should be a steady share of the rain.", "",
     sprintf("- Runoff ratio (flow / rain) for the whole record: **%.2f**.", rec$runoff_ratio),
     sprintf("- Losses (rain - flow) against potential evaporation: **%.2f**. Below 1 is",
             rec$loss_over_pet),
     "  normal: actual evaporation is less than potential.",
     if (is.finite(bfi)) sprintf("- Baseflow index: %.2f (near 1: groundwater-fed).", bfi),
     sprintf("- %d of %d water years are flagged (amber in `runoff_ratio_by_year.png`).",
             n_flagged, nrow(yr)),
     "", verdict, "",
     "Plots in `2_water_balance/`: `runoff_ratio_by_year.png`; `budyko.png` (each year",
     "against the limits physics allows: a point above the water limit loses more than its",
     "rain); `double_mass.png` (cumulative flow against cumulative rain: a bend means the",
     "rain or the flow changed, such as a new gauge or rating); `years.png`.", "")
if (length(wb$change$message)) {
  note(sprintf("**The runoff ratio shifts after %s**, from %.2f to %.2f. %s", wb$change$after_year,
               wb$change$before, wb$change$after, wb$change$message),
       "Look for the bend in `double_mass.png`. If the shift is in the data (a new rain gauge,",
       "a new rating), calibrate on the years after it.", "")
}

# Several rain files: how much they disagree is the size of the rain's uncertainty.
if (length(rains) > 1) {
  totals <- vapply(rains, function(r) sum(r, na.rm = TRUE) / years, numeric(1))
  ratio <- vapply(forcings, function(f) water_balance(f, flow, area)$record$runoff_ratio,
                  numeric(1))
  comparison <- data.frame(rain = names(rains), rain_mm_per_year = round(totals),
                           runoff_ratio = round(ratio, 3))
  fwrite(comparison, file.path(d2, "rain_series_compared.csv"))
  # HOW TO READ rain_series_compared.png
  # One bar per rain file: the average rain a year each gives the catchment.
  # Good: bars within a few per cent of each other.
  # Worry if: they differ by 10% or more. The model cannot tell which is right; the spread is
  #   a measure of how uncertain the rain is, and so of how uncertain any flow forecast is. The
  #   table beside it gives the runoff ratio from each: the one nearer a sensible ratio for
  #   the catchment is likelier to be right.
  png_of(file.path(d2, "rain_series_compared.png"), function() {
    graphics::par(mar = c(5, 4.5, 2, 1))
    graphics::barplot(totals, col = "#1B6F80", border = NA, ylab = "Rain, mm a year",
                      main = "The rain series compared")
  })
  spread <- 100 * (max(totals) - min(totals)) / min(totals)
  note(sprintf("**The rain series differ by %.0f%%** in their yearly totals", spread),
       sprintf("(%s). That spread is the size of the error in the rain: the model can only",
               paste(sprintf("%s %.0f mm", names(totals), totals), collapse = ", ")),
       "be as good as the rain it is given. The first series is used to calibrate.", "")
}
write_summary()

# ---- 3. Events --------------------------------------------------------------------------

say("3. Floods and their rain")
d3 <- folder("3_events")
events <- screen_events(find_events(forcing$rain, flow, forcing$time, dt = dt, area_km2 = area),
                        flow, highest_gauged_m3s = s$highest_gauged_m3s)
fwrite(events, file.path(d3, "events.csv"))
# HOW TO READ events_balance.png
# One point per flood: across, the rain that fell on the catchment for it; up, the quick flow
# it produced (the flood's water above the baseflow), both in mm. Both axes are logarithmic.
# The dashed line is a runoff ratio of 1, quick flow equal to rain; the faint lines are 0.5
# and 0.1. Grey points are floods set aside.
# Good: a band of points rising from lower left to upper right, below the dashed line, wet
#   winter floods nearer 0.5 and summer storms nearer 0.1.
# Worry if: points above the dashed line. A flood cannot produce more quick flow than its
#   rain, so the gauges missed the storm (it fell between them, or as snow that melted
#   later). Those floods are set aside; many of them mean the rain record is poor.
pdm_save(events, file.path(d3, "events_balance.png"), type = "balance")
flagged <- unlist(strsplit(events$flags[nzchar(events$flags)], "; ", fixed = TRUE))
reasons <- if (length(flagged)) {
  tab <- sort(table(flagged), decreasing = TRUE)
  paste(sprintf("%s (%d)", names(tab), as.integer(tab)), collapse = ", ")
} else {
  "none"
}
note("## 3. Floods and their rain", "",
     sprintf("- %d floods found; %d set aside from the flood scores. Reasons: %s.",
             nrow(events), sum(!events$use), reasons),
     "- `events_balance.png` sets each flood's quick flow against its rain. A flood with more",
     "  quick flow than rain is a storm the rain gauges missed: it would teach the model the",
     "  wrong lesson, so it is set aside. Many of them point to a poor rain record.", "")

# Recessions: how the river drains in dry weather says which groundwater store suits it,
# before any model is run.
recessions <- recession_analysis(flow, forcing$rain, dt = dt, time = forcing$time)
fwrite(recessions$stores, file.path(d3, "recession_stores.csv"))
# HOW TO READ recessions.png
# Each point is a day in a dry spell: across, the flow that day; up, how fast it was falling.
# Both axes are logarithmic. The bold line is fitted through the binned points; the reference
# lines show the slope a linear store (1), a cubic store (5/3) and an exponential store (2)
# would give. The fitted slope says how the river's store empties.
# Good: the points form a clear band and the fitted slope lies near one reference line. That
#   store is the one to expect in the calibration (summary.md names it).
# Worry if: the points are a wide cloud (few dry spells, or noisy low flows); the interval on
#   the slope is wide (the data cannot choose); the points bend (two stores at work, such as
#   soil water then groundwater); or the calibration later picks a store far from this one.
png_of(file.path(d3, "recessions.png"), function() plot(recessions))
note(sprintf(paste("- Recessions: the flow falls with a slope of %.2f (95%% interval %.2f to",
                   "%.2f), nearest %s **%s** store; consistent with the record: %s."),
             recessions$slope, recessions$ci[1], recessions$ci[2],
             if (grepl("^[aeiou]", recessions$nearest)) "an" else "a", recessions$nearest,
             listed(recessions$stores$store[recessions$stores$within_ci])),
     "  `recessions.png` shows it; the calibration's choice of groundwater store can be",
     "  checked against it.", "")

# Single gauges, if given: which one the river answers to, and which miss storms.
if (length(gauge_names)) {
  gauges <- as.data.frame(stats::setNames(lapply(gauge_names, function(n) {
    convert_units(grid[[paste0("gauge: ", n)]], "mm_per_step", dt, "rain")
  }), gauge_names), check.names = FALSE)
  response <- gauge_response(gauges, flow, forcing$time, dt = dt, rain = forcing$rain,
                             area_km2 = area)
  fwrite(response$summary, file.path(d3, "gauge_response.csv"))
  fwrite(response$events, file.path(d3, "gauge_response_events.csv"))
  # HOW TO READ gauge_response.png
  # One line per rain gauge: how closely the rise in river flow follows that gauge's rain
  # (correlation, up) at each lag (across, hours after the rain). The peak of each line is
  # that gauge's best lag. gauge_response.csv adds, flood by flood, which gauge explained the
  # rise best (event_wins), and how often a gauge saw almost no rain when the others saw a
  # storm (dry_events).
  # Good: every gauge peaks at a positive lag of a few hours, the heights close together; the
  #   wins shared about as you would expect from where the gauges sit.
  # Worry if: a gauge peaks at a negative lag (rain cannot follow the flow it causes: its clock
  #   is wrong); one gauge's lag differs from the rest by a whole number of hours (a time zone
  #   or clock change); a gauge has no wins, a low line, or several dry events (a blocked
  #   funnel, a logger down, or a gauge in the wrong place). Correlations between gauges blur
  #   the differences: read the order and the gaps, not the values alone.
  png_of(file.path(d3, "gauge_response.png"), function() plot(response))
  odd <- response$summary$gauge[response$summary$lag_h < 0 | response$summary$dry_events > 1]
  lags <- stats::setNames(response$summary$lag_h, response$summary$gauge)
  apart <- length(lags) > 1 && diff(range(lags)) >= 1
  note(sprintf("- Rain gauges: %s. %s", paste(gauge_names, collapse = ", "),
               if (length(odd)) {
                 sprintf("Check %s: a negative lag or several dry events.",
                         paste(odd, collapse = ", "))
               } else {
                 "None has a negative lag or repeated dry events."
               }),
       if (apart) {
         c(sprintf("  The river answers to them at lags of %s.",
                   paste(sprintf("%s %g h", names(lags), lags), collapse = ", ")),
           "  Gauges a whole hour or more apart often mean a clock or time-zone error in one:",
           "  check the gauge whose lag differs from the rest, or from its neighbours on the map.")
       },
       "  See `gauge_response.png` and `gauge_response.csv`.", "")
}
write_summary()

if (s$stop_after_checks) {
  note("## Next", "", "The checks are done. Read the sections above. If they look sound, set",
       "`stop_after_checks: false` in the settings file, or in R",
       "`settings$stop_after_checks <- FALSE`, and run the script again to calibrate.")
  write_summary()
  say("\nChecks written to %s.", out)
  say("Read summary.md and the plots; the results are also in this session: wb (the water")
  say("balance), events and forcing. To calibrate: settings$stop_after_checks <- FALSE, then")
  say("run the script again.")
  # Ends the run here without an error: quietly back to the prompt in R, or out of Rscript.
  if (interactive()) invokeRestart("abort") else quit(save = "no")
}

# ---- 4. Calibrate -----------------------------------------------------------------------

say("4. Calibrating (effort %s); this is the long part", effort)
d4 <- folder("4_calibration")
project <- file.path(d4, "project")
start <- pdm_presets("standard")
start$dt <- dt
start$area_km2 <- area
stages <- function(config) {
  st <- pdm_stages(config, overrides = overrides, events = TRUE, td_max = 6,
                   event_budget = plan$budget, method = "dds", budget = plan$budget,
                   coarse_dt = if (dt < 1) 1 else NULL)
  polish <- which(vapply(st, function(x) identical(x$name, "polish"), logical(1)))
  st[[polish]]$objective <- "boxcox"
  st
}
thresholds <- s$thresholds
if (dir.exists(project)) {
  say("   A project from an earlier run is already in %s: reusing it. Change 'output' in the",
      project)
  say("   settings for a fresh calibration.")
}
calibrate_project(project, forcing, flow, area, calibration, validation, structure = start,
                  stages = stages, recommend = plan$recommend, overrides = overrides,
                  starts = plan$starts, seed = 1L, control = list(maxit = plan$budget),
                  method = "dds", catchment = site$name, gauge = as.character(site$gauge %||% ""),
                  owner = s$owner, steward = s$steward,
                  report = TRUE, wettest_years = 0, thresholds = thresholds,
                  highest_gauged_m3s = s$highest_gauged_m3s,
                  reasoning = paste("Starter script, settings", basename(s$file)))
result <- read_projects(project)
model <- candidate_model(project)
config <- read_entry(project, result$candidate)$configuration
grade <- function(x) {
  if (!is.finite(x)) "not available" else if (x >= 0.8) "good" else if (x >= 0.6) "fair" else
    "poor"
}
note("## 4. Calibration", "",
     sprintf("- Structure chosen: %s recharge, %s soil store, %s groundwater store.",
             config$recharge$type, config$distribution$type, config$groundwater$type),
     sprintf("- Nash-Sutcliffe efficiency (NSE; 1 is perfect, 0 no better than the mean flow):"),
     sprintf("  calibration **%.2f**, validation **%.2f** (%s, as a rule of thumb).",
             result$candidate_score, result$validation_score, grade(result$validation_score)),
     if (is.finite(result$validation_score) &&
         result$candidate_score - result$validation_score > 0.1) {
       "- Validation is well below calibration: the model may lean on the calibration years."
     },
     "- The full record of the calibration, every step and why, is the report in",
     "  `4_calibration/project/report/`. The project folder is the calibration log: keep it.",
     "")
write_summary()

# ---- 5. Diagnostics ---------------------------------------------------------------------

say("5. Diagnostic plots")
d5 <- folder("5_diagnostics")
series <- project_series(project)
# These four are in the validation years, which the calibration never saw: the fairest test.
# HOW TO READ hydrograph_validation.png
# Observed flow and the model's flow against time, rain above.
# Good: the model rises and falls with the river, its peaks close in size and time.
# Worry if: peaks are consistently too high or too low (the fast response is wrong); the
#   model rises before or after the river (the time delay is wrong); low flows between
#   storms drift away (the slow stores are wrong); a single storm is missed entirely (look
#   for that storm in the rain first: the model can only respond to rain it is given).
pdm_save(series, file.path(d5, "hydrograph_validation.png"), type = "hydrograph",
         period = "validation")
# HOW TO READ duration_validation.png
# The flow duration curve: every flow, sorted from highest to lowest. Across, the
# percentage of time a flow is exceeded; up, the flow, on a log scale. The left end is
# floods, the right end droughts.
# Good: the two curves lie on top of each other from end to end.
# Worry if: the model's curve is above or below on the left (floods too big or too small)
#   or on the right (low flows wrong: the groundwater store or the losses). A model can match
#   one end and miss the other; for flood forecasting the left half matters most.
pdm_save(series, file.path(d5, "duration_validation.png"), type = "duration",
         period = "validation")
# HOW TO READ volume_validation.png
# Cumulative volume of water: everything that has passed the gauge since the window began,
# observed and modelled.
# Good: the lines stay together and finish within a few per cent (the subtitle gives it).
# Worry if: the gap widens steadily. The model makes too much or too little water overall:
#   rain bias, evaporation, or water lost or gained underground. A gap that opens in one
#   storm or one season points to that storm or season.
pdm_save(series, file.path(d5, "volume_validation.png"), type = "volume",
         period = "validation")
# HOW TO READ residuals_validation.png
# Modelled minus observed flow at each step (faint), with its 30-day average (bold). Above 0
# the model is too high, below too low. Storm peaks run off the scale on purpose.
# Good: the average line hugs 0 all year.
# Worry if: it sits above or below 0 for months (a bias), or swings with the seasons, such as
#   too high in summer and too low in winter (evaporation or the soil store is wrong).
pdm_save(series, file.path(d5, "residuals_validation.png"), type = "residuals",
         period = "validation")
checks <- calibration_checks(project, top = 20)
fwrite(checks$parameters, file.path(d5, "parameters.csv"))
fwrite(checks$events, file.path(d5, "largest_floods.csv"))
# HOW TO READ checks_bounds.png
# One row per parameter: where the calibrated value sits in the range the search was
# allowed, from 0 (the lower limit) to 1 (the upper). Amber: at a limit.
# Good: every point somewhere inside, away from the ends.
# Worry if: a point is pressed against 0 or 1. The search wanted to go further than a
#   sensible value, usually to make up for something else: rain that is too low or high, a
#   structure that does not suit the catchment, or a gauge problem. Find the cause before
#   using the model; widening the range rarely fixes it.
pdm_save(checks, file.path(d5, "checks_bounds.png"), type = "bounds")
# HOW TO READ checks_peaks.png
# The largest floods: across, the observed peak; up, the model's peak. Points on the
# diagonal are exact; the band either side is 20%. Colours mark calibration and validation.
# Good: most points inside the band, scattered either side of the diagonal.
# Worry if: points fall below the band at the right (the biggest floods underestimated, the
#   most costly error for warnings); validation points fare worse than calibration points.
pdm_save(checks, file.path(d5, "checks_peaks.png"), type = "peaks")
# HOW TO READ checks_timing.png
# The same floods: up, how many hours the model's peak came after the observed one (above 0
# late, below 0 early).
# Good: points within an hour or two of 0, either side.
# Worry if: most points sit on one side. A model consistently late gives less warning time;
#   the time delay or the fast store needs looking at.
pdm_save(checks, file.path(d5, "checks_timing.png"), type = "timing")
# HOW TO READ checks_balance.png
# The event balance (see events_balance.png in 3_events), for the floods the calibration
# scored, coloured by window. Read it the same way: points above the dashed line had more
# quick flow than rain, so their rain is doubtful.
pdm_save(checks, file.path(d5, "checks_balance.png"), type = "balance")
route <- calibration_path(project)
# HOW TO READ search_stages.png
# The calibration's scores after each stage of the search: NSE (weighted to floods), log NSE
# (weighted to low flows) and 1 minus the volume error. 1 is perfect.
# Good: scores rising, or holding, from stage to stage.
# Worry if: a stage makes things clearly worse; the later stages then had to repair it.
pdm_save(route, file.path(d5, "search_stages.png"), type = "stages")
# HOW TO READ search_starts.png
# Each stage was run from several random starting points. Each point is where one start
# finished (lower is better); the highlighted one was kept.
# Good: the starts finish close together. The record pins the model down.
# Worry if: they finish far apart. Different parameter sets fit almost as well, so the
#   values are not to be trusted one by one, and a rerun may give a different model.
pdm_save(route, file.path(d5, "search_starts.png"), type = "starts")
# HOW TO READ search_windows.png
# The chosen model's NSE, log NSE and KGE (another overall score; 1 is perfect) on the
# calibration years and on the validation years, side by side.
# Good: validation close to calibration.
# Worry if: validation falls well below calibration (by 0.1 or more). The model has learnt
#   the calibration years rather than the catchment; try a longer calibration window.
pdm_save(route, file.path(d5, "search_windows.png"), type = "windows")
at_bound <- checks$parameters$path[!is.na(checks$parameters$at_bound)]
note("## 5. Diagnostics", "",
     "In `5_diagnostics/`:",
     "- `hydrograph_validation.png`: modelled against observed flow in the validation years.",
     "  Look at the floods first: are the peaks the right size and at the right time?",
     "- `duration_validation.png`: the flow duration curve. The high end is floods, the low",
     "  end droughts; a model can match one and miss the other.",
     "- `volume_validation.png` and `residuals_validation.png`: whether the model gains or",
     "  loses water over time, and where its errors fall.",
     "- `checks_bounds.png`: each parameter within its search range. One pressed against a",
     "  limit means the model wanted to go further: question the data or the structure.",
     "- `checks_peaks.png`, `checks_timing.png`: the largest floods' peak and timing errors.",
     "- `search_starts.png`: if the random starts ended far apart, the record does not pin",
     "  the parameters down.",
     sprintf("- Parameters at a limit: %s.",
             if (length(at_bound)) paste(at_bound, collapse = ", ") else "none"), "")

b <- calibration_bounds(config, overrides = overrides)
lower <- stats::setNames(b$lower, b$path)
upper <- stats::setNames(b$upper, b$path)
log_scale <- b$path[b$scale == "log"]
warm <- sum(forcing$time < as.POSIXct(calibration[1], tz = "UTC"))
if (plan$sensitivity) {
  say("   Which parameters the record determines")
  sens <- pdm_sensitivity(config, forcing, flow, lower, upper,
                          objectives = c("nse_loss", "boxcox_loss"), r = 10L, warmup = warm,
                          log_scale = log_scale)
  fwrite(as.data.frame(sens), file.path(d5, "sensitivity.csv"))
  # HOW TO READ sensitivity.png
  # One bar per parameter, one panel per score: how much moving that parameter over its whole
  # range moves the score. Long bars matter; short bars hardly matter.
  # Good: the bars you expect to matter are long (the soil store size and the fast store for
  #   floods; the slow stores for low flows).
  # Worry if: a parameter's bar is very short. The record cannot fix it, so its calibrated
  #   value is little better than a guess: do not read meaning into it, and do not compare it
  #   between catchments. Fixing it at a typical value is safer.
  png_of(file.path(d5, "sensitivity.png"), function() plot(sens))
  weak <- unique(sens$parameter[sens$negligible])
  note("- `sensitivity.png`: how much each parameter moves the score over its whole range.",
       if (length(weak)) {
         c(sprintf("  Barely matters here: %s. The record cannot fix these well, so their",
                   paste(weak, collapse = ", ")),
           "  values are best not over-interpreted.")
       } else {
         "  Every parameter matters here, so the record determines them all."
       }, "")
}
if (plan$forecast) {
  say("   Forecasting the validation years")
  rows <- which(forcing$time >= as.POSIXct(validation[1], tz = "UTC") &
                  forcing$time <= as.POSIXct(validation[2], tz = "UTC"))
  fc <- compare_forecasts(list(calibrated = model), forcing, flow, leads_h = c(1, 3, 6, 12),
                          horizon_h = 12, every_h = 6, window = rows,
                          ar = list(ea = ar_ea_default()))
  fwrite(fc$scores, file.path(d5, "forecast_skill.csv"))
  # HOW TO READ forecast_skill.png
  # Across, how far ahead the forecast looks (hours); up, its skill compared with persistence,
  # the forecast that the flow stays as it is now. The dashed line at 0 is persistence; 1 would
  # be perfect. Forecasts are updated with the flow observed up to their start, as in operations.
  # Good: the line well above 0 at every lead time, highest at the longer leads (persistence
  #   is hard to beat an hour ahead, easy to beat twelve hours ahead).
  # Worry if: the line sits near or below 0. The model adds nothing over watching the gauge.
  png_of(file.path(d5, "forecast_skill.png"), function() plot(fc))
  note("- `forecast_skill.png`: forecasts from every 6 hours of the validation years, updated",
       "  with the flow observed so far, scored against persistence (assuming the flow stays",
       "  as it is). Above 0 the model adds something; near 1 it is close to perfect.", "")
}
if (plan$stress) {
  say("   Stress tests: dry years against wet, and parameters over time")
  search <- list(objective = "boxcox", method = "dds", control = list(maxit = plan$budget),
                 starts = 1L, log_scale = log_scale)
  sst <- do.call(split_sample_test, c(list(config, forcing, flow, lower, upper), search))
  fwrite(sst$scores, file.path(d5, "dry_against_wet.csv"))
  drift <- do.call(parameter_drift, c(list(config, forcing, flow, lower, upper, periods = 3L),
                                      search))
  fwrite(drift$parameters, file.path(d5, "parameter_drift.csv"))
  # HOW TO READ parameter_drift.png
  # The record cut into periods and the model calibrated on each in turn. Each line is one
  # parameter's place in its range (0 lower limit, 1 upper), period by period.
  # Good: flat lines. The record says the same thing about the catchment throughout.
  # Worry if: a line climbs or falls steadily, or steps. Something changed: a new rain gauge
  #   (shows in the rainfall factor or soil store), a new rating (the slow stores), land use or
  #   abstraction. A line that jumps about with no pattern is a parameter the data cannot fix
  #   (see sensitivity.png).
  png_of(file.path(d5, "parameter_drift.png"), function() plot(drift))
  note("- `dry_against_wet.csv`: calibrated on the drier years, scored on the wetter, and the",
       "  reverse. A large drop means the model will not hold in a wetter future.",
       "- `parameter_drift.png`: parameters calibrated period by period. A steady drift points",
       "  to a change in the catchment or the record, such as a new rain gauge.", "")
}

# ---- 5b. Floods and warnings ------------------------------------------------------------

say("   Floods and warnings: thresholds, lead time, annual maxima, seasons")
in_val <- forcing$time >= as.POSIXct(validation[1], tz = "UTC") &
  forcing$time <= as.POSIXct(validation[2], tz = "UTC")
after_warm <- forcing$time >= as.POSIXct(calibration[1], tz = "UTC")
# The model's flow over the whole record, from a half-full soil store, as the checks below use.
simulated <- run_pdm(model, forcing[c("rain", "pet")], initial_state(model, 0.5))$output$q_m3s
markers <- suppressWarnings(flow_markers(flow[after_warm], dt, forcing$time[after_warm]))
qmed <- markers$value[markers$name == "QMED"]

# Warning thresholds: the settings' own, or stand-ins at half QMED and QMED.
stand_in <- is.null(s$thresholds)
levels <- if (stand_in) {
  c("Half QMED" = round(qmed / 2, 2), "QMED" = round(qmed, 2))
} else {
  stats::setNames(s$thresholds$value, s$thresholds$name)
}
val_rows <- which(in_val)
threshold_scores <- pdm_threshold_scores(simulated[val_rows], flow[val_rows], levels,
                                         dt_hours = dt)
fwrite(threshold_scores, file.path(d5, "thresholds_validation.csv"))
# HOW TO READ thresholds_validation.png
# For each warning threshold, the times in the validation years the river crossed it, split
# into hits (the model crossed it too, within six hours), misses (the river crossed, the model
# did not), and false alarms (the model crossed, the river did not).
# These count the model's plain run, without updating: the test of the model itself. The
# updated forecasts, as issued in operations, are in warning_lead_time.png, so a crossing can
# be a miss here and still be warned there.
# Good: mostly hits, few misses, few false alarms.
# Worry if: misses outnumber false alarms (the model is too low in floods: warnings would come
#   late or not at all), or false alarms dominate (warnings would be issued for nothing and
#   people would stop trusting them). Misses usually cost more than false alarms.
png_of(file.path(d5, "thresholds_validation.png"), function() {
  graphics::par(mar = c(4, 4.5, 2, 1))
  counts <- rbind(Hits = threshold_scores$hits, Misses = threshold_scores$misses,
                  `False alarms` = threshold_scores$false_alarms)
  graphics::barplot(counts, beside = TRUE, names.arg = threshold_scores$threshold, border = NA,
                    col = c("#1B6F80", "#B3261E", "#E3A51C"), ylab = "Number of crossings",
                    main = "Threshold crossings in the validation years",
                    legend.text = TRUE, args.legend = list(bty = "n", x = "topright"))
})

# Warning lead time: for each crossing, how long before it a forecast first showed the river
# reaching the threshold. Forecasts are issued every hour, as in operations, through the 12
# hours before each crossing, with the rain that fell.
horizon_h <- 12
crossings <- do.call(rbind, lapply(names(levels), function(n) {
  above <- flow >= levels[[n]] & in_val
  above[is.na(above)] <- FALSE
  up <- which(above & !c(FALSE, utils::head(above, -1)))
  up <- up[c(TRUE, diff(up) > 24 / dt)]
  if (length(up)) data.frame(threshold = n, level = levels[[n]], row = up)
}))
lead_times <- NULL
if (!is.null(crossings) && nrow(crossings)) {
  window <- sort(unique(unlist(lapply(crossings$row, function(r) {
    seq.int(max(3L, r - round(horizon_h / dt)), r)
  }))))
  hindcast <- pdm_hindcast(model, forcing, flow, window = window, every_h = max(1, dt),
                           horizon_h = horizon_h, ar = list(ea = ar_ea_default()))
  forecasts <- hindcast$forecasts
  lead_for <- function(row, level, how) {
    f <- forecasts[forecasts$method == how & forecasts$origin <= row &
                     forecasts$origin >= row - round(horizon_h / dt) &
                     forecasts$time <= forcing$time[row] + 3600, ]
    if (!nrow(f)) return(NA_real_)
    warned <- tapply(f$forecast >= level, f$origin, any)
    if (!any(warned)) return(NA_real_)
    (row - min(as.numeric(names(warned))[warned])) * dt
  }
  lead_times <- data.frame(
    threshold = crossings$threshold, time = forcing$time[crossings$row],
    updated_lead_h = mapply(lead_for, crossings$row, crossings$level, "ea"),
    not_updated_lead_h = mapply(lead_for, crossings$row, crossings$level, "none"))
  fwrite(lead_times, file.path(d5, "warning_lead_time.csv"))
  # HOW TO READ warning_lead_time.png
  # One row per time the river crossed a threshold in the validation years. The filled point is
  # the notice an updated forecast gave: how many hours before the crossing the first forecast
  # issued showed the river reaching the threshold. The open point is the same without
  # updating, which is the model's plain run. Forecasts are issued hourly, so notice comes in
  # whole hours; 12 hours is the most this check looks for. A missing point means no forecast
  # before the crossing showed it.
  # Important: these forecasts use the rain that actually fell, as if the rain forecast were
  #   perfect. They show the notice the catchment and the model allow, an upper limit. Real
  #   warnings lose some of it to errors in the rain forecast.
  # Good: most crossings warned several hours ahead, and the updated points no worse than the
  #   others.
  # Worry if: many crossings have little or no notice (a fast catchment, or a model late on
  #   its rising limbs: see checks_timing.png); or updating gives less notice than the bare
  #   model (the updating drags the forecast towards the current, lower flow, or chases noise
  #   in a 15-minute record).
  png_of(file.path(d5, "warning_lead_time.png"), function() {
    k <- seq_len(nrow(lead_times))
    graphics::par(mar = c(4, 11, 2, 1))
    graphics::plot(c(0, horizon_h), range(c(0.5, k + 0.5)), type = "n", yaxt = "n",
                   xlab = "Hours of notice before the crossing", ylab = "",
                   main = "Warning lead time (rain as it fell)")
    graphics::axis(2, at = k, las = 1, cex.axis = 0.75,
                   labels = sprintf("%s %s", format(lead_times$time, "%d %b %Y"),
                                    lead_times$threshold))
    graphics::abline(h = k, col = "grey92")
    graphics::points(lead_times$not_updated_lead_h, k, pch = 1, cex = 1.4, col = "#46525E")
    graphics::points(lead_times$updated_lead_h, k, pch = 19, col = "#1B6F80")
    graphics::legend("bottomright", bty = "n", pch = c(19, 1), col = c("#1B6F80", "#46525E"),
                     c("Updated forecast", "Not updated"))
  })
}

# Annual maxima: the largest flow of each complete water year, observed and modelled.
wy <- as.integer(format(forcing$time, "%Y")) + (as.integer(format(forcing$time, "%m")) >= 10)
maxima <- do.call(rbind, lapply(unique(wy[after_warm]), function(y) {
  k <- which(wy == y & after_warm)
  if (mean(is.finite(flow[k])) < 0.9 || length(k) < 0.9 * 8760 / dt) return(NULL)
  data.frame(water_year = y, observed = max(flow[k], na.rm = TRUE),
             modelled = max(simulated[k], na.rm = TRUE),
             date = format(forcing$time[k][which.max(flow[k])], "%d %b %Y"))
}))
hg <- s$highest_gauged_m3s
if (!is.null(maxima)) {
  maxima$above_highest_gauged <- if (is.null(hg)) NA else maxima$observed > hg
  fwrite(maxima, file.path(d5, "annual_maxima.csv"))
  # HOW TO READ annual_maxima.png
  # One point per complete water year: across, the largest flow observed that year; up, the
  # largest the model gave. The diagonal is exact, the faint lines 20% either side. The
  # dashed lines, if shown, are the highest flow ever gauged: beyond them the observed flows
  # come from extending the rating, and are less certain (amber points).
  # Good: points close to the diagonal across the range, the model's median annual maximum
  #   (its QMED) close to the observed.
  # Worry if: the largest years fall below the diagonal (the model underestimates the floods
  #   that matter most); or the amber points are the ones the model misses, in which case
  #   the rating, not the model, may be wrong.
  png_of(file.path(d5, "annual_maxima.png"), function() {
    top <- max(c(maxima$observed, maxima$modelled), na.rm = TRUE) * 1.1
    graphics::par(mar = c(4.5, 4.5, 2, 1))
    graphics::plot(maxima$observed, maxima$modelled, xlim = c(0, top), ylim = c(0, top),
                   pch = 19, cex = 1.3, xlab = "Observed annual maximum (m3/s)",
                   ylab = "Modelled annual maximum (m3/s)",
                   col = ifelse(isTRUE(!is.null(hg)) & maxima$observed > (hg %||% Inf),
                                "#E3A51C", "#1B6F80"),
                   main = "Annual maxima, observed and modelled")
    graphics::abline(0, 1, col = "#13212E")
    graphics::abline(0, 1.2, col = "grey70")
    graphics::abline(0, 0.8, col = "grey70")
    if (!is.null(hg)) graphics::abline(v = hg, h = hg, lty = 2, col = "#E3A51C")
    graphics::text(maxima$observed, maxima$modelled, maxima$water_year, pos = 4, cex = 0.7)
  })
}

# Seasons: the validation years month by month and season by season.
month <- as.integer(format(forcing$time, "%m"))
season <- c("Winter", "Winter", "Spring", "Spring", "Spring", "Summer", "Summer", "Summer",
            "Autumn", "Autumn", "Autumn", "Winter")[month]
seasons <- do.call(rbind, lapply(c("Autumn", "Winter", "Spring", "Summer"), function(x) {
  k <- in_val & season == x & is.finite(flow) & is.finite(simulated)
  data.frame(season = x, mean_observed_m3s = round(mean(flow[k]), 3),
             mean_modelled_m3s = round(mean(simulated[k]), 3),
             volume_bias_pct = round(100 * (sum(simulated[k]) / sum(flow[k]) - 1), 1),
             nse = round(1 - sum((simulated[k] - flow[k])^2) /
                           sum((flow[k] - mean(flow[k]))^2), 3))
}))
fwrite(seasons, file.path(d5, "seasons_validation.csv"))
# HOW TO READ seasonal_flows.png
# The average flow in each calendar month of the validation years, observed and modelled,
# from October (the start of the water year) to September. seasons_validation.csv gives each
# season's volume bias and NSE.
# Good: the two lines follow each other through the year, high in winter, low in late summer.
# Worry if: the model is too high in summer and too low in winter, or the reverse (the
#   evaporation or the soil store's size is wrong); the summer recession falls too fast or too
#   slowly (the groundwater store). A model good in winter and poor in summer will miss
#   summer thunderstorm floods.
png_of(file.path(d5, "seasonal_flows.png"), function() {
  order_m <- c(10:12, 1:9)
  mean_by <- function(q) vapply(order_m, function(m) {
    k <- in_val & month == m & is.finite(flow) & is.finite(q)
    mean(q[k])
  }, numeric(1))
  obs_m <- mean_by(flow)
  sim_m <- mean_by(simulated)
  graphics::par(mar = c(4, 4.5, 2, 1))
  graphics::plot(seq_along(order_m), obs_m, type = "b", pch = 19, lwd = 2, col = "#46525E",
                 ylim = c(0, max(c(obs_m, sim_m), na.rm = TRUE) * 1.1), xaxt = "n", xlab = "",
                 ylab = "Mean flow (m3/s)", main = "Flow through the year, validation years")
  graphics::axis(1, at = seq_along(order_m), labels = month.abb[order_m])
  graphics::lines(seq_along(order_m), sim_m, type = "b", pch = 17, lwd = 2, col = "#1B6F80")
  graphics::legend("topright", bty = "n", c("Observed", "Model"), pch = c(19, 17),
                   col = c("#46525E", "#1B6F80"), lwd = 2)
})

# Recessions again, of the model's flow: does the model drain as the river does?
recessions_model <- recession_analysis(simulated, forcing$rain, dt = dt, time = forcing$time)
# HOW TO READ recessions_model.png
# The recession plot of 3_events/recessions.png, with the model's own recessions drawn over
# the river's in orange.
# Good: the two clouds and their fitted lines lie together: the model's stores empty at the
#   river's pace.
# Worry if: the model's line is steeper or flatter, or sits above or below the river's. The
#   model then drains too fast or too slowly in dry weather, and its low flows, and the wetness
#   of the catchment when the next storm arrives, will be wrong.
png_of(file.path(d5, "recessions_model.png"), function() {
  plot_recession(recessions, recessions_model, main = "Recessions: river and model")
})

val_maxima <- if (!is.null(maxima)) maxima else data.frame(observed = numeric(0))
note("### Floods and warnings", "",
     sprintf("Warning thresholds%s: %s.",
             if (stand_in) " (stand-ins: none were given in the settings)" else "",
             paste(sprintf("%s %.2f m3/s", names(levels), levels), collapse = ", ")),
     sprintf("- %s: %d hits, %d misses, %d false alarms in the validation years.",
             threshold_scores$threshold, threshold_scores$hits, threshold_scores$misses,
             threshold_scores$false_alarms),
     if (!is.null(lead_times)) {
       c(sprintf(paste("- Warning lead time: an updated forecast gave a median of %.1f hours'",
                       "notice over %d crossings, without updating %.1f hours;"),
                 stats::median(lead_times$updated_lead_h, na.rm = TRUE), nrow(lead_times),
                 stats::median(lead_times$not_updated_lead_h, na.rm = TRUE)),
         sprintf("  %d of them had no notice at all. These use the rain that fell: real",
                 sum(is.na(lead_times$updated_lead_h) | lead_times$updated_lead_h == 0)),
         "  warnings, with forecast rain, give less.")
     } else {
       "- The river crossed no threshold in the validation years, so no lead time is measured."
     },
     if (nrow(val_maxima)) {
       sprintf(paste("- Annual maxima: median (QMED) %.2f m3/s observed, %.2f modelled, from",
                     "%d years%s."), stats::median(maxima$observed),
               stats::median(maxima$modelled), nrow(maxima),
               if (is.null(hg)) "" else sprintf("; %d above the highest gauged flow",
                                                 sum(maxima$above_highest_gauged)))
     },
     sprintf("- Seasons (validation): volume bias %s.",
             paste(sprintf("%s %+.1f%%", seasons$season, seasons$volume_bias_pct),
                   collapse = ", ")),
     sprintf("- Recessions: the river falls with slope %.2f, the model %.2f.",
             recessions$slope, recessions_model$slope),
     "", "See `thresholds_validation.png`, `warning_lead_time.png`, `annual_maxima.png`,",
     "`seasonal_flows.png` and `recessions_model.png`.", "")

# ---- 5c. Regional context ---------------------------------------------------------------

if (!is.null(s$regional_results)) {
  say("   Setting the site beside similar CAMELS-GB catchments")
  regional <- fread(s$regional_results)
  regional <- regional[regional$state == "done" & is.finite(regional$runoff_ratio) &
                         is.finite(regional$loss_over_pet), ]
  # Similar: nearest in runoff ratio and loss over potential evaporation, each scaled by its
  # spread across the catchments, so neither dominates.
  distance <- sqrt(((regional$runoff_ratio - rec$runoff_ratio) /
                      stats::sd(regional$runoff_ratio))^2 +
                     ((regional$loss_over_pet - rec$loss_over_pet) /
                        stats::sd(regional$loss_over_pet))^2)
  neighbours <- regional[order(distance)[seq_len(min(20L, nrow(regional)))], ]
  fwrite(neighbours[, intersect(c("gauge", "name", "runoff_ratio", "loss_over_pet",
                                  "recharge", "distribution", "groundwater",
                                  "nse_validation"), names(neighbours)), with = FALSE],
         file.path(d5, "regional_neighbours.csv"))
  # The site's parameters as the bulk run records them: the two surface time constants as a
  # sorted pair, since two stores in series give the same flow whichever way round.
  site_p <- stats::setNames(checks$parameters$value, checks$parameters$path)
  if (all(c("surface.k1", "surface.k2") %in% names(site_p))) {
    k <- sort(site_p[c("surface.k1", "surface.k2")])
    site_p <- site_p[setdiff(names(site_p), c("surface.k1", "surface.k2"))]
    site_p[c("surface.k_fast", "surface.k_slow")] <- k
  }
  bound_of <- function(p) sub("surface.k_(fast|slow)", "surface.k1", p)
  shared <- intersect(names(site_p), names(neighbours))
  place <- function(v, p) {
    q <- checks$parameters[checks$parameters$path == bound_of(p), ]
    if (q$scale == "log") (log(v) - log(q$lower)) / (log(q$upper) - log(q$lower)) else
      (v - q$lower) / (q$upper - q$lower)
  }
  compared <- do.call(rbind, lapply(shared, function(p) {
    v <- neighbours[[p]][is.finite(neighbours[[p]])]
    data.frame(parameter = p, site = site_p[[p]], neighbours = length(v),
               neighbour_median = if (length(v)) stats::median(v) else NA_real_,
               site_percentile = if (length(v)) round(100 * mean(v < site_p[[p]])) else NA)
  }))
  fwrite(compared, file.path(d5, "regional_parameters.csv"))
  # HOW TO READ regional_parameters.png
  # One row per parameter. Grey points: the values calibrated for the 20 CAMELS-GB catchments
  # whose water balance is most like this site's (runoff ratio and losses). Blue: this site.
  # All are placed within the search range, 0 at the lower limit, 1 at the upper.
  # Good: the blue point sits among the grey ones. Similar catchments, similar models.
  # Worry if: the blue point is far outside the grey cloud. Either this catchment really is
  #   different (look for a reason: chalk, a reservoir, a town), or the calibration has made up
  #   for a problem in the data. Grey points spread across the whole range mean the parameter
  #   is poorly determined everywhere, and the comparison says little. The bulk run is hourly
  #   with the rainfall factor fixed at 1; keep that in mind for fc and the time constants.
  png_of(file.path(d5, "regional_parameters.png"), function() {
    k <- seq_along(shared)
    graphics::par(mar = c(4.5, 11, 2, 1))
    graphics::plot(c(0, 1), c(0.5, length(k) + 0.5), type = "n", yaxt = "n", ylab = "",
                   xlab = "Place in the search range (0 lower limit, 1 upper)",
                   main = "This site among similar catchments")
    graphics::axis(2, at = k, labels = shared, las = 1, cex.axis = 0.8)
    graphics::abline(h = k, col = "grey92")
    for (i in k) {
      v <- neighbours[[shared[i]]]
      v <- v[is.finite(v)]
      if (length(v)) {
        graphics::points(pmin(pmax(place(v, shared[i]), 0), 1), rep(i, length(v)),
                         pch = 19, col = grDevices::adjustcolor("#46525E", 0.45))
      }
      graphics::points(place(site_p[[shared[i]]], shared[i]), i, pch = 19, cex = 1.6,
                       col = "#1B6F80")
    }
  })
  same <- if (all(c("recharge", "distribution", "groundwater") %in% names(neighbours))) {
    mean(neighbours$recharge == config$recharge$type &
           neighbours$distribution == config$distribution$type &
           neighbours$groundwater == config$groundwater$type)
  } else NA
  outside <- compared$parameter[!is.na(compared$site_percentile) &
                                  (compared$site_percentile <= 5 | compared$site_percentile >= 95)]
  note("### Among similar catchments", "",
       sprintf(paste("The %d CAMELS-GB catchments with the most similar water balance (runoff",
                     "ratio %.2f to %.2f):"), nrow(neighbours), min(neighbours$runoff_ratio),
               max(neighbours$runoff_ratio)),
       if (is.finite(same)) {
         sprintf("- %.0f%% of them chose the same structure as this site.", 100 * same)
       },
       if ("nse_validation" %in% names(neighbours)) {
         sprintf("- Their median validation NSE is %.2f; this site's is %.2f.",
                 stats::median(neighbours$nse_validation, na.rm = TRUE),
                 result$validation_score)
       },
       sprintf(paste("- Parameters outside the neighbours' range (below their 5th or above",
                     "their 95th percentile): %s."), listed(outside)),
       "", "See `regional_parameters.png`, `regional_parameters.csv` and",
       "`regional_neighbours.csv`.", "")
}

write_summary()

# ---- 6. Input uncertainty ---------------------------------------------------------------

say("6. How errors in the rain and evaporation carry into the flow")
d6 <- folder("6_input_uncertainty")
state0 <- initial_state(model, 0.5)
run_with <- function(rain_factor, pe_factor) {
  f <- forcing
  f$rain <- f$rain * rain_factor
  f$pet <- f$pet * pe_factor
  run_pdm(model, f[c("rain", "pet")], state0)$output$q_m3s
}
nse <- function(sim) {
  ok <- in_val & is.finite(flow) & is.finite(sim)
  1 - sum((sim[ok] - flow[ok])^2) / sum((flow[ok] - mean(flow[ok]))^2)
}
scenarios <- data.frame(
  scenario = c("as measured", "rain 10% lower", "rain 10% higher",
               "evaporation 10% lower", "evaporation 10% higher"),
  rain = c(1, 0.9, 1.1, 1, 1), pet = c(1, 1, 1, 0.9, 1.1))
sims <- lapply(seq_len(nrow(scenarios)), function(i) run_with(scenarios$rain[i], scenarios$pet[i]))
ok <- in_val & is.finite(flow)
peak_at <- which(ok)[which.max(flow[ok])]
scenarios$flow_volume_change_pct <- vapply(sims, function(q) {
  round(100 * (sum(q[ok]) / sum(sims[[1]][ok]) - 1), 1)
}, numeric(1))
scenarios$largest_peak_change_pct <- vapply(sims, function(q) {
  w <- max(1, peak_at - 48 / dt):min(length(q), peak_at + 48 / dt)
  round(100 * (max(q[w]) / max(sims[[1]][w]) - 1), 1)
}, numeric(1))
scenarios$validation_nse <- round(vapply(sims, nse, numeric(1)), 3)
fwrite(scenarios, file.path(d6, "rain_and_evaporation_scenarios.csv"))
# HOW TO READ largest_flood_with_rain_10pct_out.png
# The largest flood in the validation years: observed (grey), the model with the rain as
# measured (blue), and the model with every rain value 10% lower (amber dashed) and 10% higher
# (red dashed). Nothing else is changed.
# What it shows: the spread between the dashed lines is how far the forecast peak moves for
#   a rain error of a size that is common. If that spread is wider than the gap between the
#   model and the observed flow, the rain, not the model, limits the forecast.
# Typical: the peak moves by more than 10%, because once the soil is wet nearly all the
#   extra rain runs off.
png_of(file.path(d6, "largest_flood_with_rain_10pct_out.png"), function() {
  w <- max(1, peak_at - 72 / dt):min(length(flow), peak_at + 120 / dt)
  graphics::par(mar = c(4, 4.5, 2, 1))
  graphics::plot(forcing$time[w], flow[w], type = "l", lwd = 2, col = "#46525E",
                 ylim = c(0, max(c(flow[w], unlist(lapply(sims[1:3], `[`, w))), na.rm = TRUE)),
                 xlab = "", ylab = "Flow (m3/s)",
                 main = "The largest validation flood, with the rain 10% out")
  graphics::lines(forcing$time[w], sims[[1]][w], lwd = 3, col = "#1B6F80")
  graphics::lines(forcing$time[w], sims[[2]][w], lwd = 2, lty = 2, col = "#E3A51C")
  graphics::lines(forcing$time[w], sims[[3]][w], lwd = 2, lty = 2, col = "#B3261E")
  graphics::legend("topright", bty = "n",
                   c("Observed", "Model", "Rain 10% lower", "Rain 10% higher"),
                   col = c("#46525E", "#1B6F80", "#E3A51C", "#B3261E"),
                   lty = c(1, 1, 2, 2), lwd = c(2, 3, 2, 2))
})
up <- scenarios[scenarios$scenario == "rain 10% higher", ]
note("## 6. Input uncertainty: how errors in the rain carry into the flow", "",
     "The calibrated model is run again with the rain, then the evaporation, 10% out. Rain",
     "errors of 10% are common: gauges catch less in wind and on hills, and one gauge can",
     "miss a storm entirely. Studies that separate the sources of error usually find the",
     "rain the largest.", "",
     sprintf("- Rain 10%% higher: flow volume %+.1f%%, the largest flood's peak %+.1f%%.",
             up$flow_volume_change_pct, up$largest_peak_change_pct),
     sprintf("- Validation NSE across the five scenarios: %.2f to %.2f.",
             min(scenarios$validation_nse), max(scenarios$validation_nse)), "",
     if (abs(up$largest_peak_change_pct) > 10) {
       paste("A 10% error in the rain moves the flood peak by more than 10%: the floods",
             "amplify rain errors. A forecast can be no more certain than its rain.")
     } else {
       "The peak moves by about as much as the rain, or less."
     }, "",
     "See `6_input_uncertainty/largest_flood_with_rain_10pct_out.png` and",
     "`rain_and_evaporation_scenarios.csv`.", "")

# Storm by storm: each storm's rain multiplied by its own random factor, as gauges err storm by
# storm rather than all by the same amount. Many runs give a band of flows the rain allows.
say("   The band of flows the rain's errors allow (%d runs)", plan$members)
sd_log <- s$rain_error
# A storm: a spell of rain with no dry gap of six hours or more inside it.
wet <- which(forcing$rain > 0)
storm <- cumsum(c(1L, diff(wet) > 6 / dt))
# The ten largest floods of the validation years: the highest flows at least three days apart.
largest_floods <- function(n = 10L, apart_h = 72) {
  rows <- which(in_val & is.finite(flow))
  chosen <- integer(0)
  for (r in rows[order(-flow[rows])]) {
    if (all(abs(chosen - r) > apart_h / dt)) chosen <- c(chosen, r)
    if (length(chosen) == n) break
  }
  chosen
}
top_rows <- largest_floods()
around <- function(r) max(1, r - 24 / dt):min(nrow(forcing), r + 24 / dt)
w_big <- max(1, peak_at - 72 / dt):min(length(flow), peak_at + 120 / dt)
set.seed(1)
members <- lapply(seq_len(plan$members), function(i) {
  factor <- exp(stats::rnorm(max(storm), -sd_log^2 / 2, sd_log))
  f <- forcing[c("rain", "pet")]
  f$rain[wet] <- f$rain[wet] * factor[storm]
  q <- run_pdm(model, f, state0)$output$q_m3s
  list(peaks = vapply(top_rows, function(r) max(q[around(r)]), numeric(1)), largest = q[w_big])
})
peaks <- do.call(rbind, lapply(members, `[[`, "peaks"))
band_peaks <- apply(peaks, 2, stats::quantile, c(0.05, 0.5, 0.95))
storm_table <- data.frame(
  flood = format(forcing$time[top_rows], "%d %b %Y"),
  observed_peak = round(flow[top_rows], 2),
  model_peak = round(vapply(top_rows, function(r) max(sims[[1]][around(r)]), numeric(1)), 2),
  band_low = round(band_peaks[1, ], 2), band_mid = round(band_peaks[2, ], 2),
  band_high = round(band_peaks[3, ], 2))
storm_table$observed_within_band <- storm_table$observed_peak >= storm_table$band_low &
  storm_table$observed_peak <= storm_table$band_high
fwrite(storm_table, file.path(d6, "rain_error_band_floods.csv"))
largest <- do.call(cbind, lapply(members, `[[`, "largest"))
band_big <- apply(largest, 1, stats::quantile, c(0.05, 0.5, 0.95))
draw_band <- function(lo, mid, hi, title, label) {
  x <- forcing$time[w_big]
  graphics::par(mar = c(4, 4.5, 2, 1))
  graphics::plot(x, flow[w_big], type = "n", xlab = "", ylab = "Flow (m3/s)", main = title,
                 ylim = c(0, max(c(hi, flow[w_big]), na.rm = TRUE) * 1.05))
  graphics::polygon(c(x, rev(x)), c(lo, rev(hi)), border = NA,
                    col = grDevices::adjustcolor("#1B6F80", 0.25))
  graphics::lines(x, mid, lwd = 2, col = "#1B6F80")
  graphics::lines(x, flow[w_big], lwd = 2, col = "#46525E")
  graphics::legend("topright", bty = "n", c("Observed", "Middle of the band", label),
                   col = c("#46525E", "#1B6F80", grDevices::adjustcolor("#1B6F80", 0.25)),
                   lwd = c(2, 2, 10))
}
# HOW TO READ rain_error_band.png
# The largest flood in the validation years. The model was run many times, each time with
# every storm's rain multiplied by its own random factor (typically within the rain_error in
# the settings), and the shaded band holds the middle 90% of the flows those runs gave. The
# grey line is the observed flow.
# What it shows: how much a flood forecast can be trusted when the rain is no better than
#   this. The band is wider at the peak than in the recession: rain errors matter most when
#   the catchment is wet. rain_error_band_floods.csv does the same for the ten largest
#   validation floods.
# Good: the observed peak inside the band for most of the ten floods. The model is then as
#   good as its rain allows.
# Worry if: the observed peaks fall outside the band, most on one side. The model, not just
#   the rain, is off for those floods; or the rain error is larger than the setting assumes.
png_of(file.path(d6, "rain_error_band.png"), function() {
  draw_band(band_big[1, ], band_big[2, ], band_big[3, ],
            "The largest validation flood, with storm-by-storm rain errors",
            sprintf("90%% of runs, storms %.0f%% out", 100 * sd_log))
})
span <- round(100 * exp(c(-1.645, 1.645) * sd_log))
note("### Storm-by-storm rain errors", "",
     sprintf(paste("Gauges do not err by the same amount in every storm. The model was run %d",
                   "times with each storm's rain multiplied by its own random factor, 90%% of"),
             plan$members),
     sprintf("them between %d%% and %d%% of the measured rain (rain_error %.2f).", span[1],
             span[2], sd_log),
     sprintf(paste("- The observed peak falls within the band of the runs for %d of the %d",
                   "largest validation floods."), sum(storm_table$observed_within_band),
             nrow(storm_table)),
     sprintf("- For the largest, the runs' peaks span %.1f to %.1f m3/s; observed, %.1f.",
             storm_table$band_low[1], storm_table$band_high[1], storm_table$observed_peak[1]),
     "", "See `rain_error_band.png` and `rain_error_band_floods.csv`.", "")

# Parameter uncertainty (thorough effort): a Bayesian calibration gives not one set of
# parameters but many, each as likely as the data allow, and a band of flows from them.
if (plan$bayes) {
  say("   Parameter uncertainty: a Bayesian calibration")
  to_cal_end <- forcing$time <= as.POSIXct(calibration[2], tz = "UTC")
  bayes <- calibrate_bayes(config, forcing[to_cal_end, ], flow[to_cal_end], lower, upper,
                           generations = s$bayes_generations, warmup = warm,
                           log_scale = log_scale)
  fwrite(bayes$summary, file.path(d6, "parameter_posterior.csv"))
  band <- posterior_band(bayes, forcing, draws = 100L)
  covered <- in_val & is.finite(flow)
  coverage <- mean(flow[covered] >= band$q05[covered] & flow[covered] <= band$q95[covered])
  # HOW TO READ parameter_uncertainty_band.png
  # The largest validation flood again. This band comes not from the rain but from the
  # model: a Bayesian calibration finds every parameter set the calibration years allow, and
  # the band holds 90% of the flows they give, with the model's usual error added.
  # parameter_posterior.csv gives each parameter's range.
  # Good: about 90% of the observed flow inside the band over the validation years
  #   (summary.md gives the share), and the band narrow enough to be useful.
  # Worry if: far less than 90% of the flow falls inside (the model is overconfident: its
  #   errors are larger than it believes); the band is very wide (the data cannot pin the
  #   parameters down); rhat in the table above 1.2 for any parameter (the search had not
  #   settled; set bayes_generations higher, such as 4000, and run again).
  png_of(file.path(d6, "parameter_uncertainty_band.png"), function() {
    draw_band(band$q05[w_big], band$q50[w_big], band$q95[w_big],
              "The largest validation flood, with parameter uncertainty",
              "90% of parameter sets")
  })
  unsettled <- bayes$summary$parameter[bayes$summary$rhat > 1.2]
  note("### Parameter uncertainty", "",
       "A Bayesian calibration finds every parameter set the calibration years allow.",
       sprintf("- %.0f%% of the observed validation flow falls inside its 90%% band.",
               100 * coverage),
       sprintf("- Parameters whose search had not settled (rhat above 1.2): %s.%s",
               listed(unsettled),
               if (length(unsettled)) {
                 sprintf(" Set bayes_generations above %d and run again.", s$bayes_generations)
               } else ""),
       "", "See `parameter_uncertainty_band.png` and `parameter_posterior.csv`.", "")
}

# ---- Comparisons and export -------------------------------------------------------------

others <- list(new = project)
others$previous <- s$previous_project
others$pdm_for_pcs <- s$pdm_for_pcs_inp
if (length(others) > 1) {
  say("   Comparing with %s", toString(names(others)[-1]))
  cmp <- compare_calibrations(others, forcing, flow,
                              windows = list(calibration = calibration, validation = validation),
                              warmup = warm)
  fwrite(cmp$scores, file.path(d5, "comparison_scores.csv"))
  # HOW TO READ comparison_largest_flood.png
  # The largest flood, with the observed flow (black) and each model on the same rain: the new
  # calibration, and the earlier project or the PDM for PCs model.
  # Good: the new model as close to the observed flow as the old, or closer, in peak and timing.
  # Worry if: the old model is clearly better on this flood. Check the scores table too: one
  #   flood is one flood, but the largest matters most for warnings.
  png_of(file.path(d5, "comparison_largest_flood.png"), function() plot(cmp, event = 1))
  note("## Compared with the existing model", "",
       "`5_diagnostics/comparison_scores.csv` and `comparison_largest_flood.png`: every model",
       "on the same rain, from the same start, scored on the same windows.", "")
}
inp <- file.path(d4, paste0(gsub("[^A-Za-z0-9]+", "_", site$name), ".inp"))
tryCatch({
  write_pdm_inp(model, inp, title = paste(site$name, "pdmS7 candidate"), event = calibration)
  note(sprintf("The model is also written for PDM for PCs: `4_calibration/%s`.", basename(inp)))
}, error = function(e) note(paste("No PDM for PCs file:", conditionMessage(e))))
note("", "## Next", "",
     "1. Read the report in `4_calibration/project/report/`.",
     sprintf("2. Look at the largest floods with `calibration_app(\"%s\")`, Events tab.", project),
     "3. Sign-off is the steward's decision: `sign_off_project()` once the report is read.")
write_summary()
say("\nDone. Read %s", file.path(out, "summary.md"))
say("The results are also in this session: wb (water balance), events, model (the calibrated")
say("PDM), checks, series (modelled and observed flow) and scenarios (rain and evaporation 10%%")
say("out). For example: plot(series, type = \"hydrograph\", period = \"validation\").")
