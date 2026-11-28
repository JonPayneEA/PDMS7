# ============================================================ #
# Tool:         calibration_mask
# Description:  What calibration leaves out and how it scores the peaks (calibration-mask-
#               design.md): the mask of flows known to be wrong, never the high ones; the
#               rating's band at each step; and the dead band that treats a simulated flow
#               inside it as a perfect fit, for a forecast whose use needs true flow
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-28
# Tier:         1
# Inputs:       Step-start times; periods to leave out; flow quality codes; observed flow; the
#               rating's band as a table of flow and its lower and upper shares
# Outputs:      A pdm_calibration_mask list; a data frame of each step's band; simulated flow
#               moved by the dead band
# Dependencies: stats
# ============================================================ #

#' Leave flows known to be wrong out of calibration
#'
#' Calibration should fit the river, not the faults in its record. The mask leaves out flow known
#' not to be what the river did: periods given by hand or found by the checks (flow off the
#' applied rating, an event the calibration rain missed) and, if asked, steps whose quality code
#' marks them. It never leaves a flow out for being high, above the top of the rating or above
#' bankfull: those are uncertain, not wrong, and the peaks are what a flood model needs. Their
#' uncertainty is for [peak_band()].
#'
#' The mask is passed to [calibrate_pdm()] (`mask`), which still runs the model through every
#' step and finds events on the whole record, but scores only the steps the mask keeps.
#'
#' @param time Step-start times, POSIXct in UTC.
#' @param periods `NULL`, or a data frame of periods to leave out: `from` and `to` (times, or
#'   text such as `"2015-12-05 06:00"`; `to` inclusive) and `reason`.
#' @param quality `NULL`, or the flow's quality code at each step, such as `"Good"`,
#'   `"Suspect"`, `"Estimated"`.
#' @param mask_quality The quality codes to leave out, such as `c("Suspect", "Estimated")`.
#'   None by default: quality flags vary by station, so masking on them is a choice.
#' @param within `NULL`, or `TRUE` at each step of the calibration window, for the share masked
#'   and the warning.
#' @param warn_share The share of the calibration window masked above which a warning says the
#'   calibration may rest on too little.
#' @return A `pdm_calibration_mask` list: `keep` (`TRUE` to score, one value a step), `reason`
#'   (why each step is left out, `NA` where it is kept), `masked`
#'   (a data frame, one row per reason: `reason`, `steps`, and `share` of the calibration
#'   window) and `share` (the share of the window masked in all).
#' @examples
#' time <- seq(as.POSIXct("2020-01-01", tz = "UTC"), by = "hour", length.out = 48)
#' m <- calibration_mask(time, periods = data.frame(from = "2020-01-01 06:00",
#'                                                  to = "2020-01-01 11:00",
#'                                                  reason = "flow off the applied rating"))
#' m$masked
#' @seealso [peak_band()], [calibrate_pdm()]
#' @export
calibration_mask <- function(time, periods = NULL, quality = NULL, mask_quality = character(0),
                             within = NULL, warn_share = 0.25) {
  .check(inherits(time, "POSIXct") && length(time) >= 1 && !anyNA(time),
         "time must be POSIXct step-start times")
  n <- length(time)
  .check(is.null(within) || (is.logical(within) && length(within) == n && !anyNA(within)),
         "within must be TRUE or FALSE at each step")
  .check(is.character(mask_quality), "mask_quality must be text, such as c(\"Suspect\")")
  .check(.scalar(warn_share, 0, 1), "warn_share must be a share between 0 and 1")
  if (is.null(within)) within <- rep(TRUE, n)
  reason <- rep(NA_character_, n)
  if (!is.null(periods) && nrow(periods)) {
    .check(is.data.frame(periods) && all(c("from", "to") %in% names(periods)),
           "periods needs from and to, and a reason")
    as_time <- function(x) {
      if (inherits(x, "POSIXct")) return(x)
      as.POSIXct(as.character(x), tz = "UTC", optional = TRUE)
    }
    from <- as_time(periods$from)
    to <- as_time(periods$to)
    .check(!anyNA(from) && !anyNA(to) && all(from <= to),
           "Each period needs a from and a to that are times, from first")
    why <- if (is.null(periods$reason)) rep("given by hand", nrow(periods)) else
      as.character(periods$reason)
    for (k in seq_len(nrow(periods))) {
      hit <- time >= from[k] & time <= to[k] & is.na(reason)
      reason[hit] <- why[k]
    }
  }
  if (length(mask_quality)) {
    .check(is.character(quality) && length(quality) == n,
           "mask_quality needs quality: the flow's quality code at each step")
    hit <- quality %in% mask_quality & is.na(reason)
    reason[hit] <- paste("quality code", quality[hit])
  }
  keep <- is.na(reason)
  counted <- !keep & within
  window <- max(1L, sum(within))
  reasons <- sort(unique(reason[counted]))
  masked <- data.frame(
    reason = reasons,
    steps = vapply(reasons, function(r) sum(counted & reason == r), integer(1)),
    share = vapply(reasons, function(r) sum(counted & reason == r) / window, numeric(1)),
    row.names = NULL)
  share <- sum(counted) / window
  if (share > warn_share) {
    warning(sprintf(paste("The mask leaves out %.0f%% of the calibration window, over the %.0f%%",
                          "the design allows without a warning: the calibration may rest on",
                          "too little."), 100 * share, 100 * warn_share), call. = FALSE)
  }
  structure(list(keep = keep, reason = reason, masked = masked, share = share),
            class = "pdm_calibration_mask")
}

