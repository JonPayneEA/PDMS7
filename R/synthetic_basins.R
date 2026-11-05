# ============================================================ #
# Tool:         synthetic_basins
# Description:  A large sample of synthetic catchments, each with its own climate and its own
#               true parameters, written as basin folders for calibrate_batch()
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-05
# Modified:     2026-11-05 - Add synthetic_basins()
# Tier:         3
# Inputs:       Sample size, record length, ranges for climate and parameters
# Outputs:      Basin folders (forcing.csv, flow.csv, basin.yml, truth.yml); sample table
# Dependencies: stats; data.table
# ============================================================ #

#' A large sample of synthetic catchments
#'
#' Writes `n` synthetic catchments as basin folders that [calibrate_batch()] reads directly,
#' each with its own climate and its own true model. Calibrating the whole sample then shows,
#' across many catchments at once, what automatic calibration recovers, because every truth is
#' known.
#'
#' **Climate.** Each catchment's rain comes from the Neyman-Scott generator
#' ([synthetic_rain()]) with the built-in parameters changed in two ways: `wetness` scales the
#' cell intensity, and so the annual total; `storminess` multiplies the number of cells per
#' storm and divides their intensity by the same factor, so storms grow more clustered and
#' intense with no change in the total. Potential evaporation has its own annual mean.
#'
#' **Catchment.** The true model is the standard structure. Its area and parameters are drawn
#' independently for each catchment: uniformly for `fc` and `b`, and uniformly on a log scale
#' for the area and for the parameters that span orders of magnitude. The second surface store
#' is the first times a factor between 1 and 3. Every drawn value lies inside
#' [calibration_bounds()]. The ranges are arguments, so a sample can be made of any kind of
#' catchment.
#'
#' **Gauge.** Each catchment is recorded with persistent gauge error and, above the flow
#' exceeded 0.5 per cent of the time, a rating 15 per cent low at twice that flow, as
#' [synthetic_catchment()] describes. The highest gauged flow goes into `basin.yml`, so
#' registration flags the flows above it.
#'
#' **Windows.** After a warm-up of three months, the first 70 per cent of the record is for
#' calibration and the rest for validation. With seven years or more, the batch holds back
#' each record's two wettest years; shorter records hold back none (`wettest_years: 0`).
#'
#' @param folder Folder to write the basin folders into; created if needed. Existing basin
#'   folders of the same names are refused.
#' @param n Number of catchments.
#' @param years,dt,start Length (years), step (hours) and first time of every record.
#' @param seed Seed for the whole sample; each catchment is reproducible from it.
#' @param ranges Named list of `c(low, high)` ranges for `area_km2`, `wetness`, `storminess`,
#'   `pet_mean` (mm/day), `fc`, `cmax` (mm), `b`, `kg` (h), `k1` (h) and `kb`. Names left out
#'   keep their defaults.
#'
#' @return The sample, invisibly: a data frame with one row per basin giving its climate (mean
#'   annual rain and PET, mm), its true parameters, its mean flow and its highest gauged flow.
#'   It is also written to `sample.csv` in `folder`. Each basin folder holds `forcing.csv`,
#'   `flow.csv`, `basin.yml` and `truth.yml`, the true configuration.
#' @examples
#' \donttest{
#' folder <- file.path(tempdir(), "sample")
#' sample <- synthetic_basins(folder, n = 3, years = 4, seed = 1)
#' sample[, c("basin", "area_km2", "rain_mm", "cmax", "kg")]
#' unlink(folder, recursive = TRUE)
#' }
#' @seealso [synthetic_catchment()], [calibrate_batch()]
#' @export
synthetic_basins <- function(folder, n = 30, years = 10, dt = 24, start = "2010-10-01",
                             seed = 1, ranges = list()) {
  .check(.scalar(n, 1) && n == floor(n), "n must be a whole number of at least 1")
  .check(.scalar(years, 1), "years must be at least 1")
  r <- utils::modifyList(.basin_ranges(), ranges)
  .check(all(vapply(r, function(x) length(x) == 2L && all(is.finite(x)) && x[1] <= x[2] &&
                      x[1] > 0, logical(1))),
         "Each range must be c(low, high) with 0 < low <= high")
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  ids <- sprintf("S%03d", seq_len(n))
  .check(!any(dir.exists(file.path(folder, ids))),
         paste("Basin folders already exist in", folder, "; use an empty folder"))
  rows <- .seeded(seed, lapply(ids, function(id) .one_basin(folder, id, r, years, dt, start)))
  sample <- do.call(rbind, rows)
  data.table::fwrite(sample, file.path(folder, "sample.csv"))
  invisible(sample)
}

