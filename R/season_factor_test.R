# ============================================================ #
# Tool:         season_factor_test
# Description:  Whether the radar's monthly factors hold on years they were not fitted to:
#               the water years split in two alternate folds, the factors fitted on each and
#               applied to the other, the scaled radar scored against the gauges, and each
#               month's factor compared between the folds
# Flode Module: standalone; target reach.forcing
# Author:       pdmS7 contributors
# Created:      2026-11-28
# Tier:         1
# Inputs:       Daily pairs of gauge and radar totals, with their dates
# Outputs:      A pdm_season_factor_test list
# Dependencies: stats
# ============================================================ #

#' Whether the radar's monthly factors hold on years they were not fitted to
#'
#' [radar_season_factors()] fits a factor a month that scales radar rain to the gauges.
#' Scored on the days it was fitted to, a factor always looks good: it was chosen to fit
#' them. Before a forecasting system relies on the factors, they need scoring on years they
#' have not seen.
#'
#' The water years are numbered from the first and split into two folds, odd and even, so
#' each fold spans the whole record and neither is all wet years or all dry ones. The factors
#' are fitted on each fold with [radar_season_factors()] and applied to the other's days. The
#' scaled radar is then scored against the gauges, out of sample, beside two benchmarks: the
#' raw radar, and the factors fitted to all the days scored on those same days (in sample).
#'
#' - **Total bias**: the scaled radar's total over the gauges' total, less 1, as a percentage.
#' - **Daily error**: the median, over days, of the absolute log of the scaled radar's daily
#'   total over the gauge's, given back as a percentage (`100 * (exp(x) - 1)`): how far out a
#'   typical day is, either way.
#'
#' The verdict:
#'
#' - **the factors hold**: out of sample, the total bias is within `tolerance` and smaller than
#'   the raw radar's;
#' - **the factors help, less than in sample**: smaller than the raw radar's, but beyond
#'   `tolerance`;
#' - **the factors do not help**: out of sample, the total bias is no smaller than the raw
#'   radar's;
#' - **not tested**: either fold has fewer than `min_days` days.
#'
#' A month whose factor differs between the folds by more than `steady` (as a share of the
#' factor from all the days) is named in `why`: its factor rests on the particular years.
#'
#' @param pairs A data frame of daily totals, one row per day (and gauge): `date` (Date),
#'   `gauge_mm` and `radar_mm`, with at least 1 mm in both.
#' @param water_year_start The month the water years start in: 10 for October.
#' @param tolerance The out-of-sample total bias, as a share, within which the factors hold.
#' @param steady The share by which a month's factor may differ between the folds before it is
#'   named as resting on the years.
#' @param min_days The fewest days a fold needs to be tested.
#' @param ... Passed to [radar_season_factors()]: `min_days` for a month's own factor, and
#'   `limits`.
#' @return A `pdm_season_factor_test` list: `verdict`, `why` (one sentence or two), `scores`
#'   (for `raw radar`, `in sample` and `out of sample`: `days`, `total_bias_pct` and
#'   `daily_error_pct`), `months` (each month's factor from all the days and from each fold,
#'   and `fold_change`, the folds' difference over the factor from all the days) and `folds`
#'   (each fold's water years and days).
#' @examples
#' date <- seq(as.Date("2016-10-01"), as.Date("2022-09-30"), by = "3 days")
#' set.seed(1)
#' gauge <- 1 + rexp(length(date), 1 / 6)
#' # Radar reading 80% of the gauges every year, with day-to-day scatter: the factors hold.
#' radar <- 0.8 * gauge * exp(rnorm(length(date), 0, 0.2))
#' test_season_factors(data.frame(date = date, gauge_mm = gauge, radar_mm = radar))
#' @seealso [radar_season_factors()], [radar_by_season()]
#' @export
test_season_factors <- function(pairs, water_year_start = 10, tolerance = 0.1, steady = 0.25,
                                min_days = 60, ...) {
  .check(is.data.frame(pairs) && all(c("date", "gauge_mm", "radar_mm") %in% names(pairs)),
         "pairs needs date, gauge_mm and radar_mm, one row per day")
  .check(inherits(pairs$date, "Date"), "pairs$date must be a Date")
  .check(water_year_start %in% 1:12, "water_year_start must be a month from 1 to 12")
  .check(.scalar(tolerance, 0, 1) && .scalar(steady, 0), "tolerance and steady must be shares")
  ok <- !is.na(pairs$date) & is.finite(pairs$gauge_mm) & is.finite(pairs$radar_mm) &
    pairs$gauge_mm > 0 & pairs$radar_mm > 0
  p <- pairs[ok, c("date", "gauge_mm", "radar_mm"), drop = FALSE]
  p$month <- as.integer(format(p$date, "%m"))
  year <- as.integer(format(p$date, "%Y"))
  p$water_year <- year + (p$month >= water_year_start) - (water_year_start == 1)
  first <- if (nrow(p)) min(p$water_year) else 0L
  p$fold <- ifelse((p$water_year - first) %% 2 == 0, "A", "B")

  folds <- do.call(rbind, lapply(c("A", "B"), function(f) {
    wy <- sort(unique(p$water_year[p$fold == f]))
    data.frame(fold = f, water_years = if (length(wy)) paste(wy, collapse = ", ") else "none",
               days = sum(p$fold == f))
  }))
  score <- function(set, factor) {
    scaled <- p$radar_mm * factor
    data.frame(set = set, days = nrow(p),
               total_bias_pct = 100 * (sum(scaled) / sum(p$gauge_mm) - 1),
               daily_error_pct = 100 * (exp(stats::median(abs(log(scaled / p$gauge_mm)))) - 1))
  }
  if (any(folds$days < min_days)) {
    return(structure(list(
      verdict = "not tested",
      why = sprintf(paste("Too few days to test the factors on years they were not fitted to:",
                          "%d and %d in the two folds of alternate water years; %d needed in",
                          "each."), folds$days[1], folds$days[2], as.integer(min_days)),
      scores = NULL, months = NULL, folds = folds), class = "pdm_season_factor_test"))
  }

  all_f <- radar_season_factors(p, ...)$factor
  f_a <- radar_season_factors(p[p$fold == "A", ], ...)$factor
  f_b <- radar_season_factors(p[p$fold == "B", ], ...)$factor
  # Each fold's days scaled by the factors fitted to the other fold.
  crossed <- ifelse(p$fold == "A", f_b[p$month], f_a[p$month])
  scores <- rbind(score("raw radar", 1),
                  score("in sample", all_f[p$month]),
                  score("out of sample", crossed))
  months <- data.frame(month = 1:12, factor_all = all_f, factor_a = f_a, factor_b = f_b,
                       fold_change = abs(f_a - f_b) / all_f)

  raw <- abs(scores$total_bias_pct[1])
  out <- abs(scores$total_bias_pct[3])
  verdict <- if (out >= raw) {
    "the factors do not help"
  } else if (out <= 100 * tolerance) {
    "the factors hold"
  } else {
    "the factors help, less than in sample"
  }
  why <- sprintf(paste("On years they were not fitted to, the factors leave the radar %+.0f%%",
                       "from the gauges in total, against %+.0f%% raw and %+.0f%% in sample;",
                       "a typical day is %.0f%% out, against %.0f%% raw."),
                 scores$total_bias_pct[3], scores$total_bias_pct[1], scores$total_bias_pct[2],
                 scores$daily_error_pct[3], scores$daily_error_pct[1])
  unsteady <- months$month[months$fold_change > steady]
  if (length(unsteady)) {
    why <- paste(why, sprintf(paste("The factor for %s differs between the two sets of years",
                                    "by more than %.0f%%: it rests on the years it came from."),
                              paste(month.abb[unsteady], collapse = ", "), 100 * steady))
  }
  structure(list(verdict = verdict, why = why, scores = scores, months = months, folds = folds),
            class = "pdm_season_factor_test")
}

#' @export
print.pdm_season_factor_test <- function(x, ...) {
  cat("Radar factors out of sample: ", x$verdict, "\n", x$why, "\n", sep = "")
  if (!is.null(x$scores)) {
    s <- x$scores
    s$total_bias_pct <- round(s$total_bias_pct, 1)
    s$daily_error_pct <- round(s$daily_error_pct, 1)
    print(s, row.names = FALSE)
  }
  invisible(x)
}