#' @export
print.pdm_calibration_mask <- function(x, ...) {
  cat(sprintf("Calibration mask: %.1f%% of the calibration window left out\n", 100 * x$share))
  if (nrow(x$masked)) print(x$masked, row.names = FALSE) else cat("  Nothing masked.\n")
  invisible(x)
}

#' The rating's band at each step, for the peak tolerance
#'
#' The true flow at each step is likely to lie between `q (1 + lower)` and `q (1 + upper)`, where
#' `q` is the rated flow and `lower` and `upper` come from the rating's band, interpolated at `q`
#' on log flow and held flat beyond the table. They are scaled by `factor` and held within
#' `cap` either way. [tolerate()] uses them; [calibrate_pdm()] applies them through its `band`.
#'
#' `factor` is 0.5 by default. The band is a 95% interval, so half its width is about one
#' standard error: errors within that are what the rating's own noise would make, and those
#' beyond it say something about the model. The full band (`factor = 1`) would forgive almost
#' any peak error the rating could explain, and on a wide band above the top of the rating it
#' would leave the peaks nearly unscored. Run 0.5, 1 and 2 to see how much the peaks drive the
#' calibration.
#'
#' @param observed Rated flow, m3/s, one value a step.
#' @param band A data frame of the rating's band: `q` (flow, m3/s), `lower` (a share, 0 or
#'   below, such as -0.12) and `upper` (0 or above, such as 0.15).
#' @param factor The multiple of the band to tolerate.
#' @param cap The most the tolerance may be either way, as a share of the flow.
#' @return A data frame, one row a step: `lower` and `upper` shares (0 where the flow is
#'   missing), with attribute `capped`, the number of steps where the cap bound.
#' @examples
#' band <- data.frame(q = c(1, 10, 100), lower = c(-0.05, -0.1, -0.3), upper = c(0.05, 0.1, 0.4))
#' peak_band(c(1, 10, 100), band)
#' @seealso [tolerate()], [calibration_mask()]
#' @export
peak_band <- function(observed, band, factor = 0.5, cap = 0.5) {
  .check(is.numeric(observed), "observed must be numeric")
  .check(is.data.frame(band) && all(c("q", "lower", "upper") %in% names(band)) &&
           nrow(band) >= 1 && all(is.finite(band$q) & band$q > 0) &&
           all(is.finite(band$lower) & band$lower <= 0) &&
           all(is.finite(band$upper) & band$upper >= 0),
         "band needs q above 0, lower 0 or below and upper 0 or above")
  .check(.scalar(factor, 0), "factor must be 0 or more")
  .check(.scalar(cap, 0, 1), "cap must be a share between 0 and 1")
  b <- band[order(band$q), , drop = FALSE]
  ok <- is.finite(observed) & observed > 0
  at <- function(col) {
    out <- rep(0, length(observed))
    if (any(ok)) {
      out[ok] <- if (nrow(b) == 1L) b[[col]] else
        stats::approx(log(b$q), b[[col]], log(observed[ok]), rule = 2, ties = mean)$y
    }
    out
  }
  lower <- factor * at("lower")
  upper <- factor * at("upper")
  capped <- sum(lower < -cap | upper > cap)
  out <- data.frame(lower = pmax(lower, -cap), upper = pmin(upper, cap))
  attr(out, "capped") <- capped
  out
}

