# ============================================================ #
# Tool:         water_balance
# Description:  Water balance checks before calibration: each water year's rain, evaporation
#               and flow, the Budyko limits, a double-mass curve and the baseflow index
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-08
# Modified:     2026-11-08 - First version
# Tier:         1
# Inputs:       Forcing (time, rain, pet in mm per step), observed flow (m3/s), area (km2)
# Outputs:      A pdm_water_balance with a table by water year, flags and plots
# Dependencies: stats; graphics; ggplot2 (suggested)
# ============================================================ #

#' Check the water balance before calibrating
#'
#' Over a year a catchment stores little, so what it loses, rain minus flow, is mostly
#' evaporation. Two limits follow (Budyko, 1974):
#'
#' - **The water limit.** Flow cannot exceed rain: a runoff ratio above one means the rain is
#'   too low, the flow too high or the area wrong.
#' - **The energy limit.** The loss cannot much exceed the potential evaporation: the
#'   atmosphere cannot take more. A loss above it means too much rain, too little flow, an
#'   area too large, or water leaving underground past the gauge.
#'
#' `water_balance()` measures both for the whole record and for each water year (from
#' October in the UK), and flags years whose runoff ratio stands apart from the rest: a gauge
#' moved, a rating revised or a rain gauge that failed for part of the year hide in a record's
#' average but show in its years. A lasting change, such as a new rating from one year on, can
#' leave no single year apart from the median, so the years are also split at each boundary in
#' turn: if the mean runoff ratio after a boundary differs from the mean before by more than
#' `shift`, the record is flagged as changing there. Steps with missing flow are left out of all
#' three totals, so a gap does not look like a dry year; a year with less than `min_complete` of
#' its flow is reported but not judged.
#'
#' It also returns a **double-mass curve**, cumulative flow against cumulative rain, which is
#' straight when the two records agree throughout and kinks where one of them changed; and
#' the **baseflow index**, the share of flow under the baseflow line of [find_events()]. That
#' line follows the flow between events, so the index is close to, but not the same as, the
#' UK's standard baseflow index from five-day minima: about 0.2 on clay, 0.9 on chalk.
#'
#' `plot()` and `autoplot()` draw:
#'
#' | `type` | Shows |
#' |---|---|
#' | `budyko` | each year's loss over rain against aridity, with both limits and Fu's curve |
#' | `years` | each year's runoff ratio and loss over potential evaporation, flagged years marked |
#' | `double_mass` | cumulative flow against cumulative rain, with a line through the ends |
#'
#' @param forcing Data frame of `time`, `rain` and `pet`, mm per step.
#' @param observed Observed flow, m3/s, aligned with `forcing`.
#' @param area_km2 Catchment area.
#' @param water_year_start Month the water year starts: 10 (October) in the UK.
#' @param min_complete Least share of a year's flow that must be present to judge the year.
#' @param tolerance How far a year's runoff ratio may stand from the median of the years, as a
#'   share of it, before the year is flagged.
#' @param shift Change in the mean runoff ratio across a year boundary, as a share, beyond
#'   which the record is flagged as changing there. Needs two judged years either side.
#' @param energy_margin Loss allowed above potential evaporation, as a share of it, before a
#'   year is flagged: potential evaporation is itself an estimate.
#' @param x,object A `pdm_water_balance`.
#' @param type One of the plots above.
#' @param ... Not used.
#' @return A `pdm_water_balance` list: `years` (one row per water year: steps, share of flow
#'   present, rain, pet, flow and loss in mm, runoff ratio, loss over pet, aridity and flags),
#'   `record` (the same for the whole record), `double_mass` (cumulative rain and flow, mm),
#'   `change` (the year boundary where the runoff ratio changes most), `bfi` and
#'   `flags`. `plot()`: `x`, invisibly. `autoplot()`: a ggplot.
#' @references Budyko, M. I. (1974). Climate and Life. Academic Press.
#'
#'   Fu, B. P. (1981). On the calculation of the evaporation from land surface. Scientia
#'   Atmospherica Sinica, 5, 23-31.
#' @examples
#' rain <- synthetic_rain("2019-10-01", years = 4, dt = 1, seed = 4)
#' forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
#' config <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(config), forcing)$output$q_m3s
#' wb <- water_balance(forcing, flow, area_km2 = 20)
#' wb
#' plot(wb)
#' plot(wb, type = "years")
#' @seealso [check_inputs()], [find_events()]
#' @export
water_balance <- function(forcing, observed, area_km2, water_year_start = 10,
                          min_complete = 0.9, tolerance = 0.4, shift = 0.25,
                          energy_margin = 0.1) {
  .check(is.data.frame(forcing) && all(c("time", "rain", "pet") %in% names(forcing)),
         "forcing needs time, rain and pet columns")
  .check(is.numeric(observed) && length(observed) == nrow(forcing),
         "observed must be numeric and as long as forcing")
  .check(.scalar(area_km2, 0, strict = TRUE), "area_km2 must be a positive area")
  .check(.whole(water_year_start, 1, 12), "water_year_start must be a month, 1 to 12")
  time <- as.POSIXct(forcing$time, tz = "UTC")
  dt <- as.numeric(stats::median(diff(time)), units = "hours")
  to_mm <- dt * 3.6 / area_km2
  ok <- is.finite(observed) & is.finite(forcing$rain) & is.finite(forcing$pet)
  month <- as.integer(format(time, "%m"))
  year <- as.integer(format(time, "%Y")) + (month >= water_year_start)
  # A year is complete when its present steps cover a whole year, so a part year at either end
  # of the record is reported but not judged against whole ones.
  full_year <- 8766 / dt
  years <- do.call(rbind, lapply(sort(unique(year)), function(y) {
    k <- year == y
    .balance_row(as.character(y), forcing$rain[k], forcing$pet[k], observed[k], ok[k], to_mm,
                 full_year)
  }))
  record <- .balance_row("record", forcing$rain, forcing$pet, observed, ok, to_mm,
                         length(observed))
  years <- .flag_years(years, record, min_complete, tolerance, energy_margin, dt)
  record <- .flag_years(record, record, 0, Inf, energy_margin, dt)
  events <- tryCatch(find_events(forcing$rain, observed, time, dt = dt, area_km2 = area_km2),
                     error = function(e) NULL)
  base <- if (is.null(events)) NULL else attr(events, "baseflow")
  out <- structure(list(
    years = years, record = record,
    double_mass = data.frame(time = time[ok], rain_mm = cumsum(forcing$rain[ok]),
                             flow_mm = cumsum(observed[ok]) * to_mm),
    bfi = if (is.null(base)) NA_real_ else sum(base[ok], na.rm = TRUE) / sum(observed[ok]),
    water_year_start = water_year_start, dt = dt, years_of_data = sum(ok) * dt / 8766
  ), class = "pdm_water_balance")
  out$change <- .ratio_change(years, min_complete, shift)
  out$flags <- c(.balance_flags(out), out$change$message)
  out
}

