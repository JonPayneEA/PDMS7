# ============================================================ #
# Tool:         compare_rain
# Description:  Builds catchment rainfall from rain gauges several ways (the Thiessen weights
#               given, equal weights, multiquadric) and finds which best explains a river's
#               flow, judged from the data alone, before any model: the water balance, the
#               double-mass curve, how closely the river's quick response follows each series,
#               storms each missed, and how many gauges' worth of rain each average uses
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-24
# Tier:         1
# Inputs:       CSV files: flow (m3/s), potential evaporation, and each rain gauge (mm per
#               step), each a date-time column and a value column, or the gauges downloaded
#               from the EA Hydrology API with reach.io; the Thiessen weights; for
#               multiquadric, the gauges' positions and the catchment boundary
#               (British National Grid metres); optionally other catchment series
# Outputs:      A folder: summary.md, rain_ranking.csv, weights_and_error.csv, plots each with a
#               note on how to read it, and catchment_rain/ with each average built, as CSV
#               ready for calibrate_site.R
# Dependencies: pdmS7 (0.42.2 or later); reach.io to download the gauges; ncdf4
#               for H19 radar
# ============================================================ #
#
# How to use it
#   1. Copy the script to your own folder, so you can fill in its settings:
#        file.copy(system.file("scripts", "compare_rain.R", package = "pdmS7"), "compare_rain.R")
#        file.edit("compare_rain.R")
#   2. Fill in the settings below: the catchment area, the time step, the flow and evaporation
#      files, the rain gauges and the Thiessen weights. To download the gauges instead, give
#      each its WISKI ID and set gauge_source to "hydrology_api". For the multiquadric average,
#      add a boundary file and, unless they are downloaded, each gauge's position.
#   3. Run the whole script (Ctrl+Shift+S in RStudio). It takes a minute or two.
#   4. Read summary.md in the output folder.
#
# What it does
#   First it builds the catchment averages from the gauges:
#     thiessen      the Thiessen weights given;
#     equal         the same gauges, weighted equally;
#     equal_all     every gauge listed, inside the catchment or not, weighted equally (only
#                   when some gauge has no Thiessen weight);
#     multiquadric  a smooth surface through every gauge, averaged over the catchment (with the
#                   positions and the boundary).
#   Each is renormalised over the gauges reporting at each step. With the boundary it also
#   works out Thiessen weights from the geometry, to check those given.
#   Then every series (the averages, each gauge, and any other series given) is set against the
#   same flow, five ways. None needs a model, so the
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
#     6. Weights (when the gauges and weights are given): how many gauges' worth of independent
#        rain each catchment average uses, how much of a single gauge's random error survives
#        into it, the single-gauge error the gauges' own disagreement suggests, and when gauges
#        dropping out left the average resting on fewer of them.
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

# The rain gauges: one file each, rain in mm per step. x and y are each gauge's position in
# metres on British National Grid (easting and northing); they are needed only for the
# multiquadric average, so they can stay NA when there is no boundary below. wiski_id is the
# gauge's WISKI ID, needed only to download it.
gauges <- data.frame(
  name = c("gauge_A", "gauge_B", "gauge_C"),
  file = c("gauge_a.csv", "gauge_b.csv", "gauge_c.csv"),
  wiski_id = c(NA, NA, NA),
  x = c(NA, NA, NA),
  y = c(NA, NA, NA)
)

# Where the gauge data come from. "files": the CSV files above, already in data_folder.
# "hydrology_api": each gauge's 15-minute rain downloaded from the EA Hydrology API with
# reach.io, by its WISKI ID, and saved to data_folder under the file name above. A file already
# there is used as it is, so a rerun downloads nothing; delete a file to download it again.
# Positions left NA are filled from the API. Dates: from (inclusive) to (exclusive).
gauge_source <- "files"
download_from <- "2014-10-01"
download_to <- "2025-10-01"

# The Thiessen weights: each gauge's share of the catchment. A gauge outside the catchment has
# none: leave it out, or give it 0. They should add up to 1.
thiessen_weights <- c(gauge_A = 0.264, gauge_B = 0.737)

# The catchment boundary, for the multiquadric average: a CSV in data_folder with columns x and
# y, the boundary's corners in order, in metres on British National Grid. NULL to skip the
# multiquadric average. The grid it is worked out on has cells this many metres across.
catchment_boundary <- NULL     # such as "boundary.csv"
grid_spacing_m <- 500

# H19 radar (optional): the folder of daily H19 NetCDF files, searched with its sub-folders.
# The files' layouts are checked first (the archive changed how it saved them part way
# through): set radar_scan_only to TRUE to see them and stop. Then the radar over the catchment
# joins the comparison as "h19" (with a boundary), and the radar over each gauge is set against
# the gauge (with the gauges' positions). H19 is restricted: keep the output folder on
# restricted storage, as the radar extracts are written there.
radar_folder <- NULL           # such as "C:/.../04_RADAR/01_H19"
radar_pattern <- "_H19\\.nc$"
radar_scan_only <- FALSE

