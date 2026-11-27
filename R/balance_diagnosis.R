# ============================================================ #
# Tool:         balance_diagnosis
# Description:  Where a water balance fails: rain, rating, a slow loss or
#               gain (groundwater, abstraction, the catchment's area), or a
#               change over time. Sets the gap against the rain's spread and
#               the flow's stage error, the floods against the years, and
#               reads a flow record check where one is given, then ranks the
#               suspects with the evidence for each
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-27
# Tier:         1
# Inputs:       Time, flow, rain series, potential evaporation, the floods,
#               optionally reach.rate::check_flow_record() output
# Outputs:      A pdm_balance_diagnosis list
# Dependencies: stats
# ============================================================ #

#' Where a water balance fails
#'
#' A runoff deficit or excess has four usual causes, and each leaves a different mark.
#' `balance_diagnosis()` lines the marks up and ranks the suspects:
#'
#' - **Rain.** The gap is set against how far the rain could be out: the spread between the
#'   rain series given, and, for rain too low, gauge under-catch.
#' - **Rating.** A rating is weakest above its top, where it is extrapolated. Floods peaking
#'   there are set against the relation of runoff ratio to rain fitted to the floods below
#'   it: a rating reading high puts them above that relation, and bypass or a rating reading
#'   low, below. With a flow record check, revisions, flow off the curve, stage rising in dry
#'   weather and the flow a stage error makes are read too. Runoff ratios rising with peak
#'   size alone is not counted: bigger storms fall on wetter ground, so they rise anyway.
#' - **A slow loss or gain.** Groundwater, abstraction, effluent and a wrong catchment area
#'   drain or feed the slow stores: over a few days they hardly touch a flood, over a year they
#'   pile up. A gap left after the rain's and the flow's bounds, with nothing in the floods
#'   pointing elsewhere, points here.
#' - **A change over time.** A lasting change of runoff ratio from one year (a new rating, a
#'   changed channel, a new abstraction), dated, and matched to a rating revision where the
#'   record check found one.
#'
#' The gap is judged on the mean over complete years. Fu's curve gives the evaporation a
#' catchment's rain and potential evaporation lead to, and so its flow, for a parameter `w`.
#' Over the band `omega` the curve gives a range of flow: a **deficit** is flow below the
#' range (more lost than even a thirsty catchment evaporates), an **excess** flow above it
#' (less lost than even a wet one). Inside the range the balance **closes**, and a water
#' balance alone cannot see a loss or a gain: a tenth of the flow drawn off usually hides
#' there. The rain's bounds are applied by working the range out again at the rain moved by
#' each bound, the flow's by moving the flow.
#'
#' No check proves a cause. Gauges under-reading and a rating over-reading at peaks look alike
#' in the floods, and a rating reading low at every flow looks like a slow loss; only gaugings,
#' the record check's stage error or a second flow gauge separate them.
#'
#' @param time POSIXct, the start of each step.
#' @param flow Observed flow, m3/s, one value a step.
#' @param rain A named list (or data frame) of rain series, mm per step, each one value a step.
#' @param pet Potential evaporation, mm per step.
#' @param area_km2 Catchment area, km2.
#' @param floods The floods, from [find_events()] with `area_km2` (and, usually,
#'   [screen_events()]): it needs `rain_start`, `rain_end`, `peak_row`, `peak_flow` and
#'   `quickflow_mm`.
#' @param reference The rain series the balance is worked out for: its name or position.
#' @param water_year_start Month the years start in; 1 for calendar years.
#' @param undercatch How far gauges may under-read, as a share of the rain: 3 to 10% from
#'   wind is usual, more in snow. It only widens the bound for rain too low.
#' @param record_check The output of `reach.rate::check_flow_record()` for the flow station,
#'   or `NULL`.
#' @param top_flow The flow at the top of the rating, m3/s. By default it is read from the
#'   record check: its latest curve at the top stage given to it.
#' @param high_flow_excess How far, as a share, the floods above the top must sit from the
#'   relation of the floods below (their median) to count against the rating. With at least
#'   three floods above the top and eight below.
#' @param rating_band Optional: how far the year's flow could be out from the rating's own
#'   uncertainty, as shares of the flow volume, `c(lower, upper)` (such as `c(-0.04, 0.05)`):
#'   the flow from the lower and upper edges of a rating's bootstrap band, over the record's
#'   stage, against its median. It covers the gaugings' sampling only. It is combined with the
#'   stage error from `record_check`, the two taken as independent (the square root of the sum
#'   of their squares).
#' @param omega The band of Fu's parameter `w` the catchment may lie in: a broad band about the
#'   usual 2.6. Narrow it from neighbouring catchments where their balances are known.
#' @param min_complete Share of a year's steps that must have flow and the reference rain for
#'   the year to count.
#' @return A `pdm_balance_diagnosis` list:
#'   \describe{
#'     \item{suspects}{One row per suspect, ranked: `suspect`, `verdict` (`"likely"`,
#'       `"possible"`, `"unlikely"` or `"not assessed"`) and `evidence`.}
#'     \item{gap}{The mean year's rain, flow and potential evaporation (mm), the range of
#'       flow Fu's curve allows, the gap outside it and its kind (`"deficit"`, `"excess"`,
#'       `"closes"`, or `"not assessed"` without a complete year), the bounds from rain and
#'       flow, and the gap left once each and both are taken off.}
#'     \item{years}{The reference series' years, from [water_balance()], with the gap.}
#'     \item{series}{Each rain series' mean year over the steps every series covers.}
#'     \item{floods}{Each flood's peak, rain, quick flow, runoff ratio, season and whether it
#'       peaked above the top of the rating.}
#'     \item{flood_summary}{The floods' rank correlation with peak (a description, not
#'       evidence), the share with more quick flow than rain, the summer and winter medians,
#'       and how far the floods above the top sit from the relation of those below.}
#'     \item{change}{The lasting change of runoff ratio from [water_balance()].}
#'     \item{record}{What the record check found, where given.}
#'   }
#' @examples
#' rain <- synthetic_rain("2019-10-01", years = 4, dt = 1, seed = 4)
#' forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
#' config <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(config), forcing)$output$q_m3s
#' floods <- find_events(rain$rain, flow, rain$time, dt = 1, area_km2 = 20)
#' # The model's own flow from the same rain, so the balance closes and nothing is suspected.
#' balance_diagnosis(rain$time, flow, list(gauges = rain$rain), rain$pet, 20, floods)
#' # Most of the flow lost, as to an aquifer draining out of the catchment: a slow loss.
#' less <- 0.4 * flow
#' balance_diagnosis(rain$time, less, list(gauges = rain$rain), rain$pet, 20,
#'                   find_events(rain$rain, less, rain$time, dt = 1, area_km2 = 20))
#' @seealso [water_balance()], [find_events()]
#' @export
balance_diagnosis <- function(time, flow, rain, pet, area_km2, floods, reference = 1L,
                              water_year_start = 10, undercatch = 0.05, record_check = NULL,
                              top_flow = NULL, high_flow_excess = 0.2, omega = c(1.5, 3.5),
                              min_complete = 0.9, rating_band = NULL) {
  .check(inherits(time, "POSIXct"), "time must be POSIXct")
  n <- length(time)
  .check(is.numeric(flow) && length(flow) == n, "flow must be numeric, one value a step")
  .check(is.numeric(pet) && length(pet) == n, "pet must be numeric, one value a step")
  if (is.data.frame(rain)) rain <- as.list(rain)
  .check(is.list(rain) && length(rain) > 0 && !is.null(names(rain)) && all(nzchar(names(rain))),
         "rain must be a named list of rain series")
  .check(all(vapply(rain, function(r) is.numeric(r) && length(r) == n, logical(1))),
         "every rain series must be numeric, one value a step")
  .check(.scalar(area_km2, 0, strict = TRUE), "area_km2 must be a positive number")
  .check(is.data.frame(floods) &&
           all(c("rain_start", "rain_end", "peak_row", "peak_flow", "quickflow_mm") %in%
                 names(floods)),
         paste("floods must come from find_events() with area_km2: it needs rain_start,",
               "rain_end, peak_row, peak_flow and quickflow_mm"))
  ref <- if (is.character(reference)) match(reference, names(rain)) else as.integer(reference)
  .check(length(ref) == 1 && !is.na(ref) && ref >= 1 && ref <= length(rain),
         "reference must name or number one of the rain series")
  .check(.scalar(undercatch, 0), "undercatch must be a share, 0 or more")
  .check(is.numeric(omega) && length(omega) == 2 && all(omega > 1) && omega[1] < omega[2],
         "omega must be two values of Fu's parameter above 1, the lower first")
  dt <- as.numeric(stats::median(diff(as.numeric(time)))) / 3600
  ref_rain <- rain[[ref]]

  # The years, from the reference series; the gap in each and over the complete ones.
  ok <- is.finite(ref_rain) & is.finite(flow) & is.finite(pet)
  wb <- water_balance(data.frame(time = time, rain = ifelse(ok, ref_rain, 0),
                                 pet = ifelse(ok, pet, 0)),
                      ifelse(ok, flow, NA_real_), area_km2,
                      water_year_start = water_year_start, min_complete = min_complete)
  years <- wb$years
  # Each year's flow against the range Fu's curve allows for its rain and evaporation.
  years$flow_low_mm <- .fu_flow(years$rain_mm, years$pet_mm, omega[2])
  years$flow_high_mm <- .fu_flow(years$rain_mm, years$pet_mm, omega[1])
  # Without a complete year the balance is not judged: over part of a year, water going into
  # or out of storage looks like a loss or a gain. The rating's evidence is still read.
  whole <- years[years$complete >= min_complete, , drop = FALSE]
  mean_year <- if (nrow(whole)) {
    c(rain = mean(whole$rain_mm), flow = mean(whole$flow_mm), pet = mean(whole$pet_mm))
  } else {
    c(rain = NA_real_, flow = NA_real_, pet = NA_real_)
  }
  P <- mean_year[["rain"]]
  Q <- mean_year[["flow"]]
  E <- mean_year[["pet"]]
  q_low <- .fu_flow(P, E, omega[2])
  q_high <- .fu_flow(P, E, omega[1])
  kind <- if (!nrow(whole)) {
    "not assessed"
  } else if (Q < q_low) {
    "deficit"
  } else if (Q > q_high) {
    "excess"
  } else {
    "closes"
  }

  # The rain's bounds: each series' mean year over the steps all of them cover, against the
  # reference's. Rain too high by up to the reference less the lowest; too low by up to the
  # highest less the reference, plus under-catch.
  all_ok <- Reduce(`&`, lapply(rain, is.finite))
  per_year <- sum(all_ok) * dt / 8766
  series <- data.frame(series = names(rain),
                       rain_mm_per_year = vapply(rain, function(r) sum(r[all_ok]), 0) /
                         max(per_year, .Machine$double.eps),
                       row.names = NULL)
  scale <- mean_year[["rain"]] / series$rain_mm_per_year[ref]
  spread <- series$rain_mm_per_year * scale
  rain_high <- max(spread[ref] - min(spread), 0)
  rain_low <- max(max(spread) - spread[ref], 0) + undercatch * mean_year[["rain"]]

  # The flow's bounds, from the record check's stage error over the whole record.
  rec <- .diagnosis_record(record_check)
  .check(is.null(rating_band) ||
           (is.numeric(rating_band) && length(rating_band) == 2 && all(is.finite(rating_band)) &&
              rating_band[1] <= 0 && rating_band[2] >= 0),
         "rating_band must be two shares of the flow, c(lower, upper), the first 0 or below")
  # The flow could be too low (truth above it) by the stage error raised and the rating's upper
  # edge, too high by the stage error lowered and its lower edge; the two sources independent.
  combine <- function(a, b) {
    if (is.na(a) && is.na(b)) NA_real_ else sqrt(sum(c(a, b)^2, na.rm = TRUE))
  }
  rating_up <- if (is.null(rating_band)) NA_real_ else rating_band[2]
  rating_down <- if (is.null(rating_band)) NA_real_ else -rating_band[1]
  flow_low <- combine(rec$share_raised, rating_up) * Q
  flow_high <- combine(-rec$share_lowered, rating_down) * Q
  rec$rating_band <- rating_band
  zero_na <- function(x) if (is.na(x)) 0 else x
  # The gap outside the range, and what is left of it with the rain moved by its bound, the
  # flow moved by its own, and both.
  gap_at <- function(rain_shift, flow_shift) {
    switch(kind,
           deficit = max(.fu_flow(P - rain_shift, E, omega[2]) - (Q + flow_shift), 0),
           excess = max((Q - flow_shift) - .fu_flow(P + rain_shift, E, omega[1]), 0),
           closes = 0,
           NA_real_)
  }
  rain_bound <- switch(kind, deficit = rain_high, excess = rain_low, 0)
  flow_bound <- zero_na(switch(kind, deficit = flow_low, excess = flow_high, NA_real_))
  gap <- data.frame(rain_mm = P, flow_mm = Q, pet_mm = E,
                    flow_range_low_mm = q_low, flow_range_high_mm = q_high,
                    kind = kind, gap_mm = gap_at(0, 0),
                    rain_could_be_high_mm = rain_high, rain_could_be_low_mm = rain_low,
                    flow_could_be_low_mm = flow_low, flow_could_be_high_mm = flow_high,
                    rating_could_be_low_mm = rating_up * Q,
                    rating_could_be_high_mm = rating_down * Q,
                    gap_after_rain_mm = gap_at(rain_bound, 0),
                    gap_after_flow_mm = gap_at(0, flow_bound),
                    left_after_bounds_mm = gap_at(rain_bound, flow_bound),
                    years = nrow(whole))

  # The floods: each one's runoff ratio on the reference series, its peak and season, and
  # whether it peaked above the top of the rating.
  if (is.null(top_flow)) top_flow <- rec$top_flow
  .check(is.null(top_flow) || is.na(top_flow) || .scalar(top_flow, 0, strict = TRUE),
         "top_flow must be a positive flow, m3/s")
  fl <- .diagnosis_floods(floods, ref_rain, time, top_flow)
  fs <- .diagnosis_flood_summary(fl)
  high <- fs$above_top_excess
  rating_high <- isTRUE(abs(high) >= high_flow_excess)
  storms_missed <- isTRUE(fs$floods >= 8 && fs$share_above_one >= 0.1)

  suspects <- .diagnosis_suspects(gap, fs, rating_high, storms_missed, wb$change, rec,
                                  !is.null(record_check), top_flow)
  structure(list(suspects = suspects, gap = gap, years = years, series = series, floods = fl,
                 flood_summary = fs, change = wb$change, record = rec),
            class = "pdm_balance_diagnosis")
}