# Default ranges: lowland to upland UK-like catchments, every parameter inside the bounds table.
.basin_ranges <- function() {
  list(area_km2 = c(10, 500), wetness = c(0.6, 1.6), storminess = c(0.6, 1.8),
       pet_mean = c(1.2, 1.8), fc = c(0.9, 1.1), cmax = c(100, 600), b = c(0.2, 1.2),
       kg = c(500, 5000), k1 = c(2, 20), kb = c(1000, 50000))
}

# Draws one basin's climate and truth, simulates it, writes its folder and returns its row.
.one_basin <- function(folder, id, r, years, dt, start) {
  unif <- function(x) stats::runif(1, x[1], x[2])
  logunif <- function(x) exp(stats::runif(1, log(x[1]), log(x[2])))
  wet <- unif(r$wetness)
  storm <- unif(r$storminess)
  pet_mean <- unif(r$pet_mean)
  par <- rain_parameters("nsrp")
  par$mux <- par$mux * wet / storm
  par$nu <- pmax(par$nu * storm, 1.01)
  rain <- synthetic_rain(start, years, dt, parameters = par,
                         pet = list(mean = pet_mean, amplitude = 0.85 * pet_mean,
                                    peak_day = 182))
  truth <- pdm_presets("standard")
  truth$dt <- dt
  truth$area_km2 <- logunif(r$area_km2)
  truth$fc <- unif(r$fc)
  truth$distribution$cmax <- unif(r$cmax)
  truth$distribution$b <- unif(r$b)
  truth$recharge$kg <- logunif(r$kg)
  truth$surface$k1 <- logunif(r$k1)
  truth$surface$k2 <- truth$surface$k1 * stats::runif(1, 1, 3)
  truth$groundwater$kb <- logunif(r$kb)
  # The gauge is checked to the flow exceeded 0.5 per cent of the time.
  exact <- synthetic_catchment(rain, truth, error = list(sd = 0, memory_h = 72))
  limit <- signif(stats::quantile(exact$true_flow, 0.995, names = FALSE), 3)
  river <- synthetic_catchment(rain, truth, highest_gauged_m3s = limit)
  dir <- file.path(folder, id)
  dir.create(dir)
  f <- river$forcing
  data.table::fwrite(data.frame(time = .format_time(f$time), rain = f$rain, pet = f$pet),
                     file.path(dir, "forcing.csv"))
  data.table::fwrite(data.frame(q_m3s = river$observed), file.path(dir, "flow.csv"))
  write_pdm_config(truth, file.path(dir, "truth.yml"))
  n <- nrow(f)
  warm <- round(91 * 24 / dt)
  split <- warm + round(0.7 * (n - warm))
  day <- function(i) format(f$time[i], "%Y-%m-%d")
  writeLines(c(
    paste("catchment:", paste("Synthetic", id)), paste("gauge:", id),
    paste("area_km2:", signif(truth$area_km2, 6)),
    sprintf("calibration: [%s, %s]", day(warm + 1), day(split)),
    sprintf("validation: [%s, %s]", day(split + 1), day(n)),
    paste("highest_gauged_m3s:", limit),
    # Holding back the two wettest years needs enough record to leave three for calibration.
    if (years < 7) "wettest_years: 0"
  ), file.path(dir, "basin.yml"))
  per_year <- 8766 / (n * dt)
  data.frame(
    basin = id, area_km2 = truth$area_km2, rain_mm = sum(f$rain) * per_year,
    pet_mm = sum(f$pet) * per_year, storminess = storm, fc = truth$fc,
    cmax = truth$distribution$cmax, b = truth$distribution$b, kg = truth$recharge$kg,
    k1 = truth$surface$k1, k2 = truth$surface$k2, kb = truth$groundwater$kb,
    mean_flow_m3s = mean(river$true_flow), highest_gauged_m3s = limit
  )
}