# Other catchment rain series built elsewhere, to compare as well (optional), such as
# other_rain_files <- c(multiquadric_ea = "rain_multiquadric.csv", radar = "rain_h19.csv")
other_rain_files <- c()

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
gauge_names <- as.character(gauges$name)
built_names <- c("thiessen", "equal", "equal_all", "multiquadric", "h19")
clash <- intersect(c(gauge_names, names(other_rain_files)), built_names)
if (length(clash) || anyDuplicated(c(gauge_names, names(other_rain_files)))) {
  stop("Give each gauge and other series a name of its own, not one of ",
       toString(built_names), ".", call. = FALSE)
}
if (length(setdiff(names(thiessen_weights), gauge_names))) {
  stop("thiessen_weights names gauges not in the gauges table: ",
       toString(setdiff(names(thiessen_weights), gauge_names)), call. = FALSE)
}
# ---- Download the gauges (gauge_source "hydrology_api") ------------------------------------

# One request at a time, with a pause between them, as the EA asks of Hydrology API users:
# one to find each gauge, then one for each year of its record. Missing readings become gaps;
# other quality flags are counted, not acted on (quality control belongs upstream).
downloads <- NULL
if (identical(gauge_source, "hydrology_api")) {
  if (!requireNamespace("reach.io", quietly = TRUE)) {
    stop("gauge_source \"hydrology_api\" needs the reach.io package: ",
         "remotes::install_github(\"JonPayneEA/reach.io\").", call. = FALSE)
  }
  if (anyNA(gauges$wiski_id) || any(!nzchar(as.character(gauges$wiski_id)))) {
    stop("Give every gauge its wiski_id in the gauges table to download it.", call. = FALSE)
  }
  pause <- function() Sys.sleep(1)
  downloads <- do.call(rbind, lapply(seq_len(nrow(gauges)), function(i) {
    path <- here(gauges$file[i])
    id <- as.character(gauges$wiski_id[i])
    if (file.exists(path) && !is.na(gauges$x[i]) && !is.na(gauges$y[i])) {
      say("  %s (%s): using %s, already downloaded", gauges$name[i], id, basename(path))
      return(data.frame(gauge = gauges$name[i], wiski_id = id, label = NA, measure = NA,
                        readings = NA, missing = NA, flags = NA, file = basename(path)))
    }
    pause()
    found <- reach.io::find_stations(wiski_ids = id)
    rain <- found[found$parameter %in% "rainfall" & found$period %in% "15min", ]
    if (!nrow(rain)) stop("No 15-minute rainfall at WISKI ID ", id, ".", call. = FALSE)
    rain <- rain[order(!grepl("qualified$", rain$measure_notation)), ][1, ]
    if (is.na(gauges$x[i])) gauges$x[i] <<- rain$easting
    if (is.na(gauges$y[i])) gauges$y[i] <<- rain$northing
    if (file.exists(path)) {
      say("  %s (%s): using %s, already downloaded", gauges$name[i], id, basename(path))
      return(data.frame(gauge = gauges$name[i], wiski_id = id, label = rain$label,
                        measure = rain$measure_notation, readings = NA, missing = NA,
                        flags = NA, file = basename(path)))
    }
    chunks <- reach.io::make_date_chunks(download_from, download_to)
    say("  %s (%s, %s): downloading %d year%s", gauges$name[i], id, rain$label, nrow(chunks),
        if (nrow(chunks) == 1) "" else "s")
    readings <- data.table::rbindlist(lapply(seq_len(nrow(chunks)), function(k) {
      pause()
      reach.io::fetch_readings(rain$measure_notation, chunks$chunk_from[k], chunks$chunk_to[k])
    }), fill = TRUE)
    if (!nrow(readings)) stop("No readings for ", id, " in the dates asked.", call. = FALSE)
    value <- as.numeric(readings$value)
    quality <- if ("quality" %in% names(readings)) readings$quality else rep(NA, nrow(readings))
    value[quality %in% "Missing"] <- NA
    data.table::fwrite(data.table::data.table(
      time = format(readings$dateTime, "%Y-%m-%d %H:%M:%S", tz = "UTC"), value = value), path)
    flagged <- table(quality[!quality %in% c("Good", "Missing", NA)])
    data.frame(gauge = gauges$name[i], wiski_id = id, label = rain$label,
               measure = rain$measure_notation, readings = nrow(readings),
               missing = sum(is.na(value)),
               flags = if (length(flagged)) {
                 paste(sprintf("%s %d", names(flagged), as.integer(flagged)), collapse = ", ")
               } else "none", file = basename(path))
  }))
  fwrite(downloads, file.path(output_folder, "gauge_downloads.csv"))
}

inputs <- c(stats::setNames(as.character(gauges$file), gauge_names), other_rain_files)
missing_files <- inputs[!file.exists(here(inputs))]
if (length(missing_files)) {
  stop("Cannot find ", toString(here(missing_files)), ".", call. = FALSE)
}
say("Reading %d rain gauges, %d other series, the flow and the evaporation", length(gauge_names),
    length(other_rain_files))
