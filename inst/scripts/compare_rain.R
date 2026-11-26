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
# Modified:     2026-11-26 - laid out one argument a line, with in-line comments
#               2026-11-26 - multiquadric scaled by a long-term average grid; the check
#               against it
#               2026-11-25 - H19 from the team's processed yearly extracts, in seconds
#               2026-11-25 - the gauges found by a search around the catchment's centroid
#               and downloaded with reach.io by default; the boundary from a shapefile;
#               Thiessen weights from the geometry when none are given
# Inputs:       The catchment boundary (a shapefile, GeoPackage or CSV of x and y); CSV files
#               of flow (m3/s) and potential evaporation, each a date-time column and a value
#               column; the rain gauges found and downloaded from the EA Hydrology API with
#               reach.io, or CSV files of your own; optionally Thiessen weights and other
#               catchment series
# Outputs:      A folder: summary.md, rain_ranking.csv, weights_and_error.csv, plots each with a
#               note on how to read it, and catchment_rain/ with each average built, as CSV
#               ready for calibrate_site.R
# Dependencies: pdmS7 (0.44.0 or later); sf for a shapefile and the search; reach.io
#               to find and download the gauges; arrow (or nanoparquet) for the processed
#               H19 extracts, ncdf4 for the daily H19 files
# ============================================================ #
#
# How to use it
#   1. Copy the script to your own folder, so you can fill in its settings:
#        file.copy(system.file("scripts", "compare_rain.R", package = "pdmS7"), "compare_rain.R")
#        file.edit("compare_rain.R")
#   2. Fill in the settings below: the catchment area, the time step, the flow and evaporation
#      files, and the catchment boundary (a shapefile is fine).
#   3. Run the whole script (Ctrl+Shift+S in RStudio). The first run searches the EA Hydrology
#      API for 15-minute rain gauges around the catchment, lists them in nearby_gauges.csv
#      with a map, nearby_gauges.png, and stops.
#   4. Choose the gauges from the list, put their WISKI IDs in gauge_ids, and run again. Their
#      rain is downloaded and the comparison runs. It takes a minute or two after the download.
#   5. Read summary.md in the output folder.
#   With gauge files of your own instead, set gauge_source to "files" and fill in the gauges
#   table.
#
# What it does
#   First it builds the catchment averages from the gauges:
#     thiessen      the Thiessen weights given, or worked out from the gauges' positions and
#                   the boundary when none are given;
#     equal         the same gauges, weighted equally;
#     equal_all     every gauge listed, inside the catchment or not, weighted equally (only
#                   when some gauge has no Thiessen weight);
#     multiquadric  a smooth surface through every gauge, averaged over the catchment (with the
#                   positions and the boundary): the gauges only;
#     multiquadric_lta  the same, fitted to each gauge's rain as a share of its long-term
#                   average and scaled back by the grid (with lta_rain_file);
#     multiquadric_h19  the same surface through the gauges, with the radar's pattern between
#                   them (conditional merging): with H19 from radar_folder, at 15-minute steps.
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

# The catchment boundary: a shapefile (.shp, with its .dbf, .shx and .prj beside it), a
# GeoPackage, or a CSV with columns x and y, in data_folder. A shapefile is moved onto British
# National Grid. Its centroid is the centre of the gauge search, and it bounds the averages.
catchment_boundary <- "catchment.shp"
# The averaging grid, not the catchment's delineation: the spacing of the points over the
# catchment where the surfaces (idw, the multiquadrics) are worked out and averaged. 500 m
# suits most catchments, 250 m one under about 20 km2; finer gains nothing (the gauges are
# kilometres apart) and is much slower.
grid_spacing_m <- 500

# A long-term average rainfall grid (optional): NetCDF in data_folder, on British National Grid,
# mm a year, such as the Met Office's HadUK-Grid average for 1991 to 2020,
# "rainfall_hadukgrid_uk_1km_ann-30y_199101-202012.nc". With it, the multiquadric is also fitted
# to each gauge's rain as a share of its long-term average and scaled back by the grid
# (multiquadric_lta), and each series' annual rain is set against the long-term average.
lta_rain_file <- NULL

# Correcting the gauges to the long-term average (optional; needs lta_rain_file). Each gauge's
# average year over a long record, correction_from to correction_to, set against the grid at
# the gauge, gives the gauge a factor, which then scales its rain over the period compared.
#   "relative": each factor divided by the gauges' median factor, so the gauges keep their
#               overall level and only how they differ from each other is corrected; the long
#               record's own weather, wetter or drier than the grid's years, cancels.
#   "absolute": each gauge put onto the grid's own level.
#   "none":     the gauges as measured.
# The gauge downloads cover both the correction record and the period compared.
lta_correction <- "none"
correction_from <- "2010-10-01"
correction_to <- "2024-10-01"

# The period compared: from (inclusive) to (exclusive), in UTC. Every series (flow,
# evaporation, gauges, radar) is cut to it, and gauges are downloaded for it. A series that does
# not cover the whole period is padded with gaps, with a warning.
period_from <- "2015-10-01"
period_to <- "2024-10-01"
# The years the water balance and its plots are counted in: 1 for calendar years (January to
# December, as H19 is stored), 10 for water years (October to September).
year_start_month <- 1

# The rain gauges, from the EA Hydrology API with reach.io (gauge_source "hydrology_api").
#   1. Leave gauge_ids empty and run: every 15-minute rain gauge within search_radius_km of
#      the catchment's centroid is listed in nearby_gauges.csv, nearest the catchment first,
#      with a map, and the script stops.
#   2. Put the WISKI IDs you choose in gauge_ids and run again: each gauge's rain is downloaded
#      to data_folder (a file already there is used as it is; delete it to download again).
# search_radius_km NULL searches from the centroid to the boundary's farthest point, plus
# 10 km. The downloads cover period_from to period_to.
gauge_source <- "hydrology_api"
search_radius_km <- NULL
gauge_ids <- c()               # such as c("254336TP", "SS92F014")

# Gauge files of your own instead (gauge_source "files"): one file each, rain in mm per step,
# in data_folder. x and y are each gauge's position in metres on British National Grid, for
# the multiquadric average and the Thiessen weights from the geometry.
gauges <- data.frame(
  name = c("gauge_A", "gauge_B", "gauge_C"),
  file = c("gauge_a.csv", "gauge_b.csv", "gauge_c.csv"),
  x = c(NA, NA, NA),
  y = c(NA, NA, NA)
)

# Thiessen weights, if you have the operational ones: each gauge's share of the catchment, by
# the gauge's WISKI ID or its name, adding up to 1; a gauge outside the catchment has none.
# Left empty, they are worked out from the gauges' positions and the boundary.
thiessen_weights <- c()        # such as c("254336TP" = 0.264, SS92F014 = 0.737)

# The catchment averages to build: delete any you do not want. One whose inputs are missing is
# skipped, and the summary and the report say why.
#   thiessen          the Thiessen weights (given, or from the gauges' positions)
#   equal             the gauges with a Thiessen weight, weighted equally
#   equal_all         every gauge weighted equally (when some gauge has no Thiessen weight)
#   idw               inverse distance weighting over the catchment (boundary, positions)
#   multiquadric      a smooth surface through the gauges (boundary, positions)
#   multiquadric_lta  the same, shaped by the long-term average (lta_rain_file)
#   h19               the radar alone (radar_folder or radar_processed_folder)
#   h19_bias          the radar scaled day by day to the gauges (radar_folder, positions)
#   multiquadric_h19  the gauges' surface with the radar's pattern (radar_folder, 15 minutes)
rain_methods <- c("thiessen", "equal", "equal_all", "idw", "multiquadric", "multiquadric_lta",
                  "h19", "h19_bias", "multiquadric_h19")

# H19 radar (optional): the folder of daily H19 NetCDF files, with a folder for each year.
# The files' layouts are checked first (the archive changed how it saved them part way
# through): set radar_scan_only to TRUE to see them and stop. Then the radar over the catchment
# joins the comparison as "h19" (with a boundary), and the radar over each gauge is set against
# the gauge (with the gauges' positions). H19 is restricted: keep the output folder on
# restricted storage, as the radar extracts are written there.
radar_folder <- NULL           # such as "C:/.../04_RADAR/01_H19"
# H19 file names: the date and time (14 digits), anything, then .nc: both the older
# ..._1km_H19.nc names and the newer 20210401000000.nc.
radar_pattern <- "^[0-9]{14}.*\\.nc$"
radar_scan_only <- FALSE
# Much faster, for a catchment Hyrad already has: the team's yearly H19 extracts for every
# current PDM polygon (the archive's Processed_Annual folder, H19_YYYY_all_polygons.parquet,
# made by the ProcessingNetCDF scripts). Give the folder and the polygon's ID in Hyrad, and
# the catchment average is read in seconds, not hours. Leave radar_folder NULL then, unless
# you also want the radar over each gauge: that still reads every daily file.
radar_processed_folder <- NULL # such as "F:/.../04_RADAR/01_H19/Processed_Annual"
radar_polygon_id <- NULL       # such as "02_10_Southern"

# Other catchment rain series built elsewhere, to compare as well (optional), such as
# other_rain_files <- c(multiquadric_ea = "rain_multiquadric.csv", radar = "rain_h19.csv")
other_rain_files <- c()

# ---- Read and line up the data ------------------------------------------------------------

# A message to the console, with sprintf()'s formatting.
say <- function(...) cat(sprintf(...), "\n", sep = "")

# The area is left blank in the settings, so the script cannot run on a wrong default.
if (!is.numeric(area_km2) || !is.finite(area_km2) || area_km2 <= 0) {
  stop("Fill in area_km2 at the top of the script: the catchment area in km2.",
       call. = FALSE)
}
if (!dir.exists(data_folder)) {
  stop("No folder ",
       normalizePath(data_folder, mustWork = FALSE),
       ": set data_folder at the ",
       "top of the script to the folder holding the CSV files.",
       call. = FALSE)
}
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)

# The path of a file in the data folder.
here <- function(f) file.path(data_folder, f)

# Stops a run part way, at a point the settings ask for, without an error.
stop_here <- function(...) {
  say(...)
  if (interactive()) invokeRestart("abort") else quit(save = "no")
}

# ---- The catchment boundary ---------------------------------------------------------------

boundary <- NULL
if (!is.null(catchment_boundary)) {
  if (!file.exists(here(catchment_boundary))) {
    stop("Cannot find the boundary ",
         here(catchment_boundary),
         ". Set catchment_boundary to ",
         "its file name in data_folder, or NULL to do without it.",
         call. = FALSE)
  }
  # The outer ring on British National Grid, with its centroid and area as attributes.
  boundary <- read_boundary(here(catchment_boundary))
  centroid <- attr(boundary, "centroid")
  say("Catchment boundary: %.1f km2, centroid %.0f, %.0f",
      attr(boundary, "area_km2"),
      centroid[["x"]],
      centroid[["y"]])
  # A boundary far from the area given is probably another catchment's, or the area is wrong.
  if (abs(attr(boundary, "area_km2") / area_km2 - 1) > 0.05) {
    warning(sprintf(paste("The boundary encloses %.1f km2, but area_km2 is %g: check that the",
                          "boundary is this catchment's, and the area."),
                    attr(boundary, "area_km2"),
                    area_km2),
            call. = FALSE)
  }
}

# ---- The rain gauges: found and downloaded (gauge_source "hydrology_api") --------------------

# One request at a time, with a pause between them, as the EA asks of Hydrology API users.
downloads <- NULL
nearby_file <- file.path(output_folder, "nearby_gauges.csv")

# A gauge's name in the tables and plots: its station name, made short and safe (lower case,
# underscores, never starting with a digit, and never the same as another's).
name_of <- function(label) {
  n <- gsub("^_+|_+$", "", gsub("[^a-z0-9]+", "_", tolower(label)))
  n <- ifelse(nzchar(n) & !grepl("^[0-9]", n), n, paste0("gauge_", n))
  make.unique(n, sep = "_")
}

