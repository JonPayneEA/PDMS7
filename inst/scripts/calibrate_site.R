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
# Dependencies: pdmS7 (0.37.0 or later); data.table; yaml
# ============================================================ #
#
# How to run it
#   1. Copy the example settings and fill in its first section:
#        file.copy(system.file("examples", "site.yml", package = "pdmS7"), "my_site.yml")
#   2. Run this script. From RStudio: source(system.file("scripts", "calibrate_site.R",
#      package = "pdmS7")), and choose your settings file when asked. Or set
#      Sys.setenv(PDM_SITE_CONFIG = "my_site.yml") first, or from a terminal:
#        Rscript calibrate_site.R my_site.yml
#   3. Read summary.md in the output folder. It says what each result means and what to do.
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
stopifnot(utils::packageVersion("pdmS7") >= "0.37.0")
`%||%` <- function(x, y) if (is.null(x)) y else x
say <- function(...) cat(sprintf(...), "\n", sep = "")

# ---- Settings ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
settings_file <- if (length(args)) args[1] else Sys.getenv("PDM_SITE_CONFIG")
if (!nzchar(settings_file) && interactive()) settings_file <- file.choose()
if (!nzchar(settings_file) || !file.exists(settings_file)) {
  stop("No settings file. Copy one with file.copy(system.file(\"examples\", \"site.yml\", ",
       "package = \"pdmS7\"), \"my_site.yml\"), fill it in, and run this again.", call. = FALSE)
}
s <- yaml::read_yaml(settings_file)
home <- dirname(normalizePath(settings_file))
absolute <- function(p) grepl("^(/|~|[A-Za-z]:|\\\\)", p)
here <- function(p) if (absolute(p)) path.expand(p) else file.path(home, p)
need <- function(value, what) {
  if (!length(value) || (is.character(value) && !all(nzchar(value)))) {
    stop("The settings file needs ", what, call. = FALSE)
  }
  value
}
site <- need(s$site, "a site section")
area <- as.numeric(need(site$area_km2, "site: area_km2"))
dt <- as.numeric(s$data$step_hours %||% 0.25)
rain_files <- need(s$data$rain, "data: rain")
if (!is.list(rain_files)) rain_files <- list(rain = rain_files)
calibration <- as.character(need(s$calibration, "calibration: [start, end]"))
validation <- as.character(need(s$validation, "validation: [start, end]"))
effort <- match.arg(s$effort %||% "standard", c("quick", "standard", "thorough"))
plan <- list(
  quick = list(starts = 2L, budget = 150L, recommend = TRUE, sensitivity = FALSE,
               forecast = FALSE, stress = FALSE),
  standard = list(starts = 3L, budget = 300L, recommend = TRUE, sensitivity = TRUE,
                  forecast = TRUE, stress = FALSE),
  thorough = list(starts = 4L, budget = 600L, recommend = TRUE, sensitivity = TRUE,
                  forecast = TRUE, stress = TRUE)
)[[effort]]
overrides <- if (is.numeric(s$rainfall_factor) && length(s$rainfall_factor) == 2) {
  list(fc = as.numeric(s$rainfall_factor))
}
options(pdmS7.user = Sys.getenv("USERNAME", Sys.getenv("USER", "analyst")),
        pdmS7.role = "custodian")
logger::log_threshold(logger::WARN, namespace = "pdmS7")

out <- here(s$output %||% "output")
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
                   sprintf("Settings: %s. Effort: %s. pdmS7 %s, %s.", basename(settings_file),
                           effort, utils::packageVersion("pdmS7"), format(Sys.Date())), "")
note <- function(...) summary_lines <<- c(summary_lines, unlist(list(...)))
write_summary <- function() writeLines(summary_lines, file.path(out, "summary.md"))
say("pdmS7 single-site calibration: %s (%s km2), effort %s", site$name, area, effort)

# ---- 1. Data ----------------------------------------------------------------------------

say("\n1. Reading and checking the data")
d1 <- folder("1_data")
path <- function(f) if (absolute(f)) path.expand(f) else here(file.path(s$data$folder %||% ".", f))
raw <- c(list(flow = read_hydro_series(path(s$data$flow)),
              pe = read_hydro_series(path(s$data$pet))),
         lapply(rain_files, function(f) read_hydro_series(path(f))))
if (isTRUE(s$snow)) raw$temperature <- read_hydro_series(path(need(s$temperature, "temperature")))
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
for (type in c("budyko", "years", "double_mass")) {
  pdm_save(wb, file.path(d2, paste0(type, ".png")), type = type)
}
yr <- wb$years
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

if (isTRUE(s$stop_after_checks %||% TRUE)) {
  note("## Next", "", "The checks are done. Read the sections above. If they look sound, set",
       "`stop_after_checks: false` in the settings file and run the script again to",
       "calibrate.")
  write_summary()
  say("\nChecks written to %s. Read summary.md, then set stop_after_checks: false.", out)
  if (!interactive()) quit(save = "no")
  stop("stop_after_checks is true: stopped before calibrating (this is expected).",
       call. = FALSE)
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
thresholds <- if (length(s$thresholds)) {
  data.frame(name = vapply(s$thresholds, function(t) t$name, ""),
             value = vapply(s$thresholds, function(t) as.numeric(t$value), 0), unit = "flow")
}
if (dir.exists(project)) {
  say("   A project from an earlier run is already in %s: reusing it. Change 'output' in the",
      project)
  say("   settings for a fresh calibration.")
}
calibrate_project(project, forcing, flow, area, calibration, validation, structure = start,
                  stages = stages, recommend = plan$recommend, overrides = overrides,
                  starts = plan$starts, seed = 1L, control = list(maxit = plan$budget),
                  method = "dds", catchment = site$name, gauge = as.character(site$gauge %||% ""),
                  owner = s$owner %||% "Not recorded", steward = s$steward %||% "Not recorded",
                  report = TRUE, wettest_years = 0, thresholds = thresholds,
                  highest_gauged_m3s = s$highest_gauged_m3s,
                  reasoning = paste("Starter script, settings", basename(settings_file)))
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
for (type in c("hydrograph", "duration", "volume", "residuals")) {
  pdm_save(series, file.path(d5, paste0(type, "_validation.png")), type = type,
           period = "validation")
}
checks <- calibration_checks(project, top = 20)
fwrite(checks$parameters, file.path(d5, "parameters.csv"))
fwrite(checks$events, file.path(d5, "largest_floods.csv"))
for (type in c("bounds", "peaks", "timing", "balance")) {
  pdm_save(checks, file.path(d5, paste0("checks_", type, ".png")), type = type)
}
route <- calibration_path(project)
for (type in c("stages", "starts", "windows")) {
  pdm_save(route, file.path(d5, paste0("search_", type, ".png")), type = type)
}
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
if (!is.null(s$previous_project) && dir.exists(here(s$previous_project))) {
  others$previous <- here(s$previous_project)
}
if (!is.null(s$pdm_for_pcs_inp) && file.exists(here(s$pdm_for_pcs_inp))) {
  others$pdm_for_pcs <- here(s$pdm_for_pcs_inp)
}
if (length(others) > 1) {
  say("   Comparing with %s", toString(names(others)[-1]))
  cmp <- compare_calibrations(others, forcing, flow,
                              windows = list(calibration = calibration, validation = validation),
                              warmup = warm)
  fwrite(cmp$scores, file.path(d5, "comparison_scores.csv"))
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