# The flow, mm, Fu's curve gives for rain P and potential evaporation E with parameter w.
.fu_flow <- function(P, E, w) P - P * .fu(E / P, w)

# What the record check found, as plain numbers; NA where not given or not assessed.
.diagnosis_record <- function(rc) {
  out <- list(revisions = as.POSIXct(character(0), tz = "UTC"), revision_kinds = character(0),
              off_curve_share = NA_real_, above_top_share = NA_real_,
              bankfull_peaks = NA_integer_, share_raised = NA_real_, share_lowered = NA_real_,
              dry_rise_months = character(0), winter_rise_months = character(0),
              stage_uncertainty_m = NA_real_,
              top_flow = NA_real_)
  if (is.null(rc)) return(out)
  .check(is.list(rc) && !is.null(rc$revisions) && !is.null(rc$periods),
         "record_check must be the output of reach.rate::check_flow_record()")
  out$revisions <- rc$revisions$time
  out$revision_kinds <- rc$revisions$kind
  vol <- sum(rc$steps$discharge_cms[rc$steps$period %in% rc$periods$period[rc$periods$assessed]],
             na.rm = TRUE)
  step_s <- rc$settings$step_seconds
  if (!is.null(step_s) && vol > 0) {
    out$off_curve_share <- sum(rc$off_curve$volume_m3) / (vol * step_s)
  }
  shares <- attr(rc$above, "shares")
  if (!is.null(shares) && !is.na(shares[["top"]])) out$above_top_share <- shares[["top"]]
  if (!is.null(rc$settings$bankfull_stage_m)) {
    out$bankfull_peaks <- sum(rc$above$limit == "bankfull")
  }
  if (!is.null(rc$stage_error)) {
    whole <- rc$stage_error[rc$stage_error$year == "all" & rc$stage_error$band == "all", ]
    out$share_raised <- whole$share_raised
    out$share_lowered <- whole$share_lowered
    out$stage_uncertainty_m <- rc$settings$stage_uncertainty_m
  }
  # The flow at the top stage, from the latest curve read back.
  top <- rc$settings$top_stage_m
  if (!is.null(top) && length(rc$curves)) {
    curve <- rc$curves[[length(rc$curves)]]
    if (nrow(curve) >= 2 && top >= min(curve$stage_m) && top <= max(curve$stage_m)) {
      out$top_flow <- stats::approx(curve$stage_m, curve$discharge_cms, xout = top)$y
    }
  }
  if (!is.null(rc$dry_rises)) {
    # Weed grows in summer. In winter, flow on a permeable catchment can go on rising for days
    # after rain as the groundwater answers it, so a winter rise is not counted against the
    # rating.
    limit <- rc$settings$dry_rise_m_per_day
    rising <- rc$dry_rises$month[rc$dry_rises$stage_change_m_per_day > limit]
    summer <- as.integer(substr(rising, 6, 7)) %in% 5:9
    out$dry_rise_months <- rising[summer]
    out$winter_rise_months <- rising[!summer]
  }
  out
}