#' Score a simulated flow inside the rating's band as a perfect fit
#'
#' The dead band of the peak tolerance (calibration-mask-design.md): a simulated flow `s` inside
#' `[q (1 + lower), q (1 + upper)]` becomes the observed `q`; one outside it is moved by the
#' band's nearer edge, so it counts as out by its distance from the band:
#'
#' - `s` above the band: `s - q upper`;
#' - `s` below it: `s - q lower`.
#'
#' Every objective then scores the result against `q` in place of `s`, so the tolerance works
#' for each of them unchanged. Steps with no observed flow are left as they are.
#'
#' @param sim Simulated flow, m3/s.
#' @param observed Observed flow, m3/s.
#' @param band Each step's `lower` and `upper` shares, from [peak_band()].
#' @return The simulated flow, moved by the band.
#' @examples
#' band <- data.frame(lower = rep(-0.1, 3), upper = rep(0.2, 3))
#' # Inside the band, above it and below it: 10, 13 - 2 = 11 and 8 + 1 = 9.
#' tolerate(c(11, 13, 8), c(10, 10, 10), band)
#' @seealso [peak_band()], [calibrate_pdm()]
#' @export
tolerate <- function(sim, observed, band) {
  .check(is.numeric(sim) && is.numeric(observed) && length(sim) == length(observed),
         "sim and observed must be numeric and the same length")
  .check(is.data.frame(band) && nrow(band) == length(sim) &&
           all(c("lower", "upper") %in% names(band)),
         "band must have lower and upper for each step, from peak_band()")
  lo <- observed * (1 + band$lower)
  hi <- observed * (1 + band$upper)
  out <- sim
  ok <- is.finite(observed) & is.finite(sim)
  inside <- ok & sim >= lo & sim <= hi
  above <- ok & sim > hi
  below <- ok & sim < lo
  out[inside] <- observed[inside]
  out[above] <- sim[above] - observed[above] * band$upper[above]
  out[below] <- sim[below] - observed[below] * band$lower[below]
  out
}

# A mask as the runs of steps it leaves out, for a project's data card: first_row, last_row and
# reason, so a long record is stored as a few rows, not a value a step.
.mask_runs <- function(mask) {
  why <- ifelse(mask$keep, "", mask$reason)
  r <- rle(why)
  last <- cumsum(r$lengths)
  first <- last - r$lengths + 1L
  out <- r$values != ""
  data.frame(first_row = as.integer(first[out]), last_row = as.integer(last[out]),
             reason = r$values[out])
}

# The mask and the peak band a project's data card holds, over its first n rows: NULL for each
# that was not registered.
.card_scoring <- function(card, observed, n) {
  mask <- NULL
  if (length(card$mask$first_row)) {
    mask <- rep(TRUE, n)
    for (k in seq_along(card$mask$first_row)) {
      r <- seq.int(card$mask$first_row[[k]], card$mask$last_row[[k]])
      mask[r[r <= n]] <- FALSE
    }
  }
  band <- NULL
  pt <- card$peak_tolerance
  if (!is.null(pt) && pt$factor > 0) {
    band <- peak_band(observed[seq_len(n)],
                      data.frame(q = unlist(pt$band$q), lower = unlist(pt$band$lower),
                                 upper = unlist(pt$band$upper)),
                      factor = pt$factor, cap = pt$cap)
  }
  list(mask = mask, band = band)
}