# The year boundary where the mean runoff ratio changes most, with two judged years or more on
# each side; a message when the change exceeds the threshold. Years already flagged on their own
# are left out, so one bad year is not mistaken for a lasting change.
.ratio_change <- function(years, min_complete, shift) {
  judged <- years[years$complete >= min_complete & !nzchar(years$flags), ]
  n <- nrow(judged)
  if (n < 4) return(NULL)
  splits <- 2:(n - 2)
  change <- vapply(splits, function(k) {
    mean(judged$runoff_ratio[(k + 1):n]) / mean(judged$runoff_ratio[1:k]) - 1
  }, numeric(1))
  best <- which.max(abs(change))
  k <- splits[best]
  before <- mean(judged$runoff_ratio[1:k])
  after <- mean(judged$runoff_ratio[(k + 1):n])
  list(after_year = judged$period[k], before = before, after = after, change = change[best],
       message = if (abs(change[best]) > shift) {
         sprintf(paste0("The runoff ratio changes after water year %s, from %.2f to %.2f ",
                        "(%+.0f%%): a new rating, a moved gauge or a changed rain network?"),
                 judged$period[k], before, after, 100 * change[best])
       })
}

# One period's totals over the steps where rain, pet and flow are all present.
.balance_row <- function(label, rain, pet, flow, ok, to_mm, expected) {
  r <- sum(rain[ok])
  p <- sum(pet[ok])
  q <- sum(flow[ok]) * to_mm
  data.frame(period = label, steps = length(flow), complete = min(1, sum(ok) / expected),
             rain_mm = r,
             pet_mm = p, flow_mm = q, loss_mm = r - q, runoff_ratio = q / r,
             loss_over_pet = (r - q) / p, aridity = p / r)
}

