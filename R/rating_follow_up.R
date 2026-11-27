# ============================================================ #
# Tool:         rating_follow_up
# Description:  Whether a balance diagnosis calls for work on the rating, and which: fit a
#               candidate rating from the gaugings, get high-flow gaugings, ask the
#               hydrometry team, or nothing; one row per finding, with what to do about it
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-27
# Tier:         1
# Inputs:       A balance_diagnosis(); optionally reach.rate's flow record check and the
#               gaugings against the rating in force (compare_gaugings_to_rating()$limbs)
# Outputs:      A pdm_rating_follow_up list
# Dependencies: none
# ============================================================ #

#' Whether the rating needs more work
#'
#' Reads what [balance_diagnosis()], the flow record check and the gaugings found, and says
#' whether the rating calls for more work, and which:
#'
#' - **Fit a candidate rating** when a limb's gaugings sit consistently off the rating in force
#'   (median residual beyond `residual_pct`, or under `within_share` of them within 10%) and
#'   there are at least `min_gaugings` over it to fit from.
#' - **Get high-flow gaugings** when a limb is off but too thinly gauged to refit, or when much
#'   of the flow (over `above_top_share`) comes from above the highest gauging.
#' - **Ask the hydrometry team** when the record was made with a rating not in the export, or
#'   stage rose in dry summer weather (weed): neither is fixed by refitting.
#' - **No rating work** when nothing above holds and the diagnosis does not suspect the rating.
#'
#' Revisions of the applied rating and peaks above bankfull are listed as notes: the first to
#' check against the rating history, the second to treat those floods with care, since a
#' rating cannot correct flow that bypasses the section.
#'
#' A candidate rating is evidence for the team who own the rating, not a replacement: a water
#' balance alone should not change an operational rating.
#'
#' @param diagnosis The output of [balance_diagnosis()].
#' @param record_check The output of `reach.rate::check_flow_record()`, or `NULL`.
#' @param gaugings The gaugings against the rating in force, limb by limb: the `limbs` table of
#'   `reach.rate::compare_gaugings_to_rating()`, or `NULL`.
#' @param residual_pct,within_share A limb is off the rating when its gaugings' median residual
#'   is beyond `residual_pct` per cent, or fewer than `within_share` of them are within 10%.
#' @param min_gaugings The fewest gaugings over a limb to fit it from.
#' @param above_top_share The share of flow volume above the top of the rating above which the
#'   top needs testing.
#' @return A `pdm_rating_follow_up` list: `verdict` (one of `"fit a candidate rating"`,
#'   `"get high-flow gaugings"`, `"ask the hydrometry team"`, `"no rating work needed"`),
#'   `action_needed` (`TRUE` unless the verdict is the last), `why` (one sentence) and
#'   `findings` (a data frame: `check`, `finding`, `action`, and `status`, one of `"act"`,
#'   `"ask"`, `"note"`, `"fine"` or `"not assessed"`).
#' @examples
#' rain <- synthetic_rain("2019-10-01", years = 4, dt = 1, seed = 4)
#' forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
#' config <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(config), forcing)$output$q_m3s
#' floods <- find_events(rain$rain, flow, rain$time, dt = 1, area_km2 = 20)
#' d <- balance_diagnosis(rain$time, flow, list(gauges = rain$rain), rain$pet, 20, floods)
#' # Gaugings 12% above the top limb of the rating in force, 15 of them: fit a candidate.
#' limbs <- data.frame(limb = 1:2, lower_level = c(0, 1), upper_level = c(1, 3),
#'                     n_gaugings = c(20, 15), gauged_max_stage = c(1, 2.6),
#'                     median_residual_pct = c(1, 12), share_within_tol = c(0.95, 0.4))
#' rating_follow_up(d, gaugings = limbs)
#' @seealso [balance_diagnosis()]
#' @export
rating_follow_up <- function(diagnosis, record_check = NULL, gaugings = NULL, residual_pct = 5,
                             within_share = 0.8, min_gaugings = 10, above_top_share = 0.05) {
  .check(inherits(diagnosis, "pdm_balance_diagnosis"),
         "diagnosis must be the output of balance_diagnosis()")
  .check(is.null(gaugings) ||
           (is.data.frame(gaugings) &&
              all(c("n_gaugings", "median_residual_pct", "share_within_tol") %in% names(gaugings))),
         paste("gaugings must be the limbs table of compare_gaugings_to_rating(): it needs",
               "n_gaugings, median_residual_pct and share_within_tol"))
  rec <- diagnosis$record
  rating_verdict <- diagnosis$suspects$verdict[diagnosis$suspects$suspect == "rating"]
  rows <- list()
  add <- function(check, status, finding, action) {
    rows[[length(rows) + 1L]] <<- data.frame(check = check, status = status, finding = finding,
                                             action = action, stringsAsFactors = FALSE)
  }

  # The diagnosis: does the balance point at the rating at all?
  add("balance diagnosis",
      if (rating_verdict %in% c("likely", "possible")) "note" else "fine",
      sprintf("the rating is %s as a cause of the balance's gap", rating_verdict),
      if (rating_verdict %in% c("likely", "possible")) {
        "read the gaugings and the record below"
      } else {
        "none from the balance"
      })

  # The gaugings, limb by limb.
  off_fit <- off_thin <- FALSE
  if (is.null(gaugings)) {
    add("gaugings against the rating", "not assessed", "no gaugings or no ratings were given",
        "give gaugings_file and ratings_file: only gaugings test whether the rating is right")
  } else {
    g <- gaugings[gaugings$n_gaugings > 0, , drop = FALSE]
    off <- abs(g$median_residual_pct) > residual_pct | g$share_within_tol < within_share
    off[is.na(off)] <- FALSE
    enough <- g$n_gaugings >= min_gaugings
    limb_name <- paste("limb", if ("limb" %in% names(g)) g$limb else seq_len(nrow(g)))
    range_of <- if (all(c("lower_level", "upper_level") %in% names(g))) {
      sprintf(" (%.2f to %.2f m)", g$lower_level, pmin(g$upper_level, 99))
    } else {
      ""
    }
    for (k in seq_len(nrow(g))) {
      finding <- sprintf("%s%s: %d gaugings, median %+.1f%% off the rating, %.0f%% within 10%%",
                         limb_name[k], range_of[k], as.integer(g$n_gaugings[k]),
                         g$median_residual_pct[k], 100 * g$share_within_tol[k])
      if (!off[k]) {
        add("gaugings against the rating", "fine", finding, "none: the gaugings sit on it")
      } else if (enough[k]) {
        off_fit <- TRUE
        add("gaugings against the rating", "act", finding,
            "fit a candidate rating from the gaugings, and send it to the hydrometry team")
      } else {
        off_thin <- TRUE
        add("gaugings against the rating", "act", finding,
            sprintf("too few to refit (under %d): ask for more gaugings over this range",
                    min_gaugings))
      }
    }
    if (!nrow(g)) {
      add("gaugings against the rating", "not assessed", "no gauging falls on any limb",
          "check the gaugings are for this station")
    }
  }

  # The top of the rating.
  top_untested <- isTRUE(rec$above_top_share > above_top_share)
  if (is.na(rec$above_top_share)) {
    add("flow above the top of the rating", "not assessed",
        "the top of the rating was not given or the record was not checked",
        "give stage and the gaugings (or top_stage_m)")
  } else {
    add("flow above the top of the rating", if (top_untested) "act" else "fine",
        sprintf("%.0f%% of the flow came from above the top of the rating",
                100 * rec$above_top_share),
        if (top_untested) {
          "that flow rests on extrapolation: ask for high-flow gaugings to test the top"
        } else {
          "none"
        })
  }

  # The record: a rating not in the export, revisions, bankfull and weed.
  unknown <- FALSE
  if (!is.null(record_check) && !is.null(record_check$periods$known_departing_share)) {
    fit_share <- record_check$settings$known_fit_share
    if (is.null(fit_share)) fit_share <- 0.05
    p <- record_check$periods[record_check$periods$assessed %in% TRUE, , drop = FALSE]
    bad <- !(p$known_departing_share <= fit_share)
    unknown <- any(bad)
    add("record against the known ratings", if (unknown) "ask" else "fine",
        if (unknown) {
          sprintf("%d period(s) of the record fit no rating in the export", sum(bad))
        } else {
          "every period of the record was made with a rating in the export"
        },
        if (unknown) {
          "ask the hydrometry team which rating made those periods: the export is incomplete"
        } else {
          "none"
        })
  }
  if (length(rec$revisions)) {
    add("revisions of the applied rating", "note",
        sprintf("revised %s", paste(format(rec$revisions, "%Y-%m-%d", tz = "UTC"),
                                    collapse = ", ")),
        "check each date against the rating history; a balance across one is two balances")
  }
  if (isTRUE(rec$bankfull_peaks > 0)) {
    add("peaks above bankfull", "note", sprintf("%d peak(s) above bankfull", rec$bankfull_peaks),
        "treat those floods with care: a rating cannot correct flow that bypasses the section")
  }
  if (length(rec$dry_rise_months)) {
    add("dry-weather rises in summer", "ask",
        sprintf("stage rose in dry summer weather in %s",
                paste(rec$dry_rise_months, collapse = ", ")),
        "ask the hydrometry team about weed cutting: summer flow there is overstated")
  }

  findings <- do.call(rbind, rows)
  verdict <- if (off_fit) {
    "fit a candidate rating"
  } else if (off_thin || top_untested) {
    "get high-flow gaugings"
  } else if (unknown || any(findings$status == "ask")) {
    "ask the hydrometry team"
  } else {
    "no rating work needed"
  }
  why <- switch(verdict,
                "fit a candidate rating" = paste(
                  "The gaugings sit off the rating in force over a limb with enough of them to",
                  "fit from: a candidate rating is worth making and sending for review."),
                "get high-flow gaugings" = paste(
                  "The rating is in doubt where too few gaugings test it: more gaugings, not a",
                  "refit, are what would settle it."),
                "ask the hydrometry team" = paste(
                  "The record raises questions a refit cannot answer: the hydrometry team hold",
                  "the answers."),
                "no rating work needed" = if (rating_verdict %in% c("likely", "possible")) {
                  paste("The balance points at the rating, but nothing tested found it wrong;",
                        "give the gaugings and the ratings to test it.")
                } else {
                  "Nothing points at the rating: look to the other suspects."
                })
  if (verdict == "no rating work needed" && rating_verdict %in% c("likely", "possible") &&
        is.null(gaugings)) {
    verdict <- "ask the hydrometry team"
    why <- paste("The balance points at the rating, but no gaugings were given to test it: ask",
                 "the hydrometry team for them.")
  }
  # The verdict names the strongest action; a question for the team behind it is not left to
  # the table alone.
  if (verdict %in% c("fit a candidate rating", "get high-flow gaugings") &&
        any(findings$status == "ask")) {
    why <- paste(why, "Ask the hydrometry team too:",
                 paste(findings$check[findings$status == "ask"], collapse = "; "), "(see below).")
  }
  structure(list(verdict = verdict, action_needed = verdict != "no rating work needed",
                 why = why, findings = findings),
            class = "pdm_rating_follow_up")
}

#' @export
print.pdm_rating_follow_up <- function(x, ...) {
  cat(sprintf("Rating: %s\n  %s\n", x$verdict, x$why))
  for (i in seq_len(nrow(x$findings))) {
    f <- x$findings[i, ]
    cat(sprintf("  [%s] %s: %s\n         %s\n", f$status, f$check, f$finding, f$action))
  }
  invisible(x)
}