if (identical(gauge_source, "hydrology_api")) {
  if (!requireNamespace("reach.io", quietly = TRUE)) {
    stop("gauge_source \"hydrology_api\" needs the reach.io package: ",
         "remotes::install_github(\"JonPayneEA/reach.io\").",
         call. = FALSE)
  }
  pause <- function() Sys.sleep(1)

  # The 15-minute rain measure of each station found, the qualified one first where there are
  # two.
  rain_measures <- function(found) {
    rain <- as.data.frame(found)[found$parameter %in% "rainfall" & found$period %in% "15min", ]
    rain <- rain[order(rain$notation, !grepl("qualified$", rain$measure_notation)), ]
    rain[!duplicated(rain$notation), ]
  }

  if (!length(gauge_ids)) {
    # The search: every 15-minute rain gauge within the radius of the centroid.
    if (is.null(boundary)) {
      stop("The gauge search needs the catchment boundary: set catchment_boundary, or list ",
           "the gauges in gauge_ids.",
           call. = FALSE)
    }
    if (!requireNamespace("sf", quietly = TRUE)) {
      stop("The gauge search needs the sf package: install.packages(\"sf\").",
           call. = FALSE)
    }

    # By default, the radius reaches the boundary's farthest point from the centroid, plus
    # 10 km: a fixed radius would miss gauges beyond the far end of a long catchment.
    reach_km <- max(sqrt((boundary$x - centroid[["x"]])^2 +
                           (boundary$y - centroid[["y"]])^2)) / 1000
    radius <- if (is.null(search_radius_km)) ceiling(reach_km + 10) else search_radius_km

    # The API searches by latitude and longitude, so the centroid is moved off the grid.
    lonlat <- sf::st_coordinates(sf::st_transform(sf::st_sfc(sf::st_point(unname(centroid)),
                                                             crs = 27700),
                                                  4326))
    say("Searching for 15-minute rain gauges within %g km of the centroid", radius)
    rain <- rain_measures(reach.io::find_stations(lat = lonlat[1, "Y"],
                                                  long = lonlat[1, "X"],
                                                  dist = radius))
    # Gauges are chosen and downloaded by WISKI ID, so a station without one is left out.
    rain <- rain[!is.na(rain$wiskiID) & nzchar(rain$wiskiID), ]
    if (!nrow(rain)) {
      stop("No 15-minute rain gauges with a WISKI ID within ",
           radius,
           " km. Set ",
           "search_radius_km larger.",
           call. = FALSE)
    }

    # Each gauge's place: inside or how far outside the boundary, and how far from the
    # centroid. The list is sorted nearest the catchment first.
    x <- as.numeric(rain$easting)
    y <- as.numeric(rain$northing)
    outside <- distance_to_boundary(x, y, boundary) / 1000
    nearby <- data.frame(
      wiski_id = rain$wiskiID,
      label = rain$label,
      name = name_of(rain$label),
      x = x,
      y = y,
      inside = outside == 0,
      km_outside = round(outside, 1),
      km_from_centroid = round(sqrt((x - centroid[["x"]])^2 + (y - centroid[["y"]])^2) / 1000,
                               1),
      measure = rain$measure_notation
    )
    nearby <- nearby[order(nearby$km_outside, nearby$km_from_centroid), ]
    fwrite(nearby, nearby_file)

    # HOW TO READ nearby_gauges.png
    # The catchment (outlined), its centroid (cross), the search circle (dashed), and every
    # 15-minute rain gauge the EA Hydrology API lists inside it: filled inside the catchment,
    # open outside, each with its WISKI ID. The rings are 5 and 10 km out from the boundary.
    # Good: several gauges inside the catchment, spread across it, and a few just outside on
    #   each side, which steady the multiquadric average at the edges.
    # Worry if: no gauge inside, or all of them bunched in one corner (the average will lean
    #   on the gauges outside: choose those on the sides storms come from); a gauge far from
    #   the rest on high ground (it may see a different climate). Gauges more than 10 km out
    #   rarely add anything. The API lists EA gauges only: a gap here may not be a gap on the
    #   ground.
    grDevices::png(file.path(output_folder, "nearby_gauges.png"),
                   width = 1400,
                   height = 1400,
                   res = 150)
    graphics::par(mar = c(4, 4.5, 2, 1))

    # The search circle first, as it sets the extent of the map.
    circle <- seq(0, 2 * pi, length.out = 200)
    graphics::plot(centroid[["x"]] + 1000 * radius * cos(circle),
                   centroid[["y"]] + 1000 * radius * sin(circle),
                   type = "l",
                   lty = 2,
                   col = "grey50",
                   asp = 1,
                   xlab = "Easting (m)",
                   ylab = "Northing (m)",
                   main = sprintf("Rain gauges within %g km of the centroid", radius))

    # Rings 5 and 10 km out from the boundary, by buffering it.
    ring <- sf::st_sfc(sf::st_polygon(list(as.matrix(rbind(boundary, boundary[1, ])))),
                       crs = 27700)
    for (km in c(5, 10)) {
      xy <- sf::st_coordinates(sf::st_buffer(ring, 1000 * km))
      graphics::lines(xy[, "X"], xy[, "Y"], col = "grey75")
    }

    # The catchment, its centroid, and the gauges (filled inside, open outside).
    graphics::polygon(boundary$x, boundary$y, border = "#B3261E", lwd = 2)
    graphics::points(centroid[["x"]], centroid[["y"]], pch = 3, cex = 1.5, lwd = 2)
    graphics::points(nearby$x,
                     nearby$y,
                     pch = ifelse(nearby$inside, 19, 1),
                     cex = 1.3,
                     col = "#1B6F80",
                     lwd = 2)
    graphics::text(nearby$x, nearby$y, nearby$wiski_id, pos = 3, cex = 0.7)
    graphics::legend("bottomleft",
                     bty = "n",
                     cex = 0.8,
                     c("Catchment", "Centroid", "Gauge inside", "Gauge outside",
                       "5 and 10 km from the boundary", "Search radius"),
                     col = c("#B3261E", "black", "#1B6F80", "#1B6F80", "grey75", "grey50"),
                     pch = c(NA, 3, 19, 1, NA, NA),
                     lty = c(1, NA, NA, NA, 1, 2),
                     lwd = c(2, 2, 2, 2, 1, 1))
    grDevices::dev.off()

    # The list, and a line ready to paste for the gauges inside or within 5 km; then stop, so
    # the gauges can be chosen before anything is downloaded.
    print(nearby[, c("wiski_id", "label", "inside", "km_outside", "km_from_centroid")],
          row.names = FALSE)
    near <- nearby$wiski_id[nearby$km_outside <= 5]
    stop_here(paste0("\n%d gauges listed in %s, with a map in nearby_gauges.png. Choose the ",
                     "ones to use and put their WISKI IDs in gauge_ids, then run again. Those ",
                     "inside or within 5 km:\n  gauge_ids <- c(%s)"),
              nrow(nearby),
              nearby_file,
              paste0('"', near, '"', collapse = ", "))
  }

  # The gauges chosen: from the search's list where they are in it, otherwise looked up.
  listed <- if (file.exists(nearby_file)) {
    fread(nearby_file, colClasses = "character")
  } else {
    data.table(wiski_id = character(0))
  }
  ids <- as.character(gauge_ids)
  if (anyDuplicated(ids)) stop("gauge_ids lists a gauge twice.", call. = FALSE)
  info <- do.call(rbind, lapply(ids, function(id) {
    k <- match(id, listed$wiski_id)
    if (!is.na(k)) {
      return(data.frame(wiski_id = id,
                        label = listed$label[k],
                        x = as.numeric(listed$x[k]),
                        y = as.numeric(listed$y[k]),
                        measure = listed$measure[k]))
    }
    # Not in the list (chosen without a search, or from further away): one request to find it.
    pause()
    rain <- rain_measures(reach.io::find_stations(wiski_ids = id))
    if (!nrow(rain)) stop("No 15-minute rainfall at WISKI ID ", id, ".", call. = FALSE)
    data.frame(wiski_id = id,
               label = rain$label[1],
               x = as.numeric(rain$easting[1]),
               y = as.numeric(rain$northing[1]),
               measure = rain$measure_notation[1])
  }))
  # The same table as for gauge files of your own, so the rest of the script treats both alike.
  gauges <- data.frame(name = name_of(info$label),
                       file = paste0("rain_", ids, ".csv"),
                       wiski_id = ids,
                       x = info$x,
                       y = info$y)

  # The downloads cover the period compared and, when the gauges are corrected, the long
  # record too. A file already there is used when it was downloaded for at least that window
  # (as gauge_downloads_record.csv in data_folder says), or, with no record, when its readings
  # span it; otherwise it is downloaded again. Missing readings become gaps; other quality
  # flags are counted, not acted on (quality control belongs upstream).
  correcting <- !identical(lta_correction, "none")
  dl_from <- if (correcting) min(period_from, correction_from) else period_from
  dl_to <- if (correcting) max(period_to, correction_to) else period_to
  record_file <- here("gauge_downloads_record.csv")
  record <- if (file.exists(record_file)) {
    fread(record_file, colClasses = "character")
  } else {
    data.table(wiski_id = character(0), from = character(0), to = character(0))
  }

  # Whether gauge i's file already covers the download window. The dates are ISO text, so
  # they compare in order as text.
  covered <- function(i, path) {
    k <- match(ids[i], record$wiski_id)
    if (!is.na(k)) return(record$from[k] <= dl_from && record$to[k] >= dl_to)
    t <- as.POSIXct(fread(path, select = 1L)[[1]], tz = "UTC")
    min(t, na.rm = TRUE) <= as.POSIXct(dl_from, tz = "UTC") + 86400 &&
      max(t, na.rm = TRUE) >= as.POSIXct(dl_to, tz = "UTC") - 2 * 86400
  }

  # The previous run's download table, so a gauge already downloaded keeps its counts of
  # readings and quality flags.
  earlier_file <- file.path(output_folder, "gauge_downloads.csv")
  earlier <- if (file.exists(earlier_file)) {
    fread(earlier_file, colClasses = "character")
  } else {
    data.table(wiski_id = character(0))
  }

  downloads <- do.call(rbind, lapply(seq_len(nrow(gauges)), function(i) {
    path <- here(gauges$file[i])
    if (file.exists(path) && covered(i, path)) {
      say("  %s (%s): using %s, already downloaded", gauges$name[i], ids[i], basename(path))
      k <- match(ids[i], earlier$wiski_id)
      if (!is.na(k) && !is.na(suppressWarnings(as.integer(earlier$readings[k])))) {
        return(data.frame(gauge = gauges$name[i],
                          wiski_id = ids[i],
                          label = info$label[i],
                          readings = as.integer(earlier$readings[k]),
                          missing = as.integer(earlier$missing[k]),
                          flags = earlier$flags[k],
                          file = basename(path)))
      }
      return(data.frame(gauge = gauges$name[i],
                        wiski_id = ids[i],
                        label = info$label[i],
                        readings = NA,
                        missing = NA,
                        flags = NA,
                        file = basename(path)))
    }

    # A year at a time, each request after a pause.
    chunks <- reach.io::make_date_chunks(dl_from, dl_to)
    say("  %s (%s, %s): downloading %d year%s",
        gauges$name[i],
        ids[i],
        info$label[i],
        nrow(chunks),
        if (nrow(chunks) == 1) "" else "s")
    readings <- data.table::rbindlist(lapply(seq_len(nrow(chunks)), function(k) {
      pause()
      reach.io::fetch_readings(info$measure[i], chunks$chunk_from[k], chunks$chunk_to[k])
    }), fill = TRUE)
    if (!nrow(readings)) stop("No readings for ", ids[i], " in the dates asked.", call. = FALSE)

    # Readings flagged Missing become gaps; the rest are written as they came.
    value <- as.numeric(readings$value)
    quality <- if ("quality" %in% names(readings)) readings$quality else rep(NA, nrow(readings))
    value[quality %in% "Missing"] <- NA
    data.table::fwrite(data.table::data.table(time = format(readings$dateTime,
                                                            "%Y-%m-%d %H:%M:%S",
                                                            tz = "UTC"),
                                              value = value),
                       path)

    # Note the window downloaded, so the next run knows the file covers it.
    record <<- rbind(record[record$wiski_id != ids[i]],
                     data.table(wiski_id = ids[i], from = dl_from, to = dl_to))
    fwrite(record, record_file)

    # The other quality flags, counted for the summary.
    flagged <- table(quality[!quality %in% c("Good", "Missing", NA)])
    data.frame(gauge = gauges$name[i],
               wiski_id = ids[i],
               label = info$label[i],
               readings = nrow(readings),
               missing = sum(is.na(value)),
               flags = if (length(flagged)) {
                 paste(sprintf("%s %d", names(flagged), as.integer(flagged)), collapse = ", ")
               } else "none",
               file = basename(path))
  }))
  fwrite(downloads, file.path(output_folder, "gauge_downloads.csv"))
} else if (!identical(gauge_source, "files")) {
  stop("gauge_source must be \"hydrology_api\" or \"files\".", call. = FALSE)
}