.diagnosis_floods <- function(floods, rain, time, top_flow) {
  if (!nrow(floods)) {
    return(data.frame(peak_time = time[0], peak_flow = numeric(0), rain_mm = numeric(0),
                      quickflow_mm = numeric(0), runoff_ratio = numeric(0),
                      season = character(0), above_top = logical(0)))
  }
  event_rain <- vapply(seq_len(nrow(floods)), function(e) {
    w <- floods$rain_start[e]:floods$rain_end[e]
    if (any(!is.finite(rain[w]))) NA_real_ else sum(rain[w])
  }, 0)
  month <- as.integer(format(time[floods$peak_row], "%m", tz = "UTC"))
  data.frame(peak_time = time[floods$peak_row], peak_flow = floods$peak_flow,
             rain_mm = event_rain, quickflow_mm = floods$quickflow_mm,
             runoff_ratio = ifelse(event_rain >= 0.5, floods$quickflow_mm / event_rain, NA_real_),
             season = ifelse(month %in% 4:9, "summer", "winter"),
             above_top = if (is.null(top_flow) || is.na(top_flow)) {
               NA
             } else {
               floods$peak_flow > top_flow
             })
}

.diagnosis_flood_summary <- function(fl) {
  ok <- is.finite(fl$runoff_ratio) & is.finite(fl$peak_flow)
  n <- sum(ok)
  rho <- p <- NA_real_
  if (n >= 3 && stats::sd(fl$runoff_ratio[ok]) > 0 && stats::sd(fl$peak_flow[ok]) > 0) {
    test <- suppressWarnings(stats::cor.test(fl$peak_flow[ok], fl$runoff_ratio[ok],
                                             method = "spearman", exact = FALSE))
    rho <- unname(test$estimate)
    p <- test$p.value
  }
  med <- function(s) {
    v <- fl$runoff_ratio[ok & fl$season == s]
    if (length(v)) stats::median(v) else NA_real_
  }
  # The floods above the top of the rating against the floods below: log runoff ratio on log
  # rain, fitted to those below, and the median of the residuals of those above, as a share.
  above <- ok & fl$above_top %in% TRUE & fl$runoff_ratio > 0
  below <- ok & fl$above_top %in% FALSE & fl$runoff_ratio > 0 & fl$rain_mm > 0
  excess <- NA_real_
  if (sum(above) >= 3 && sum(below) >= 8) {
    fit <- stats::lm(log(runoff_ratio) ~ log(rain_mm), data = fl[below, ])
    predicted <- stats::predict(fit, newdata = fl[above, ])
    excess <- exp(stats::median(log(fl$runoff_ratio[above]) - predicted)) - 1
  }
  data.frame(floods = n, median_ratio = if (n) stats::median(fl$runoff_ratio[ok]) else NA_real_,
             peak_rho = rho, peak_p = p,
             share_above_one = if (n) mean(fl$runoff_ratio[ok] > 1) else NA_real_,
             summer_median = med("summer"), winter_median = med("winter"),
             floods_above_top = sum(above), above_top_excess = excess)
}

