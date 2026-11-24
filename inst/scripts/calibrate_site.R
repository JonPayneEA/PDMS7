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
# Modified:     2026-11-24 - First version
# Tier:         1
# Inputs:       A settings file like inst/examples/site.yml, and the CSV files it names
# Outputs:      An output folder: summary.md, then 1_data, 2_water_balance, 3_events,
#               4_calibration (the calibration project and its report), 5_diagnostics and
#               6_input_uncertainty, each with plots (PNG) and tables (CSV)
# Dependencies: pdmS7 (0.38.0 or later); data.table; yaml
# ============================================================ #
#
# How to run it
#   1. Copy the example settings and fill in its first section:
#        file.copy(system.file("examples", "site.yml", package = "pdmS7"), "my_site.yml")
#   2. Load them into R, look at them, and run this script:
#        library(pdmS7)
#        settings <- read_site_settings("my_site.yml")
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
#   3. Events     each flood's quick flow against its rain; storms the gauges missed
#   (the first run stops here: read the summary, then set stop_after_checks: false)
#   4. Calibrate  the structure chosen on the record, then a staged search: water balance and
#                 slow stores first, then the fast response, a polish that weighs high and low
#                 flows fairly, and the largest floods
#   5. Diagnose   hydrographs, flow duration, residuals, parameters against their limits, the
#                 largest floods' peaks and timing, and, with effort standard or thorough,
#                 which parameters the record determines and how well the model forecasts
#   6. Input      how far the flow moves when the rain or the evaporation is 10% out, and, with
#      uncertainty several rain files, how much they disagree

suppressPackageStartupMessages({
  library(pdmS7)
  library(data.table)
})
stopifnot(utils::packageVersion("pdmS7") >= "0.38.0")
`%||%` <- function(x, y) if (is.null(x)) y else x
say <- function(...) cat(sprintf(...), "\n", sep = "")

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
    stop("No settings. Copy the example with file.copy(system.file(\"examples\", \"site.yml\", ",
         "package = \"pdmS7\"), \"my_site.yml\"), fill it in, then ",
         "settings <- read_site_settings(\"my_site.yml\") and run this again.", call. = FALSE)
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
               forecast = FALSE, stress = FALSE),
  standard = list(starts = 3L, budget = 300L, recommend = TRUE, sensitivity = TRUE,
                  forecast = TRUE, stress = FALSE),
  thorough = list(starts = 4L, budget = 600L, recommend = TRUE, sensitivity = TRUE,
                  forecast = TRUE, stress = TRUE)
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
  settings <- list(objective = "boxcox", method = "dds", control = list(maxit = plan$budget),
                   starts = 1L, log_scale = log_scale)
  sst <- do.call(split_sample_test, c(list(config, forcing, flow, lower, upper), settings))
  fwrite(sst$scores, file.path(d5, "dry_against_wet.csv"))
  drift <- do.call(parameter_drift, c(list(config, forcing, flow, lower, upper, periods = 3L),
                                      settings))
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
write_summary()

# ---- 6. Input uncertainty ---------------------------------------------------------------

say("6. How errors in the rain and evaporation carry into the flow")
d6 <- folder("6_input_uncertainty")
in_val <- forcing$time >= as.POSIXct(validation[1], tz = "UTC") &
  forcing$time <= as.POSIXct(validation[2], tz = "UTC")
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