# ---- The names of the series --------------------------------------------------------------

gauge_names <- as.character(gauges$name)

# Thiessen weights may name a gauge by its WISKI ID: put its name in its place.
if (length(thiessen_weights) && !is.null(gauges$wiski_id)) {
  by_id <- match(names(thiessen_weights), gauges$wiski_id)
  names(thiessen_weights)[!is.na(by_id)] <- gauge_names[by_id[!is.na(by_id)]]
}

# The averages the script builds have these names, so no gauge or other series may take one.
built_names <- c("thiessen", "equal", "equal_all", "idw", "multiquadric", "multiquadric_lta",
                 "h19", "h19_bias", "multiquadric_h19")
unknown_methods <- setdiff(rain_methods, built_names)
if (length(unknown_methods)) {
  stop("rain_methods names averages the script cannot build: ",
       toString(unknown_methods),
       ". The averages it can build: ",
       toString(built_names),
       ".",
       call. = FALSE)
}

# The averages asked for that cannot be built, with the reason, for the summary and the report.
skipped_methods <- character(0)
skip_method <- function(name, reason) {
  if (name %in% rain_methods) skipped_methods[[name]] <<- reason
}
clash <- intersect(c(gauge_names, names(other_rain_files)), built_names)
if (length(clash) || anyDuplicated(c(gauge_names, names(other_rain_files)))) {
  stop("Give each gauge and other series a name of its own, not one of ",
       toString(built_names),
       ".",
       call. = FALSE)
}
if (length(setdiff(names(thiessen_weights), gauge_names))) {
  in_use <- if (is.null(gauges$wiski_id)) {
    gauge_names
  } else {
    sprintf("%s (WISKI ID %s)", gauge_names, gauges$wiski_id)
  }
  stop("thiessen_weights names gauges not in use: ",
       toString(setdiff(names(thiessen_weights), gauge_names)),
       ". Name each gauge by its ",
       "WISKI ID or its name here. The gauges in use: ",
       toString(in_use),
       call. = FALSE)
}

# ---- Read the files and put them on one time step ---------------------------------------

inputs <- c(stats::setNames(as.character(gauges$file), gauge_names), other_rain_files)
missing_files <- inputs[!file.exists(here(inputs))]
if (length(missing_files)) {
  stop("Cannot find ", toString(here(missing_files)), ".", call. = FALSE)
}
say("Reading %d rain gauges, %d other series, the flow and the evaporation",
    length(gauge_names),
    length(other_rain_files))
raw <- c(list(flow = read_hydro_series(here(flow_file)),
              pe = read_hydro_series(here(pet_file))),
         lapply(inputs, function(f) read_hydro_series(here(f))))

from_t <- as.POSIXct(period_from, tz = "UTC")
to_t <- as.POSIXct(period_to, tz = "UTC")
if (is.na(from_t) || is.na(to_t) || from_t >= to_t) {
  stop("period_from and period_to must be dates, the first before the second.",
       call. = FALSE)
}

# Each series against the period: one that starts late or ends early is padded with gaps.
# A day's slack at the start and two at the end, so a file that stops at 23:45 on the last day
# is not flagged.
for (n in names(raw)) {
  span <- range(raw[[n]]$time[is.finite(raw[[n]]$value)])
  if (span[1] > from_t + 86400 || span[2] < to_t - 2 * 86400) {
    warning(sprintf(paste("%s covers %s to %s only, not the whole period %s to %s: the rest",
                          "is gaps.%s"),
                    n,
                    format(span[1], "%Y-%m-%d"),
                    format(span[2], "%Y-%m-%d"),
                    period_from,
                    period_to,
                    if (n %in% gauge_names && !is.null(downloads)) {
                      " Delete its file to download it again for the period."
                    } else ""),
            call. = FALSE)
  }
}

# Every series on the same steps over the period (the end is the start of the last step), then
# each in its own units: flow in m3/s, evaporation and rain in mm per step.
grid <- do.call(align_series, c(raw, list(dt = step_hours,
                                          start = from_t,
                                          end = to_t - 3600 * step_hours)))
flow <- convert_units(grid$flow, "auto", step_hours, "flow")
pe <- fill_gaps(convert_units(grid$pe, "mm_per_step", step_hours, "pet"),
                "interpolate",
                grid$time,
                "pe")
as_rain <- function(n) convert_units(grid[[n]], "mm_per_step", step_hours, "rain")

# G: the gauges' rain, one column per gauge, one row per step.
G <- vapply(gauge_names, as_rain, numeric(length(grid$time)))
if (is.null(dim(G))) G <- matrix(G, ncol = 1, dimnames = list(NULL, gauge_names))

# ---- The long-term average grid, and the gauges corrected to it ----------------------------

have_positions <- !anyNA(gauges$x) && !anyNA(gauges$y)
lta <- NULL
corrections <- NULL
if (!lta_correction %in% c("none", "relative", "absolute")) {
  stop("lta_correction must be \"none\", \"relative\" or \"absolute\".", call. = FALSE)
}
if (!identical(lta_correction, "none") && is.null(lta_rain_file)) {
  stop("lta_correction needs lta_rain_file, the long-term average grid.", call. = FALSE)
}

if (!is.null(lta_rain_file)) {
  if (is.null(boundary) || !have_positions) {
    stop("The long-term average grid needs the boundary and every gauge's position.",
         call. = FALSE)
  }
  if (!file.exists(here(lta_rain_file))) {
    stop("Cannot find ", here(lta_rain_file), ".", call. = FALSE)
  }
  # Only the cells around the catchment and the gauges, with a 3 km margin.
  lta <- read_lta_grid(here(lta_rain_file),
                       extent = c(range(c(boundary$x, gauges$x)) + c(-3000, 3000),
                                  range(c(boundary$y, gauges$y)) + c(-3000, 3000)))
  # Each gauge's long-term average: the value of the grid cell it sits in.
  lta_gauges <- stats::setNames(lta_at(lta, gauges$x, gauges$y), gauge_names)
  if (anyNA(lta_gauges)) {
    stop("The long-term average grid has no value at ",
         toString(gauge_names[is.na(lta_gauges)]),
         ".",
         call. = FALSE)
  }
}

if (!identical(lta_correction, "none")) {
  # Each gauge's average year over the long record: its rain over the steps it has, scaled to
  # a year by the share of the record those steps cover. Under 70% of the record is too little
  # to trust: that gauge is left as measured.
  c_from <- as.POSIXct(correction_from, tz = "UTC")
  c_to <- as.POSIXct(correction_to, tz = "UTC")
  corrections <- do.call(rbind, lapply(gauge_names, function(n) {
    # The gauge's whole file, read above, not only the period compared.
    d <- raw[[n]]
    k <- d$time >= c_from & d$time < c_to & is.finite(d$value)
    step_h <- stats::median(as.numeric(diff(d$time), units = "hours"))
    cover <- sum(k) * step_h / as.numeric(difftime(c_to, c_from, units = "hours"))
    # 8766 hours: a year of 365.25 days.
    mean_year <- if (cover > 0) sum(d$value[k]) / (sum(k) * step_h / 8766) else NA_real_
    data.frame(gauge = n,
               record_years = round(sum(k) * step_h / 8766, 1),
               coverage = round(cover, 3),
               mm_per_year = round(mean_year, 1),
               lta_mm_per_year = round(lta_gauges[[n]], 1),
               raw_factor = if (cover >= 0.7) lta_gauges[[n]] / mean_year else NA_real_)
  }))
  short <- corrections$gauge[is.na(corrections$raw_factor)]
  if (length(short)) {
    warning("Under 70% of the correction record for ",
            toString(short),
            ": left as measured.",
            call. = FALSE)
  }

  # Relative: divided by the median factor, so the network keeps its level. Absolute: as is.
  corrections$factor <- if (identical(lta_correction, "relative")) {
    corrections$raw_factor / stats::median(corrections$raw_factor, na.rm = TRUE)
  } else {
    corrections$raw_factor
  }
  corrections$factor[is.na(corrections$factor)] <- 1
  corrections$raw_factor <- round(corrections$raw_factor, 3)
  corrections$factor <- round(corrections$factor, 3)
  fwrite(corrections, file.path(output_folder, "lta_corrections.csv"))
  say("Gauges corrected to the long-term average (%s): %s",
      lta_correction,
      paste(sprintf("%s x %.3f", corrections$gauge, corrections$factor), collapse = ", "))

  # Each gauge's column scaled by its factor: every series built below uses the corrected rain.
  G <- sweep(G, 2, corrections$factor, "*")
}

# ---- The catchment averages -------------------------------------------------------------------

# A weighted average, renormalised over the gauges reporting at each step, as a weighting
# method does when a gauge is missing: the weights of the missing gauges are shared among the
# rest. A step with no weighted gauge reporting is missing.
weighted_average <- function(w) {
  full <- stats::setNames(rep(0, length(gauge_names)), gauge_names)
  full[names(w)] <- w
  reporting <- !is.na(G)
  # At each step: the weight of the gauges reporting, and their weighted rain.
  share <- as.numeric(reporting %*% full)
  total <- as.numeric(ifelse(reporting, G, 0) %*% full)
  out <- total / share
  out[share <= 0] <- NA
  out
}

# The grid over the catchment, for the multiquadric average and the Thiessen weights from the
# geometry: each gauge's share of the cells inside the boundary that lie nearest to it.
geometry_weights <- NULL
if (!is.null(boundary) && have_positions) {
  cells_x <- seq(min(boundary$x) - grid_spacing_m,
                 max(boundary$x) + grid_spacing_m,
                 by = grid_spacing_m)
  cells_y <- seq(min(boundary$y) - grid_spacing_m,
                 max(boundary$y) + grid_spacing_m,
                 by = grid_spacing_m)
  cell_grid <- list(x = cells_x, y = cells_y)
  # TRUE for the cells whose centres fall inside the boundary.
  mask <- catchment_mask(cells_x, cells_y, boundary)
  inside_cells <- which(mask, arr.ind = TRUE)
  cx <- cells_x[inside_cells[, 1]]
  cy <- cells_y[inside_cells[, 2]]
  # For each cell inside, the nearest gauge; each gauge's weight is its share of the cells.
  nearest <- apply(outer(cx, gauges$x, `-`)^2 + outer(cy, gauges$y, `-`)^2, 1, which.min)
  geometry_weights <- stats::setNames(tabulate(nearest, length(gauge_names)) / length(nearest),
                                      gauge_names)
}

# With no Thiessen weights given, those from the geometry stand in.
thiessen_source <- "given"
if (!length(thiessen_weights) && !is.null(geometry_weights)) {
  thiessen_weights <- geometry_weights[geometry_weights > 0]
  thiessen_source <- "from the geometry"
}

# thiessen and equal use the gauges with a Thiessen weight; equal_all every gauge, built only
# when some gauge has no weight (otherwise it would be the same as equal).
inside <- names(thiessen_weights)[thiessen_weights > 0]
weights <- list()
if (length(inside)) {
  weights$thiessen <- thiessen_weights
  weights$equal <- stats::setNames(rep(1 / length(inside), length(inside)), inside)
}
if (length(setdiff(gauge_names, inside))) {
  weights$equal_all <- stats::setNames(rep(1 / length(gauge_names), length(gauge_names)),
                                       gauge_names)
} else {
  skip_method("equal_all", "every gauge has a Thiessen weight, so it would be the same as equal")
}
if (!length(inside)) {
  skip_method("thiessen", "no Thiessen weights were given and there is no boundary to make them")
  skip_method("equal", "no Thiessen weights were given and there is no boundary to make them")
}
# Only the averages asked for.
weights <- weights[intersect(names(weights), rain_methods)]
built <- lapply(weights, weighted_average)