raw <- c(list(flow = read_hydro_series(here(flow_file)), pe = read_hydro_series(here(pet_file))),
         lapply(inputs, function(f) read_hydro_series(here(f))))
grid <- do.call(align_series, c(raw, list(dt = step_hours)))
flow <- convert_units(grid$flow, "auto", step_hours, "flow")
pe <- fill_gaps(convert_units(grid$pe, "mm_per_step", step_hours, "pet"), "interpolate",
                grid$time, "pe")
as_rain <- function(n) convert_units(grid[[n]], "mm_per_step", step_hours, "rain")
G <- vapply(gauge_names, as_rain, numeric(length(grid$time)))
if (is.null(dim(G))) G <- matrix(G, ncol = 1, dimnames = list(NULL, gauge_names))

# ---- The catchment averages -------------------------------------------------------------------

# A weighted average, renormalised over the gauges reporting at each step, as a weighting
# method does when a gauge is missing: the weights of the missing gauges are shared among the
# rest. A step with no weighted gauge reporting is missing.
weighted_average <- function(w) {
  full <- stats::setNames(rep(0, length(gauge_names)), gauge_names)
  full[names(w)] <- w
  reporting <- !is.na(G)
  share <- as.numeric(reporting %*% full)
  total <- as.numeric(ifelse(reporting, G, 0) %*% full)
  out <- total / share
  out[share <= 0] <- NA
  out
}
inside <- names(thiessen_weights)[thiessen_weights > 0]
weights <- list(thiessen = thiessen_weights,
                equal = stats::setNames(rep(1 / length(inside), length(inside)), inside))
if (length(setdiff(gauge_names, inside))) {
  weights$equal_all <- stats::setNames(rep(1 / length(gauge_names), length(gauge_names)),
                                       gauge_names)
}
built <- lapply(weights, weighted_average)

# Multiquadric: a smooth surface through every gauge, inside the catchment or near it, averaged
# over the cells inside the boundary (pdmS7's merge_rainfall()). Worked out on the wet steps
# only: a step where every reporting gauge is dry has no rain anywhere.
geometry_weights <- NULL
if (!is.null(catchment_boundary)) {
  if (anyNA(gauges$x) || anyNA(gauges$y)) {
    stop("The multiquadric average needs every gauge's x and y in the gauges table.",
         call. = FALSE)
  }
  boundary <- fread(here(catchment_boundary))
  if (!all(c("x", "y") %in% names(boundary))) {
    stop(catchment_boundary, " needs columns x and y.", call. = FALSE)
  }
  say("Multiquadric average over the catchment")
  cells_x <- seq(min(boundary$x) - grid_spacing_m, max(boundary$x) + grid_spacing_m,
                 by = grid_spacing_m)
  cells_y <- seq(min(boundary$y) - grid_spacing_m, max(boundary$y) + grid_spacing_m,
                 by = grid_spacing_m)
  cell_grid <- list(x = cells_x, y = cells_y)
  mask <- catchment_mask(cells_x, cells_y, boundary)
  located <- data.frame(id = gauge_names, x = gauges$x, y = gauges$y)
  wet_steps <- which(rowSums(G > 0, na.rm = TRUE) > 0)
  multiquadric <- ifelse(rowSums(!is.na(G)) > 0, 0, NA_real_)
  fit <- merge_rainfall(located, G[wet_steps, , drop = FALSE], cell_grid, mask,
                        method = "multiquadric")
  multiquadric[wet_steps] <- fit$rain
  built$multiquadric <- multiquadric
  multiquadric_c <- fit$c
  # Thiessen weights from the geometry, to check those given: each gauge's share of the cells
  # inside the boundary that lie nearest to it.
  inside_cells <- which(mask, arr.ind = TRUE)
  cx <- cells_x[inside_cells[, 1]]
  cy <- cells_y[inside_cells[, 2]]
  nearest <- apply(outer(cx, gauges$x, `-`)^2 + outer(cy, gauges$y, `-`)^2, 1, which.min)
  geometry_weights <- stats::setNames(tabulate(nearest, length(gauge_names)) / length(nearest),
                                      gauge_names)
}

# ---- H19 radar ------------------------------------------------------------------------------

