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
# Modified:     2026-11-27 - events, not floods; events missed measured against the median
#                            series; event windows reported and plotted; plots reworked
#               2026-11-27 - the candidate's band source by source, from
#               reach.rate::rating_uncertainty(), with shared gauging error and structure
#               2026-11-27 - the candidate's bootstrap band: the refit test and a flow bound
#               2026-11-27 - a candidate rating fitted from the gaugings when they call for
#               one, written up for review, and the balance on its flow
#               2026-11-27 - whether the rating needs more work, flagged in the report
#               2026-11-27 - the stage from the flow station's WISKI ID alone; the gaugings
#               and the ratings as data frames, or file names
#               2026-11-27 - where the balance fails: rain, rating, a slow loss or gain, or a
#               change over time, with the flow record checked from stage by reach.rate
#               2026-11-26 - laid out one argument a line, with in-line comments
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
# Dependencies: pdmS7 (0.51.0 or later); sf for a shapefile and the search; reach.io
#               to find and download the gauges; arrow (or nanoparquet) for the processed
#               H19 extracts, ncdf4 for the daily H19 files; reach.rate to check the flow
#               record from stage, gaugings and ratings
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
#                   them (conditional merging): with H19 from radar_folder, at 15-minute steps;
#     ked_h19       kriging of the gauges with each step's radar as the drift: the same inputs.
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
#        lag. The series the river answers to best catches the storms that matter for events.
#     5. Event by event: on one common set of events, how often each series had less rain
#        than the event's quick flow (a storm it missed), and how steady each series' event
#        runoff ratios are. Good rain gives steady ratios; poor rain makes them jump about.
#     6. Weights (when the gauges and weights are given): how many gauges' worth of independent
#        rain each catchment average uses, how much of a single gauge's random error survives
#        into it, the single-gauge error the gauges' own disagreement suggests, and when gauges
#        dropping out left the average resting on fewer of them.
#   The ranking at the end puts the evidence together. It is a guide, not a verdict: read
#   the reasons, and look at the plots.

library(pdmS7)
library(data.table)

# The script is written for this pdmS7 or later: an older one lacks functions it uses, and
# would fail part way through.
if (utils::packageVersion("pdmS7") < "0.51.0") {
  stop("compare_rain.R needs pdmS7 0.51.0 or later; this is ",
       as.character(utils::packageVersion("pdmS7")),
       ". Update it with remotes::install_github(\"JonPayneEA/PDMS7\"), then restart R.",
       call. = FALSE)
}

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
#   kriging           block kriging, with each step's standard error (boundary, 3+ gauges)
#   ked_lta           kriging with the long-term average as a drift (lta_rain_file)
#   h19               the radar alone (radar_folder or radar_processed_folder)
#   h19_bias          the radar scaled day by day to the gauges (radar_folder, positions)
#   multiquadric_h19  the gauges' surface with the radar's pattern (radar_folder, 15 minutes)
#   ked_h19           kriging with each step's radar as the drift (radar_folder, 15 minutes)
rain_methods <- c("thiessen", "equal", "equal_all", "idw", "multiquadric", "multiquadric_lta",
                  "kriging", "ked_lta", "h19", "h19_bias", "multiquadric_h19", "ked_h19")

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

# Where the balance fails (optional): the rating's part of a water balance that does not close.
# With 15-minute stage at the flow station, the reach.rate package reads the applied rating back
# from the stage and flow and checks it (revisions, flow off the curve, flow above the top of
# the rating and above bankfull, the flow a stage error makes, stage rising in dry weather).
# With the gaugings and the operational ratings export too, the rating in force is tested
# against the gaugings. Each input left NULL leaves its check out, and the report says so.
# The gaugings and the ratings can each be a file name in data_folder or a data frame already
# in R, as exported or as reach.rate reads it.
stage_file <- NULL             # stage, m, in data_folder: time and value (and quality)
flow_station_wiski <- NULL     # the flow station's WISKI ID: stage downloaded if no file
top_stage_m <- NULL            # the rating's top: NULL takes the highest gauging, if given
bankfull_stage_m <- NULL       # the stage above which water may bypass the section
stage_uncertainty_m <- 0.005   # a systematic stage error to test, m
gaugings_file <- NULL          # the station's gaugings: a file name or a data frame
gauging_station_id <- NULL     # the station's id in the gaugings file, if it holds others
ratings_file <- NULL           # the operational ratings export: a file name or a data frame
rating_station_id <- NULL      # the station's id in the ratings export (its FFFSLocID)
dry_hours <- 48                # a step is dry after this many hours of little rain...
dry_rain_mm <- 0.5             # ...no more than this, on the rain series recommended first
# A candidate rating fitted from the gaugings, for the hydrometry team to review (never to use
# in place of the operational one without them). "auto" fits one when the report says the
# gaugings call for it; "always" fits one whenever there are gaugings; "never" does not.
candidate_rating <- "auto"
candidate_boot <- 500          # draws for the candidate's band (100 or more); 0 for none
# The candidate's band covers the gaugings' sampling and, with these, gauging error shared
# between gaugings (a meter or method reading high or low for all of them), as
# reach.rate::rating_uncertainty() reports it. NULL leaves the shared error not assessed: the
# scripts never assume one. Random error in each gauging is already in the sampling: give only
# the shared part.
gauging_uncertainty <- NULL    # the shared gauging error, a fraction, such as 0.03
gauging_group <- NULL          # a gaugings column whose values share an error, such as a method
# The events. Their windows come from DMCA-ESR's response time; in a catchment fed by
# groundwater that can run to days, and windows that long count later rain against each event.
event_max_response_h <- 150    # the longest response time searched, h: lower it if the windows run on
event_independent <- TRUE      # merge the bursts of one event into one; FALSE keeps an event per burst
missed_share <- 0.25           # a series missed a storm below this share of the median series' rain
missed_min_mm <- 2             # events the median series gives less rain than this are not scored

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
                 "kriging", "ked_lta", "h19", "h19_bias", "multiquadric_h19", "ked_h19")
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
surface_methods <- c("idw", "multiquadric", "multiquadric_lta", "kriging", "ked_lta",
                     "multiquadric_h19", "ked_h19")