# Multiquadric: a smooth surface through every gauge, inside the catchment or near it, averaged
# over the cells inside the boundary (pdmS7's merge_rainfall()). Worked out on the wet steps
# only: a step where every reporting gauge is dry has no rain anywhere.
surface_methods <- c("idw", "multiquadric", "multiquadric_lta", "multiquadric_h19")
if (is.null(boundary)) {
  for (m in surface_methods) skip_method(m, "it needs the catchment boundary")
} else if (any(surface_methods %in% rain_methods)) {
  if (!have_positions) {
    stop("The multiquadric average needs every gauge's x and y in the gauges table.",
         call. = FALSE)
  }
  located <- data.frame(id = gauge_names, x = gauges$x, y = gauges$y)
  wet_steps <- which(rowSums(G > 0, na.rm = TRUE) > 0)
  # Dry steps are 0 where some gauge reports, missing where none does.
  dry_or_missing <- ifelse(rowSums(!is.na(G)) > 0, 0, NA_real_)

  # The multiquadric's shape parameter c is chosen by leaving out one gauge at a time; the
  # conditional merge uses the same c, so it is worked out for either.
  if (any(c("multiquadric", "multiquadric_h19") %in% rain_methods)) {
    say("Multiquadric average over the catchment")
    fit <- merge_rainfall(located,
                          G[wet_steps, , drop = FALSE],
                          cell_grid,
                          mask,
                          method = "multiquadric")
    multiquadric_c <- fit$c
    if ("multiquadric" %in% rain_methods) {
      built$multiquadric <- dry_or_missing
      built$multiquadric[wet_steps] <- fit$rain
    }
  }

  # Inverse distance weighting: each cell a mean of the gauges, weighted by 1 / distance^2.
  if ("idw" %in% rain_methods) {
    say("Inverse distance weighting over the catchment")
    fit_idw <- merge_rainfall(located,
                              G[wet_steps, , drop = FALSE],
                              cell_grid,
                              mask,
                              method = "idw")
    built$idw <- dry_or_missing
    built$idw[wet_steps] <- fit_idw$rain
  }
}

# Multiquadric scaled by the long-term average: at each step, each gauge's rain as a share of
# its long-term average, a multiquadric surface through those shares, and the surface times
# the grid, averaged over the catchment. A storm then falls more heavily where it usually rains
# more. The shares are kept in mm by scaling each gauge to the catchment's mean long-term
# average L (z = g x L / L_gauge); with each cell weighted by its own long-term average, the
# merge's weighted mean of the surface through z is then the mean of share times average. A
# flat grid gives the plain multiquadric exactly.
if (!is.null(lta)) {
  # The long-term average at every cell of the multiquadric's grid.
  lta_cells <- matrix(lta_at(lta,
                             rep(cells_x, length(cells_y)),
                             rep(cells_y, each = length(cells_x))),
                      length(cells_x))
  if (anyNA(lta_cells[mask])) {
    stop("The long-term average grid has no value for part of the catchment.", call. = FALSE)
  }
  lta_catchment <- mean(lta_cells[mask])
  if ("multiquadric_lta" %in% rain_methods) {
    say("Multiquadric scaled by the long-term average (catchment %.0f mm a year)",
        lta_catchment)
    scaled <- sweep(G, 2, lta_catchment / lta_gauges, "*")
    # The cells' weights are their long-term averages (0 outside the catchment).
    fit_lta <- merge_rainfall(located,
                              scaled[wet_steps, , drop = FALSE],
                              cell_grid,
                              ifelse(mask, lta_cells, 0),
                              method = "multiquadric")
    built$multiquadric_lta <- dry_or_missing
    built$multiquadric_lta[wet_steps] <- fit_lta$rain
    multiquadric_lta_c <- fit_lta$c
  }
} else {
  skip_method("multiquadric_lta", "it needs lta_rain_file, the long-term average grid")
}

# ---- H19 radar ------------------------------------------------------------------------------

# The files' layouts first, from their headers alone: each layout's time stamp, units and grid
# are checked, and each file gets the shift and factor that put it on the same footing (times
# at the start of each step, depths in mm per step). Then the radar is read in a window around
# the catchment and the gauges, one daily file at a time, and kept: a rerun with the same files
# reads nothing.
radar_at_gauges <- NULL
radar_layouts <- NULL
radar_processed <- NULL
radar_bias <- NULL
# The radar's catchment average on the record's steps, from the extracts or the daily files.
h19_series <- NULL

# Onto the record's steps: 15-minute radar summed into longer steps when step_hours is longer,
# a step counting only when all its quarter hours are present.
per_step <- 4 * step_hours
onto_grid <- function(v, time) {
  # The record step each radar step falls in, by the step's start time.
  bucket <- floor(as.numeric(time) / (step_hours * 3600))
  total <- tapply(v, bucket, function(x) if (sum(!is.na(x)) == per_step) sum(x) else NA)
  out <- rep(NA_real_, length(grid$time))
  k <- match(floor(as.numeric(grid$time) / (step_hours * 3600)), as.numeric(names(total)))
  out[!is.na(k)] <- total[k[!is.na(k)]]
  out
}

# The quick way: the catchment average from the team's processed yearly extracts.
if (!is.null(radar_processed_folder)) {
  if (is.null(radar_polygon_id)) {
    stop("Give radar_polygon_id, the catchment's polygon ID in Hyrad, with ",
         "radar_processed_folder.",
         call. = FALSE)
  }
  say("H19 radar from the processed extracts, polygon %s", radar_polygon_id)
  # To the last quarter hour of the last record step.
  radar_processed <- h19_processed(radar_processed_folder,
                                   radar_polygon_id,
                                   min(grid$time),
                                   max(grid$time) + 3600 * step_hours - 900)
  h19_series <- onto_grid(radar_processed$rain, radar_processed$time)
  say("  %.1f%% of 15-minute steps missing", 100 * mean(is.na(radar_processed$rain)))
}

# The slow way: the daily NetCDF files.
if (!is.null(radar_folder)) {
  say("H19 radar")
  # Only the year folders of the record (and their month folders), not other folders beside
  # them; without year folders, the whole folder is searched.
  span <- as.Date(range(grid$time))
  year_dirs <- file.path(radar_folder,
                         seq(as.integer(format(span[1] - 1, "%Y")),
                             as.integer(format(span[2] + 1, "%Y"))))
  year_dirs <- year_dirs[dir.exists(year_dirs)]
  radar_files <- list.files(if (length(year_dirs)) year_dirs else radar_folder,
                            pattern = radar_pattern,
                            recursive = TRUE,
                            full.names = TRUE)
  if (!length(radar_files)) {
    stop("No files matching ", radar_pattern, " in ", radar_folder, ".", call. = FALSE)
  }

  # The files of the record's days, by the date at the start of each name, with a day either
  # side; a file whose name holds no date is kept.
  file_day <- as.Date(substr(basename(radar_files), 1, 8), "%Y%m%d")
  radar_files <- radar_files[is.na(file_day) | (file_day >= span[1] - 1 &
                                                  file_day <= span[2] + 1)]
  if (!length(radar_files)) stop("No H19 files fall within the record.", call. = FALSE)

  # The layouts, from a file a month, bisecting to each change.
  radar_layouts <- h19_layouts(radar_files)
  print(radar_layouts)
  fwrite(radar_layouts$layouts, file.path(output_folder, "radar_layouts.csv"))
  if (radar_scan_only) {
    say("radar_scan_only is TRUE: layouts written to radar_layouts.csv; stopping here.")
    if (interactive()) invokeRestart("abort") else quit(save = "no")
  }
  bad <- radar_layouts$layouts[nzchar(radar_layouts$layouts$problems), ]
  if (nrow(bad)) {
    stop("H19 layout ",
         paste(sprintf("%d (%s to %s): %s",
                       bad$layout,
                       bad$first_day,
                       bad$last_day,
                       bad$problems),
               collapse = "; "),
         ". See radar_layouts.csv.",
         call. = FALSE)
  }

  have_boundary <- !is.null(boundary)
  if (!have_boundary && !have_positions) {
    stop("The radar needs the catchment boundary or the gauges' positions, to know where to ",
         "read.",
         call. = FALSE)
  }
  # The window read from each file: the catchment and the gauges, with a 3 km margin.
  px <- c(if (have_boundary) boundary$x, if (have_positions) gauges$x)
  py <- c(if (have_boundary) boundary$y, if (have_positions) gauges$y)
  extent <- c(min(px) - 3000, max(px) + 3000, min(py) - 3000, max(py) + 3000)

  # Multiquadric through the gauges and the radar (conditional merging): the multiquadric
  # surface through the gauges, plus the radar's own pattern between them (the radar field less
  # a multiquadric surface through the radar at the gauges), averaged over the catchment's
  # radar cells. Worked out step by step as the radar is read, at 15-minute steps.
  conditional <- "multiquadric_h19" %in% rain_methods && have_boundary && have_positions &&
    exists("multiquadric_c") && step_hours == 0.25

  # A radar extract kept from an earlier run is used when it came from the same files (and has
  # the conditional merge, when that is wanted).
  cache <- file.path(output_folder, "radar_extract.csv")
  cache_files <- file.path(output_folder, "radar_extract_files.txt")
  cached <- file.exists(cache) && file.exists(cache_files) &&
    identical(sort(readLines(cache_files)), sort(radar_files)) &&
    (!conditional || "h19_multiquadric" %in% names(fread(cache, nrows = 0)))

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

    # The record step of each radar step, to find the gauges' rain at the same time.
    gauge_row <- match(as.numeric(h$time), as.numeric(grid$time))

    # The cell each gauge sits in, for the conditional merge.
    gauge_cell <- if (have_positions) {
      cbind(vapply(gauges$x, function(x) which.min(abs(h$grid$x - x)), integer(1)),
            vapply(gauges$y, function(y) which.min(abs(h$grid$y - y)), integer(1)))
    }

    # One step's conditional merge: missing without the gauges, or with radar missing over the
    # catchment or at a gauge; 0 when gauges and radar are all dry.
    merge_step <- function(r, s) {
      g <- if (is.na(gauge_row[s])) rep(NA_real_, length(gauge_names)) else G[gauge_row[s], ]
      inside <- r[in_catchment]
      if (all(is.na(g)) || anyNA(inside) || anyNA(r[gauge_cell])) return(NA_real_)
      if (all(g <= 0, na.rm = TRUE) && all(inside <= 0) && all(r[gauge_cell] <= 0)) return(0)
      merge_rainfall(located,
                     matrix(g, nrow = 1),
                     h$grid,
                     in_catchment,
                     radar = function(t) r,
                     method = "conditional",
                     c = multiquadric_c)$rain
    }

    # Every radar step: the catchment average, the conditional merge, and the radar over each
    # gauge. A step missing more than a tenth of the catchment's cells is missing.
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
      c(catchment, if (conditional) merge_step(r, s) else NA_real_, at_gauges)
    }, numeric(2 + length(gauge_names))))

    # Files the reader could not use: their steps are missing, and they are listed.
    skipped <- h$skipped()
    if (nrow(skipped)) {
      fwrite(skipped, file.path(output_folder, "radar_skipped_files.csv"))
      say("  %d radar files could not be read and were skipped (their steps are missing): see",
          nrow(skipped))
      say("  radar_skipped_files.csv")
    }

    # Kept for the next run, with the list of files it came from.
    extract <- data.table(time = h$time, values)
    setnames(extract, c("time", "h19", "h19_multiquadric", paste0("radar_at_", gauge_names)))
    fwrite(extract[, time := format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC")], cache)
    extract$time <- as.POSIXct(extract$time, tz = "UTC")
    writeLines(radar_files, cache_files)
  }

  # The processed extract, where given, is the catchment average; the daily files then give
  # only the radar over each gauge.
  if (have_boundary && is.null(radar_processed)) {
    h19_series <- onto_grid(extract$h19, extract$time)
  }
  if (conditional && "h19_multiquadric" %in% names(extract)) {
    built$multiquadric_h19 <- onto_grid(extract$h19_multiquadric, extract$time)
  }
  if (have_positions) {
    radar_at_gauges <- vapply(gauge_names, function(n) {
      onto_grid(extract[[paste0("radar_at_", n)]], extract$time)
    }, numeric(length(grid$time)))
  }
}

# The radar alone, when asked for.
if (!is.null(h19_series) && "h19" %in% rain_methods) built$h19 <- h19_series