# The files' layouts first, from their headers alone: each layout's time stamp, units and grid
# are checked, and each file gets the shift and factor that put it on the same footing (times
# at the start of each step, depths in mm per step). Then the radar is read in a window around
# the catchment and the gauges, one daily file at a time, and kept: a rerun with the same files
# reads nothing.
radar_at_gauges <- NULL
radar_layouts <- NULL
if (!is.null(radar_folder)) {
  say("H19 radar")
  radar_files <- list.files(radar_folder, pattern = radar_pattern, recursive = TRUE,
                            full.names = TRUE)
  if (!length(radar_files)) {
    stop("No files matching ", radar_pattern, " in ", radar_folder, ".", call. = FALSE)
  }
  file_day <- as.Date(substr(basename(radar_files), 1, 8), "%Y%m%d")
  span <- as.Date(range(grid$time))
  radar_files <- radar_files[is.na(file_day) | (file_day >= span[1] - 1 &
                                                  file_day <= span[2] + 1)]
  if (!length(radar_files)) stop("No H19 files fall within the record.", call. = FALSE)
  radar_layouts <- h19_layouts(radar_files)
  print(radar_layouts)
  fwrite(radar_layouts$layouts, file.path(output_folder, "radar_layouts.csv"))
  if (radar_scan_only) {
    say("radar_scan_only is TRUE: layouts written to radar_layouts.csv; stopping here.")
    if (interactive()) invokeRestart("abort") else quit(save = "no")
  }
  bad <- radar_layouts$layouts[nzchar(radar_layouts$layouts$problems), ]
  if (nrow(bad)) {
    stop("H19 layout ", paste(sprintf("%d (%s to %s): %s", bad$layout, bad$first_day,
                                      bad$last_day, bad$problems), collapse = "; "),
         ". See radar_layouts.csv.", call. = FALSE)
  }
  have_boundary <- !is.null(catchment_boundary)
  have_positions <- !anyNA(gauges$x) && !anyNA(gauges$y)
  if (!have_boundary && !have_positions) {
    stop("The radar needs the catchment boundary or the gauges' positions, to know where to ",
         "read.", call. = FALSE)
  }
  if (have_boundary && !exists("boundary")) boundary <- fread(here(catchment_boundary))
  px <- c(if (have_boundary) boundary$x, if (have_positions) gauges$x)
  py <- c(if (have_boundary) boundary$y, if (have_positions) gauges$y)
  extent <- c(min(px) - 3000, max(px) + 3000, min(py) - 3000, max(py) + 3000)
  cache <- file.path(output_folder, "radar_extract.csv")
  cache_files <- file.path(output_folder, "radar_extract_files.txt")
  cached <- file.exists(cache) && file.exists(cache_files) &&
    identical(sort(readLines(cache_files)), sort(radar_files))
  if (cached) {
    say("  using the radar already extracted (%s)", basename(cache))
    extract <- fread(cache)
    extract$time <- as.POSIXct(extract$time, tz = "UTC")
  } else {
    # With the layouts, the reader moves each file's times to the start of their step and puts
    # its values in mm per step, by that file's own layout.
    h <- h19_radar(radar_files, extent, layouts = radar_layouts)
    in_catchment <- if (have_boundary) catchment_mask(h$grid$x, h$grid$y, boundary)
    # The 3 x 3 cells around each gauge: a gauge and the cell it sits in rarely line up.
    near <- if (have_positions) {
      lapply(seq_len(nrow(gauges)), function(k) {
        i <- which.min(abs(h$grid$x - gauges$x[k]))
        j <- which.min(abs(h$grid$y - gauges$y[k]))
        list(i = max(1, i - 1):min(length(h$grid$x), i + 1),
             j = max(1, j - 1):min(length(h$grid$y), j + 1))
      })
    }
    say("  reading %d steps from %d files", length(h$time), length(radar_files))
    values <- t(vapply(seq_along(h$time), function(s) {
      r <- h$radar(s)
      r[r < 0] <- NA
      catchment <- if (have_boundary) {
        inside <- r[in_catchment]
        if (mean(is.na(inside)) > 0.1) NA_real_ else mean(inside, na.rm = TRUE)
      } else {
        NA_real_
      }
      at_gauges <- if (have_positions) {
        vapply(near, function(n) mean(r[n$i, n$j], na.rm = TRUE), numeric(1))
      } else {
        rep(NA_real_, length(gauge_names))
      }
      c(catchment, at_gauges)
    }, numeric(1 + length(gauge_names))))
    extract <- data.table(time = h$time, values)
    setnames(extract, c("time", "h19", paste0("radar_at_", gauge_names)))
    fwrite(extract[, time := format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC")], cache)
    extract$time <- as.POSIXct(extract$time, tz = "UTC")
    writeLines(radar_files, cache_files)
  }
  # Onto the record's steps: 15-minute radar summed into longer steps when step_hours is
  # longer, a step counting only when all its quarter hours are present.
  bucket <- floor(as.numeric(extract$time) / (step_hours * 3600))
  per_step <- 4 * step_hours
  onto_grid <- function(v) {
    total <- tapply(v, bucket, function(x) if (sum(!is.na(x)) == per_step) sum(x) else NA)
    out <- rep(NA_real_, length(grid$time))
    k <- match(floor(as.numeric(grid$time) / (step_hours * 3600)), as.numeric(names(total)))
    out[!is.na(k)] <- total[k[!is.na(k)]]
    out
  }
  if (have_boundary) built$h19 <- onto_grid(extract$h19)
  if (have_positions) {
    radar_at_gauges <- vapply(gauge_names, function(n) onto_grid(extract[[paste0("radar_at_",
                                                                                 n)]]),
                              numeric(length(grid$time)))
  }
}

# Write the averages out, ready for calibrate_site.R.
dir.create(file.path(output_folder, "catchment_rain"), showWarnings = FALSE)
for (n in names(built)) {
  fwrite(data.table(time = format(grid$time, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                    value = round(built[[n]], 4)),
         file.path(output_folder, "catchment_rain", paste0(n, ".csv")))
}

rains <- c(built, lapply(stats::setNames(gauge_names, gauge_names), function(n) G[, n]),
           lapply(stats::setNames(names(other_rain_files), names(other_rain_files)), as_rain))
names_r <- names(rains)
gauge_series <- gauge_names
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

# ---- 6. Weights -------------------------------------------------------------------------

# How much of one gauge's random error survives into a weighted average. With weights w that
# add up to 1 and independent gauge errors of the same size, the average's error is the single
# gauge's error times sqrt(sum(w^2)), and 1 / sum(w^2) is the effective number of gauges: how
# many equal, independent gauges the average is worth. Weights that add up to something else
# (a method that also scales the rain) are divided by their sum first, so the effective number
# is sum(w)^2 / sum(w^2) and the error is relative to the average's own level. Errors the
# gauges share (wind on all of them) do not cancel: with a correlation rho between gauges'
# errors the factor becomes sqrt((1 - rho) sum(w^2) + rho).
weights_done <- FALSE
if (length(gauge_series) > 1) {
  say("Weights and the effective number of gauges")
  unknown <- setdiff(gauge_series, names_r)
  if (length(unknown)) {
    stop("gauge_series names series not in rain_files: ", toString(unknown), call. = FALSE)
  }
  averages <- setdiff(names_r, c(gauge_series, "h19"))
  G <- as.matrix(as.data.frame(rains[gauge_series]))
  given <- weights[intersect(names(weights), averages)]
  for (n in names(given)) {
    bad <- setdiff(names(given[[n]]), gauge_series)
    if (length(bad)) {
      stop("The weights for ", n, " name gauges not in gauge_series: ", toString(bad),
           call. = FALSE)
    }
  }
  # Weights not given are estimated: the average regressed on the gauges, with no intercept,
  # over wet steps where every gauge and the average have a value. A linear method with steady
  # weights fits closely (R2 near 1); a poor fit means the weights change over time, or the
  # method is not a weighted sum of these gauges (radar merging, say).
  fit_weights <- function(n) {
    y <- rains[[n]]
    ok <- stats::complete.cases(G) & is.finite(y) & (rowSums(G) > 0 | y > 0)
    fit <- stats::lm.fit(G[ok, , drop = FALSE], y[ok])
    w <- stats::setNames(as.numeric(fit$coefficients), gauge_series)
    w[!is.finite(w)] <- 0
    r2 <- 1 - sum(fit$residuals^2) / sum((y[ok] - mean(y[ok]))^2)
    list(weights = w, r2 = r2)
  }
  weight_sets <- list()
  fit_r2 <- list()
  for (n in averages) {
    if (n %in% names(given)) {
      w <- stats::setNames(rep(0, length(gauge_series)), gauge_series)
      w[names(given[[n]])] <- given[[n]]
      weight_sets[[n]] <- w
    } else {
      f <- fit_weights(n)
      weight_sets[[n]] <- f$weights
      fit_r2[[n]] <- f$r2
    }
  }

  # The single-gauge error, from the gauges' own disagreement. For two gauges with the same
  # random error s, the spread of their relative difference over the same floods is about
  # s x sqrt(2). Real differences in rain between the two sites add to that spread, so this is
  # an upper limit on s. Floods where both gauges saw at least 1 mm.
  pairs <- utils::combn(gauge_series, 2, simplify = FALSE)
  pair_error <- do.call(rbind, lapply(pairs, function(p) {
    a <- event_rain[, match(p[1], names_r)]
    b <- event_rain[, match(p[2], names_r)]
    k <- is.finite(a) & is.finite(b) & a >= 1 & b >= 1
    d <- (a[k] - b[k]) / ((a[k] + b[k]) / 2)
    data.frame(gauges = paste(p, collapse = " and "), floods = sum(k),
               single_gauge_error_pct = round(100 * stats::sd(d) / sqrt(2), 1))
  }))
  sigma <- stats::median(pair_error$single_gauge_error_pct, na.rm = TRUE)
  fwrite(pair_error, file.path(output_folder, "gauge_pair_error.csv"))

  # Through time: at each step, the weights renormalised over the gauges reporting, as a
  # weighting method does when a gauge is missing.
  available <- !is.na(G)
  n_eff_series <- lapply(weight_sets, function(w) {
    wa <- sweep(available, 2, w, `*`)
    s <- rowSums(wa)
    out <- s^2 / rowSums(wa^2)
    out[!is.finite(out) | s <= 0] <- NA
    out
  })
  largest <- utils::head(order(-floods$peak_flow), 20)
  low_in_flood <- vapply(n_eff_series, function(ne) {
    lows <- vapply(largest, function(e) {
      w <- floods$rain_start[e]:floods$rain_end[e]
      if (all(is.na(ne[w]))) NA else min(ne[w], na.rm = TRUE) < 1.5
    }, logical(1))
    sum(lows, na.rm = TRUE)
  }, numeric(1))

  weights_table <- do.call(rbind, lapply(names(weight_sets), function(n) {
    w <- weight_sets[[n]]
    s2 <- sum((w / sum(w))^2)
    data.frame(
      rain = n,
      weights = paste(sprintf("%s %.3f", names(w)[w != 0], w[w != 0]), collapse = ", "),
      source = if (n == "thiessen") "given" else if (n %in% c("equal", "equal_all")) "equal" else
        if (n %in% names(given)) "given" else sprintf("estimated, R2 %.3f", fit_r2[[n]]),
      weights_sum = round(sum(w), 3),
      sum_of_squares = round(s2, 3),
      effective_gauges = round(1 / s2, 2),
      error_factor = round(sqrt(s2), 2),
      error_factor_rho_0.3 = round(sqrt(0.7 * s2 + 0.3), 2),
      error_factor_rho_0.5 = round(sqrt(0.5 * s2 + 0.5), 2),
      suggested_rain_error = round(sigma / 100 * sqrt(s2), 3),
      effective_gauges_p05 = round(stats::quantile(n_eff_series[[n]], 0.05, na.rm = TRUE), 2),
      largest_floods_below_1.5 = as.integer(low_in_flood[[n]]))
  }))
  fwrite(weights_table, file.path(output_folder, "weights_and_error.csv"))
  weights_done <- TRUE

  # HOW TO READ effective_gauges_over_time.png
  # One line per catchment average: how many gauges' worth of independent rain it used, day by
  # day (the lowest value in each day). Flat at its full value when every gauge reports; it
  # drops when a gauge is missing and the average leans on the rest. Grey ticks along the top
  # mark the 20 largest floods. The dashed line is 1.5, below which the average is effectively
  # one gauge.
  # Good: lines flat at their full value, with few and short dips, none of them during the
  #   large floods.
  # Worry if: a line sits below 1.5 even when every gauge reports (the weighting rests on one
  #   gauge: its faults go straight into the catchment rain); long dips (gauges missing for
  #   weeks); dips under the flood ticks (those floods' rain rests on fewer gauges, so their
  #   scores in calibration are less to be trusted).
  png_of("effective_gauges_over_time.png", function() {
    day <- as.Date(grid$time)
    daily <- lapply(n_eff_series, function(ne) {
      suppressWarnings(tapply(ne, day, min, na.rm = TRUE))
    })
    days <- as.Date(names(daily[[1]]))
    top <- max(c(1.5, unlist(daily)[is.finite(unlist(daily))])) * 1.15
    graphics::par(mar = c(4, 4.5, 2, 1))
    graphics::plot(range(days), c(0, top), type = "n", xlab = "",
                   ylab = "Effective number of gauges",
                   main = "How many gauges each catchment average used, day by day")
    graphics::abline(h = 1.5, lty = 2, col = "grey50")
    for (i in seq_along(daily)) {
      v <- daily[[i]]
      v[!is.finite(v)] <- NA
      graphics::lines(days, v, col = colours[match(names(daily)[i], names_r)], lwd = 2)
    }
    graphics::rug(as.Date(grid$time[floods$rain_start[largest]]), side = 3, col = "grey40",
                  lwd = 2)
    graphics::legend("bottomleft", names(daily), bty = "n", lwd = 2,
                     col = colours[match(names(daily), names_r)])
  })
}

# ---- 7. Radar against the gauges ----------------------------------------------------------

# The radar sees the rain aloft and does not lose it to wind at the gauge's rim; the gauge
# does. Day by day, at each gauge, the radar's total over the gauge against the gauge's own:
# days complete in both, with at least 1 mm in both. The radar has errors of its own (range,
# beam height, bright band), which change little from month to month; a gauge's wind loss is
# larger in winter. So a ratio that rises in winter points to the gauge catching less, and a
# ratio away from 1 all year points to the radar's own scaling.
radar_done <- FALSE
if (!is.null(radar_at_gauges)) {
  say("Radar against the gauges")
  day <- as.Date(grid$time)
  steps_a_day <- 24 / step_hours
  daily <- function(v) {
    total <- tapply(v, day, function(x) if (sum(!is.na(x)) == steps_a_day) sum(x) else NA)
    stats::setNames(as.numeric(total), names(total))
  }
  pairs_rg <- do.call(rbind, lapply(gauge_names, function(n) {
    g <- daily(G[, n])
    r <- daily(radar_at_gauges[, n])
    ok <- is.finite(g) & is.finite(r) & g >= 1 & r >= 1
    if (!any(ok)) return(NULL)
    d <- as.Date(names(g)[ok])
    data.frame(gauge = n, day = d, month = as.integer(format(d, "%m")),
               gauge_mm = g[ok], radar_mm = r[ok], ratio = r[ok] / g[ok])
  }))
  if (!is.null(pairs_rg) && nrow(pairs_rg)) {
    season_of <- c("Winter", "Winter", "Spring", "Spring", "Spring", "Summer", "Summer",
                   "Summer", "Autumn", "Autumn", "Autumn", "Winter")
    pairs_rg$season <- season_of[pairs_rg$month]
    radar_table <- do.call(rbind, lapply(split(pairs_rg, pairs_rg$gauge), function(p) {
      s <- tapply(p$ratio, p$season, stats::median)
      data.frame(gauge = p$gauge[1], days = nrow(p),
                 ratio_all = round(stats::median(p$ratio), 2),
                 ratio_winter = round(unname(s["Winter"]), 2),
                 ratio_spring = round(unname(s["Spring"]), 2),
                 ratio_summer = round(unname(s["Summer"]), 2),
                 ratio_autumn = round(unname(s["Autumn"]), 2))
    }))
    radar_table <- radar_table[match(gauge_names, radar_table$gauge), ]
    radar_table <- radar_table[!is.na(radar_table$gauge), ]
    radar_table$winter_over_summer <- round(radar_table$ratio_winter /
                                              radar_table$ratio_summer, 2)
    fwrite(radar_table, file.path(output_folder, "radar_vs_gauges.csv"))
    fwrite(pairs_rg, file.path(output_folder, "radar_vs_gauges_daily.csv"))
    radar_done <- TRUE
    # HOW TO READ radar_vs_gauge_by_month.png
    # One line per gauge: in each calendar month, the median of the radar's daily total over
    # the gauge divided by the gauge's own, over days with at least 1 mm in both. The line at 1
    # is where they agree. October to September, as the water year runs.
    # What it shows: a line above 1 means the radar saw more rain than the gauge caught.
    # Good: lines close to 1 and flat through the year.
    # Worry if: a line rises in the winter months and falls in summer. Gauges lose more rain to
    #   wind in winter (stronger winds, lighter rain, snow), so a winter rise points to the
    #   gauge under-catching. A line away from 1 by the same amount all year is more likely the
    #   radar's own scaling. One gauge apart from the rest points to that gauge's exposure or
    #   siting. Months with few rain days are noisy: radar_vs_gauges_daily.csv has the days.
    png_of("radar_vs_gauge_by_month.png", function() {
      months <- c(10:12, 1:9)
      by_month <- vapply(gauge_names, function(n) {
        p <- pairs_rg[pairs_rg$gauge == n, ]
        vapply(months, function(m) {
          x <- p$ratio[p$month == m]
          if (length(x) >= 3) stats::median(x) else NA_real_
        }, numeric(1))
      }, numeric(12))
      graphics::par(mar = c(4, 4.5, 2, 1))
      top <- max(c(1.5, by_month), na.rm = TRUE) * 1.1
      graphics::matplot(seq_along(months), by_month, type = "b", pch = 19, lty = 1, lwd = 2,
                        col = colours[match(gauge_names, names_r)], xaxt = "n", xlab = "",
                        ylim = c(0, top), ylab = "Radar / gauge, daily totals (median)",
                        main = "Radar against each gauge, month by month")
      graphics::axis(1, at = seq_along(months), labels = month.abb[months])
      graphics::abline(h = 1, lty = 2, col = "grey50")
      graphics::legend("top", gauge_names, col = colours[match(gauge_names, names_r)],
                       lwd = 2, pch = 19, bty = "n", ncol = min(5, length(gauge_names)))
    })
  }
}

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
  "", "## The catchment averages built", "",
  sprintf("- **%s**: %s.", names(weights), vapply(names(weights), function(n) {
    w <- weights[[n]]
    paste(sprintf("%s %.3f", names(w), w), collapse = ", ")
  }, "")),
  if (!is.null(catchment_boundary)) {
    c(sprintf(paste("- **multiquadric**: every gauge, on a %g m grid, shape parameter c = %.0f m",
                    "(chosen by leaving out one gauge at a time)."), grid_spacing_m,
              multiquadric_c),
      "", sprintf("Thiessen weights from the gauge positions and the boundary: %s. Given: %s.",
                  paste(sprintf("%s %.3f", names(geometry_weights), geometry_weights),
                        collapse = ", "),
                  paste(sprintf("%s %.3f", names(thiessen_weights), thiessen_weights),
                        collapse = ", ")),
      if (max(abs(geometry_weights[names(thiessen_weights)] - thiessen_weights)) > 0.05) {
        paste("**They differ by more than 0.05.** Check the gauge positions, the boundary,",
              "and how the given weights were made.")
      })
  } else {
    "- multiquadric: not built (no catchment_boundary given)."
  },
  "", "Each is in `catchment_rain/`, as a CSV ready for calibrate_site.R.",
  if (!is.null(downloads)) {
    c("", sprintf(paste("Gauges downloaded from the EA Hydrology API with reach.io, %s to %s",
                        "(`gauge_downloads.csv`):"), download_from, download_to), "",
      sprintf("- %s: WISKI ID %s%s", downloads$gauge, downloads$wiski_id,
              ifelse(is.na(downloads$readings), ", already downloaded.",
                     sprintf(" (%s), %d readings, %d missing; other flags: %s.", downloads$label,
                             downloads$readings, downloads$missing, downloads$flags))), "",
      "Readings flagged Missing are gaps. Other flags (Suspect, Estimated, Unchecked) are kept",
      "and only counted here: quality control belongs upstream, in reach.validate.")
  },
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
  if (weights_done) {
    c("", "## Weights: how many gauges each average uses", "",
      sprintf(paste("A single gauge's storm totals look to be up to %.0f%% out, from how much",
                    "the gauges disagree flood by flood (an upper limit: real differences in"),
              sigma),
      "rain between sites count too). How much of that survives into each average:", "",
      sprintf(paste("- **%s**, weights %s (%s): worth %.1f gauges; it keeps %.0f%% of a single",
                    "gauge's random error, so about %.1f%% storm error. Suggested rain_error",
                    "%.3f. Through the record it fell to %.1f gauges' worth or less 5%% of the",
                    "time; %d of the 20 largest floods fell while it was below 1.5."),
              weights_table$rain, weights_table$weights, weights_table$source,
              weights_table$effective_gauges, 100 * weights_table$error_factor,
              sigma * weights_table$error_factor, weights_table$suggested_rain_error,
              weights_table$effective_gauges_p05, weights_table$largest_floods_below_1.5),
      if (any(abs(weights_table$weights_sum - 1) > 0.02)) {
        sprintf(paste("- Weights for %s do not add up to 1: the method scales the rain as",
                      "well as weighting it. The balance checks will see the scaling."),
                toString(weights_table$rain[abs(weights_table$weights_sum - 1) > 0.02]))
      },
      if (length(fit_r2) && any(unlist(fit_r2) < 0.95)) {
        sprintf(paste("- The estimated weights for %s fit poorly (R2 below 0.95): the method",
                      "is not a fixed weighting of these gauges, so read its figures with care."),
                toString(names(fit_r2)[unlist(fit_r2) < 0.95]))
      },
      "- If gauges' errors are partly shared (wind on all of them), less cancels: see the",
      "  error_factor_rho columns in `weights_and_error.csv`.")
  },
  if (!is.null(radar_layouts)) {
    l <- radar_layouts$layouts
    c("", "## H19 radar", "",
      sprintf("%d files in %d layout%s (`radar_layouts.csv`):", sum(l$files), nrow(l),
              if (nrow(l) == 1) "" else "s"),
      sprintf(paste("- Layout %d, %d files, %s to %s: `%s` in %s, stamped at the %s of each",
                    "step%s."), l$layout, l$files, l$first_day, l$last_day, l$variable,
              l$units, l$stamp,
              ifelse(l$stamp == "end", " (moved back 15 minutes)", "")),
      "",
      if (radar_done) {
        c("The radar over each gauge against the gauge, daily totals (`radar_vs_gauges.csv`):",
          "",
          sprintf(paste("- **%s**: radar / gauge %.2f over %d days; winter %.2f, summer %.2f",
                        "(winter over summer %.2f)."), radar_table$gauge,
                  radar_table$ratio_all, radar_table$days, radar_table$ratio_winter,
                  radar_table$ratio_summer, radar_table$winter_over_summer),
          "",
          paste("A winter ratio clearly above the summer one points to the gauge losing rain",
                "to wind; the same ratio all year points to the radar's own scaling. Wind",
                "speed would separate them further."))
      },
      "", "H19 and everything made from it are restricted: keep this folder on restricted",
      "storage.")
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
  "`flood_runoff_ratios.png`.",
  if (weights_done) {
    paste("Weights: `weights_and_error.csv`, `gauge_pair_error.csv`,",
          "`effective_gauges_over_time.png`.")
  },
  if (radar_done) {
    paste("Radar: `radar_layouts.csv`, `radar_vs_gauges.csv`, `radar_vs_gauges_daily.csv`,",
          "`radar_vs_gauge_by_month.png`.")
  })
writeLines(lines, file.path(output_folder, "summary.md"))
print(ranking[, c("rain", "mean_rank", "runoff_ratio", "total_apart_pct", "response_r",
                  "lag_h", "flood_wins", "missed_storms_pct", "flood_ratio_spread")],
      row.names = FALSE)
if (weights_done) {
  print(weights_table[, c("rain", "source", "effective_gauges", "error_factor",
                          "suggested_rain_error")], row.names = FALSE)
}
say("\nWritten to %s. Read summary.md.", normalizePath(output_folder))