.diagnosis_suspects <- function(gap, fs, rating_high, storms_missed, change, rec, checked,
                                top_flow) {
  mm <- function(x) sprintf("%.0f mm a year", x)
  size <- gap$gap_mm
  gap_text <- switch(gap$kind,
                     deficit = sprintf("the flow is %s below the least Fu's curve allows (%s)",
                                       mm(size), mm(gap$flow_range_low_mm)),
                     excess = sprintf("the flow is %s above the most Fu's curve allows (%s)",
                                      mm(size), mm(gap$flow_range_high_mm)),
                     closes = "the flow is inside the range Fu's curve allows",
                     "no complete year, so the balance was not judged")
  judged <- gap$kind != "not assessed"
  open_gap <- gap$kind %in% c("deficit", "excess")

  # Rain: can its bound cover the gap on its own, or half of it.
  rain_bound <- switch(gap$kind, deficit = gap$rain_could_be_high_mm,
                       excess = gap$rain_could_be_low_mm, NA_real_)
  rain_verdict <- if (!open_gap) {
    if (storms_missed) "possible" else if (judged) "unlikely" else "not assessed"
  } else if (gap$gap_after_rain_mm <= 0) {
    "likely"
  } else if (gap$gap_after_rain_mm <= size / 2 || storms_missed) {
    "possible"
  } else {
    "unlikely"
  }
  rain_ev <- c(
    if (!judged) gap_text,
    if (open_gap) {
      sprintf("%s; the rain could be %s by up to %s (%s)", gap_text,
              if (gap$kind == "deficit") "too high" else "too low", mm(rain_bound),
              if (gap$kind == "deficit") {
                "the reference less the lowest series"
              } else {
                "the highest series less the reference, plus under-catch"
              })
    },
    if (storms_missed) {
      sprintf("%.0f%% of floods had more quick flow than rain: storms missed or under-caught",
              100 * fs$share_above_one)
    })

  # Rating. A winter rise in dry weather is noted, not counted: groundwater answering rain.
  winter_note <- if (length(rec$winter_rise_months)) {
    sprintf(paste("stage also rose in dry winter weather in %s, more likely groundwater",
                  "answering earlier rain than weed"),
            paste(rec$winter_rise_months, collapse = ", "))
  }
  rating_ev <- c(
    if (rating_high) {
      sprintf(paste("the %d floods peaking above the top of the rating have %.0f%% %s runoff",
                    "than the floods below it give for their rain: %s"),
              fs$floods_above_top, 100 * abs(fs$above_top_excess),
              if (fs$above_top_excess > 0) "more" else "less",
              if (fs$above_top_excess > 0) {
                "the rating reads high at the top"
              } else {
                "bypass, or the rating reads low at the top"
              })
    },
    if (length(rec$revisions)) {
      sprintf("the applied rating was revised %d time(s): %s", length(rec$revisions),
              paste(sprintf("%s (%s)", format(rec$revisions, "%Y-%m-%d", tz = "UTC"),
                            rec$revision_kinds), collapse = ", "))
    },
    if (isTRUE(rec$off_curve_share > 0.01)) {
      sprintf("%.1f%% of the flow is off the applied rating (infilled or edited)",
              100 * rec$off_curve_share)
    },
    if (isTRUE(rec$above_top_share > 0.05)) {
      sprintf("%.0f%% of the flow came from above the top of the rating",
              100 * rec$above_top_share)
    },
    if (isTRUE(rec$bankfull_peaks > 0)) {
      sprintf("%d peak(s) above bankfull, where flow may bypass the section", rec$bankfull_peaks)
    },
    if (length(rec$dry_rise_months)) {
      sprintf("stage rose in dry summer weather in %s, as weed growth makes it",
              paste(rec$dry_rise_months, collapse = ", "))
    })
  flow_bound <- switch(gap$kind, deficit = gap$flow_could_be_low_mm,
                       excess = gap$flow_could_be_high_mm, NA_real_)
  if (isTRUE(is.finite(flow_bound)) && open_gap) {
    sources <- c(if (!is.na(rec$stage_uncertainty_m)) {
                   sprintf("a stage error of %.3f m", rec$stage_uncertainty_m)
                 },
                 if (!is.null(rec$rating_band)) "the rating's sampling uncertainty")
    rating_ev <- c(rating_ev, sprintf("%s move%s the flow by up to %s",
                                      paste(sources, collapse = " and "),
                                      if (length(sources) == 1) "s" else "",
                                      mm(flow_bound)))
  }
  # The floods above the top apart from those below, or a stage error that could close the
  # gap on its own.
  strong_rating <- rating_high ||
    (isTRUE(is.finite(flow_bound)) && open_gap && gap$gap_after_flow_mm <= 0)
  some_rating <- length(rec$revisions) || isTRUE(rec$off_curve_share > 0.01) ||
    isTRUE(rec$above_top_share > 0.05) || isTRUE(rec$bankfull_peaks > 0) ||
    length(rec$dry_rise_months) > 0 ||
    (isTRUE(is.finite(flow_bound)) && open_gap && gap$gap_after_flow_mm <= size / 2)
  rating_verdict <- if (strong_rating) "likely" else if (some_rating) "possible" else "unlikely"
  rating_ev <- c(rating_ev, winter_note)
  if (length(rating_ev) == length(winter_note)) {
    top_note <- if (is.null(top_flow) || is.na(top_flow)) {
      "the top of the rating was not given, so the highest floods were not tested"
    } else if (is.na(fs$above_top_excess)) {
      "too few floods above the top of the rating to test them"
    } else {
      "the floods above the top of the rating follow those below"
    }
    rating_ev <- c(paste0(top_note, if (checked) {
      "; the record check found nothing against it"
    } else {
      "; the flow record was not checked"
    }), winter_note)
  }

  # A slow loss (deficit) or gain (excess): what is left once rain and flow have had their say.
  slow_name <- if (gap$kind == "excess") {
    "slow gain (groundwater in, effluent, area too small)"
  } else {
    "slow loss (groundwater out, abstraction, area too large)"
  }
  slow_verdict <- if (!judged) {
    "not assessed"
  } else if (gap$kind == "closes") {
    "unlikely"
  } else if (gap$left_after_bounds_mm > 0 && !rating_high) {
    "likely"
  } else {
    "possible"
  }
  slow_ev <- if (!judged) {
    gap_text
  } else if (gap$kind == "closes") {
    "no gap to explain"
  } else {
    c(sprintf("%s left once the rain's%s bounds are taken off", mm(gap$left_after_bounds_mm),
              if (isTRUE(is.finite(flow_bound))) " and the flow's" else ""),
      if (!rating_high && !storms_missed && fs$floods >= 8) {
        sprintf(paste("nothing in the floods points elsewhere (median runoff ratio %.2f, few",
                      "above 1)"),
                fs$median_ratio)
      },
      if (!isTRUE(is.finite(flow_bound))) {
        "the flow's own error was not assessed (no record check or rating band)"
      })
  }

  # A change over time.
  changed <- !is.null(change$message)
  change_ev <- if (changed) {
    near <- rec$revisions[format(rec$revisions, "%Y", tz = "UTC") %in%
                            c(change$after_year, as.character(as.integer(change$after_year) + 1))]
    c(change$message,
      if (length(near)) {
        sprintf("the applied rating was revised then (%s)",
                paste(format(near, "%Y-%m-%d", tz = "UTC"), collapse = ", "))
      })
  } else if (judged) {
    "no lasting change of runoff ratio from one year to the next"
  } else {
    gap_text
  }
  out <- data.frame(
    suspect = c("rain", "rating", slow_name, "change over time"),
    verdict = c(rain_verdict, rating_verdict, slow_verdict,
                if (changed) "likely" else if (judged) "unlikely" else "not assessed"),
    evidence = c(paste(rain_ev, collapse = "; "), paste(rating_ev, collapse = "; "),
                 paste(slow_ev, collapse = "; "), paste(change_ev, collapse = "; ")),
    stringsAsFactors = FALSE)
  order_of <- match(out$verdict, c("likely", "possible", "unlikely", "not assessed"))
  out[order(order_of), , drop = FALSE]
}

#' @export
print.pdm_balance_diagnosis <- function(x, ...) {
  g <- x$gap
  if (g$kind == "not assessed") {
    cat("No complete year: the water balance was not judged, only the rating's evidence\n")
  } else {
    cat(sprintf(paste("Water balance over %d year(s): rain %.0f, flow %.0f, potential",
                      "evaporation %.0f mm a year; Fu's curve allows flow of %.0f to %.0f mm:",
                      "%s (gap %.0f mm)\n"),
                g$years, g$rain_mm, g$flow_mm, g$pet_mm, g$flow_range_low_mm,
                g$flow_range_high_mm, g$kind, g$gap_mm))
  }
  for (i in seq_len(nrow(x$suspects))) {
    cat(sprintf("  %-10s %s\n             %s\n", x$suspects$verdict[i], x$suspects$suspect[i],
                x$suspects$evidence[i]))
  }
  invisible(x)
}