# The radar with a mean-field bias correction: day by day, the radar over the catchment scaled
# by the gauges' total over the radar's total at the gauges, over the steps where both have a
# value. It keeps the radar's pattern and timing and takes its level from the gauges. A day
# with under 1 mm of radar at the gauges keeps the radar as it is (too little to scale by), and
# the factor is held within 0.2 to 5, so one day's mismatch cannot wipe out or blow up a storm.
if ("h19_bias" %in% rain_methods && !is.null(h19_series) && !is.null(radar_at_gauges)) {
  say("H19 with a daily mean-field bias correction")
  bias_day <- as.Date(grid$time)
  both <- !is.na(G) & !is.na(radar_at_gauges)
  gauge_day <- tapply(rowSums(ifelse(both, G, 0)), bias_day, sum)
  radar_day <- tapply(rowSums(ifelse(both, radar_at_gauges, 0)), bias_day, sum)
  factor_day <- ifelse(radar_day >= 1, pmin(pmax(gauge_day / radar_day, 0.2), 5), 1)
  radar_bias <- data.frame(day = names(factor_day),
                           gauges_mm = round(as.numeric(gauge_day), 2),
                           radar_mm = round(as.numeric(radar_day), 2),
                           factor = round(as.numeric(factor_day), 3))
  fwrite(radar_bias, file.path(output_folder, "radar_bias_factors.csv"))
  built$h19_bias <- h19_series * as.numeric(factor_day[as.character(bias_day)])
}

# The radar averages asked for that could not be built, and why.
radar_given <- !is.null(radar_folder) || !is.null(radar_processed_folder)
if (is.null(h19_series)) {
  skip_method("h19",
              if (radar_given) {
                "it needs the catchment boundary"
              } else {
                "it needs radar_folder or radar_processed_folder"
              })
}
if ((is.null(h19_series) || is.null(radar_at_gauges)) && is.null(built$h19_bias)) {
  skip_method("h19_bias",
              "it needs radar_folder (the daily files), the boundary and the gauges' positions")
}
if (is.null(built$multiquadric_h19) && !"multiquadric_h19" %in% names(skipped_methods)) {
  skip_method("multiquadric_h19",
              if (is.null(radar_folder)) {
                "it needs radar_folder, the daily H19 files"
              } else if (step_hours != 0.25) {
                "it needs 15-minute data"
              } else {
                "it needs the catchment boundary and the gauges' positions"
              })
}