# The kriging averages' standard errors, mm per step, by average.
built_se <- list()
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

  # Block kriging: a variogram fitted once to the gauges' wet steps (rain relative to each
  # step's mean), then the catchment average weighted to have the least error as a block, with
  # that error at every step. It needs three gauges or more to fit the variogram.
  if (any(c("kriging", "ked_lta", "ked_h19") %in% rain_methods)) {
    if (nrow(gauges) < 3) {
      skip_method("kriging", "it needs three gauges or more")
      skip_method("ked_lta", "it needs three gauges or more")
      skip_method("ked_h19", "it needs three gauges or more")
    } else {
      say("Variogram of the gauges' rain")
      rain_variogram <- rainfall_variogram(located, G)
      if ("kriging" %in% rain_methods) {
        say("Block kriging over the catchment")
        fit_k <- merge_rainfall(located,
                                G[wet_steps, , drop = FALSE],
                                cell_grid,
                                mask,
                                method = "kriging",
                                variogram = rain_variogram)
        built$kriging <- dry_or_missing
        built$kriging[wet_steps] <- fit_k$rain
        built_se$kriging <- dry_or_missing
        built_se$kriging[wet_steps] <- fit_k$se
      }
    }
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
  # Kriging with the long-term average as the drift: the gauges fitted around its pattern.
  if ("ked_lta" %in% rain_methods && exists("rain_variogram")) {
    say("Kriging with the long-term average as the drift")
    fit_ked <- merge_rainfall(located,
                              G[wet_steps, , drop = FALSE],
                              cell_grid,
                              mask,
                              method = "ked",
                              variogram = rain_variogram,
                              drift = lta_cells,
                              drift_at_gauges = unname(lta_gauges))
    built$ked_lta <- dry_or_missing
    built$ked_lta[wet_steps] <- fit_ked$rain
    built_se$ked_lta <- dry_or_missing
    built_se$ked_lta[wet_steps] <- fit_ked$se
  }
} else {
  skip_method("multiquadric_lta", "it needs lta_rain_file, the long-term average grid")
  skip_method("ked_lta", "it needs lta_rain_file, the long-term average grid")
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
  # Kriging with the radar as the drift: the gauges' variogram, and at each step the weights
  # that follow that step's radar pattern, from the same cells.
  want_ked <- "ked_h19" %in% rain_methods && have_boundary && have_positions &&
    exists("rain_variogram") && step_hours == 0.25

  # The radar read from the daily files is kept for later runs: radar_extract.csv holds the
  # catchment average and the radar over each gauge; radar_cells.rds holds the radar in every
  # catchment cell and in each gauge's cell, which is all the conditional merge needs. A later
  # run with the same files and gauges reads none of the files again.
  cache <- file.path(output_folder, "radar_extract.csv")
  cache_files <- file.path(output_folder, "radar_extract_files.txt")
  cells_file <- file.path(output_folder, "radar_cells.rds")
  cached <- file.exists(cache) && file.exists(cache_files) &&
    identical(sort(readLines(cache_files)), sort(radar_files)) &&
    identical(setdiff(names(fread(cache, nrows = 0)), c("time", "h19", "h19_multiquadric")),
              paste0("radar_at_", gauge_names)) &&
    (!(conditional || want_ked) || file.exists(cells_file))

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

    # The cell each gauge sits in, for the conditional merge.
    gauge_cell <- if (have_positions) {
      cbind(vapply(gauges$x, function(x) which.min(abs(h$grid$x - x)), integer(1)),
            vapply(gauges$y, function(y) which.min(abs(h$grid$y - y)), integer(1)))
    }
    keep_cells <- have_boundary && have_positions
    n_inside <- if (keep_cells) sum(in_catchment) else 0
    cell_values <- if (keep_cells) {
      matrix(NA_real_, length(h$time), n_inside + nrow(gauge_cell))
    }
    say("  reading %d steps from %d files", length(h$time), length(radar_files))

    # Every radar step: the catchment average and the radar over each gauge, with the cells
    # kept for the conditional merge. A step missing more than a tenth of the catchment's cells
    # is missing.
    values <- t(vapply(seq_along(h$time), function(s) {
      r <- h$radar(s)
      r[r < 0] <- NA
      if (keep_cells) cell_values[s, ] <<- c(r[in_catchment], r[gauge_cell])
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
    setnames(extract, c("time", "h19", paste0("radar_at_", gauge_names)))
    fwrite(extract[, time := format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC")], cache)
    extract$time <- as.POSIXct(extract$time, tz = "UTC")
    if (keep_cells) {
      saveRDS(list(grid = h$grid,
                   in_catchment = in_catchment,
                   gauge_cell = gauge_cell,
                   time = h$time,
                   values = cell_values),
              cells_file)
    }
    writeLines(radar_files, cache_files)
  }

  # The conditional merge, from the cells kept. It depends on the gauges' rain (and any
  # correction to it), their places and the multiquadric's c, so it is kept with a key made
  # of those, and worked out again from the cells, without reading the files, when they change.
  if (conditional) {
    merge_file <- file.path(output_folder, "radar_merge.csv")
    merge_key_file <- file.path(output_folder, "radar_merge_key.txt")
    merge_key <- paste(c(gauge_names,
                         format(gauges$x, nsmall = 1),
                         format(gauges$y, nsmall = 1),
                         format(colSums(G, na.rm = TRUE), digits = 12),
                         colSums(is.na(G)),
                         format(multiquadric_c, digits = 12),
                         format(range(grid$time)),
                         readLines(cache_files)),
                       collapse = "|")
    reuse <- file.exists(merge_file) && file.exists(merge_key_file) &&
      identical(paste(readLines(merge_key_file), collapse = "|"), merge_key)
    if (reuse) {
      say("  using the conditional merge already worked out (%s)", basename(merge_file))
      merged <- fread(merge_file)
      merged$time <- as.POSIXct(merged$time, tz = "UTC")
    } else {
      say("  conditional merge of the gauges and the radar")
      kept <- readRDS(cells_file)
      n_inside <- sum(kept$in_catchment)
      gauge_row <- match(as.numeric(kept$time), as.numeric(grid$time))
      # One step's merge: missing without the gauges, or with radar missing over the catchment
      # or at a gauge; 0 when gauges and radar are all dry.
      merge_step <- function(s) {
        g <- if (is.na(gauge_row[s])) rep(NA_real_, length(gauge_names)) else G[gauge_row[s], ]
        inside <- kept$values[s, seq_len(n_inside)]
        at_gauge <- kept$values[s, n_inside + seq_len(nrow(kept$gauge_cell))]
        if (all(is.na(g)) || anyNA(inside) || anyNA(at_gauge)) return(NA_real_)
        if (all(g <= 0, na.rm = TRUE) && all(inside <= 0) && all(at_gauge <= 0)) return(0)
        # The step's field, back on the radar's grid: the cells kept, the rest unused.
        r <- matrix(NA_real_, length(kept$grid$x), length(kept$grid$y))
        r[kept$in_catchment] <- inside
        r[kept$gauge_cell] <- at_gauge
        merge_rainfall(located,
                       matrix(g, nrow = 1),
                       kept$grid,
                       kept$in_catchment,
                       radar = function(t) r,
                       method = "conditional",
                       c = multiquadric_c)$rain
      }
      merged <- data.table(time = kept$time,
                           h19_multiquadric = vapply(seq_along(kept$time), merge_step, 0))
      fwrite(merged[, .(time = format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                        h19_multiquadric)],
             merge_file)
      writeLines(strsplit(merge_key, "|", fixed = TRUE)[[1]], merge_key_file)
    }
  }

  # Kriging with each step's radar as the drift, from the cells kept, in one pass: the parts of
  # the kriging system that depend only on the gauges' places are worked out once for each set
  # of gauges reporting, and the rest at every step. Kept like the conditional merge, with a key
  # of the gauges' rain, their places and the variogram.
  if (want_ked) {
    ked_file <- file.path(output_folder, "radar_ked.csv")
    ked_key_file <- file.path(output_folder, "radar_ked_key.txt")
    ked_key <- paste(c(gauge_names,
                       format(gauges$x, nsmall = 1),
                       format(gauges$y, nsmall = 1),
                       format(colSums(G, na.rm = TRUE), digits = 12),
                       colSums(is.na(G)),
                       format(unlist(rain_variogram[c("nugget", "partial_sill", "range")]),
                              digits = 12),
                       format(range(grid$time)),
                       readLines(cache_files)),
                     collapse = "|")
    reuse_ked <- file.exists(ked_file) && file.exists(ked_key_file) &&
      identical(paste(readLines(ked_key_file), collapse = "|"), ked_key)
    if (reuse_ked) {
      say("  using the kriging with the radar already worked out (%s)", basename(ked_file))
      ked <- fread(ked_file)
      ked$time <- as.POSIXct(ked$time, tz = "UTC")
    } else {
      say("  kriging of the gauges with the radar as the drift")
      kept <- readRDS(cells_file)
      n_inside <- sum(kept$in_catchment)
      n_cell <- nrow(kept$gauge_cell)
      gauge_row <- match(as.numeric(kept$time), as.numeric(grid$time))
      g_at <- G[gauge_row, , drop = FALSE]
      # A step needs the radar in every cell kept; with that, a step with every gauge dry is 0.
      radar_whole <- !apply(is.na(kept$values), 1, any)
      wet <- which(radar_whole & rowSums(g_at > 0, na.rm = TRUE) > 0)
      ked_rain <- ifelse(radar_whole & rowSums(!is.na(g_at)) > 0, 0, NA_real_)
      ked_se <- ked_rain
      if (length(wet)) {
        # The step's radar, back on the radar's grid: the cells kept, the rest unused.
        radar_drift <- function(t) {
          r <- matrix(NA_real_, length(kept$grid$x), length(kept$grid$y))
          r[kept$in_catchment] <- kept$values[wet[t], seq_len(n_inside)]
          r[kept$gauge_cell] <- kept$values[wet[t], n_inside + seq_len(n_cell)]
          r
        }
        fit_kh <- merge_rainfall(located,
                                 g_at[wet, , drop = FALSE],
                                 kept$grid,
                                 kept$in_catchment,
                                 method = "ked",
                                 variogram = rain_variogram,
                                 drift = radar_drift)
        ked_rain[wet] <- fit_kh$rain
        ked_se[wet] <- fit_kh$se
      }
      ked <- data.table(time = kept$time, h19_ked = ked_rain, h19_ked_se = ked_se)
      fwrite(ked[, .(time = format(time, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                     h19_ked, h19_ked_se)],
             ked_file)
      writeLines(strsplit(ked_key, "|", fixed = TRUE)[[1]], ked_key_file)
    }
    built$ked_h19 <- onto_grid(ked$h19_ked, ked$time)
    built_se$ked_h19 <- onto_grid(ked$h19_ked_se, ked$time)
  }

  # The processed extract, where given, is the catchment average; the daily files then give
  # only the radar over each gauge.
  if (have_boundary && is.null(radar_processed)) {
    h19_series <- onto_grid(extract$h19, extract$time)
  }
  if (conditional) {
    built$multiquadric_h19 <- onto_grid(merged$h19_multiquadric, merged$time)
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

if (is.null(built$ked_h19) && !"ked_h19" %in% names(skipped_methods)) {
  skip_method("ked_h19",
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
  built_se <- lapply(built_se, function(v) v[keep])
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

# Names lines at their right-hand ends, in the right margin, nudged apart so none overlap: a
# legend for many lines that does not cover them. y is each line's last value; gap the least
# distance between labels, as a share of the plot's height.
label_ends <- function(y, labels, cols, gap = 0.045, cex = 0.75) {
  usr <- graphics::par("usr")
  keep <- is.finite(y)
  if (!any(keep)) return(invisible())
  y <- y[keep]
  labels <- labels[keep]
  cols <- cols[keep]
  o <- order(y)
  step <- gap * (usr[4] - usr[3])
  placed <- y[o]
  for (i in seq_along(placed)[-1]) placed[i] <- max(placed[i], placed[i - 1] + step)
  # Pulled back down if the stack has run off the top.
  over <- placed[length(placed)] - usr[4]
  if (over > 0) placed <- placed - over
  graphics::text(usr[2], placed, labels[o], col = cols[o], pos = 4, cex = cex, xpd = NA)
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
# colour): the Thiessen weights are the shares of those parts. The grey rings are 5 and 10 km
# out from the boundary; other gauges the search found are open grey circles.
# Good: the gauges spread across the catchment and around it, each part a fair share.
# Worry if: one gauge's part covers most of the catchment (the averages lean on that gauge:
#   see the effective number of gauges); a gauge in the wrong place (its position: x and y
#   swapped, or the wrong grid); weights given that differ from the parts drawn.
if (!is.null(boundary) && have_positions) {
  png_of("gauge_map.png", function() {
    gauge_colours <- colours[match(gauge_names, names_r)]
    gauge_colours[is.na(gauge_colours)] <- "grey40"
    # The rings 5 and 10 km out from the boundary, by buffering it (with sf, where installed).
    rings <- if (requireNamespace("sf", quietly = TRUE)) {
      ring <- sf::st_sfc(sf::st_polygon(list(as.matrix(rbind(boundary, boundary[1, ])))),
                         crs = 27700)
      lapply(c(5, 10), function(km) sf::st_coordinates(sf::st_buffer(ring, 1000 * km)))
    }
    # The catchment, the gauges in use and the rings, with a margin.
    reach_x <- c(boundary$x, gauges$x, if (length(rings)) rings[[2]][, "X"])
    reach_y <- c(boundary$y, gauges$y, if (length(rings)) rings[[2]][, "Y"])
    graphics::par(mar = c(4, 4.5, 2, 1))
    graphics::plot(range(reach_x) + c(-1000, 1000),
                   range(reach_y) + c(-1000, 1000),
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
    for (xy in rings) graphics::lines(xy[, "X"], xy[, "Y"], col = "grey70", lty = 2)
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
    graphics::legend("bottomleft",
                     bty = "n",
                     cex = 0.8,
                     c("Catchment", "Gauge in use (Thiessen weight)", "Other gauge found",
                       if (length(rings)) "5 and 10 km from the boundary"),
                     col = c("#B3261E", "grey30", "grey55", if (length(rings)) "grey70"),
                     pch = c(NA, 21, 1, if (length(rings)) NA),
                     pt.bg = c(NA, "grey80", NA, if (length(rings)) NA),
                     lty = c(1, NA, NA, if (length(rings)) 2),
                     lwd = c(2, NA, NA, if (length(rings)) 1))
  }, width = 1400, height = 1400)
}

# HOW TO READ variogram.png
# For each pair of gauges (a point), how differently their rain behaves, as half the mean
# squared difference of their rain relative to each wet step's mean, against the distance
# between them; the line is the exponential model kriging uses. Where the line starts (the
# nugget) is the difference between gauges side by side: gauge error and very local rain. The
# range is how far the rain stays related: the line is near its top by three times it. The
# dotted lines mark the closest and the farthest pair: outside them the line is the model's
# alone. The two pairs farthest from the line are named.
# Good: points rising with distance and levelling off, close to the line.
# Worry if: the points are flat (the gauges' rain is no more alike close together than far
#   apart: kriging then weights them nearly equally); one pair far above the others (a gauge
#   out of step with its neighbours: check its record); a range far below the gauges' spacing
#   (the gauges are too far apart to say much about the rain between them). With fewer than
#   six pairs (four gauges) three parameters rest on very few points: read the fit loosely.
if (exists("rain_variogram")) {
  png_of("variogram.png", function() {
    e <- rain_variogram$empirical
    e <- e[is.finite(e$semivariance), ]
    h <- seq(0, max(e$distance) * 1.1, length.out = 200)
    model <- ifelse(h > 0,
                    rain_variogram$nugget +
                      rain_variogram$partial_sill * (1 - exp(-h / rain_variogram$range)),
                    0)
    graphics::par(mar = c(4.5, 4.5, 2, 1))
    graphics::plot(e$distance / 1000,
                   e$semivariance,
                   pch = 19,
                   col = "#1B6F80",
                   xlim = c(0, max(h) / 1000),
                   ylim = c(0, max(c(e$semivariance, model)) * 1.1),
                   xlab = "Distance between the gauges (km)",
                   ylab = "Semivariance of relative rain",
                   main = sprintf("Variogram: nugget %.2f, sill %.2f, range %.1f km",
                                  rain_variogram$nugget,
                                  rain_variogram$nugget + rain_variogram$partial_sill,
                                  rain_variogram$range / 1000))
    graphics::lines(h / 1000, model, lwd = 2, col = "#B3261E")
    # Only the two pairs farthest from the line are named: with many pairs the names collide.
    fitted_at <- rain_variogram$nugget +
      rain_variogram$partial_sill * (1 - exp(-e$distance / rain_variogram$range))
    odd <- utils::head(order(-abs(e$semivariance - fitted_at)), 2)
    graphics::text(e$distance[odd] / 1000,
                   e$semivariance[odd],
                   paste(e$gauge_a[odd], e$gauge_b[odd], sep = "-"),
                   pos = 3,
                   cex = 0.7)
    # Where the pairs end: beyond it the line is the model's, not the data's.
    graphics::abline(v = c(min(e$distance), max(e$distance)) / 1000, lty = 3, col = "grey60")
  })
}
# Whether the fit rests on the data or runs past it: a range beyond the farthest pair, or a
# nugget with no pair close enough to pin it, are extrapolations.
variogram_note <- if (exists("rain_variogram")) {
  e <- rain_variogram$empirical
  e <- e[is.finite(e$semivariance), ]
  c(if (rain_variogram$range > max(e$distance)) {
      sprintf(paste("The fitted range (%.1f km) lies beyond the farthest pair of gauges (%.1f km):",
                    "the points never level off, so the sill and the range are extrapolated."),
              rain_variogram$range / 1000, max(e$distance) / 1000)
    },
    if (min(e$distance) > rain_variogram$range / 3) {
      sprintf(paste("No pair is closer than %.1f km, so the nugget, where the line starts, is",
                    "extrapolated too."),
              min(e$distance) / 1000)
    })
}

# Each series' rain each year against the median of all the series that year, per cent. A
# steady departure is a matter of scale, which the water balance judges; a departure that
# changes from year to year is a change in that series. The swing is the largest less the
# smallest departure over the complete years.
year_periods <- balances[[1]]$years$period
year_complete <- !grepl("incomplete", balances[[1]]$years$flags)
year_totals <- vapply(balances, function(b) b$years$rain_mm, numeric(length(year_periods)))
if (is.null(dim(year_totals))) year_totals <- matrix(year_totals, nrow = 1)
colnames(year_totals) <- names_r
year_median <- apply(year_totals, 1, stats::median, na.rm = TRUE)
year_departure <- 100 * (sweep(year_totals, 1, year_median, `/`) - 1)
rownames(year_departure) <- year_periods
swing_rows <- if (sum(year_complete) >= 2) year_complete else rep(FALSE, length(year_periods))
year_swing <- vapply(names_r, function(n) {
  d <- year_departure[swing_rows, n]
  if (sum(is.finite(d)) < 2) 0 else round(max(d, na.rm = TRUE) - min(d, na.rm = TRUE), 1)
}, 0)
year_swing_where <- lapply(names_r, function(n) {
  d <- year_departure[swing_rows, n]
  paste(sprintf("%s %+.0f%%", year_periods[swing_rows], d), collapse = ", ")
})
names(year_swing_where) <- names_r
fwrite(data.frame(period = year_periods, round(year_departure, 1), check.names = FALSE),
       file.path(output_folder, "rain_by_year_departure.csv"))

# HOW TO READ rain_by_year.png
# One row per rain series: its rain each year (calendar or water year, as year_start_month
# sets; each named by the year it ends in) against the median of all the series that year, as a
# departure in per cent, one symbol per year, joined across the years. Series whose departure
# swings by more than 5 points between years are named in red.
# Good: each series' symbols close together, whatever their distance from zero (a steady
#   difference is a matter of scale, which the water balance then judges).
# Worry if: one series' symbols sit far apart: it read high or low in some years only. A gauge
#   failed, moved or was replaced then; check its record for those years.
png_of("rain_by_year.png", function() {
  n <- length(names_r)
  y <- rev(seq_len(n))
  xr <- range(c(-5, 5, year_departure), na.rm = TRUE)
  graphics::par(mar = c(4.5, 10, 2, 1))
  graphics::plot(xr, c(0.5, n + 0.5), type = "n", yaxt = "n", ylab = "",
                 xlab = sprintf("Rain against the median of the series that %s, %%", year_word),
                 main = sprintf("Each series' rain by %s, against the others", year_word))
  graphics::abline(v = 0, col = "grey60")
  graphics::abline(v = c(-10, -5, 5, 10), col = "grey90", lty = 3)
  swung <- year_swing > 5
  graphics::mtext(names_r, side = 2, at = y, las = 1, line = 0.5, cex = 0.8,
                  col = ifelse(swung, "#B3261E", "black"))
  for (i in seq_len(n)) {
    d <- year_departure[, i]
    if (!any(is.finite(d))) next
    graphics::segments(min(d, na.rm = TRUE), y[i], max(d, na.rm = TRUE), y[i],
                       col = if (swung[i]) "#B3261E" else "grey70", lwd = 2)
  }
  pchs <- c(19, 17, 15, 18, 1, 2, 0)
  for (p in seq_along(year_periods)) {
    graphics::points(year_departure[p, ], y, pch = pchs[(p - 1) %% length(pchs) + 1],
                     col = if (year_complete[p]) "#1B6F80" else "grey60", cex = 1.1)
  }
  graphics::legend("bottomright", bty = "n", cex = 0.8,
                   legend = paste0(year_periods, ifelse(year_complete, "", " (part year)")),
                   pch = pchs[(seq_along(year_periods) - 1) %% length(pchs) + 1],
                   col = ifelse(year_complete, "#1B6F80", "grey60"))
}, height = max(900, 60 * length(names_r) + 250))

# HOW TO READ runoff_ratio_by_series.png
# The runoff ratio (flow / rain) season by season through the record (three months at a
# time, on the steps every series has): the line is the median of the series, the band the
# range between the lowest and the highest, the red line 1. Every series has the same flow, so
# the band is the rain's disagreement and the line the catchment's own rhythm: high in winter,
# when the ground is wet, low in summer.
# Good: a line well below 1 that rises each winter and falls each summer, in a narrow band.
#   Typical yearly ratios: 0.3 to 0.5 in the lowlands, 0.6 to 0.9 in wet uplands, lower on
#   chalk; one winter season can run higher.
# Worry if: the band reaches 1 (some series give less rain than flowed out: they under-catch,
#   or miss storms); the band widens in some seasons only (the series disagree then: a gauge
#   down, or summer storms the gauges caught differently); the line steps up or down and stays
#   there (the flow changed: a new rating, a changed channel).
png_of("runoff_ratio_by_series.png", function() {
  quarter <- paste0(format(grid$time, "%Y"), " Q", (as.integer(format(grid$time, "%m")) - 1) %/% 3 + 1)
  to_mm <- 3.6 * step_hours / area_km2
  q_mm <- tapply(ifelse(common, flow, 0) * to_mm, quarter, sum)
  r_mm <- vapply(rains, function(r) tapply(ifelse(common, r, 0), quarter, sum), numeric(length(q_mm)))
  if (is.null(dim(r_mm))) r_mm <- matrix(r_mm, nrow = 1)
  share <- tapply(common, quarter, mean)
  ok <- share >= 0.8 & apply(r_mm, 1, min) > 0
  if (!any(ok)) return(invisible())
  rq <- as.numeric(q_mm[ok]) / r_mm[ok, , drop = FALSE]
  k <- seq_len(nrow(rq))
  mid <- stats::setNames(apply(rq, 1, stats::median), names(q_mm)[ok])
  lo <- apply(rq, 1, min)
  hi <- apply(rq, 1, max)
  graphics::par(mar = c(5.5, 4.5, 2, 1))
  graphics::plot(k, mid, type = "n", xaxt = "n", xlab = "",
                 ylim = c(0, max(1.1, hi) * 1.05),
                 ylab = "Runoff ratio (flow / rain)",
                 main = "Runoff ratio season by season: the median series, and the range of all")
  graphics::polygon(c(k, rev(k)), c(lo, rev(hi)),
                    col = grDevices::adjustcolor("#1B6F80", 0.25), border = NA)
  graphics::lines(k, mid, type = "b", pch = 19, col = "#1B6F80", lwd = 2)
  graphics::abline(h = 1, col = "#B3261E")
  graphics::axis(1, at = k, labels = names(mid), las = 2, cex.axis = 0.8)
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
# The double-mass curves as departures: each series' cumulative rain, as a share of its total,
# less that of the median of all the series, in per cent, through the record. A series that
# keeps step with the others stays on zero. Series that bend more than 2% are drawn in colour
# and named at the right with the bend; the rest are grey.
# Good: every line near zero. The weather falls on every gauge alike, so it cancels out here:
#   only a change in one series shows.
# Worry if: a line climbs or falls steadily for a stretch and then levels off: that series
#   changed over the stretch (a gauge moved, replaced, overgrown, or its logger failing). The
#   date is on the axis; a few per cent or more deserves a look at its record then.
png_of("double_mass_by_series.png", function() {
  k <- unique(round(seq(1, length(grid$time), length.out = 2000)))
  dep <- vapply(cumulative, function(d) 100 * (d$rain[k] - d$reference[k]), numeric(length(k)))
  if (is.null(dim(dep))) dep <- matrix(dep, nrow = 1)
  bent <- bend_pct > 2
  graphics::par(mar = c(4, 4.5, 2, 11))
  graphics::plot(range(grid$time[k]), range(c(-1, 1, dep), na.rm = TRUE), type = "n",
                 xlab = "", ylab = "Departure from the median series, % of total",
                 main = "Double-mass curves, as departures from the median series")
  graphics::abline(h = 0, col = "grey50", lty = 2)
  for (i in which(!bent)) graphics::lines(grid$time[k], dep[, i], col = "grey80", lwd = 1.5)
  for (i in which(bent)) graphics::lines(grid$time[k], dep[, i], col = colours[i], lwd = 2.5)
  if (any(bent)) {
    label_ends(dep[nrow(dep), bent], sprintf("%s (%.1f%%)", names_r[bent], bend_pct[bent]),
               colours[bent])
  }
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
# Left: one line per rain series, how closely the rise in river flow follows that series' rain
# (correlation, up) at each lag (across, hours after the rain); the three highest peaks in
# colour, the rest grey. Right: the same near the peak, each series less the highest at each
# lag, so the gaps between the series show. quick_response.csv adds, event by event, which
# series explained the rise best (event_wins), whether a series sees the big storms as big
# (size_r), and how often it saw almost no rain when the others saw a storm (dry_events).
# Good: one series peaks clearly highest and wins most events: the river answers to it. All
#   lags positive and a few hours.
# Worry if: a series peaks at a negative lag (rain cannot follow the flow it causes: its
#   clock is wrong); one series' lag differs from the rest by a whole hour or more (a clock or
#   time-zone error); a series has several dry events (a blocked funnel or a logger down). The
#   series are correlated with each other, which blurs the differences: read the order and
#   the gaps between the lines, not the values alone.
png_of("quick_response.png", function() {
  cr <- response$correlation
  lags_all <- sort(unique(cr$lag_h))
  r_mat <- vapply(names_r, function(n) {
    g <- cr[cr$gauge == n, ]
    g$r[match(lags_all, g$lag_h)]
  }, numeric(length(lags_all)))
  if (is.null(dim(r_mat))) r_mat <- matrix(r_mat, nrow = 1)
  peak <- apply(r_mat, 2, max, na.rm = TRUE)
  top <- utils::head(order(-peak), 3)
  rest <- setdiff(seq_along(names_r), top)
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 2, 1))
  graphics::matplot(lags_all, r_mat[, rest, drop = FALSE], type = "l", lty = 1, lwd = 1,
                    col = "grey80", xlab = "Lag of the rise in flow behind the rain (hours)",
                    ylab = "Correlation", ylim = range(r_mat, na.rm = TRUE),
                    main = "Every lag")
  graphics::matlines(lags_all, r_mat[, top, drop = FALSE], lty = 1, lwd = 2.5,
                     col = colours[top])
  graphics::abline(h = 0, v = 0, col = "grey70")
  graphics::legend("topright", names_r[top], col = colours[top], lwd = 2.5, bty = "n",
                   cex = 0.8)
  # Near the peak: from the lag of the first rise to three times the best lag.
  best_lag <- stats::median(response$summary$lag_h, na.rm = TRUE)
  near <- lags_all >= 0 & lags_all <= max(3 * best_lag, 6)
  gap <- sweep(r_mat[near, , drop = FALSE], 1, apply(r_mat[near, , drop = FALSE], 1, max,
                                                     na.rm = TRUE))
  graphics::par(mar = c(4.5, 4.5, 2, 10))
  graphics::matplot(lags_all[near], gap[, rest, drop = FALSE], type = "l", lty = 1, lwd = 1,
                    col = "grey80", xlab = "Lag (hours)",
                    ylab = "Correlation less the highest at that lag",
                    ylim = range(gap, na.rm = TRUE), main = "Near the peak")
  graphics::matlines(lags_all[near], gap[, top, drop = FALSE], lty = 1, lwd = 2.5,
                     col = colours[top])
  graphics::abline(v = best_lag, lty = 2, col = "grey50")
  label_ends(gap[nrow(gap), ], names_r, ifelse(seq_along(names_r) %in% top,
                                               colours, "grey50"), gap = 0.05, cex = 0.6)
}, width = 1800)

# ---- 5. Event by event ---------------------------------------------------------------------

say("Event by event")
# One common set of events, found on the average of all the series, so no series picks its
# own. For each event, each series' rain over the event's rain window, against the event's
# quick flow (the water above the baseflow, from the flow alone).
average <- rowMeans(as.data.frame(rains), na.rm = TRUE)
average[!is.finite(average)] <- 0
# The events' windows come from DMCA-ESR's response time, the lag between the centres of mass
# of rain and flow. In a catchment fed by groundwater that lag can run to days, far longer than
# the quick response's few hours, and a long response time makes long windows: rain that fell
# after the rise is counted against the event, the event ratios fall and a storm the gauges
# missed hides among the later rain. event_max_response_h caps the search, and
# event_independent = FALSE keeps one event per burst of rain instead of merging an event's
# bursts. Set either in the settings to override.
if (!exists("event_max_response_h")) event_max_response_h <- 150
if (!exists("event_independent")) event_independent <- TRUE
found_floods <- screen_events(find_events(average,
                                          ifelse(is.finite(flow), flow, NA_real_),
                                          grid$time,
                                          dt = step_hours,
                                          max_response_h = event_max_response_h,
                                          area_km2 = area_km2,
                                          independent = event_independent),
                              flow,
                              exclude = c("small_rise", "gaps"))
# Kept before the events are subset, which drops a data frame's own attributes.
flood_baseflow <- attr(found_floods, "baseflow")
flood_response_h <- attr(found_floods, "response")$response_h
floods <- found_floods[found_floods$use & is.finite(found_floods$quickflow_mm) &
                         found_floods$quickflow_mm > 0, ]
# How long the windows run, in hours: the rain window, and the flow window the quick flow is
# summed over.
window_h <- data.frame(rain = (floods$rain_end - floods$rain_start + 1) * step_hours,
                       flow = (floods$flow_end - floods$flow_start + 1) * step_hours)

# Each series' rain over each event: missing if any step of the window is missing.
event_rain <- vapply(rains, function(r) {
  vapply(seq_len(nrow(floods)), function(e) {
    w <- floods$rain_start[e]:floods$rain_end[e]
    if (any(!is.finite(r[w]))) NA_real_ else sum(r[w])
  }, 0)
}, numeric(nrow(floods)))
if (is.null(dim(event_rain))) event_rain <- matrix(event_rain, ncol = length(rains))

ratio <- floods$quickflow_mm / event_rain

# An event missed. The true rain is never known, so the yardstick is the median of the series
# over each event: a series missed a storm when it recorded under missed_share of that, or less
# rain than the event's quick flow. Events the median series gives under missed_min_mm are not
# scored, since a few tenths of a millimetre either way would decide them. A series that reads
# high everywhere misses fewer storms for that alone, so each is first scaled to the median of
# the series' totals: the count then says whether the series saw the storms, not how much
# rain it records. The count as recorded, unscaled, is kept beside it.
if (!exists("missed_share")) missed_share <- 0.25
if (!exists("missed_min_mm")) missed_min_mm <- 2
flood_median_rain <- apply(event_rain, 1, stats::median, na.rm = TRUE)
series_total <- vapply(rains, function(r) sum(r[common]), 0)
rain_scale <- stats::median(series_total) / series_total
rain_scale[!is.finite(rain_scale)] <- 1
# For the events in rows k: which each series missed, and which it was scored on.
missed_matrix <- function(k = seq_len(nrow(floods)), scale = rain_scale) {
  er <- event_rain[k, , drop = FALSE]
  med <- flood_median_rain[k]
  scaled <- sweep(er, 2, scale, `*`)
  scored <- is.finite(er) & is.finite(med) & med >= missed_min_mm
  miss <- scored & (scaled < missed_share * med | floods$quickflow_mm[k] > scaled)
  list(missed = miss, scored = scored)
}
# The share of the events scored that each series missed, per cent.
missed_share_pct <- function(m) 100 * colSums(m$missed) / pmax(colSums(m$scored), 1)
# The spread of the log of the event runoff ratios, over the events each series was scored on
# and did not miss. Events differ, so the ratios always vary; poor rain adds its own scatter.
ratio_spread_of <- function(k, m) {
  seen_k <- ratio[k, , drop = FALSE]
  seen_k[!m$scored | m$missed | !is.finite(seen_k) | seen_k <= 0] <- NA
  apply(log(seen_k), 2, stats::sd, na.rm = TRUE)
}
missed_all <- missed_matrix()
missed <- colSums(missed_all$missed)
missed_pct <- round(missed_share_pct(missed_all), 1)
missed_pct_recorded <- round(missed_share_pct(missed_matrix(scale = rep(1, length(rains)))), 1)
spread <- round(ratio_spread_of(seq_len(nrow(floods)), missed_all), 3)
# For the box plot: the ratios of the events each series was scored on.
seen <- ratio
seen[!missed_all$scored | !is.finite(seen) | seen <= 0] <- NA

# The events missed, one row each, with the series that missed them. An event most series
# missed is not a fault of the rain: its window, its baseflow or the flow itself is the
# likelier cause.
missed_by <- apply(missed_all$missed, 1, function(m) paste(names_r[m], collapse = "; "))
missed_count <- rowSums(missed_all$missed)
missed_floods <- data.frame(
  rain_start = format(grid$time[floods$rain_start], "%Y-%m-%d %H:%M"),
  peak_m3s = round(floods$peak_flow, 2),
  quickflow_mm = round(floods$quickflow_mm, 1),
  median_rain_mm = round(flood_median_rain, 1),
  rain_window_h = window_h$rain,
  series_missing = missed_count,
  series_scored = rowSums(missed_all$scored),
  missed_by = missed_by
)[missed_count > 0, ]
missed_floods <- missed_floods[order(-missed_floods$series_missing, -missed_floods$peak_m3s), ]
fwrite(missed_floods, file.path(output_folder, "missed_events.csv"))
# Events at least half the series scored on missed.
missed_by_most <- missed_floods[missed_floods$series_missing >= missed_floods$series_scored / 2, ]

# How sure the missed share is: the events drawn again 200 times, as for the places below.
seed_before <- if (exists(".Random.seed", envir = globalenv())) {
  get(".Random.seed", envir = globalenv())
}
set.seed(2)
missed_draws <- vapply(seq_len(200), function(b) {
  k <- sample.int(nrow(floods), replace = TRUE)
  missed_share_pct(missed_matrix(k))
}, numeric(length(rains)))
if (!is.null(seed_before)) assign(".Random.seed", seed_before, envir = globalenv())
if (is.null(dim(missed_draws))) missed_draws <- matrix(missed_draws, nrow = 1)
missed_low <- apply(missed_draws, 1, stats::quantile, 0.05, na.rm = TRUE)
missed_high <- apply(missed_draws, 1, stats::quantile, 0.95, na.rm = TRUE)
# The kriging averages' error over each event, as a share of the event's rain: the steps'
# errors either independent of each other (the square root of the sum of their squares: the
# lower bound) or wholly shared through the event (their sum: the upper). A storm's errors are
# partly shared, so the truth lies between. Events with under 1 mm are left out.
kriging_error <- if (length(built_se)) {
  do.call(rbind, lapply(names(built_se), function(n) {
    se <- built_se[[n]]
    r <- rains[[n]]
    shares <- vapply(seq_len(nrow(floods)), function(e) {
      w <- floods$rain_start[e]:floods$rain_end[e]
      total <- sum(r[w])
      if (!is.finite(total) || total < 1 || anyNA(se[w])) {
        c(NA_real_, NA_real_)
      } else {
        c(sqrt(sum(se[w]^2)), sum(se[w])) / total
      }
    }, numeric(2))
    data.frame(average = n,
               floods = sum(is.finite(shares[1, ])),
               error_independent = round(stats::median(shares[1, ], na.rm = TRUE), 3),
               error_shared = round(stats::median(shares[2, ], na.rm = TRUE), 3))
  }))
}
if (!is.null(kriging_error)) {
  fwrite(kriging_error, file.path(output_folder, "kriging_error.csv"))
}

flood_table <- data.frame(rain = names_r,
                          events_scored = as.integer(colSums(missed_all$scored)),
                          missed_events = as.integer(missed),
                          missed_pct = missed_pct,
                          missed_pct_90 = sprintf("%.0f to %.0f", missed_low, missed_high),
                          missed_pct_as_recorded = missed_pct_recorded,
                          ratio_spread = spread)
fwrite(flood_table, file.path(output_folder, "missed_events_by_series.csv"))

# HOW TO READ flood_runoff_ratios.png
# One box per rain series: the runoff ratios (quick flow over that series' rain) of the events
# it was scored on, those with at least missed_min_mm of rain from the median series and every
# step of the series there. Above each box, how many events it was scored on and how many it
# missed. The red line is 1: above it, the event had more quick flow than the series recorded
# rain.
# Good: a narrow box well below 1, with few points near the line and few misses.
# Worry if: a box is wide (the series sees some storms well and others badly); points at or
#   above 1, or many misses (storms that passed the gauges by). Convective summer storms are
#   where single gauges fail most: a catchment average from several gauges usually does better.
png_of("flood_runoff_ratios.png", function() {
  graphics::par(mar = c(9, 4.5, 3.5, 1))
  yr <- range(c(seen, 1.2), na.rm = TRUE)
  graphics::boxplot(as.data.frame(seen),
                    names = names_r,
                    col = colours,
                    log = "y",
                    las = 2,
                    cex.axis = 0.8,
                    ylim = yr,
                    ylab = "Event runoff ratio (quick flow / rain), log scale")
  graphics::title(main = "Runoff ratios of the events each series was scored on", line = 2.3)
  graphics::abline(h = 1, col = "#B3261E")
  graphics::mtext(sprintf("%d\n%d missed", colSums(missed_all$scored), missed),
                  side = 3, at = seq_along(names_r), line = 0.1, cex = 0.55)
})

# The five largest events, by peak flow: each series' rain over each, for the cumulative plots
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
if (length(top_floods)) fwrite(largest_table, file.path(output_folder, "largest_events.csv"))

# HOW TO READ largest_floods_cumulative.png
# One panel per event, the five largest by peak flow: each series' rain added up through the
# event (left axis; the catchment averages in colour, single gauges thin grey), and the river's
# flow behind it in grey (right axis). The dashed line is the peak; the solid one the end of
# the rain window, the rain the event's runoff ratio counts. The title gives the event's start,
# peak flow and quick flow. largest_events.csv has each series' total and runoff ratio.
# Good: the lines climb together and end close together; the rain comes before the rise in
#   flow, and the lines are flat by the peak; the rain window ends soon after the peak.
# Worry if: the lines fan out (the series disagree on the storm: that spread is the event's
#   rain uncertainty); one line stays flat while the others climb (a storm that missed the
#   gauge, or a gap: a gap counts as no rain here); a line keeps climbing after the flow has
#   peaked (a clock or time-zone error); an average ending far from the gauges around it; the
#   rain window running on for days after the peak (it counts later rain against the event:
#   see event_max_response_h).
if (length(top_floods)) {
  png_of("largest_floods_cumulative.png", function() {
    graphics::par(mfrow = c(3, 2), mar = c(3, 4.5, 2.5, 4.5))
    is_average <- names_r %in% names(built)
    line_cols <- ifelse(is_average, colours, "grey60")
    for (k in seq_along(top_floods)) {
      e <- top_floods[k]
      w <- floods$rain_start[e]:min(floods$flow_end[e], length(grid$time))
      # Each series' running total over the event, a gap counted as no rain.
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
                        col = line_cols,
                        xlab = "",
                        ylab = "Cumulative rain (mm)",
                        main = sprintf("%d. %s: peak %.1f m3/s, quick flow %.1f mm",
                                       k,
                                       format(grid$time[floods$rain_start[e]], "%d %b %Y"),
                                       floods$peak_flow[e],
                                       floods$quickflow_mm[e]),
                        cex.main = 0.95)
      graphics::abline(v = grid$time[floods$peak_row[e]], lty = 2, col = "grey50")
      graphics::abline(v = grid$time[floods$rain_end[e]], lty = 1, col = "grey30")
    }
    # The last panel holds the legend: the averages by name, the single gauges together.
    graphics::plot.new()
    graphics::legend("center",
                     c(names_r[is_average], "Single gauges", "Flow (right axis)", "Flow peak",
                       "End of the rain window"),
                     col = c(colours[is_average], "grey60", "grey75", "grey50", "grey30"),
                     lwd = c(rep(2.5, sum(is_average)), 1, 2, 1, 1),
                     lty = c(rep(1, sum(is_average)), 1, 1, 2, 1),
                     bty = "n",
                     cex = 0.9,
                     ncol = 2)
  }, height = 1800)

  # HOW TO READ flood_windows.png
  # One panel per event, the five largest by peak flow: the flow (dark line), the baseflow line
  # the quick flow is measured above (dashed), the quick flow itself (shaded under the flow),
  # the rain window (pale band) and the average of the series' rain each step (bars from the
  # top, right axis). The windows are found by DMCA-ESR from the rain and flow alone.
  # Good: the rain window covers the burst that drove the rise and ends near the peak; the
  #   baseflow line runs under the hydrograph from rise to recession.
  # Worry if: the rain window runs on for days after the peak (later rain counted against the
  #   event: lower event_max_response_h); it starts after the rain (the event's own rain is
  #   missed: a ratio near or above 1); the baseflow line cuts across the rise or rides high
  #   above the start of the hydrograph (the quick flow is over- or under-stated).
  png_of("flood_windows.png", function() {
    graphics::par(mfrow = c(3, 2), mar = c(3, 4.5, 2.5, 4.5))
    for (k in seq_along(top_floods)) {
      e <- top_floods[k]
      pad <- max(1, round(0.15 * (floods$flow_end[e] - floods$rain_start[e])))
      w <- max(1, min(floods$rain_start[e], floods$flow_start[e]) - pad):
        min(length(grid$time), floods$flow_end[e] + pad)
      t <- grid$time[w]
      q <- flow[w]
      b <- flood_baseflow[w]
      top_q <- max(q, na.rm = TRUE) * 1.35
      graphics::plot(t, q, type = "n", ylim = c(0, top_q), xlab = "", ylab = "Flow (m3/s)",
                     main = sprintf("%d. %s: rain window %.0f h, flow window %.0f h",
                                    k, format(grid$time[floods$rain_start[e]], "%d %b %Y"),
                                    window_h$rain[e], window_h$flow[e]),
                     cex.main = 0.95)
      graphics::rect(grid$time[floods$rain_start[e]], 0, grid$time[floods$rain_end[e]], top_q,
                     col = grDevices::adjustcolor("#9ec9e2", 0.35), border = NA)
      inside <- w >= floods$flow_start[e] & w <= floods$flow_end[e] & is.finite(q) & is.finite(b)
      if (any(inside)) {
        graphics::polygon(c(t[inside], rev(t[inside])), c(q[inside], rev(b[inside])),
                          col = grDevices::adjustcolor("#1B6F80", 0.3), border = NA)
      }
      graphics::lines(t, b, lty = 2, col = "grey40")
      graphics::lines(t, q, lwd = 2, col = "#1B6F80")
      # The rain, hanging from the top on its own axis.
      rain_w <- average[w]
      top_r <- max(rain_w, 0.1, na.rm = TRUE) * 3
      graphics::par(new = TRUE)
      graphics::plot(t, rain_w, type = "h", col = "#3B5BA5", ylim = c(top_r, 0), axes = FALSE,
                     xlab = "", ylab = "")
      graphics::axis(4, col.axis = "#3B5BA5")
      graphics::mtext("Rain, mm per step", side = 4, line = 2.5, cex = 0.7, col = "#3B5BA5")
    }
    graphics::plot.new()
    graphics::legend("center",
                     c("Flow", "Baseflow line", "Quick flow", "Rain window",
                       "Mean of the series' rain"),
                     col = c("#1B6F80", "grey40", grDevices::adjustcolor("#1B6F80", 0.3),
                             grDevices::adjustcolor("#9ec9e2", 0.6), "#3B5BA5"),
                     lwd = c(2, 1, 10, 10, 1),
                     lty = c(1, 2, 1, 1, 1),
                     bty = "n",
                     cex = 0.9)
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
thin_floods <- integer(0)
if (length(gauge_series) > 1) {
  say("Weights and the effective number of gauges")
  unknown <- setdiff(gauge_series, names_r)
  if (length(unknown)) {
    stop("gauge_series names series not in rain_files: ", toString(unknown), call. = FALSE)
  }
  # The radar-based series are not weightings of the gauges, so they are left out here.
  averages <- setdiff(names_r,
                      c(gauge_series, "h19", "h19_bias", "multiquadric_h19", "ked_h19"))
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
  # random error s, the spread of their relative difference over the same events is about
  # s x sqrt(2). Real differences in rain between the two sites add to that spread, so this is
  # an upper limit on s. Events where both gauges saw at least 1 mm.
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

  # How many of the 20 largest events fell while an average rested on under 1.5 gauges.
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
      largest_events_below_1.5 = as.integer(low_in_flood[[n]])
    )
  }))
  fwrite(weights_table, file.path(output_folder, "weights_and_error.csv"))
  weights_done <- TRUE

  # HOW TO READ effective_gauges_over_time.png
  # One line per catchment average: how many gauges' worth of independent rain it used, day by
  # day (the lowest value in each day). Flat at its full value when every gauge reports; it
  # drops when a gauge is missing and the average leans on the rest. Grey ticks along the top
  # mark the 20 largest events. The dashed line is 1.5, below which the average is effectively
  # one gauge.
  # Good: lines flat at their full value, with few and short dips, none of them during the
  #   large events.
  # Worry if: a line sits below 1.5 even when every gauge reports (the weighting rests on one
  #   gauge: its faults go straight into the catchment rain); long dips (gauges missing for
  #   weeks); dips under the event ticks (those events' rain rests on fewer gauges, so their
  #   scores in calibration are less to be trusted).
  png_of("effective_gauges_over_time.png", function() {
    day <- as.Date(grid$time)
    daily <- lapply(n_eff_series, function(ne) {
      suppressWarnings(tapply(ne, day, min, na.rm = TRUE))
    })
    days <- as.Date(names(daily[[1]]))
    top <- max(c(1.5, unlist(daily)[is.finite(unlist(daily))])) * 1.15
    graphics::par(mar = c(4, 4.5, 2, 9))
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
    # Each line named at its right-hand end, at its usual value.
    label_ends(vapply(daily, function(v) stats::median(v[is.finite(v)]), 0),
               names(daily),
               colours[match(names(daily), names_r)])
  })

  # The largest events that fell while a gauge was missing, so an average used fewer gauges
  # than it usually does: those events' rain rests on the rest.
  full_eff <- vapply(n_eff_series, function(ne) stats::quantile(ne, 0.95, na.rm = TRUE), 0)
  thin_floods <- largest[vapply(largest, function(e) {
    w <- floods$rain_start[e]:floods$rain_end[e]
    any(vapply(names(n_eff_series), function(n) {
      v <- n_eff_series[[n]][w]
      any(is.finite(v)) && min(v, na.rm = TRUE) < 0.9 * full_eff[[n]]
    }, logical(1)))
  }, logical(1))]
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
    # Each point's size is the number of rain days behind it; a month needs three.
    # What it shows: a line above 1 means the radar saw more rain than the gauge caught.
    # Good: lines close to 1 and flat through the year.
    # Worry if: a line rises in the winter months and falls in summer. Gauges lose more rain to
    #   wind in winter (stronger winds, lighter rain, snow), so a winter rise points to the
    #   gauge under-catching. Every line rising in spring and summer instead points to the
    #   radar over-reading showery rain, or the gauges missing its cores. A line away from 1 by
    #   the same amount all year is more likely the radar's own scaling. One gauge apart from
    #   the rest points to that gauge's exposure or siting. Small points are few days: noisy.
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
      days_in <- vapply(gauge_names, function(n) {
        p <- pairs_rg[pairs_rg$gauge == n, ]
        vapply(months, function(m) sum(p$month == m), numeric(1))
      }, numeric(12))
      gauge_cols <- colours[match(gauge_names, names_r)]
      graphics::par(mar = c(4, 4.5, 2, 9))
      yr <- range(c(0.5, 1.5, by_month), na.rm = TRUE)
      graphics::matplot(seq_along(months),
                        by_month,
                        type = "l",
                        lty = 1,
                        lwd = 2,
                        col = gauge_cols,
                        xaxt = "n",
                        xlab = "",
                        ylim = yr,
                        ylab = "Radar / gauge, daily totals (median)",
                        main = "Radar against each gauge, month by month")
      for (j in seq_along(gauge_names)) {
        graphics::points(seq_along(months), by_month[, j], pch = 19, col = gauge_cols[j],
                         cex = 0.5 + sqrt(days_in[, j]) / 3)
      }
      graphics::axis(1, at = seq_along(months), labels = month.abb[months])
      graphics::abline(h = 1, lty = 2, col = "grey50")
      last <- apply(by_month, 2, function(v) {
        if (any(is.finite(v))) utils::tail(v[is.finite(v)], 1) else NA_real_
      })
      label_ends(last, gauge_names, gauge_cols)
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
  event_wins = rs$event_wins,
  storm_size_r = round(rs$size_r, 3),
  dry_events = rs$dry_events,
  missed_events_pct = flood_table$missed_pct,
  event_ratio_spread = flood_table$ratio_spread,
  # Not ranked: a warning only, since a swing is a fault to look into, not a scale.
  year_swing_pct = unname(year_swing)
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
# for the response correlation, the event wins and the storm size correlation; lower for the
# rest.
better_low <- c("missing_pct", "balance_problem", "flagged_years", "double_mass_bend_pct",
                "dry_events", "missed_events_pct", "event_ratio_spread", "total_apart_pct",
                "lag_apart_h")
better_high <- c("response_r", "event_wins", "storm_size_r")
ranks <- cbind(sapply(better_low, function(m) rank(ranking[[m]], ties.method = "average")),
               sapply(better_high, function(m) rank(-ranking[[m]], ties.method = "average")))
if (is.null(dim(ranks))) ranks <- matrix(ranks, nrow = 1)
ranking$mean_rank <- round(rowMeans(ranks), 2)
ranking <- ranking[order(ranking$mean_rank), ]
ranking$place <- seq_len(nrow(ranking))

# How sure is the order? The events are drawn again at random, with replacement, 200 times, and
# the event measures scored on each draw; the measures over the whole record (the balance, the
# double-mass, the correlation, the totals) are kept as they are. A series' range is the places
# it took in 90% of the draws. Series whose ranges overlap the leader's cannot be told apart
# from it on this record.
place_of <- function(tab) {
  r <- cbind(sapply(better_low, function(m) rank(tab[[m]], ties.method = "average")),
             sapply(better_high, function(m) rank(-tab[[m]], ties.method = "average")))
  if (is.null(dim(r))) r <- matrix(r, nrow = 1)
  rank(rowMeans(r), ties.method = "min")
}
order_r <- match(ranking$rain, names_r)
events_r <- response$events
draws <- 200
old_seed <- if (exists(".Random.seed", envir = globalenv())) {
  get(".Random.seed", envir = globalenv())
}
set.seed(1)
places <- vapply(seq_len(draws), function(b) {
  tab <- ranking
  # The common events, drawn again: the events missed and the spread of their ratios.
  if (nrow(floods) > 1) {
    k <- sample.int(nrow(floods), replace = TRUE)
    m_k <- missed_matrix(k)
    tab$missed_events_pct <- missed_share_pct(m_k)[order_r]
    tab$event_ratio_spread <- ratio_spread_of(k, m_k)[order_r]
  }
  # The largest events the quick response was judged on, drawn again: the wins, the storm
  # sizes and the dry events.
  if (nrow(events_r) > 1) {
    j <- sample.int(nrow(events_r), replace = TRUE)
    ev <- events_r[j, , drop = FALSE]
    tab$event_wins <- vapply(tab$rain, function(n) sum(ev$winner == n, na.rm = TRUE), 0)
    size <- if (!is.null(ev$quickflow_mm)) ev$quickflow_mm else ev$peak_flow
    tab$storm_size_r <- vapply(tab$rain, function(n) {
      depth <- ev[[paste0(n, ".rain_mm")]]
      ok <- is.finite(depth) & is.finite(size)
      if (is.null(depth) || sum(ok) < 3 || stats::sd(depth[ok]) == 0) {
        0
      } else {
        stats::cor(depth[ok], size[ok])
      }
    }, 0)
    tab$dry_events <- vapply(tab$rain, function(n) {
      sum(vapply(strsplit(ev$dry, ";", fixed = TRUE), function(d) n %in% d, logical(1)))
    }, 0)
  }
  # Missing values rank last, as they would count against a series.
  for (m in c(better_low, better_high)) {
    tab[[m]][!is.finite(tab[[m]])] <- if (m %in% better_low) Inf else -Inf
  }
  place_of(tab)
}, numeric(nrow(ranking)))
if (!is.null(old_seed)) assign(".Random.seed", old_seed, envir = globalenv())
if (is.null(dim(places))) places <- matrix(places, nrow = 1)
ranking$place_low <- apply(places, 1, stats::quantile, 0.05, type = 1)
ranking$place_high <- apply(places, 1, stats::quantile, 0.95, type = 1)
ranking$apart_from_best <- ranking$place_low > ranking$place_high[1]
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
    if (x$dry_events > 1) sprintf("%d events it saw almost no rain for", x$dry_events),
    if (x$missed_events_pct > 5) {
      sprintf("it missed %.0f%% of the events scored (under %.0f%% of the median series' rain, or less than the quick flow)",
              x$missed_events_pct, 100 * missed_share)
    },
    if (x$year_swing_pct > 5) {
      sprintf("its rain against the others' moves %.0f points from year to year (%s): check its record then",
              x$year_swing_pct, year_swing_where[[x$rain]])
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

# ---- Recommended for PDM calibration -----------------------------------------------------

# Up to three catchment averages, in the ranking's order, each not a near-copy of one chosen
# before it (series correlated above 0.995 step by step, with totals within 2%, would give the
# model the same rain); and the best radar-based one, if not among them, when its range of
# places reaches the leader's. Single gauges are left out: a catchment average almost always
# serves the model better, and a gauge that ranks well is better used to check an average.
averages_ranked <- ranking$rain[ranking$rain %in% names(built)]
near_copy <- function(a, b) {
  ok <- common & is.finite(rains[[a]]) & is.finite(rains[[b]])
  if (sum(ok) < 10) return(FALSE)
  stats::cor(rains[[a]][ok], rains[[b]][ok]) > 0.995 &&
    abs(sum(rains[[a]][ok]) / sum(rains[[b]][ok]) - 1) < 0.02
}
chosen <- character(0)
reasons <- character(0)
for (n in averages_ranked) {
  copy_of <- Filter(function(m) near_copy(n, m), chosen)
  if (length(copy_of)) next
  chosen <- c(chosen, n)
  reasons <- c(reasons, if (length(chosen) == 1) {
    "first by the data"
  } else {
    "next by the data, and not a near-copy of those above it"
  })
  if (length(chosen) == 3) break
}
radar_ranked <- intersect(averages_ranked,
                          c("multiquadric_h19", "ked_h19", "h19_bias", "h19"))
if (length(radar_ranked) && !any(radar_ranked %in% chosen)) {
  r <- radar_ranked[1]
  if (ranking$place_low[ranking$rain == r] <= ranking$place_high[1]) {
    chosen <- c(chosen, r)
    reasons <- c(reasons, "the best radar-based series; its range of places reaches the first's")
  }
}
# And the catchment average that missed fewest storms, if none chosen so far missed as few:
# the model cannot make an event it was given no rain for, whatever the ranking says. Its
# misses are counted with every series scaled to the same total, so a series that reads high
# does not win this for that alone; one that fails the balance is said so.
missed_of_average <- stats::setNames(flood_table$missed_pct, names_r)[averages_ranked]
fewest_missed <- names(which.min(missed_of_average))
if (length(fewest_missed) && !fewest_missed %in% chosen &&
      missed_of_average[[fewest_missed]] < min(missed_of_average[chosen], Inf)) {
  i_fm <- match(fewest_missed, names_r)
  i_first <- match(chosen[1], names_r)
  chosen <- c(chosen, fewest_missed)
  reasons <- c(reasons, paste0(
    sprintf("fewest events missed among the averages: %.0f%% (%s in 90%% of draws), against %.0f%% for %s",
            missed_pct[i_fm], flood_table$missed_pct_90[i_fm], missed_pct[i_first], chosen[1]),
    if (ranking$balance_problem[ranking$rain == fewest_missed] > 0) {
      "; its total fails the water balance, so check its scale before calibrating"
    } else {
      ""
    }))
}
# The rain_error for each, from the weights where they were worked out; a radar-based series
# has none of its own, so the first gauge average's is the place to start.
error_of <- function(n) {
  if (weights_done && n %in% weights_table$rain) {
    weights_table$suggested_rain_error[weights_table$rain == n]
  } else {
    NA_real_
  }
}
recommended <- data.frame(series = chosen,
                          place = ranking$place[match(chosen, ranking$rain)],
                          places_90pct = sprintf("%d to %d",
                                                 ranking$place_low[match(chosen, ranking$rain)],
                                                 ranking$place_high[match(chosen, ranking$rain)]),
                          rain_error = vapply(chosen, error_of, 0),
                          file = file.path("catchment_rain", paste0(chosen, ".csv")),
                          why = reasons,
                          row.names = NULL)
# For a radar-based series, the rain_error of the best gauge average to start from.
fallback_error <- if (weights_done) {
  first_weighted <- intersect(ranking$rain, weights_table$rain)[1]
  weights_table$suggested_rain_error[weights_table$rain == first_weighted]
} else {
  NA_real_
}
if (!length(fallback_error)) fallback_error <- NA_real_
fwrite(recommended, file.path(output_folder, "recommended_for_calibration.csv"))

# ---- 8. Where the balance fails ------------------------------------------------------------

say("Where the balance fails")
# The plots of this section are drawn afresh, or not at all: none is left from an earlier run.
unlink(file.path(output_folder, c("record_curves.png", "balance_years.png",
                                  "flood_ratio_vs_rain.png", "candidate_band.png")))
# The balance is worked out for the series recommended first. The rain's spread is taken over
# the catchment averages, not the single gauges, which differ from each other for good reason.
reference_rain <- recommended$series[1]
spread_series <- unique(c(reference_rain, intersect(names_r, names(built))))

# The flow record checked with reach.rate, where stage is given: read from stage_file, or
# downloaded there with reach.io when missing and flow_station_wiski is set.
record_check <- NULL
gaugings_vs_rating <- NULL
stage <- NULL
gaugings <- NULL
ratings <- NULL
in_force <- NULL
# With only the WISKI ID, the stage is kept as stage_<id>.csv in data_folder: downloaded the
# first time, read from there after.
if (is.null(stage_file) && !is.null(flow_station_wiski)) {
  stage_file <- paste0("stage_", flow_station_wiski, ".csv")
}
# The gaugings and the ratings: a file name in data_folder, a data frame as exported, or one
# reach.rate has already read (it has the columns reach.rate gives).
read_or_take <- function(x, read, made_by_read) {
  if (!is.data.frame(x)) return(read(here(x)))
  if (all(made_by_read %in% names(x))) x else read(x)
}
record_skip <- if (is.null(stage_file)) {
  "neither stage_file nor flow_station_wiski was given"
} else if (step_hours != 0.25) {
  paste("it needs 15-minute data: flow averaged over a longer step is not the rating's flow at",
        "the step's mean stage")
} else if (!requireNamespace("reach.rate", quietly = TRUE)) {
  "it needs the reach.rate package: remotes::install_github(\"JonPayneEA/reach.rate\")"
}
if (is.null(record_skip)) {
  stage_path <- here(stage_file)
  if (!file.exists(stage_path) && !is.null(flow_station_wiski)) {
    if (!requireNamespace("reach.io", quietly = TRUE)) {
      stop("Downloading the stage needs the reach.io package: ",
           "remotes::install_github(\"JonPayneEA/reach.io\").",
           call. = FALSE)
    }
    # The station's 15-minute level measure, the qualified one first; a year at a time, each
    # request after a pause, as the EA asks.
    Sys.sleep(1)
    found <- as.data.frame(reach.io::find_stations(wiski_ids = as.character(flow_station_wiski)))
    level <- found[found$parameter %in% "level" & found$period %in% "15min", ]
    level <- level[order(!grepl("qualified$", level$measure_notation)), ]
    if (!nrow(level)) {
      stop("No 15-minute level at WISKI ID ", flow_station_wiski, ".", call. = FALSE)
    }
    chunks <- reach.io::make_date_chunks(period_from, period_to)
    say("  downloading stage at %s: %d year%s",
        flow_station_wiski,
        nrow(chunks),
        if (nrow(chunks) == 1) "" else "s")
    readings <- data.table::rbindlist(lapply(seq_len(nrow(chunks)), function(k) {
      Sys.sleep(1)
      reach.io::fetch_readings(level$measure_notation[1],
                               chunks$chunk_from[k],
                               chunks$chunk_to[k])
    }), fill = TRUE)
    if (!nrow(readings)) {
      stop("No stage readings for ", flow_station_wiski, " in the dates asked.", call. = FALSE)
    }
    quality <- if ("quality" %in% names(readings)) readings$quality else NA_character_
    value <- as.numeric(readings$value)
    value[quality %in% "Missing"] <- NA
    fwrite(data.table(time = format(readings$dateTime, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                      value = value,
                      quality = quality),
           stage_path)
  }
  if (!file.exists(stage_path)) {
    stop("Cannot find ", stage_path, ". Set flow_station_wiski to download it.", call. = FALSE)
  }
  stage_series <- read_hydro_series(stage_path)
  stage <- stage_series$value[match(as.numeric(grid$time), as.numeric(stage_series$time))]

  # The gaugings, and the rating's top from the highest of them unless top_stage_m is set.
  if (!is.null(gaugings_file)) {
    gaugings <- read_or_take(gaugings_file,
                             function(x) reach.rate::read_gaugings(x, quiet = TRUE),
                             c("stage_m", "discharge_cms", "station_id"))
    if (!is.null(gauging_station_id)) {
      gaugings <- gaugings[gaugings$station_id %in% gauging_station_id, ]
    }
    gaugings <- gaugings[is.finite(gaugings$stage_m) & is.finite(gaugings$discharge_cms), ]
    if (!nrow(gaugings)) {
      stop("No gaugings with a stage and a flow in gaugings_file.", call. = FALSE)
    }
  }
  top_stage <- if (!is.null(top_stage_m)) {
    top_stage_m
  } else if (!is.null(gaugings)) {
    max(gaugings$stage_m)
  }

  # The station's ratings, and the gaugings against the one in force (the one starting last).
  if (!is.null(ratings_file)) {
    limbs <- read_or_take(ratings_file,
                          reach.rate::read_operational_ratings,
                          c("rating_key", "lower_level", "upper_level", "C", "a", "n"))
    if (!is.null(rating_station_id)) limbs <- limbs[limbs$station_id %in% rating_station_id, ]
    if (!nrow(limbs)) {
      stop("No ratings for station ", rating_station_id, " in ratings_file.",
           call. = FALSE)
    }
    ratings <- reach.rate::operational_rating_tables(limbs)
    if (!length(ratings$tables)) {
      stop("None of the station's ratings in ratings_file could be built.", call. = FALSE)
    }
    if (!is.null(gaugings)) {
      starts <- tapply(as.numeric(limbs$start_date), limbs$rating_key, max, na.rm = TRUE)
      in_force <- intersect(names(sort(starts, decreasing = TRUE)), names(ratings$tables))[1]
      compared <- reach.rate::compare_gaugings_to_rating(ratings$tables[[in_force]], gaugings)
      gaugings_vs_rating <- as.data.frame(compared$limbs)
      gaugings_vs_rating$rating <- in_force
      fwrite(compared$gaugings[, c("observation_time", "stage_m", "discharge_cms",
                                   "discharge_predicted_cms", "residual_pct", "within_tol")],
             file.path(output_folder, "gaugings_vs_rating.csv"))
    }
  }

  # Dry steps: no more than dry_rain_mm over the last dry_hours of the reference rain.
  window <- max(1L, round(dry_hours / step_hours))
  rain_sum <- stats::filter(rains[[reference_rain]], rep(1, window), sides = 1)
  dry <- !is.na(rain_sum) & as.numeric(rain_sum) <= dry_rain_mm

  record <- data.frame(time = grid$time,
                       stage_m = stage,
                       discharge_cms = ifelse(is.finite(flow) & flow >= 0, flow, NA_real_))
  record_check <- tryCatch(
    reach.rate::check_flow_record(record,
                                  top_stage_m = top_stage,
                                  bankfull_stage_m = bankfull_stage_m,
                                  stage_uncertainty_m = stage_uncertainty_m,
                                  dry = dry,
                                  ratings = ratings),
    error = function(e) {
      record_skip <<- conditionMessage(e)
      NULL
    })
  if (!is.null(record_check)) {
    checks <- as.data.frame(reach.rate::assessment_checks(record_check$assessment))
    fwrite(checks[, c("check_id", "status", "message")],
           file.path(output_folder, "record_checks.csv"))
    fwrite(record_check$periods, file.path(output_folder, "record_periods.csv"))
    fwrite(record_check$revisions, file.path(output_folder, "record_revisions.csv"))
    fwrite(record_check$off_curve, file.path(output_folder, "record_off_curve.csv"))

    # HOW TO READ record_curves.png
    # The rating read back from the record: every pair of stage and archived flow, coloured by
    # period, with each period's curve. A new period starts where the applied rating changed.
    # Red points are flow off the curve: not made from the stage at the time. Dashed lines
    # mark the top of the rating and bankfull, where given.
    # Good: one tight curve, or a few, each with its date in record_revisions.csv, and few red
    #   points.
    # Worry if: a period nobody can date to a rating revision, red points in runs (infilled
    #   or edited flow), or much of the flow above the top of the rating.
    # With one period and nothing off the curve the plot is a single line that says no more
    # than the table: it is left out.
    if (nrow(record_check$periods) > 1 || nrow(record_check$off_curve) > 0) {
      png_of("record_curves.png", function() print(ggplot2::autoplot(record_check)))
    }
  }
}

# The record's highest stage against the stage at the largest event's peak. A stage far above
# every event found, at a time no event peaked, is more often a spike in the stage record
# than an event: it then inflates the flow said to come from above the rating's top.
stage_note <- NULL
if (!is.null(stage) && length(stage) == length(grid$time) && nrow(floods) &&
      any(is.finite(stage))) {
  top_row <- which.max(stage)
  biggest <- floods$peak_row[which.max(floods$peak_flow)]
  at_biggest <- suppressWarnings(
    max(stage[max(1, biggest - 4):min(length(stage), biggest + 4)], na.rm = TRUE))
  in_a_flood <- any(top_row >= floods$flow_start & top_row <= floods$flow_end)
  if (is.finite(at_biggest) && stage[top_row] > at_biggest + 0.3 && !in_a_flood) {
    stage_note <- sprintf(paste("The record's highest stage, %.2f m at %s, is %.2f m above the",
                                "largest event's peak (%.2f m) and in no event found: check the",
                                "stage record there for a spike before trusting the flow said",
                                "to come from above the rating's top."),
                          stage[top_row], format(grid$time[top_row], "%Y-%m-%d %H:%M"),
                          stage[top_row] - at_biggest, at_biggest)
  }
}

diagnosis <- balance_diagnosis(grid$time,
                               flow,
                               rains[spread_series],
                               pe,
                               area_km2,
                               floods,
                               reference = reference_rain,
                               water_year_start = year_start_month,
                               record_check = record_check)
fwrite(diagnosis$suspects, file.path(output_folder, "balance_diagnosis.csv"))
fwrite(diagnosis$gap, file.path(output_folder, "balance_gap.csv"))
fwrite(diagnosis$floods, file.path(output_folder, "balance_floods.csv"))

# Whether the rating needs more work, and which: a candidate rating from the gaugings, more
# gaugings, a question for the hydrometry team, or nothing.
follow_up <- rating_follow_up(diagnosis,
                              record_check = record_check,
                              gaugings = gaugings_vs_rating)
fwrite(follow_up$findings, file.path(output_folder, "rating_follow_up.csv"))
say("  rating: %s", follow_up$verdict)

# The candidate rating: fitted from the gaugings at the breakpoints of the rating in force (as
# many as the gaugings span), so the two compare limb by limb; assessed, exported and written
# up for review in candidate_rating/; and, with stage, the balance worked out again on the
# flow it gives. It is evidence for the team who own the rating, not a replacement.
candidate <- NULL
candidate_gap <- NULL
rating_band_share <- NULL
band <- NULL
band_curve <- NULL
band_source <- NULL
band_label <- NULL
structure_range <- NULL
candidate_compared <- NULL
candidate_note <- NULL
candidate_folder <- file.path(output_folder, "candidate_rating")
want_candidate <- switch(candidate_rating,
                         auto = follow_up$verdict == "fit a candidate rating",
                         always = TRUE,
                         never = FALSE,
                         stop("candidate_rating must be \"auto\", \"always\" or \"never\".",
                              call. = FALSE))
candidate_skip <- if (!want_candidate) {
  if (candidate_rating == "never") {
    "candidate_rating is \"never\""
  } else {
    "the gaugings do not call for one"
  }
} else if (is.null(gaugings)) {
  "it needs gaugings_file, and stage (stage_file or flow_station_wiski) for the check that reads it"
}
if (is.null(candidate_skip)) {
  say("  fitting a candidate rating from %d gaugings", nrow(gaugings))
  dir.create(candidate_folder, showWarnings = FALSE)
  # reach.rate's rating_uncertainty() gives the band source by source; an older reach.rate
  # has only the bootstrap.
  has_e2 <- exists("rating_uncertainty", envir = asNamespace("reach.rate"), inherits = FALSE)
  in_force_table <- if (!is.null(in_force)) ratings$tables[[in_force]]
  breaks <- if (!is.null(in_force_table)) {
    b <- sort(in_force_table@table$lower_level)[-1]
    b[b > min(gaugings$stage_m) & b < max(gaugings$stage_m)]
  }
  # The fit's own warnings (a limb's bootstrap draws that failed, say) go to the report.
  note_warning <- function(w) {
    candidate_note <<- c(candidate_note, sub("\\s+$", "", conditionMessage(w)))
    invokeRestart("muffleWarning")
  }
  candidate <- withCallingHandlers(
    tryCatch(
      reach.rate::fit_rating(gaugings,
                             controls = if (length(breaks)) breaks,
                             breakpoint_origin = "existing_rating",
                             n_boot = if (has_e2) 0L else candidate_boot,
                             seed = 1,
                             quiet = TRUE),
      error = function(e) {
        # Too few gaugings on some limb: one limb over them all, said so in the report.
        candidate_note <<- c(candidate_note,
                             sprintf(paste("The rating in force's breakpoints (%s m) could not",
                                           "be fitted (%s), so the candidate has one limb."),
                                     toString(round(breaks, 3)), conditionMessage(e)))
        reach.rate::fit_rating(gaugings,
                               n_boot = if (has_e2) 0L else candidate_boot,
                               seed = 1,
                               quiet = TRUE)
      }),
    warning = note_warning)
  candidate_assessment <- reach.rate::assess_rating(candidate)
  reach.rate::export_rating(candidate,
                            candidate_assessment,
                            file.path(candidate_folder, "export"),
                            overwrite = TRUE)
  # The review page needs rmarkdown, knitr and pandoc; without them the export still stands.
  if (requireNamespace("rmarkdown", quietly = TRUE) &&
        requireNamespace("knitr", quietly = TRUE) && rmarkdown::pandoc_available()) {
    reach.rate::rating_report(candidate,
                              candidate_assessment,
                              path = file.path(candidate_folder, "rating_report.html"),
                              title = "Candidate rating from the gaugings",
                              overwrite = TRUE)
  } else {
    candidate_note <- c(candidate_note,
                        paste("The review page needs rmarkdown, knitr and pandoc; install",
                              "them to have rating_report.html written."))
  }
  if (!is.null(in_force_table)) {
    candidate_compared <- reach.rate::compare_ratings(in_force_table, candidate)
    fwrite(candidate_compared$discharge, file.path(candidate_folder, "candidate_vs_in_force.csv"))
  }
  # The balance again, on the flow the candidate gives from the stage.
  if (!is.null(stage)) {
    has_stage <- is.finite(stage)
    candidate_flow <- rep(NA_real_, length(stage))
    # Stages beyond the gaugings are extrapolated: said in the report, not left as a warning.
    candidate_flow[has_stage] <- withCallingHandlers(
      logger::with_log_threshold(
        reach.rate::apply_rating(candidate, data.frame(stage = stage[has_stage]))$discharge,
        threshold = logger::WARN),
      warning = function(w) {
        candidate_note <<- c(candidate_note, sub("\\s+$", "", conditionMessage(w)))
        invokeRestart("muffleWarning")
      })
    candidate_gap <- balance_diagnosis(grid$time,
                                       candidate_flow,
                                       rains[spread_series],
                                       pe,
                                       area_km2,
                                       floods,
                                       reference = reference_rain,
                                       water_year_start = year_start_month)$gap
    fwrite(rbind(cbind(flow = "archived", diagnosis$gap),
                 cbind(flow = "candidate rating", candidate_gap)),
           file.path(candidate_folder, "balance_with_candidate.csv"))
  }

  # The candidate's band, at each stage the record reaches (or, without stage, every centimetre
  # the gaugings span), with the steps at each: the combined band (sampling and the shared
  # gauging error) where gauging_uncertainty is given, the sampling band where it is not.
  # Neither has stage error in it, so it is a lower bound.
  lims <- NULL
  if (candidate_boot > 0) {
    quietly <- function(x) {
      withCallingHandlers(logger::with_log_threshold(x, threshold = logger::WARN),
                          warning = function(w) invokeRestart("muffleWarning"))
    }
    gauged <- range(gaugings$stage_m)
    h_all <- if (!is.null(stage)) {
      round(stage[is.finite(stage)], 3)
    } else {
      seq(gauged[1], gauged[2], by = 0.01)
    }
    steps_at <- table(h_all)
    hs <- as.numeric(names(steps_at))
    n_at <- as.numeric(steps_at)
    if (has_e2) {
      uncertainty <- withCallingHandlers(
        tryCatch(
          logger::with_log_threshold(
            reach.rate::rating_uncertainty(candidate,
                                           stage = hs,
                                           n_draws = max(candidate_boot, 100),
                                           gauging_uncertainty = gauging_uncertainty,
                                           group_by = gauging_group,
                                           seed = 1),
            threshold = logger::WARN),
          error = function(e) {
            candidate_note <<- c(candidate_note,
                                 paste("The candidate's band could not be made:",
                                       conditionMessage(e)))
            NULL
          }),
        warning = note_warning)
      if (!is.null(uncertainty)) {
        bands_all <- reach.rate::uncertainty_bands(uncertainty)
        sources_done <- as.data.frame(uncertainty@assessed)
        fwrite(bands_all, file.path(candidate_folder, "candidate_uncertainty.csv"))
        fwrite(sources_done, file.path(candidate_folder, "candidate_uncertainty_sources.csv"))
        done <- function(src) isTRUE(sources_done$assessed[sources_done$source == src])
        band_source <- if (done("combined")) "combined" else if (done("sampling")) "sampling"
        for (src in c("gauging", "combined")) {
          if (src %in% sources_done$source && !done(src)) {
            candidate_note <- c(candidate_note,
                                sprintf("The %s band: %s", src,
                                        sources_done$reason[sources_done$source == src]))
          }
        }
        if (!is.null(band_source)) {
          bb <- bands_all[bands_all$source == band_source, ]
          k <- match(hs, bb$stage_m)
          lims <- data.frame(lower = bb$lower[k], median = bb$median[k], upper = bb$upper[k])
        }
        # Other reasonable structures, over the gauged range: a range, not an interval.
        sr <- bands_all[bands_all$source == "structure" & bands_all$support == "observed", ]
        if (nrow(sr)) {
          structure_range <- c(min(sr$min / sr$rating_cms - 1), max(sr$max / sr$rating_cms - 1))
        }
      }
    } else {
      boot <- tryCatch(reach.rate::rating_bootstrap(candidate), error = function(e) NULL)
      if (!is.null(boot) && nrow(boot)) {
        iv <- quietly(reach.rate::apply_rating_interval(data.frame(stage = hs), boot))
        lims <- data.frame(lower = iv$discharge_lower,
                           median = iv$discharge_median,
                           upper = iv$discharge_upper)
        band_source <- "sampling (bootstrap)"
        candidate_note <- c(candidate_note,
                            paste("This reach.rate has no rating_uncertainty(): the band is the",
                                  "bootstrap's, sampling only. Update reach.rate for the band",
                                  "with shared gauging error and the structural range."))
      }
    }
  }
  shared_text <- if (is.null(gauging_uncertainty)) {
    "the shared gauging error the gaugings state"
  } else {
    sprintf("a shared gauging error of %g%%", 100 * gauging_uncertainty)
  }
  band_label <- switch(if (is.null(band_source)) "none" else band_source,
                       combined = paste("sampling and", shared_text),
                       sampling = "sampling only: no shared gauging error given",
                       "sampling (bootstrap)" = "sampling only, from the bootstrap",
                       "none")
  if (!is.null(lims)) {
    band_curve <- data.frame(stage_m = hs,
                             steps = n_at,
                             lower_cms = lims$lower,
                             median_cms = lims$median,
                             upper_cms = lims$upper)
    # How far a year's flow could be out from the rating alone, as shares of the volume.
    if (!is.null(stage)) {
      volume <- sum(n_at * lims$median, na.rm = TRUE)
      rating_band_share <- c(min(sum(n_at * lims$lower, na.rm = TRUE) / volume - 1, 0),
                             max(sum(n_at * lims$upper, na.rm = TRUE) / volume - 1, 0))
    }
    # The rating in force against the band, over the stages the gaugings cover, each stage
    # weighted by its steps times its flow: its share of the flow.
    if (!is.null(in_force_table)) {
      band_curve$in_force_cms <- quietly(
        reach.rate::apply_rating(in_force_table, data.frame(stage = hs))$discharge)
      within_gauged <- hs >= gauged[1] & hs <= gauged[2]
      band <- data.frame(stage_m = hs,
                         weight = n_at * band_curve$in_force_cms,
                         in_force_cms = band_curve$in_force_cms,
                         lower_cms = lims$lower,
                         upper_cms = lims$upper)[within_gauged, ]
    }
    fwrite(band_curve, file.path(candidate_folder, "candidate_band.csv"))
  }
}

# With the band, the diagnosis and the follow-up again: the rating's own uncertainty joins the
# flow's bound, and the band, not the rule of thumb, decides whether to refit.
if (!is.null(rating_band_share) || !is.null(band)) {
  if (!is.null(rating_band_share)) {
    diagnosis <- balance_diagnosis(grid$time,
                                   flow,
                                   rains[spread_series],
                                   pe,
                                   area_km2,
                                   floods,
                                   reference = reference_rain,
                                   water_year_start = year_start_month,
                                   record_check = record_check,
                                   rating_band = rating_band_share)
    fwrite(diagnosis$suspects, file.path(output_folder, "balance_diagnosis.csv"))
    fwrite(diagnosis$gap, file.path(output_folder, "balance_gap.csv"))
  }
  follow_up <- rating_follow_up(diagnosis,
                                record_check = record_check,
                                gaugings = gaugings_vs_rating,
                                band = band)
  fwrite(follow_up$findings, file.path(output_folder, "rating_follow_up.csv"))
  say("  rating, with the candidate's band: %s", follow_up$verdict)
}

# HOW TO READ candidate_band.png
# Left: the candidate rating fitted to the gaugings (dark line), its 95% band (shaded; what it
# covers is in the legend: the gaugings' sampling, and the shared gauging error when
# gauging_uncertainty is given; never stage error or the choice of limbs), the rating in force
# (red, where given), and the gaugings (points), stage against flow on a log scale, so the low
# flows where most gaugings sit are not crushed into a corner. Above the highest gauging
# (dashed) the band is extrapolated and widens. Right: each gauging's flow against the
# candidate's (dark) and the rating in force's (red), per cent, by date.
# Good: the rating in force inside the band wherever the gaugings are; the gaugings scattered
#   evenly about zero on the right, with no drift through the years.
# Worry if: the red line leaves the band where most of the flow passes (the gaugings say the
#   rating in force is off there), or the band balloons above the gaugings where the events
#   are (the top of the rating needs gaugings, not a refit); the gaugings drift on the right
#   (the channel changed over time: weed, a bed shift, a new structure), or summer gaugings
#   sit apart from winter ones (weed growth).
if (!is.null(band_curve)) png_of("candidate_band.png", function() {
  b <- band_curve[order(band_curve$stage_m), ]
  b$lower_cms <- pmax(b$lower_cms, 1e-4)
  pos <- function(x) x[is.finite(x) & x > 0]
  graphics::par(mfrow = c(1, 2), mar = c(4.5, 4.5, 2, 1))
  graphics::plot(range(pos(c(b$median_cms, b$upper_cms, b$in_force_cms,
                             gaugings$discharge_cms))) * c(0.7, 1),
                 range(b$stage_m, gaugings$stage_m),
                 type = "n",
                 log = "x",
                 xlab = "Flow, m3/s (log scale)",
                 ylab = "Stage, m",
                 main = "The candidate rating, its band, and the rating in force")
  graphics::polygon(c(b$lower_cms, rev(b$upper_cms)),
                    c(b$stage_m, rev(b$stage_m)),
                    col = grDevices::adjustcolor("#1B6F80", 0.25),
                    border = NA)
  graphics::lines(b$median_cms, b$stage_m, col = "#1B6F80", lwd = 2)
  if (!is.null(b$in_force_cms)) {
    graphics::lines(b$in_force_cms, b$stage_m, col = "#B3261E", lwd = 1.5)
  }
  graphics::points(gaugings$discharge_cms, gaugings$stage_m, pch = 19, cex = 0.7)
  graphics::abline(h = max(gaugings$stage_m), lty = 2, col = "grey40")
  graphics::legend("topleft",
                   bty = "n",
                   cex = 0.75,
                   c("Candidate", sprintf("Its 95%% band (%s)", band_label), "Rating in force",
                     "Gaugings", "Highest gauging"),
                   col = c("#1B6F80", grDevices::adjustcolor("#1B6F80", 0.25), "#B3261E",
                           "black", "grey40"),
                   lwd = c(2, 8, 1.5, NA, 1),
                   lty = c(1, 1, 1, NA, 2),
                   pch = c(NA, NA, NA, 19, NA))
  # The gaugings against both ratings, by date.
  when <- gaugings$observation_time
  if (is.null(when) || !any(!is.na(when))) {
    graphics::plot.new()
    graphics::text(0.5, 0.5, "The gaugings carry no dates.")
    return(invisible())
  }
  at <- function(curve) {
    stats::approx(b$stage_m, curve, xout = gaugings$stage_m, rule = 2)$y
  }
  res_c <- 100 * (gaugings$discharge_cms / at(b$median_cms) - 1)
  res_f <- if (!is.null(b$in_force_cms)) 100 * (gaugings$discharge_cms / at(b$in_force_cms) - 1)
  yr <- range(c(-25, 25, res_c, res_f), finite = TRUE)
  graphics::plot(when, res_c, ylim = yr, pch = 19, col = "#1B6F80", cex = 0.8, xlab = "",
                 ylab = "Gauged flow against the rating, %",
                 main = "The gaugings against each rating, by date")
  if (!is.null(res_f)) graphics::points(when, res_f, pch = 1, col = "#B3261E", cex = 0.8)
  graphics::abline(h = 0, col = "grey50")
  graphics::abline(h = c(-10, 10), lty = 3, col = "grey70")
  graphics::legend("topleft", bty = "n", cex = 0.75,
                   c("Against the candidate", if (!is.null(res_f)) "Against the rating in force"),
                   pch = c(19, if (!is.null(res_f)) 1),
                   col = c("#1B6F80", if (!is.null(res_f)) "#B3261E"))
}, width = 2000)

# HOW TO READ balance_years.png
# Each year's flow (points) against the range Fu's curve allows for that year's rain and
# potential evaporation (bars), on the series recommended first. Below the bar, more water
# left than even a thirsty catchment evaporates; above it, more came than the rain explains.
# Good: points inside their bars.
# Worry if: every year below its bar (a slow loss: groundwater out, abstraction, or an area
#   too large), every year above (a slow gain), or the points stepping from one level to
#   another (a change: a new rating, a changed channel, a new abstraction).
# Drawn only with a complete year.
if (diagnosis$gap$kind != "not assessed") png_of("balance_years.png", function() {
  y <- diagnosis$years[diagnosis$years$complete >= 0.9, ]
  graphics::par(mar = c(4, 4.5, 2, 1))
  k <- seq_len(nrow(y))
  span_mm <- range(y$flow_mm, y$flow_low_mm, y$flow_high_mm, na.rm = TRUE)
  graphics::plot(k,
                 y$flow_mm,
                 xlim = c(0.5, length(k) + 0.5),
                 ylim = span_mm + c(-0.1, 0.1) * diff(span_mm),
                 xaxt = "n",
                 pch = 19,
                 col = "#1B6F80",
                 xlab = "",
                 ylab = "Flow, mm",
                 main = sprintf("Flow each %s against the range Fu's curve allows (%s)",
                                year_word, reference_rain))
  graphics::segments(k, y$flow_low_mm, k, y$flow_high_mm, lwd = 8, col = "grey80")
  graphics::points(k, y$flow_mm, pch = 19, col = "#1B6F80")
  graphics::axis(1, at = k, labels = y$period)
})

# HOW TO READ flood_ratio_vs_rain.png
# Each event's runoff ratio against its rain, both on log scales, on the series recommended
# first. Events peaking above the top of the rating are filled red; the line is the relation
# fitted to the events below it.
# Good: the red points on the line's run, among the rest.
# Worry if: the red points sit well above the line (the rating reads high at the top) or well
#   below it (bypass, or the rating reads low at the top). Bigger storms giving higher ratios
#   is normal: they fall on wetter ground.
png_of("flood_ratio_vs_rain.png", function() {
  f <- diagnosis$floods[is.finite(diagnosis$floods$runoff_ratio) &
                          diagnosis$floods$runoff_ratio > 0 & diagnosis$floods$rain_mm > 0, ]
  if (!nrow(f)) return(invisible())
  above <- f$above_top %in% TRUE
  graphics::par(mar = c(4.5, 4.5, 2, 1))
  graphics::plot(f$rain_mm,
                 f$runoff_ratio,
                 log = "xy",
                 pch = ifelse(above, 19, 1),
                 col = ifelse(above, "#B3261E", "#1B6F80"),
                 xlab = "Event rain, mm",
                 ylab = "Runoff ratio (quick flow / rain)",
                 main = sprintf("Event runoff ratios against rain (%s)", reference_rain))
  below <- !above
  if (sum(below) >= 3) {
    fit <- stats::lm(log(runoff_ratio) ~ log(rain_mm), data = f[below, ])
    r <- exp(seq(log(min(f$rain_mm)), log(max(f$rain_mm)), length.out = 50))
    graphics::lines(r, exp(stats::predict(fit, newdata = data.frame(rain_mm = r))),
                    col = "grey40")
  }
  graphics::legend("topleft",
                   bty = "n",
                   cex = 0.8,
                   c("Peak below the top of the rating", "Peak above it", "Fitted to those below"),
                   pch = c(1, 19, NA),
                   lty = c(NA, NA, 1),
                   col = c("#1B6F80", "#B3261E", "grey40"))
})

# ---- The summary ---------------------------------------------------------------------------

# summary.md, built a section at a time; a section left out is NULL, which c() drops.
lines <- c(
  "# Which rain series best explains the flow", "",
  sprintf("%.1f years of %s data, %s to %s; %d rain series; %d events compared.",
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
                    "balance and double-mass checks use those steps alone; the event checks",
                    "judge each series on the events it covers. The shortest: %s. Leave",
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
  sprintf(paste("%d. **%s** (mean rank %.1f; places %d to %d in 90%% of draws of the events):",
                "runoff ratio %.2f, quick-response correlation %.2f, first for %d of %d events."),
          seq_len(nrow(ranking)),
          ranking$rain,
          ranking$mean_rank,
          ranking$place_low,
          ranking$place_high,
          ranking$runoff_ratio,
          ranking$response_r,
          ranking$event_wins,
          sum(response$summary$event_wins)),

  "",
  sprintf(paste("The places are how sure the order is: the events drawn again at random %d",
                "times, the record-wide measures kept. %s"),
          draws,
          if (any(!ranking$apart_from_best[-1])) {
            sprintf("%s cannot be told apart from %s on this record.",
                    toString(ranking$rain[-1][!ranking$apart_from_best[-1]]),
                    best)
          } else {
            "Every other series sits clearly behind the first."
          }),

  # The averages recommended for calibration.
  "", "## Recommended for PDM calibration", "",
  sprintf("- **%s** (place %d, %s): %s. rain_error %s; `%s`.",
          recommended$series,
          recommended$place,
          recommended$places_90pct,
          recommended$why,
          ifelse(is.finite(recommended$rain_error),
                 sprintf("%.3f", recommended$rain_error),
                 if (is.finite(fallback_error)) {
                   sprintf("not worked out (start from %.3f)", fallback_error)
                 } else {
                   "not worked out"
                 }),
          recommended$file),
  "",
  paste("Calibrate on each with calibrate_site.R, into its own output folder: copy its file",
        "into the site's data folder, set it as rain in site.yml, and set rain_error. Then",
        "compare their validation scores on the largest events."),

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
      if (!is.null(built$kriging)) {
        sprintf(paste("- **kriging**: block kriging of the catchment, with the variogram of",
                      "relative rain fitted to the gauges (nugget %.2f, sill %.2f, range %.1f",
                      "km; `variogram.png`)."),
                rain_variogram$nugget,
                rain_variogram$nugget + rain_variogram$partial_sill,
                rain_variogram$range / 1000)
      },
      if (!is.null(built$ked_lta)) {
        "- **ked_lta**: the same, with the long-term average grid as the drift."
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
      if (!is.null(built$ked_h19)) {
        paste("- **ked_h19**: kriging of the gauges with each step's H19 as the drift, with",
              "the kriging's variogram, on the radar's 1 km cells (`radar_ked.csv`). A step",
              "needs the radar over the catchment and at every gauge.")
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

  # The kriging averages' own error over the events.
  if (!is.null(kriging_error)) {
    c("", "## The kriging error", "",
      sprintf(paste("- **%s**: over %d events, a storm's rain is typically %.0f%% to %.0f%%",
                    "out, by kriging's own reckoning (steps' errors independent, or wholly",
                    "shared)."),
              kriging_error$average,
              kriging_error$floods,
              100 * kriging_error$error_independent,
              100 * kriging_error$error_shared),
      "",
      paste("It says how well the gauges pin the catchment's rain down, from their spacing",
            "and the variogram; set it beside the rain_error from the weights. It does not",
            "include gauge error the gauges share, such as undercatch."))
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
                    "the gauges disagree event by event (an upper limit: real differences in"),
              sigma),
      "rain between sites count too). How much of that survives into each average:", "",
      sprintf(paste("- **%s**, weights %s (%s): worth %.1f gauges; it keeps %.0f%% of a single",
                    "gauge's random error, so about %.1f%% storm error. Suggested rain_error",
                    "%.3f. Through the record it fell to %.1f gauges' worth or less 5%% of the",
                    "time; %d of the 20 largest events fell while it was below 1.5."),
              weights_table$rain,
              weights_table$weights,
              weights_table$source,
              weights_table$effective_gauges,
              100 * weights_table$error_factor,
              sigma * weights_table$error_factor,
              weights_table$suggested_rain_error,
              weights_table$effective_gauges_p05,
              weights_table$largest_events_below_1.5),
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

  # Where the balance fails.
  c("", "## Where the balance fails", "",
    if (diagnosis$gap$kind == "not assessed") {
      paste("No complete year was compared, so the water balance was not judged: over part of",
            "a year, water going into or out of storage looks like a loss or a gain.")
    } else {
      sprintf(paste("On %s, a mean year of %.0f mm of rain, %.0f of flow and %.0f of potential",
                    "evaporation; Fu's curve allows flow of %.0f to %.0f mm: %s."),
              reference_rain,
              diagnosis$gap$rain_mm,
              diagnosis$gap$flow_mm,
              diagnosis$gap$pet_mm,
              diagnosis$gap$flow_range_low_mm,
              diagnosis$gap$flow_range_high_mm,
              switch(diagnosis$gap$kind,
                     deficit = sprintf("%.0f mm short", diagnosis$gap$gap_mm),
                     excess = sprintf("%.0f mm over", diagnosis$gap$gap_mm),
                     closes = "inside it"))
    },
    "",
    sprintf("- **%s** (%s): %s.", diagnosis$suspects$verdict, diagnosis$suspects$suspect,
            diagnosis$suspects$evidence),
    "",
    sprintf("**Rating: %s.** %s", follow_up$verdict, follow_up$why),
    "",
    sprintf("- [%s] %s: %s; %s.", follow_up$findings$status, follow_up$findings$check,
            follow_up$findings$finding, follow_up$findings$action),
    if (!is.null(candidate)) {
      c("",
        paste("A candidate rating was fitted from the gaugings, for the hydrometry team to",
              "review: `candidate_rating/` holds `rating_report.html`, the export, and",
              "`candidate_vs_in_force.csv`."),
        if (!is.null(candidate_gap)) {
          sprintf(paste("On the flow it gives, the balance is %s (gap %.0f mm a year),",
                        "against %s (gap %.0f mm) on the archived flow."),
                  candidate_gap$kind, candidate_gap$gap_mm, diagnosis$gap$kind,
                  diagnosis$gap$gap_mm)
        },
        candidate_note)
    } else if (follow_up$verdict == "fit a candidate rating") {
      c("", sprintf("No candidate rating was fitted: %s.", candidate_skip))
    },
    "",
    if (is.null(record_check)) {
      sprintf("The flow record was not checked: %s.", record_skip)
    } else {
      sprintf(paste("The flow record was checked with reach.rate: %d period(s), %d",
                    "revision(s); see `record_checks.csv`."),
              nrow(record_check$periods),
              nrow(record_check$revisions))
    },
    if (!is.null(gaugings_vs_rating)) {
      sprintf("Gaugings against the rating in force (%s): %d gaugings, %.0f%% within 10%%.",
              gaugings_vs_rating$rating[1],
              sum(gaugings_vs_rating$n_gaugings),
              100 * stats::weighted.mean(gaugings_vs_rating$share_within_tol,
                                         gaugings_vs_rating$n_gaugings, na.rm = TRUE))
    },
    "",
    paste("No check proves a cause: gauges under-reading and a rating reading high at peaks",
          "look alike in the events, and a rating reading low at every flow looks like a slow",
          "loss. Gaugings, or a second flow gauge, separate them.")),

  # What to do next, and the files written.
  "", "## What next", "",
  "- The ranking is a guide. A series that ranks well but carries a warning may still be the",
  "  best choice once the fault is fixed (a clock corrected, a gap filled).",
  "- A catchment average from several gauges usually beats any single gauge for events,",
  "  because storms miss single gauges. If a single gauge ranks first, ask why: it may sit",
  "  where the storms that drive events fall, or the averages may be built on poor gauges.",
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
                  "lag_h", "event_wins", "missed_events_pct", "event_ratio_spread")],
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

# The largest events, one row per series, one column per event: rain (runoff ratio).
largest_wide <- if (length(top_floods)) {
  cells <- sprintf("%.1f (%.2f)", largest_table$rain_mm, largest_table$runoff_ratio)
  cells[is.na(largest_table$rain_mm)] <- "missing"
  wide <- data.frame(series = names_r)
  for (k in seq_along(top_floods)) {
    wide[[sprintf("event %d, %s", k, substr(largest_table$rain_start[largest_table$flood == k][1],
                                             1, 10))]] <- cells[largest_table$flood == k]
  }
  wide
}

blocks <- c(
  list(report_heading("Which rain series best explains the flow", 1),
       report_text(sprintf(paste("%.1f years of %s data, %s to %s; %d rain series; %d events",
                                 "found. Every series is judged from the data alone, before",
                                 "any model, against the same flow. The water balance and",
                                 "double-mass use the steps every series has; each event test",
                                 "scores a series on the events its record covers in full and",
                                 "the median series gives at least %g mm, %d to %d events here."),
                           years,
                           step_text,
                           compared_from,
                           compared_to,
                           length(names_r),
                           nrow(floods),
                           missed_min_mm,
                           min(colSums(missed_all$scored)),
                           max(colSums(missed_all$scored))))),
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
                   "warnings, and the plots. The twelve measures: the share missing, the",
                   "balance problem, the years flagged, the double-mass bend, the dry events,",
                   "the events missed, the spread of the event ratios, the total's distance",
                   "from the median, the lag's distance from the median lag, the",
                   "quick-response correlation, the events won and the storm-size",
                   "correlation. rain_ranking.csv has them all; the table shows the main",
                   "ones. A measure on which every series ties adds nothing to the order."),
       report_table(data.frame(ranking[, c("rain", "mean_rank")],
                               places_90pct = sprintf("%d to %d",
                                                      ranking$place_low,
                                                      ranking$place_high),
                               ranking[, c("runoff_ratio", "response_r", "lag_h", "event_wins",
                                           "missed_events_pct", "total_apart_pct",
                                           "double_mass_bend_pct")]),
                    caption = "The ranking, best first"),
       report_text(sprintf(paste("places_90pct is how sure the order is: the events drawn again",
                                 "at random %d times and the event measures scored on each",
                                 "draw, the measures over the whole record kept. A series'",
                                 "range is the places it took in 90%% of the draws; ranges",
                                 "that overlap the first's cannot be told apart from it."),
                           draws)),
       report_list(vapply(seq_len(nrow(ranking)), function(i) {
         w <- warnings_for(i)
         sprintf("%s: %s.", ranking$rain[i], if (length(w)) paste(w, collapse = "; ") else "none")
       }, ""))),

  # Recommended for calibration.
  list(report_heading("Recommended for PDM calibration"),
       report_text("Up to three catchment averages in the ranking's order, each not a near-copy",
                   "of one above it; the best radar-based one when its range of places",
                   "reaches the first's; and the average that missed fewest events, when none",
                   "above missed as few, since the model cannot make an event it was given no",
                   "rain for. Single gauges are left out: an average almost always serves the",
                   "model better."),
       report_table(data.frame(series = recommended$series,
                               place = recommended$place,
                               places_90pct = recommended$places_90pct,
                               rain_error = recommended$rain_error,
                               file = recommended$file,
                               why = recommended$why),
                    caption = "Recommended for calibration"),
       report_list(c(
         "Calibrate on each with calibrate_site.R, into its own output folder.",
         paste("Copy the series' file from catchment_rain/ into the site's data folder, set it",
               "as rain in site.yml, and set rain_error to its value",
               if (is.finite(fallback_error)) {
                 sprintf("(for a radar-based series, start from %.3f).", fallback_error)
               } else {
                 "."
               }),
         paste("Compare their validation scores on the largest events: that says which rain",
               "helps the model, not only which agrees best with the flow before any model.")))),

  # The data.
  list(report_heading("The data"),
       report_text(sprintf(paste("Flow, evaporation, %d rain gauges and %d other series, cut to",
                                 "the period and put on %s steps. Missing is the share of the",
                                 "period each gauge lacks; flags are the readings the Hydrology",
                                 "API marked other than Good or Missing, kept as they are."),
                           length(gauge_names),
                           length(other_rain_files),
                           step_text)),
       report_table(gauge_table, caption = "The gauges"),
       if (!is.null(gauge_table$km_outside) && all(gauge_table$km_outside > 0)) {
         report_alert(paste(
           sprintf(paste("Every gauge lies outside the catchment, %.1f to %.1f km beyond its",
                         "boundary: each average infers the catchment's rain from its edges,",
                         "and storms that fall inside and miss the edges are missed."),
                   min(gauge_table$km_outside), max(gauge_table$km_outside)),
           if (!is.null(h19_series)) {
             "The radar-based series in this run see between the gauges: compare their events missed."
           } else {
             "Radar, where it is available, sees between the gauges: a run with it would test this."
           }),
           FALSE)
       }),
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
         if (!is.null(built$kriging)) {
           paste("kriging: block kriging of the catchment from a variogram fitted to the",
                 "gauges, with each step's standard error.")
         },
         if (!is.null(built$ked_lta)) {
           "ked_lta: kriging with the long-term average grid as the drift."
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
         },
         if (!is.null(built$ked_h19)) {
           paste("ked_h19: kriging of the gauges with each step's radar as the drift: the",
                 "gauges set the level, the radar the pattern between them, with each step's",
                 "standard error.")
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
                                   "to %.0f%% out here, from how much the gauges disagree event",
                                   "by event; the suggested rain_error for calibrate_site.R is",
                                   "that times the error factor."),
                             sigma)),
         report_table(weights_wide, caption = "Weights by gauge, and what they mean"))
  },
  plot_blocks("effective_gauges_over_time.png", "The effective number of gauges, day by day"),
  if (length(thin_floods)) {
    list(report_alert(sprintf(paste("%d of the 20 largest events fell while a gauge was",
                                    "missing, so the averages used fewer gauges than usual:",
                                    "%s. Their rain, and their scores in calibration, rest on",
                                    "the rest."),
                              length(thin_floods),
                              toString(format(grid$time[floods$rain_start[thin_floods]],
                                              "%Y-%m-%d"))),
                      FALSE))
  },
  if (exists("rain_variogram")) {
    c(list(report_heading("Kriging: the variogram and the error", 3),
           report_text(sprintf(paste("The variogram of relative rain fitted to the gauges:",
                                     "nugget %.2f, sill %.2f, range %.1f km. Kriging weights",
                                     "the gauges from it, and says how well they pin the",
                                     "catchment's rain down at every step."),
                               rain_variogram$nugget,
                               rain_variogram$nugget + rain_variogram$partial_sill,
                               rain_variogram$range / 1000))),
      if (length(variogram_note)) {
        list(report_alert(paste(c(variogram_note, "Read kriging's weights and errors loosely."),
                                collapse = " "), FALSE))
      },
      plot_blocks("variogram.png", "The variogram of the gauges' rain"),
      if (!is.null(kriging_error)) {
        list(report_text("A storm's rain error by kriging's own reckoning, as a share of the",
                         "storm's rain, typical over the events: with the steps' errors",
                         "independent (lower) or wholly shared through the storm (upper). It",
                         "leaves out error the gauges share, such as undercatch."),
             report_table(kriging_error, caption = "The kriging error over the events"))
      })
  },

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
  plot_blocks("rain_by_year.png", paste("Each series' rain by", year_word, "against the others")),
  if (any(year_swing > 5)) {
    list(report_alert(paste0("Read in some years only, not as a steady scale: ",
                             paste(sprintf("%s (%s)", names_r[year_swing > 5],
                                           unlist(year_swing_where[year_swing > 5])),
                                   collapse = "; "),
                             ". Check those records for the years apart, before using them."),
                      FALSE))
  },
  plot_blocks("runoff_ratio_by_series.png", "Runoff ratio season by season"),
  list(report_heading("Test 2: double-mass"),
       report_text("Did any series change part way through? Each series' running total against",
                   "that of the median series: the weather falls on all alike and cancels, so a",
                   "bend is a change in that series (a gauge moved, replaced or failing).")),
  plot_blocks("double_mass_by_series.png", "Double-mass curves"),
  list(report_heading("Test 3: the quick response"),
       report_text("Which series does the river answer to? The correlation of each series' rain",
                   "with the rises in flow, at each lag, and event by event which series best",
                   "explains the rise."),
       report_table(response$summary, caption = "The quick response")),
  plot_blocks("quick_response.png", "The quick response at each lag"),
  list(report_heading("Test 4: event by event"),
       report_text(sprintf(paste(
         "One set of rainfall-runoff events (a rise in flow and the rain behind it), found once on the mean of all the series, so no series picks its",
         "own; each series' rain over each event's rain window against the event's quick flow.",
         "The windows come from DMCA-ESR, from a response time of %.1f h (the quick response",
         "peaks at %g h); the median rain window is %.0f h and the longest %.1f days."),
         flood_response_h, stats::median(response$summary$lag_h, na.rm = TRUE),
         stats::median(window_h$rain), max(window_h$rain) / 24)),
       if (flood_response_h > 4 * max(stats::median(response$summary$lag_h, na.rm = TRUE),
                                      step_hours)) {
         report_alert(sprintf(paste(
           "The events' response time, %.1f h, is far longer than the quick response's %g h,",
           "as groundwater-fed catchments give: the windows then run on after the rise and",
           "count later rain against the event, which lowers every event ratio and hides",
           "storms the gauges missed among the later rain. The event windows plot shows them.",
           "Try event_max_response_h near %.0f h, or event_independent = FALSE, and compare."),
           flood_response_h, stats::median(response$summary$lag_h, na.rm = TRUE),
           ceiling(4 * stats::median(response$summary$lag_h, na.rm = TRUE))), FALSE)
       }),
  plot_blocks("flood_windows.png", "The windows of the largest events"),
  list(report_heading("Events missed", 3),
       report_text(sprintf(paste(
         "The true rain is never known, so the yardstick is the median of the series over",
         "each event. A series missed an event when it recorded under %.0f%% of that, or less",
         "rain than the event's quick flow. Events the median series gives under %g mm (%d",
         "here) are not scored: a window holding a millimetre or two of rain is one that opens",
         "after its storm fell, not a response to so little rain, and a few tenths either way would",
         "decide it. A series that reads high everywhere would miss fewer events for that",
         "alone, so each is scaled to the median of the series' totals first; the count as",
         "recorded is in missed_pct_as_recorded, and missed_pct_90 is the range over 200",
         "draws of the events. Steady ratios across the events mark good rain."),
         100 * missed_share, missed_min_mm,
         sum(!is.finite(flood_median_rain) | flood_median_rain < missed_min_mm))),
       report_table(flood_table, caption = "Events missed, and the spread of the event ratios"),
       if (nrow(missed_by_most)) {
         report_alert(sprintf(paste(
           "%d events were missed by at least half the series scored on them: %s. An event",
           "nearly every series missed is not the rain's fault: look at the event's window,",
           "its baseflow line or the flow itself (missed_events.csv)."),
           nrow(missed_by_most), toString(utils::head(substr(missed_by_most$rain_start, 1, 10),
                                                      8))), FALSE)
       }),
  plot_blocks("flood_runoff_ratios.png", "Event runoff ratios"),
  if (length(top_floods)) {
    c(list(report_heading("The largest events", 3),
           report_text("The five largest events by peak flow: each series' rain over the event,",
                       "with its runoff ratio in brackets.")),
      plot_blocks("largest_floods_cumulative.png", "Cumulative rain through the largest events"),
      list(report_table(largest_wide, caption = "Rain over each event, mm (runoff ratio)")))
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

  # Where the balance fails.
  list(report_heading("Where the balance fails"),
       if (diagnosis$gap$kind != "not assessed") {
         report_text(sprintf(paste("Is the gap in the water balance the rain, the rating, or",
                                   "the catchment? On %s, a mean year of %.0f mm of rain, %.0f",
                                   "of flow and %.0f of potential evaporation; Fu's curve",
                                   "allows flow of %.0f to %.0f mm."),
                             reference_rain,
                             diagnosis$gap$rain_mm,
                             diagnosis$gap$flow_mm,
                             diagnosis$gap$pet_mm,
                             diagnosis$gap$flow_range_low_mm,
                             diagnosis$gap$flow_range_high_mm))
       },
       report_alert(switch(diagnosis$gap$kind,
                           deficit = sprintf("The flow is %.0f mm a year short of the range.",
                                             diagnosis$gap$gap_mm),
                           excess = sprintf("The flow is %.0f mm a year over the range.",
                                            diagnosis$gap$gap_mm),
                           closes = "The flow is inside the range: the balance closes.",
                           paste("No complete year was compared, so the balance was not",
                                 "judged; the rating's evidence still was.")),
                    diagnosis$gap$kind == "closes"),
       report_table(diagnosis$suspects, caption = "The suspects, most likely first"),
       report_alert(sprintf("Rating: %s. %s", follow_up$verdict, follow_up$why),
                    !follow_up$action_needed),
       report_table(follow_up$findings[, c("status", "check", "finding", "action")],
                    caption = "Whether the rating needs more work: act, ask, note or fine"),
       if (!is.null(candidate)) {
         report_heading("A candidate rating from the gaugings", 3)
       },
       if (!is.null(candidate)) {
         report_text(sprintf(paste("Fitted from %d gaugings%s, for the hydrometry team to",
                                   "review: candidate_rating/rating_report.html is the review",
                                   "page, candidate_rating/export/ the rating itself, and",
                                   "candidate_vs_in_force.csv the two set side by side. A",
                                   "water balance alone should not change an operational",
                                   "rating: this is evidence for the team who own it."),
                             nrow(gaugings),
                             if (!is.null(in_force)) {
                               sprintf(paste(" with the breakpoints of the rating in force",
                                             "(%s) that the gaugings span"),
                                       in_force)
                             } else {
                               ""
                             }))
       },
       if (!is.null(candidate_gap)) {
         report_table(rbind(cbind(flow = "archived", diagnosis$gap),
                            cbind(flow = "candidate rating", candidate_gap))[
                              , c("flow", "rain_mm", "flow_mm", "flow_range_low_mm",
                                  "flow_range_high_mm", "kind", "gap_mm")],
                      caption = "The balance on the archived flow and on the candidate's")
       },
       if (!is.null(candidate_gap) && diagnosis$gap$kind == "deficit" &&
             candidate_gap$kind == "deficit" && candidate_gap$gap_mm > diagnosis$gap$gap_mm) {
         report_alert(sprintf(paste(
           "The candidate widens the balance's deficit, from %.0f to %.0f mm a year: it gives",
           "less flow where the balance already has too little. Either the rain is too high,",
           "or the gaugings that pull the candidate down carry a bias of their own (weed at",
           "the time of gauging, a low-flow method). Settle which before the candidate goes",
           "to the hydrometry team as evidence that the rating in force reads high."),
           diagnosis$gap$gap_mm, candidate_gap$gap_mm), FALSE)
       },
       if (!is.null(stage_note)) report_alert(stage_note, FALSE),
       if (!is.null(rating_band_share)) {
         report_text(sprintf(paste("Its 95%% band, %s, over the record's stage, puts a year's",
                                   "flow within %+.1f%% to %+.1f%% of the candidate's: now part",
                                   "of the flow's bound in the diagnosis above. Stage error is",
                                   "not in it."),
                             band_label,
                             100 * rating_band_share[1], 100 * rating_band_share[2]))
       },
       if (!is.null(structure_range)) {
         report_text(sprintf(paste("Other reasonable structures (the other objective, a limb",
                                   "fewer, a breakpoint moved) put the curve %+.1f%% to %+.1f%%",
                                   "from the candidate over the gauged range: a range, not an",
                                   "interval (candidate_uncertainty.csv)."),
                             100 * structure_range[1], 100 * structure_range[2]))
       },
       if (length(candidate_note)) report_list(candidate_note),
       if (is.null(candidate) && follow_up$verdict == "fit a candidate rating") {
         report_alert(sprintf("No candidate rating was fitted: %s.", candidate_skip), FALSE)
       },
       report_text("Each suspect leaves its own mark. The rain is set against the spread",
                   "between the catchment averages and gauge under-catch; the rating against",
                   "the events above its top and, with stage, the record checked with",
                   "reach.rate; a slow loss or gain is what is left; a change over time is",
                   "dated. No check proves a cause: gauges under-reading and a rating reading",
                   "high at peaks look alike in the events, and a rating reading low at every",
                   "flow looks like a slow loss.")),
  plot_blocks("candidate_band.png", "The candidate rating, its band, and the rating in force"),
  plot_blocks("balance_years.png", paste("Flow each", year_word, "against Fu's range")),
  plot_blocks("flood_ratio_vs_rain.png", "Event runoff ratios against rain"),
  if (!is.null(record_check)) {
    c(list(report_heading("The flow record", 3),
           report_table(as.data.frame(reach.rate::assessment_checks(
             record_check$assessment))[, c("check_id", "status", "message")],
             caption = "The flow record checked with reach.rate")),
      plot_blocks("record_curves.png", "The rating read back from the record"))
  } else {
    list(report_alert(sprintf("The flow record was not checked: %s.", record_skip), FALSE))
  },
  if (!is.null(gaugings_vs_rating)) {
    list(report_table(gaugings_vs_rating[, c("rating", "limb", "lower_level", "upper_level",
                                             "n_gaugings", "median_residual_pct",
                                             "share_within_tol")],
                      caption = "Gaugings against the rating in force, limb by limb"))
  },

  # What next.
  list(report_heading("What next"),
       report_list(c(
         paste("Calibrate the PDM on the best two or three series with calibrate_site.R, each",
               "into its own output folder, with the suggested rain_error for each."),
         paste("Compare their validation scores on the largest events: that says which rain",
               "helps the model, not only which agrees best with the flow before any model."),
         paste("A series that ranks well but carries a warning may still be the best once the",
               "fault is fixed (a clock corrected, a gap filled).")))),
  list(report_text("Tables: rain_ranking.csv, quick_response.csv, largest_events.csv,",
                   "weights_and_error.csv; the averages in catchment_rain/, ready for",
                   "calibrate_site.R."))
)
report_file <- write_report(blocks, output_folder, "Rain comparison")

say("\nWritten to %s. Read report.html (or summary.md).", normalizePath(output_folder))