# Each period's flags: flow above rain, loss above evaporation, a runoff ratio apart from the
# others, or too little flow to judge.
.flag_years <- function(rows, record, min_complete, tolerance, energy_margin, dt) {
  typical <- stats::median(rows$runoff_ratio[rows$complete >= min_complete], na.rm = TRUE)
  rows$flags <- vapply(seq_len(nrow(rows)), function(i) {
    r <- rows[i, ]
    if (r$complete < min_complete) return("incomplete")
    out <- c(
      if (r$runoff_ratio > 1) "flow above rain",
      if (r$loss_over_pet > 1 + energy_margin) "loss above potential evaporation",
      if (is.finite(tolerance) && is.finite(typical) &&
            abs(r$runoff_ratio / typical - 1) > tolerance) "runoff ratio apart from other years"
    )
    paste(out, collapse = "; ")
  }, character(1))
  rows
}

.balance_flags <- function(x) {
  judged <- x$years[x$years$flags != "incomplete" & nzchar(x$years$flags), ]
  c(
    if (nzchar(x$record$flags)) paste("Whole record:", x$record$flags),
    if (nrow(judged)) paste0("Water year ending ", judged$period, ": ", judged$flags)
  )
}

#' @export
print.pdm_water_balance <- function(x, ...) {
  r <- x$record
  n <- x$years_of_data
  cat(sprintf(paste0("Water balance over %.1f years with flow: rain %.0f mm, potential ",
                     "evaporation %.0f mm, flow %.0f mm a year\n"),
              n, r$rain_mm / n, r$pet_mm / n, r$flow_mm / n))
  cat(sprintf("Runoff ratio %.2f; loss over potential evaporation %.2f; baseflow index %.2f\n",
              r$runoff_ratio, r$loss_over_pet, x$bfi))
  y <- x$years
  shown <- data.frame(year = y$period, complete = sprintf("%.0f%%", 100 * y$complete),
                      rain = round(y$rain_mm), pet = round(y$pet_mm), flow = round(y$flow_mm),
                      ratio = round(y$runoff_ratio, 2), loss_pet = round(y$loss_over_pet, 2),
                      flag = ifelse(nzchar(y$flags), "*", ""))
  print(shown, row.names = FALSE)
  if (length(x$flags)) cat("CHECK:\n", paste0("  ", x$flags, "\n"), sep = "") else
    cat("Nothing implausible found\n")
  invisible(x)
}

#' @rdname water_balance
#' @export
plot.pdm_water_balance <- function(x, type = c("budyko", "years", "double_mass"), ...) {
  .draw_base(.balance_spec(x, match.arg(type)))
  invisible(x)
}

#' @rdname water_balance
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_water_balance <- function(object, type = c("budyko", "years", "double_mass"), ...) {
  .draw_gg(.balance_spec(object, match.arg(type)))
}

.balance_spec <- function(x, type) {
  switch(type, budyko = .spec_budyko(x), years = .spec_balance_years(x),
         double_mass = .spec_double_mass(x))
}

# Fu's curve: loss over rain for an aridity, with the usual catchment parameter.
.fu <- function(aridity, w = 2.6) 1 + aridity - (1 + aridity^w)^(1 / w)