# Write the averages out, ready for calibrate_site.R.
dir.create(file.path(output_folder, "catchment_rain"), showWarnings = FALSE)
for (n in names(built)) {
  fwrite(data.table(time = format(grid$time, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                    value = round(built[[n]], 4)),
         file.path(output_folder, "catchment_rain", paste0(n, ".csv")))
}

# ---- Every series together ------------------------------------------------------------------

# The averages built, then each gauge, then any other series given: each is judged alike.
rains <- c(built,
           lapply(stats::setNames(gauge_names, gauge_names), function(n) G[, n]),
           lapply(stats::setNames(names(other_rain_files), names(other_rain_files)), as_rain))
names_r <- names(rains)
gauge_series <- gauge_names

# The comparison runs over the stretch every series and the flow cover: from the latest first
# value to the earliest last one. A series that covers less of the period (one or two years of
# H19 beside ten of gauges, say) would otherwise leave the tests that need every series at
# once with empty years. The catchment averages written above keep the whole period.
span_of <- function(r) {
  k <- which(is.finite(r))
  if (length(k)) c(k[1], k[length(k)]) else c(NA_real_, NA_real_)
}
spans <- vapply(c(rains, list(flow = flow)), span_of, numeric(2))
empty <- colnames(spans)[is.na(spans[1, ])]
if (length(empty)) {
  stop("No values over the period for ", toString(empty), ".", call. = FALSE)
}
keep <- seq(max(spans[1, ]), min(spans[2, ]))
if (!length(keep) || max(spans[1, ]) > min(spans[2, ])) {
  stop("The series share no stretch of the period: check their dates.", call. = FALSE)
}
if (length(keep) < length(grid$time)) {
  # The series that set the start and the end, named in the message and the report.
  limiting <- unique(c(colnames(spans)[spans[1, ] == max(spans[1, ])],
                       colnames(spans)[spans[2, ] == min(spans[2, ])]))
  say("Compared over %s to %s, the stretch every series covers (set by %s)",
      format(grid$time[keep[1]], "%Y-%m-%d %H:%M"),
      format(grid$time[keep[length(keep)]], "%Y-%m-%d %H:%M"),
      toString(limiting))
  grid <- grid[keep, , drop = FALSE]
  flow <- flow[keep]
  pe <- pe[keep]
  G <- G[keep, , drop = FALSE]
  rains <- lapply(rains, function(r) r[keep])
  if (!is.null(radar_at_gauges)) radar_at_gauges <- radar_at_gauges[keep, , drop = FALSE]
} else {
  limiting <- character(0)
}
# The first and last steps compared, and the time after the last.
compared_from <- format(min(grid$time), "%Y-%m-%d %H:%M")
compared_to <- format(max(grid$time) + 3600 * step_hours, "%Y-%m-%d %H:%M")
years <- as.numeric(difftime(max(grid$time), min(grid$time), units = "days")) / 365.25

# One colour per series, the same in every plot.
colours <- grDevices::hcl.colors(max(3L, length(names_r)), "Dark 3")[seq_along(names_r)]

# Draws a plot into a PNG in the output folder.
png_of <- function(name, draw, width = 1600, height = 900) {
  grDevices::png(file.path(output_folder, name), width = width, height = height, res = 150)
  on.exit(grDevices::dev.off())
  draw()
}

# Steps where every series has a value: each comparison uses the same steps, so a series is
# not judged on a different stretch of the record from the others.
common <- Reduce(`&`, lapply(rains, is.finite)) & is.finite(flow)
say("%.1f years of data; %.0f%% of steps have every series and the flow",
    years,
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
  water_balance(data.frame(time = grid$time, rain = rr, pet = pe),
                q,
                area_km2,
                water_year_start = year_start_month)
}
balances <- lapply(rains, balance_of)
# The years' name in the plots' titles.
year_word <- if (year_start_month == 1) {
  "calendar year"
} else if (year_start_month == 10) {
  "water year"
} else {
  sprintf("year from %s", month.name[year_start_month])
}

# The whole record's figures for each series; the rain per year over the common steps.
balance <- data.frame(
  rain = names_r,
  rain_mm_per_year = round(vapply(balances, function(b) b$record$rain_mm, 0) /
                             (sum(common) * step_hours / 8766)),
  runoff_ratio = round(vapply(balances, function(b) b$record$runoff_ratio, 0), 3),
  loss_over_pet = round(vapply(balances, function(b) b$record$loss_over_pet, 0), 3),
  flagged_years = vapply(balances, function(b) {
    sum(nzchar(b$years$flags) & b$years$flags != "incomplete")
  }, 0L)
)
# A balance is implausible when the flow exceeds the rain (runoff ratio above 1) or the losses
# exceed what evaporation can take (loss over potential evaporation above 1). Distance beyond
# either limit counts against a series.
balance$balance_problem <- round(pmax(balance$runoff_ratio - 1, 0) +
                                   pmax(balance$loss_over_pet - 1, 0), 3)

# Each series' annual rain against the long-term average: a catchment average against the
# catchment's, a gauge against its own cell's. Over a short record the years' own weather
# moves this as much as any fault does.
lta_check <- NULL
if (!is.null(lta)) {
  lta_of <- ifelse(names_r %in% gauge_names,
                   lta_gauges[match(names_r, gauge_names)],
                   lta_catchment)
  lta_check <- data.frame(rain = names_r,
                          rain_mm_per_year = balance$rain_mm_per_year,
                          lta_mm_per_year = round(lta_of),
                          ratio = round(balance$rain_mm_per_year / lta_of, 3))
  fwrite(lta_check, file.path(output_folder, "long_term_average_check.csv"))
}

# HOW TO READ gauge_map.png
# The catchment (outlined) and the gauges in use (filled, each named with its Thiessen weight
# in brackets), over the part of the catchment nearest each gauge (shaded in that gauge's
# colour): the Thiessen weights are the shares of those parts. Other gauges the search found
# are open grey circles.
# Good: the gauges spread across the catchment and around it, each part a fair share.
# Worry if: one gauge's part covers most of the catchment (the averages lean on that gauge:
#   see the effective number of gauges); a gauge in the wrong place (its position: x and y
#   swapped, or the wrong grid); weights given that differ from the parts drawn.
if (!is.null(boundary) && have_positions) {
  png_of("gauge_map.png", function() {
    gauge_colours <- colours[match(gauge_names, names_r)]
    gauge_colours[is.na(gauge_colours)] <- "grey40"
    # The catchment and the gauges in use, with a 2 km margin.
    graphics::par(mar = c(4, 4.5, 2, 1))
    graphics::plot(range(c(boundary$x, gauges$x)) + c(-2000, 2000),
                   range(c(boundary$y, gauges$y)) + c(-2000, 2000),
                   type = "n",
                   asp = 1,
                   xlab = "Easting (m)",
                   ylab = "Northing (m)",
                   main = "The catchment, and the part of it nearest each gauge")
    # Each cell inside the catchment shaded by its nearest gauge.
    zone <- matrix(NA_real_, length(cells_x), length(cells_y))
    zone[inside_cells] <- nearest
    graphics::image(cells_x,
                    cells_y,
                    zone,
                    col = grDevices::adjustcolor(gauge_colours, alpha.f = 0.35),
                    breaks = seq(0.5, length(gauge_names) + 0.5),
                    add = TRUE)
    graphics::polygon(boundary$x, boundary$y, border = "#B3261E", lwd = 2)
    # Other gauges the search found, where there was a search.
    if (file.exists(nearby_file)) {
      others <- fread(nearby_file)
      others <- others[!as.character(others$wiski_id) %in% as.character(gauges$wiski_id)]
      graphics::points(others$x, others$y, pch = 1, col = "grey55", cex = 1.1)
    }
    # The gauges in use, each with the Thiessen weight the averages use.
    weight <- stats::setNames(rep(0, length(gauge_names)), gauge_names)
    weight[names(thiessen_weights)] <- thiessen_weights
    graphics::points(gauges$x, gauges$y, pch = 21, bg = gauge_colours, cex = 1.6)
    graphics::text(gauges$x,
                   gauges$y,
                   sprintf("%s (%.2f)", gauge_names, weight),
                   pos = 3,
                   cex = 0.8)
  }, width = 1400, height = 1400)
}

# HOW TO READ rain_by_year.png
# One group of bars per year (calendar or water year, as year_start_month sets; each named by
# the year it ends in), one bar per rain series: the rain each series gives the catchment that
# year.
# Good: the series agree within a few per cent every year, or differ by the same amount every
#   year (a steady difference is a matter of scale, which the water balance then judges).
# Worry if: one series drops or jumps in some years only. A gauge failed, moved or was
#   replaced then; check its record for those years.
png_of("rain_by_year.png", function() {
  periods <- balances[[1]]$years$period
  totals <- vapply(balances, function(b) b$years$rain_mm, numeric(length(periods)))
  if (is.null(dim(totals))) totals <- matrix(totals, nrow = 1)
  graphics::par(mar = c(5, 4.5, 2, 1))
  graphics::barplot(t(totals),
                    beside = TRUE,
                    names.arg = periods,
                    col = colours,
                    border = NA,
                    las = 2,
                    ylab = "Rain (mm)",
                    main = sprintf("Rain by %s, each series", year_word),
                    ylim = c(0, 1.3 * max(totals, na.rm = TRUE)),
                    legend.text = names_r,
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
  graphics::matplot(seq_along(periods),
                    ratio,
                    type = "b",
                    pch = 19,
                    lty = 1,
                    lwd = 2,
                    col = colours,
                    xaxt = "n",
                    xlab = "",
                    ylab = "Runoff ratio (flow / rain)",
                    ylim = c(0, 1.3 * max(1.1, max(ratio, na.rm = TRUE))),
                    main = sprintf("Runoff ratio by %s, each series", year_word))
  graphics::axis(1, at = seq_along(periods), labels = periods, las = 2)
  graphics::abline(h = 1, col = "#B3261E")
  graphics::legend("top",
                   names_r,
                   col = colours,
                   lwd = 2,
                   pch = 19,
                   bty = "n",
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
  graphics::plot(c(0, 1),
                 c(0, 1),
                 type = "n",
                 xlab = "Cumulative rain of the median series (share of total)",
                 ylab = "Cumulative rain of each series (share of total)",
                 main = "Double-mass curves, each series against the others")
  graphics::abline(0, 1, lty = 2, col = "grey50")
  for (i in seq_along(cumulative)) {
    d <- cumulative[[i]]
    # 2,000 points per line are plenty to draw, and keep the plot quick.
    k <- unique(round(seq(1, nrow(d), length.out = 2000)))
    graphics::lines(d$reference[k], d$rain[k], col = colours[i], lwd = 2)
  }
  graphics::legend("topleft",
                   sprintf("%s (bend %.1f%%)", names_r, bend_pct),
                   col = colours,
                   lwd = 2,
                   bty = "n")
})

# ---- 4. Quick response ---------------------------------------------------------------------

say("How closely the river follows each series")
response <- gauge_response(as.data.frame(rains),
                           flow,
                           grid$time,
                           dt = step_hours,
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
floods <- screen_events(find_events(average,
                                    ifelse(is.finite(flow), flow, NA_real_),
                                    grid$time,
                                    dt = step_hours,
                                    area_km2 = area_km2),
                        flow,
                        exclude = c("small_rise", "gaps"))
floods <- floods[floods$use & is.finite(floods$quickflow_mm) & floods$quickflow_mm > 0, ]

# Each series' rain over each flood: missing if any step of the window is missing.
event_rain <- vapply(rains, function(r) {
  vapply(seq_len(nrow(floods)), function(e) {
    w <- floods$rain_start[e]:floods$rain_end[e]
    if (any(!is.finite(r[w]))) NA_real_ else sum(r[w])
  }, 0)
}, numeric(nrow(floods)))
if (is.null(dim(event_rain))) event_rain <- matrix(event_rain, ncol = length(rains))

# A storm missed: more quick flow than rain, or under half a millimetre of rain at all.
ratio <- floods$quickflow_mm / event_rain
missed <- colSums(ratio > 1 | event_rain < 0.5, na.rm = TRUE)
missed_pct <- round(100 * missed / colSums(is.finite(ratio)), 1)

# Steadiness: the spread of the log of the flood runoff ratios, over floods the series saw
# some rain for (the others count as missed storms above). Floods differ, so the ratios always
# vary; poor rain adds its own scatter on top.
seen <- ratio
seen[!is.finite(seen) | event_rain < 0.5] <- NA
spread <- round(apply(log(seen), 2, stats::sd, na.rm = TRUE), 3)
flood_table <- data.frame(rain = names_r,
                          floods = colSums(is.finite(ratio)),
                          missed_storms = as.integer(missed),
                          missed_pct = missed_pct,
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
  graphics::boxplot(as.data.frame(seen),
                    names = names_r,
                    col = colours,
                    log = "y",
                    las = 2,
                    ylab = "Flood runoff ratio (quick flow / rain), log scale",
                    main = sprintf("Runoff ratios of the same %d floods, each series",
                                   nrow(floods)))
  graphics::abline(h = 1, col = "#B3261E")
})

# The five largest floods, by peak flow: each series' rain over each, for the cumulative plots
# and the report.
top_floods <- utils::head(order(-floods$peak_flow), 5)
largest_table <- do.call(rbind, lapply(seq_along(top_floods), function(k) {
  e <- top_floods[k]
  data.frame(flood = k,
             rain_start = format(grid$time[floods$rain_start[e]], "%Y-%m-%d %H:%M"),
             peak_m3s = round(floods$peak_flow[e], 2),
             quickflow_mm = round(floods$quickflow_mm[e], 1),
             rain = names_r,
             rain_mm = round(event_rain[e, ], 1),
             runoff_ratio = round(ratio[e, ], 2))
}))
if (length(top_floods)) fwrite(largest_table, file.path(output_folder, "largest_floods.csv"))

# HOW TO READ largest_floods_cumulative.png
# One panel per flood, the five largest by peak flow: each series' rain added up through the
# flood (left axis; the catchment averages bold, single gauges thin), and the river's flow
# behind it in grey (right axis). The title gives the flood's start, peak flow and quick flow.
# largest_floods.csv has each series' total and runoff ratio for each flood.
# Good: the lines climb together and end close together; the rain comes before the rise in
#   flow, and the lines are flat by the peak.
# Worry if: the lines fan out (the series disagree on the storm: that spread is the flood's
#   rain uncertainty); one line stays flat while the others climb (a storm that missed the
#   gauge, or a gap: a gap counts as no rain here); a line keeps climbing after the flow has
#   peaked (a clock or time-zone error); an average ending far from the gauges around it.
if (length(top_floods)) {
  png_of("largest_floods_cumulative.png", function() {
    graphics::par(mfrow = c(3, 2), mar = c(3, 4.5, 2.5, 4.5))
    is_average <- names_r %in% names(built)
    for (k in seq_along(top_floods)) {
      e <- top_floods[k]
      w <- floods$rain_start[e]:min(floods$flow_end[e], length(grid$time))
      # Each series' running total over the flood, a gap counted as no rain.
      totals <- vapply(rains, function(r) cumsum(ifelse(is.finite(r[w]), r[w], 0)),
                       numeric(length(w)))
      if (is.null(dim(totals))) totals <- matrix(totals, nrow = 1)
      # The flow first, in grey on its own axis at the right.
      graphics::plot(grid$time[w],
                     flow[w],
                     type = "l",
                     col = "grey75",
                     lwd = 2,
                     axes = FALSE,
                     xlab = "",
                     ylab = "")
      graphics::axis(4, col.axis = "grey40")
      graphics::mtext("Flow (m3/s)", side = 4, line = 2.5, cex = 0.7, col = "grey40")
      # Then the rain over it, on the left axis.
      graphics::par(new = TRUE)
      graphics::matplot(grid$time[w],
                        totals,
                        type = "l",
                        lty = 1,
                        lwd = ifelse(is_average, 2.5, 1),
                        col = colours,
                        xlab = "",
                        ylab = "Cumulative rain (mm)",
                        main = sprintf("%d. %s: peak %.1f m3/s, quick flow %.1f mm",
                                       k,
                                       format(grid$time[floods$rain_start[e]], "%d %b %Y"),
                                       floods$peak_flow[e],
                                       floods$quickflow_mm[e]),
                        cex.main = 0.95)
      graphics::abline(v = grid$time[floods$peak_row[e]], lty = 2, col = "grey50")
    }
    # The last panel holds the legend.
    graphics::plot.new()
    graphics::legend("center",
                     c(names_r, "Flow (right axis)", "Flow peak"),
                     col = c(colours, "grey75", "grey50"),
                     lwd = c(ifelse(is_average, 2.5, 1), 2, 1),
                     lty = c(rep(1, length(names_r)), 1, 2),
                     bty = "n",
                     cex = 0.9,
                     ncol = 2)
  }, height = 1800)
}

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
  # The radar-based series are not weightings of the gauges, so they are left out here.
  averages <- setdiff(names_r, c(gauge_series, "h19", "h19_bias", "multiquadric_h19"))
  G <- as.matrix(as.data.frame(rains[gauge_series]))
  given <- weights[intersect(names(weights), averages)]
  for (n in names(given)) {
    bad <- setdiff(names(given[[n]]), gauge_series)
    if (length(bad)) {
      stop("The weights for ",
           n,
           " name gauges not in gauge_series: ",
           toString(bad),
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
    data.frame(gauges = paste(p, collapse = " and "),
               floods = sum(k),
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

  # How many of the 20 largest floods fell while an average rested on under 1.5 gauges.
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
    # The sum of the squared weights, after dividing them by their sum.
    s2 <- sum((w / sum(w))^2)
    data.frame(
      rain = n,
      weights = paste(sprintf("%s %.3f", names(w)[w != 0], w[w != 0]), collapse = ", "),
      source = if (n == "thiessen") {
        thiessen_source
      } else if (n %in% c("equal", "equal_all")) {
        "equal"
      } else if (n %in% names(given)) {
        "given"
      } else {
        sprintf("estimated, R2 %.3f", fit_r2[[n]])
      },
      weights_sum = round(sum(w), 3),
      sum_of_squares = round(s2, 3),
      effective_gauges = round(1 / s2, 2),
      error_factor = round(sqrt(s2), 2),
      error_factor_rho_0.3 = round(sqrt(0.7 * s2 + 0.3), 2),
      error_factor_rho_0.5 = round(sqrt(0.5 * s2 + 0.5), 2),
      suggested_rain_error = round(sigma / 100 * sqrt(s2), 3),
      effective_gauges_p05 = round(stats::quantile(n_eff_series[[n]], 0.05, na.rm = TRUE), 2),
      largest_floods_below_1.5 = as.integer(low_in_flood[[n]])
    )
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
    graphics::plot(range(days),
                   c(0, top),
                   type = "n",
                   xlab = "",
                   ylab = "Effective number of gauges",
                   main = "How many gauges each catchment average used, day by day")
    graphics::abline(h = 1.5, lty = 2, col = "grey50")
    for (i in seq_along(daily)) {
      v <- daily[[i]]
      v[!is.finite(v)] <- NA
      graphics::lines(days, v, col = colours[match(names(daily)[i], names_r)], lwd = 2)
    }
    graphics::rug(as.Date(grid$time[floods$rain_start[largest]]),
                  side = 3,
                  col = "grey40",
                  lwd = 2)
    graphics::legend("bottomleft",
                     names(daily),
                     bty = "n",
                     lwd = 2,
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
  # A day's total, missing unless every step of the day is there.
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
    data.frame(gauge = n,
               day = d,
               month = as.integer(format(d, "%m")),
               gauge_mm = g[ok],
               radar_mm = r[ok],
               ratio = r[ok] / g[ok])
  }))
  if (!is.null(pairs_rg) && nrow(pairs_rg)) {
    # Meteorological seasons, by calendar month.
    season_of <- c("Winter", "Winter", "Spring", "Spring", "Spring", "Summer", "Summer",
                   "Summer", "Autumn", "Autumn", "Autumn", "Winter")
    pairs_rg$season <- season_of[pairs_rg$month]
    radar_table <- do.call(rbind, lapply(split(pairs_rg, pairs_rg$gauge), function(p) {
      s <- tapply(p$ratio, p$season, stats::median)
      data.frame(gauge = p$gauge[1],
                 days = nrow(p),
                 ratio_all = round(stats::median(p$ratio), 2),
                 ratio_winter = round(unname(s["Winter"]), 2),
                 ratio_spring = round(unname(s["Spring"]), 2),
                 ratio_summer = round(unname(s["Summer"]), 2),
                 ratio_autumn = round(unname(s["Autumn"]), 2))
    }))
    # In the gauges' own order, without gauges that had no days.
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
      # A month's median needs at least three days.
      by_month <- vapply(gauge_names, function(n) {
        p <- pairs_rg[pairs_rg$gauge == n, ]
        vapply(months, function(m) {
          x <- p$ratio[p$month == m]
          if (length(x) >= 3) stats::median(x) else NA_real_
        }, numeric(1))
      }, numeric(12))
      graphics::par(mar = c(4, 4.5, 2, 1))
      top <- max(c(1.5, by_month), na.rm = TRUE) * 1.1
      graphics::matplot(seq_along(months),
                        by_month,
                        type = "b",
                        pch = 19,
                        lty = 1,
                        lwd = 2,
                        col = colours[match(gauge_names, names_r)],
                        xaxt = "n",
                        xlab = "",
                        ylim = c(0, top),
                        ylab = "Radar / gauge, daily totals (median)",
                        main = "Radar against each gauge, month by month")
      graphics::axis(1, at = seq_along(months), labels = month.abb[months])
      graphics::abline(h = 1, lty = 2, col = "grey50")
      graphics::legend("top",
                       gauge_names,
                       col = colours[match(gauge_names, names_r)],
                       lwd = 2,
                       pch = 19,
                       bty = "n",
                       ncol = min(5, length(gauge_names)))
    })
  }
}

# ---- The ranking ---------------------------------------------------------------------------

# One row per series, every measure side by side.
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
  flood_ratio_spread = flood_table$ratio_spread
)

# Two measures against the other series, since a catchment's true rain is never known: how
# far a series' total sits from the median of all the series, and how far its lag sits from
# their median lag. One series well apart from the rest is the likelier to be wrong; when
# most of the series are poor, read these with care.
med_total <- stats::median(ranking$rain_mm_per_year)
ranking$total_apart_pct <- round(100 * abs(ranking$rain_mm_per_year - med_total) / med_total,
                                 1)
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
    if (x$double_mass_bend_pct > 2) {
      sprintf("it bends %.0f%% from the other series", x$double_mass_bend_pct)
    },
    if (x$lag_h < 0) "the river rises before its rain: check its clock",
    if (x$dry_events > 1) sprintf("%d floods it saw almost no rain for", x$dry_events),
    if (x$missed_storms_pct > 5) {
      sprintf("%.0f%% of floods had more quick flow than its rain", x$missed_storms_pct)
    },
    if (x$missing_pct > 5) sprintf("%.0f%% of its record is missing", x$missing_pct),
    if (x$total_apart_pct > 10) {
      sprintf("its total is %.0f%% from the median of the series", x$total_apart_pct)
    },
    if (x$lag_apart_h >= 1) {
      sprintf("its lag is %g h from the others': check its clock", x$lag_apart_h)
    })
}
lags <- stats::setNames(ranking$lag_h, ranking$rain)
best <- ranking$rain[1]

# ---- The summary ---------------------------------------------------------------------------

# summary.md, built a section at a time; a section left out is NULL, which c() drops.
lines <- c(
  "# Which rain series best explains the flow", "",
  sprintf("%.1f years of %s data, %s to %s; %d rain series; %d floods compared.",
          years,
          if (step_hours < 1) {
            sprintf("%g-minute", step_hours * 60)
          } else {
            sprintf("%g-hour", step_hours)
          },
          compared_from,
          compared_to,
          length(names_r),
          nrow(floods)),
  if (length(limiting)) {
    c("",
      sprintf(paste("The period asked for was %s to %s; the comparison is cut to the stretch",
                    "every series covers, set by %s. The averages in `catchment_rain/` cover",
                    "the whole period."),
              period_from,
              period_to,
              toString(limiting)))
  },

  # The balance and double-mass checks use only the steps where every series has a value, so
  # a short series narrows them all.
  if (mean(common) < 0.8) {
    short <- names(missing_pct)[missing_pct > 20]
    c("",
      sprintf(paste("**Only %.0f%% of the record (%.1f years) has every series.** The water",
                    "balance and double-mass checks use those steps alone; the flood checks",
                    "judge each series on the floods it covers. The shortest: %s. Leave",
                    "it out for a fair comparison over the whole record, or keep it to",
                    "compare everything over its period."),
              100 * mean(common),
              years * mean(common),
              paste(sprintf("%s (%.0f%% missing)", short, missing_pct[short]),
                    collapse = ", ")),
      "")
  },
  "Judged from the data alone, before any model. How to read each plot: the HOW TO READ",
  "notes in compare_rain.R, beside the line that draws it.", "",

  # The ranking.
  sprintf("**Best by the data: %s.** The ranking, best first (mean rank over twelve", best),
  "measures):", "",
  sprintf(paste("%d. **%s** (mean rank %.1f): runoff ratio %.2f, quick-response correlation",
                "%.2f, first for %d of %d floods."),
          seq_len(nrow(ranking)),
          ranking$rain,
          ranking$mean_rank,
          ranking$runoff_ratio,
          ranking$response_r,
          ranking$flood_wins,
          sum(response$summary$event_wins)),

  # The averages built, with their weights.
  "", "## The catchment averages built", "",
  sprintf("- **%s**: %s.",
          names(weights),
          vapply(names(weights), function(n) {
            w <- weights[[n]]
            paste(sprintf("%s %.3f", names(w), w), collapse = ", ")
          }, "")),
  if (!is.null(boundary)) {
    c(if (!is.null(built$multiquadric)) {
        sprintf(paste("- **multiquadric**: every gauge, on a %g m grid, shape parameter c = %.0f m",
                      "(chosen by leaving out one gauge at a time)."),
                grid_spacing_m,
                multiquadric_c)
      },
      if (!is.null(built$idw)) {
        sprintf("- **idw**: every gauge, weighted by 1 / distance^2, on a %g m grid.",
                grid_spacing_m)
      },
      if (!is.null(built$h19_bias)) {
        paste("- **h19_bias**: H19 over the catchment, scaled day by day by the gauges' total",
              "over the radar's at the gauges (`radar_bias_factors.csv`).")
      },
      if (!is.null(built$multiquadric_h19)) {
        paste("- **multiquadric_h19**: the same surface through the gauges, with H19's pattern",
              "between them (conditional merging), on the radar's 1 km cells. A step needs",
              "the radar over the catchment and at every gauge.")
      } else if (!is.null(radar_folder) && step_hours != 0.25) {
        "- multiquadric_h19: not built (it needs 15-minute data)."
      },
      "",
      # The Thiessen weights given, against those from the geometry.
      if (thiessen_source == "given") {
        c(sprintf("Thiessen weights from the gauge positions and the boundary: %s. Given: %s.",
                  paste(sprintf("%s %.3f", names(geometry_weights), geometry_weights),
                        collapse = ", "),
                  paste(sprintf("%s %.3f", names(thiessen_weights), thiessen_weights),
                        collapse = ", ")),
          if (max(abs(geometry_weights[names(thiessen_weights)] - thiessen_weights)) > 0.05) {
            paste("**They differ by more than 0.05.** Check the gauge positions, the boundary,",
                  "and how the given weights were made.")
          })
      } else {
        paste("No Thiessen weights were given: thiessen uses those worked out from the gauge",
              "positions and the boundary. The operational weights may differ.")
      })
  } else {
    "- multiquadric: not built (no catchment_boundary given)."
  },
  if (length(skipped_methods)) {
    c("", "Not built, though asked for:", "",
      sprintf("- %s: %s.", names(skipped_methods), skipped_methods))
  },
  if (!is.null(built$multiquadric_lta)) {
    sprintf(paste("- **multiquadric_lta**: each gauge's rain as a share of its long-term",
                  "average (%s), a multiquadric surface through the shares (c = %.0f m), times",
                  "the grid."),
            lta_rain_file,
            multiquadric_lta_c)
  },
  "", "Each is in `catchment_rain/`, as a CSV ready for calibrate_site.R.",

  # The downloads, with each gauge's quality flags.
  if (!is.null(downloads)) {
    c("",
      sprintf(paste("Gauges downloaded from the EA Hydrology API with reach.io, %s to %s",
                    "(`gauge_downloads.csv`):"),
              period_from,
              period_to),
      "",
      sprintf("- %s: %s, WISKI ID %s%s",
              downloads$gauge,
              downloads$label,
              downloads$wiski_id,
              ifelse(is.na(downloads$readings),
                     ", already downloaded.",
                     sprintf(", %d readings, %d missing; other flags: %s.",
                             downloads$readings,
                             downloads$missing,
                             downloads$flags))),
      "",
      "Readings flagged Missing are gaps. Other flags (Suspect, Estimated, Unchecked) are kept",
      "and only counted here: quality control belongs upstream, in reach.validate.")
  },

  # The warnings, series by series.
  "", "## Warnings", "",
  unlist(lapply(seq_len(nrow(ranking)), function(i) {
    w <- warnings_for(i)
    sprintf("- %s: %s.",
            ranking$rain[i],
            if (length(w)) paste(w, collapse = "; ") else "none")
  })),
  if (diff(range(lags)) >= 1) {
    c("",
      sprintf(paste("The river answers to the series at lags from %g to %g hours. Series",
                    "a whole hour or more apart often mean a clock or time-zone error in",
                    "one."),
              min(lags),
              max(lags)))
  },

  # The weights and the error each average keeps.
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
              weights_table$rain,
              weights_table$weights,
              weights_table$source,
              weights_table$effective_gauges,
              100 * weights_table$error_factor,
              sigma * weights_table$error_factor,
              weights_table$suggested_rain_error,
              weights_table$effective_gauges_p05,
              weights_table$largest_floods_below_1.5),
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

  # H19 from the processed extracts.
  if (!is.null(radar_processed)) {
    c("", "## H19 radar from the processed extracts", "",
      sprintf(paste("h19 is polygon %s from the yearly extracts in %s: the area-weighted mean",
                    "over Hyrad's polygon, which may not match catchment_boundary exactly.",
                    "%.1f%% of its 15-minute steps are missing%s."),
              radar_polygon_id,
              radar_processed_folder,
              100 * mean(is.na(radar_processed$rain)),
              if (length(attr(radar_processed, "years_missing"))) {
                paste0(" (no extract for ", toString(attr(radar_processed, "years_missing")), ")")
              } else ""),
      "", "H19 and everything made from it are restricted: keep this folder on restricted",
      "storage.")
  },

  # H19 from the daily files: the layouts, and the radar against the gauges.
  if (!is.null(radar_layouts)) {
    l <- radar_layouts$layouts
    c("", "## H19 radar", "",
      sprintf("%d files in %d layout%s (`radar_layouts.csv`):",
              sum(l$files),
              nrow(l),
              if (nrow(l) == 1) "" else "s"),
      sprintf(paste("- Layout %d, %d files, %s to %s: `%s` in %s, stamped at the %s of each",
                    "step%s."),
              l$layout,
              l$files,
              l$first_day,
              l$last_day,
              l$variable,
              l$units,
              l$stamp,
              ifelse(l$stamp == "end", " (moved back 15 minutes)", "")),
      "",
      if (radar_done) {
        c("The radar over each gauge against the gauge, daily totals (`radar_vs_gauges.csv`):",
          "",
          sprintf(paste("- **%s**: radar / gauge %.2f over %d days; winter %.2f, summer %.2f",
                        "(winter over summer %.2f)."),
                  radar_table$gauge,
                  radar_table$ratio_all,
                  radar_table$days,
                  radar_table$ratio_winter,
                  radar_table$ratio_summer,
                  radar_table$winter_over_summer),
          "",
          paste("A winter ratio clearly above the summer one points to the gauge losing rain",
                "to wind; the same ratio all year points to the radar's own scaling. Wind",
                "speed would separate them further."))
      },
      "", "H19 and everything made from it are restricted: keep this folder on restricted",
      "storage.")
  },

  # The gauges' corrections to the long-term average.
  if (!is.null(corrections)) {
    c("", "## Gauges corrected to the long-term average", "",
      sprintf(paste("Each gauge's average year over %s to %s, against %s at the gauge",
                    "(`lta_corrections.csv`); the factors are %s:"),
              correction_from,
              correction_to,
              lta_rain_file,
              if (identical(lta_correction, "relative")) {
                "relative (each divided by the median), so the gauges keep their overall level"
              } else {
                "absolute, putting each gauge on the grid's level"
              }),
      "",
      sprintf(paste("- **%s**: %.0f mm a year over %.1f years (%.0f%% of the record) against",
                    "%.0f; factor %.3f."),
              corrections$gauge,
              corrections$mm_per_year,
              corrections$record_years,
              100 * corrections$coverage,
              corrections$lta_mm_per_year,
              corrections$factor),
      "",
      paste("Every series built from the gauges, and the gauges themselves, use the corrected",
            "rain. Readings flagged Suspect are kept in the averages."))
  },

  # Each series against the long-term average.
  if (!is.null(lta_check)) {
    c("", "## Against the long-term average", "",
      sprintf(paste("The catchment's long-term average is %.0f mm a year (%s). Each series'",
                    "annual rain over the period compared, against it (a gauge against its own",
                    "cell's; `long_term_average_check.csv`):"),
              lta_catchment,
              lta_rain_file),
      "",
      sprintf("- **%s**: %.0f mm a year against %.0f, ratio %.2f.",
              lta_check$rain,
              lta_check$rain_mm_per_year,
              lta_check$lta_mm_per_year,
              lta_check$ratio),
      "",
      sprintf(paste("Over %.1f years the years' own weather moves every ratio together: read",
                    "the differences between series, not their level. A gauge well below the",
                    "others may undercatch. A grid made from gauges (as HadUK-Grid is) is not",
                    "independent of them."),
              years))
  },

  # What to do next, and the files written.
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
  }
)
writeLines(lines, file.path(output_folder, "summary.md"))

# The ranking and the weights in the console too.
print(ranking[, c("rain", "mean_rank", "runoff_ratio", "total_apart_pct", "response_r",
                  "lag_h", "flood_wins", "missed_storms_pct", "flood_ratio_spread")],
      row.names = FALSE)
if (weights_done) {
  print(weights_table[, c("rain", "source", "effective_gauges", "error_factor",
                          "suggested_rain_error")],
        row.names = FALSE)
}

# ---- The report -----------------------------------------------------------------------------

# report.html: one self-contained page with every plot embedded, each test explained where it
# appears, and the tables beside the plots. The text under each plot is its HOW TO READ note
# from this script, so the script and the report say the same.
notes_file <- system.file("scripts", "compare_rain.R", package = "pdmS7")
notes <- if (nzchar(notes_file)) read_plot_notes(notes_file) else list()