.spec_budyko <- function(x) {
  y <- x$years[x$years$flags != "incomplete", ]
  flagged <- nzchar(y$flags)
  top <- max(2, y$aridity * 1.1, na.rm = TRUE)
  a <- seq(0, top, length.out = 100)
  series <- rbind(
    .layer(c(0, 1, top), c(0, 1, 1), "Limits: water and energy", .pdm_roles[["threshold"]],
           lty = 2, lwd = 1.3),
    .layer(a, .fu(a), "Fu's curve, a typical catchment", .pdm_roles[["reference"]], lwd = 1.2),
    if (any(!flagged)) .layer(y$aridity[!flagged], 1 - y$runoff_ratio[!flagged], "Water years",
                              .pdm_roles[["observed"]], geom = "point", lwd = 2.6),
    if (any(flagged)) .layer(y$aridity[flagged], 1 - y$runoff_ratio[flagged], "Flagged years",
                             .pdm_roles[["flag"]], geom = "point", lwd = 3),
    .layer(x$record$aridity, 1 - x$record$runoff_ratio, "Whole record",
           .pdm_roles[["simulated"]], geom = "open", lwd = 3.4)
  )
  list(series = series, log = "", zero = FALSE, xlim = c(0, top),
       ylim = c(min(0, 1 - y$runoff_ratio, na.rm = TRUE), 1.1),
       xlab = "Potential evaporation / rain (aridity)", ylab = "Loss / rain (1 - runoff ratio)",
       title = "Water balance against the Budyko limits",
       subtitle = "Above the dashed lines is impossible; far from the curve is unusual")
}

.spec_balance_years <- function(x) {
  y <- x$years
  k <- seq_len(nrow(y))
  judged <- y$flags != "incomplete"
  flagged <- judged & nzchar(y$flags)
  pal <- pdm_palette(2)
  series <- rbind(
    .layer(k, y$runoff_ratio, "Runoff ratio", pal[[1]], lwd = 1.6),
    .layer(k, y$loss_over_pet, "Loss / potential evaporation", pal[[2]], lwd = 1.6),
    .layer(k[judged], y$runoff_ratio[judged], ".ratio points", pal[[1]], geom = "point",
           lwd = 2.4),
    if (any(!judged)) .layer(k[!judged], y$runoff_ratio[!judged], "Incomplete year",
                             .pdm_roles[["reference"]], geom = "open", lwd = 2.6),
    if (any(flagged)) .layer(k[flagged], y$runoff_ratio[flagged], "Flagged year",
                             .pdm_roles[["flag"]], geom = "point", lwd = 3)
  )
  list(series = series, log = "", xlab = "Water year ending", ylab = "Ratio",
       hlines = data.frame(panel = 1L, y = 1, label = "limit", colour = .pdm_roles[["threshold"]]),
       title = "The water balance year by year", xlim = c(0.6, nrow(y) + 0.4),
       xticks = list(at = k, labels = y$period),
       subtitle = sprintf("Median runoff ratio %.2f", stats::median(y$runoff_ratio[judged])))
}

.spec_double_mass <- function(x) {
  d <- x$double_mass
  keep <- unique(round(seq(1, nrow(d), length.out = min(nrow(d), 2000))))
  d <- d[keep, ]
  ends <- d[c(1, nrow(d)), ]
  series <- rbind(
    .layer(ends$rain_mm, ends$flow_mm, "Straight line through the ends",
           .pdm_roles[["reference"]], lty = 2, lwd = 1.2),
    .layer(d$rain_mm, d$flow_mm, "Cumulative flow", .pdm_roles[["observed"]], lwd = 1.6)
  )
  list(series = series, log = "", xlab = "Cumulative rain (mm)", ylab = "Cumulative flow (mm)",
       title = "Double-mass curve",
       subtitle = "Straight when rain and flow agree throughout; a kink marks a change in one")
}