# A plot from the output folder, with its note: nothing when the plot was not drawn.
plot_blocks <- function(file, caption) {
  path <- file.path(output_folder, file)
  if (!file.exists(path)) return(list())
  note <- notes[[file]]
  c(list(report_image(path, caption)),
    if (!is.null(note) && nzchar(note$text)) list(report_text(note$text)),
    if (!is.null(note) && length(note$points)) list(report_list(note$points)))
}

uses_radar <- !is.null(radar_layouts) || !is.null(radar_processed)
step_text <- if (step_hours < 1) {
  sprintf("%g-minute", step_hours * 60)
} else {
  sprintf("%g-hour", step_hours)
}

# The gauges: where each sits, how much of the period it has, and its flags and correction.
gauge_table <- data.frame(gauge = gauge_names)
if (!is.null(gauges$wiski_id)) gauge_table$wiski_id <- gauges$wiski_id
if (!is.null(boundary) && have_positions) {
  gauge_table$km_outside <- round(distance_to_boundary(gauges$x, gauges$y, boundary) / 1000,
                                  1)
}
gauge_table$missing_pct <- round(missing_pct[gauge_names], 1)
if (!is.null(downloads)) {
  gauge_table$flags <- downloads$flags[match(gauge_names, downloads$gauge)]
}
if (!is.null(corrections)) {
  gauge_table$lta_factor <- corrections$factor[match(gauge_names, corrections$gauge)]
}

# The weights of each average, one column per gauge, beside what they mean for the error.
weights_wide <- if (weights_done) {
  w <- do.call(rbind, lapply(names(weight_sets), function(n) {
    as.data.frame(as.list(round(weight_sets[[n]], 3)), check.names = FALSE)
  }))
  cbind(data.frame(average = names(weight_sets)),
        w,
        data.frame(source = weights_table$source,
                   effective_gauges = weights_table$effective_gauges,
                   error_factor = weights_table$error_factor,
                   suggested_rain_error = weights_table$suggested_rain_error))
}

# The largest floods, one row per series, one column per flood: rain (runoff ratio).
largest_wide <- if (length(top_floods)) {
  cells <- sprintf("%.1f (%.2f)", largest_table$rain_mm, largest_table$runoff_ratio)
  cells[is.na(largest_table$rain_mm)] <- "missing"
  wide <- data.frame(series = names_r)
  for (k in seq_along(top_floods)) {
    wide[[sprintf("flood %d, %s", k, substr(largest_table$rain_start[largest_table$flood == k][1],
                                             1, 10))]] <- cells[largest_table$flood == k]
  }
  wide
}

blocks <- c(
  list(report_heading("Which rain series best explains the flow", 1),
       report_text(sprintf(paste("%.1f years of %s data, %s to %s; %d rain series; %d floods",
                                 "compared. Every series is judged from the data alone,",
                                 "before any model, against the same flow and the same steps."),
                           years,
                           step_text,
                           compared_from,
                           compared_to,
                           length(names_r),
                           nrow(floods)))),
  if (length(limiting)) {
    list(report_text(sprintf(paste("The period asked for was %s to %s; the comparison is cut",
                                   "to the stretch every series covers, set by %s. The",
                                   "averages in catchment_rain/ cover the whole period."),
                             period_from,
                             period_to,
                             toString(limiting))))
  },
  if (uses_radar) {
    list(report_alert(paste("This report holds H19 radar and results made from it, which are",
                            "restricted: keep it on restricted storage. Run without",
                            "radar_folder and radar_processed_folder for a version to share."),
                      FALSE))
  },
  list(report_alert(sprintf("Best by the data: %s (mean rank %.1f over twelve measures).",
                            best,
                            ranking$mean_rank[1]),
                    TRUE)),
  if (mean(common) < 0.8) {
    list(report_alert(sprintf(paste("Only %.0f%% of the record has every series: the water",
                                    "balance and double-mass checks use those steps alone."),
                              100 * mean(common)),
                      FALSE))
  },

  # At a glance.
  list(report_heading("At a glance"),
       report_text("The ranking puts the tests below together: each measure ranks the series,",
                   "and the overall rank is the mean. It is a guide, not a verdict: read the",
                   "warnings, and the plots."),
       report_table(ranking[, c("rain", "mean_rank", "runoff_ratio", "response_r", "lag_h",
                                "flood_wins", "missed_storms_pct", "total_apart_pct",
                                "double_mass_bend_pct")],
                    caption = "The ranking, best first"),
       report_list(vapply(seq_len(nrow(ranking)), function(i) {
         w <- warnings_for(i)
         sprintf("%s: %s.", ranking$rain[i], if (length(w)) paste(w, collapse = "; ") else "none")
       }, ""))),

  # The data.
  list(report_heading("The data"),
       report_text(sprintf(paste("Flow, evaporation, %d rain gauges and %d other series, cut to",
                                 "the period and put on %s steps. Missing is the share of the",
                                 "period each gauge lacks; flags are the readings the Hydrology",
                                 "API marked other than Good or Missing, kept as they are."),
                           length(gauge_names),
                           length(other_rain_files),
                           step_text)),
       report_table(gauge_table, caption = "The gauges")),
  plot_blocks("gauge_map.png", "The catchment and the gauges in use"),
  plot_blocks("nearby_gauges.png", "The gauges around the catchment, from the search"),

  # The averages and their weights.
  list(report_heading("The catchment averages"),
       report_list(c(
         if (!is.null(built$thiessen)) {
           "thiessen: each gauge weighted by the share of the catchment nearest it."
         },
         if (!is.null(built$equal)) "equal: the gauges with a Thiessen weight, weighted equally.",
         if (!is.null(built$equal_all)) {
           "equal_all: every gauge, inside the catchment or not, weighted equally."
         },
         if (!is.null(built$idw)) {
           "idw: each cell a mean of the gauges, weighted by 1 / distance^2."
         },
         if (!is.null(built$multiquadric)) {
           "multiquadric: a smooth surface through every gauge, averaged over the catchment."
         },
         if (!is.null(built$h19)) "h19: the radar over the catchment, as it is.",
         if (!is.null(built$h19_bias)) {
           paste("h19_bias: the radar scaled day by day by the gauges' total over the radar's",
                 "total at the gauges (a mean-field bias correction), held within 0.2 to 5.")
         },
         if (!is.null(built$multiquadric_lta)) {
           paste("multiquadric_lta: the surface fitted to each gauge's rain as a share of its",
                 "long-term average, scaled back by the grid.")
         },
         if (!is.null(built$multiquadric_h19)) {
           paste("multiquadric_h19: the surface through the gauges, with H19's pattern between",
                 "them (conditional merging).")
         })),
       report_text("Each is renormalised over the gauges reporting at each step: a missing",
                   "gauge's weight is shared among the rest."),
       if (length(skipped_methods)) {
         report_alert(paste("Not built, though asked for:",
                            paste(sprintf("%s (%s)", names(skipped_methods), skipped_methods),
                                  collapse = "; ")),
                      FALSE)
       },
       if (thiessen_source == "given" && !is.null(geometry_weights)) {
         report_text(sprintf("Thiessen weights from the gauge positions and the boundary: %s.",
                             paste(sprintf("%s %.3f", names(geometry_weights), geometry_weights),
                                   collapse = ", ")))
       }),
  if (weights_done) {
    list(report_heading("The weights, and the error each average keeps", 3),
         report_text(sprintf(paste("With weights adding up to 1 and independent gauge errors, an",
                                   "average keeps sqrt(sum of the squared weights) of one",
                                   "gauge's random error, and is worth 1 / (sum of the squared",
                                   "weights) gauges. A single gauge's storm totals look to be up",
                                   "to %.0f%% out here, from how much the gauges disagree flood",
                                   "by flood; the suggested rain_error for calibrate_site.R is",
                                   "that times the error factor."),
                             sigma)),
         report_table(weights_wide, caption = "Weights by gauge, and what they mean"))
  },
  plot_blocks("effective_gauges_over_time.png", "The effective number of gauges, day by day"),

  # The long-term average.
  if (!is.null(corrections)) {
    list(report_heading("Gauges corrected to the long-term average"),
         report_text(sprintf(paste("Each gauge's average year over %s to %s against %s at the",
                                   "gauge gives its factor (%s). Factors within about 10%% are",
                                   "plausible siting; a factor far outside that more often means",
                                   "a fault in the gauge's record than a real difference."),
                             correction_from,
                             correction_to,
                             lta_rain_file,
                             lta_correction)),
         report_table(corrections, caption = "The corrections"))
  },
  if (!is.null(lta_check)) {
    list(report_heading("Against the long-term average", 3),
         report_text(sprintf(paste("The catchment's long-term average is %.0f mm a year. Over a",
                                   "short record the years' own weather moves every ratio",
                                   "together: read the differences between series."),
                             lta_catchment)),
         report_table(lta_check, caption = "Annual rain against the long-term average"))
  },

  # The tests.
  list(report_heading("Test 1: the water balance"),
       report_text("Does each series give a plausible amount of water? The runoff ratio is flow",
                   "over rain; the loss is rain less flow, against what evaporation can take. A",
                   "series with more flow than rain, or losses evaporation cannot explain, has",
                   "the wrong total; one that changes from year to year changed itself."),
       report_table(balance, caption = "The water balance over the record")),
  plot_blocks("rain_by_year.png", paste("Rain by", year_word)),
  plot_blocks("runoff_ratio_by_series.png", paste("Runoff ratio by", year_word)),
  list(report_heading("Test 2: double-mass"),
       report_text("Did any series change part way through? Each series' running total against",
                   "that of the median series: the weather falls on all alike and cancels, so a",
                   "bend is a change in that series (a gauge moved, replaced or failing).")),
  plot_blocks("double_mass_by_series.png", "Double-mass curves"),
  list(report_heading("Test 3: the quick response"),
       report_text("Which series does the river answer to? The correlation of each series' rain",
                   "with the rises in flow, at each lag, and flood by flood which series best",
                   "explains the rise."),
       report_table(response$summary, caption = "The quick response")),
  plot_blocks("quick_response.png", "The quick response at each lag"),
  list(report_heading("Test 4: flood by flood"),
       report_text("For one common set of floods, each series' rain against the flood's quick",
                   "flow. A storm missed has more quick flow than rain; steady ratios across",
                   "floods mark good rain."),
       report_table(flood_table, caption = "Missed storms and the spread of flood ratios")),
  plot_blocks("flood_runoff_ratios.png", "Flood runoff ratios"),
  if (length(top_floods)) {
    c(list(report_heading("The largest floods", 3),
           report_text("The five largest floods by peak flow: each series' rain over the flood,",
                       "with its runoff ratio in brackets.")),
      plot_blocks("largest_floods_cumulative.png", "Cumulative rain through the largest floods"),
      list(report_table(largest_wide, caption = "Rain over each flood, mm (runoff ratio)")))
  },

  # The radar.
  if (!is.null(radar_layouts)) {
    list(report_heading("H19 radar"),
         report_text("The files' layouts, checked from their headers before any radar is used:",
                     "each layout is put on the same footing (times at the start of each step,",
                     "depths in mm per step)."),
         report_table(radar_layouts$layouts[, c("layout", "files", "first_day", "last_day",
                                                "variable", "units", "stamp")],
                      caption = "The layouts of the H19 files"))
  },
  if (radar_done) {
    c(list(report_text("The radar over each gauge against the gauge, day by day: a winter ratio",
                       "clearly above the summer one points to the gauge losing rain to wind."),
           report_table(radar_table, caption = "Radar against each gauge")),
      plot_blocks("radar_vs_gauge_by_month.png", "Radar against each gauge, month by month"))
  },

  # What next.
  list(report_heading("What next"),
       report_list(c(
         paste("Calibrate the PDM on the best two or three series with calibrate_site.R, each",
               "into its own output folder, with the suggested rain_error for each."),
         paste("Compare their validation scores on the largest floods: that says which rain",
               "helps the model, not only which agrees best with the flow before any model."),
         paste("A series that ranks well but carries a warning may still be the best once the",
               "fault is fixed (a clock corrected, a gap filled).")))),
  list(report_text("Tables: rain_ranking.csv, quick_response.csv, largest_floods.csv,",
                   "weights_and_error.csv; the averages in catchment_rain/, ready for",
                   "calibrate_site.R."))
)
report_file <- write_report(blocks, output_folder, "Rain comparison")

say("\nWritten to %s. Read report.html (or summary.md).", normalizePath(output_folder))
