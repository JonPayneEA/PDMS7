# ============================================================ #
# Tool:         forecast_compare
# Description:  Candidate models ranked as forecasters: hindcast skill by lead time and
#               threshold scores, with the updating each would run with operationally
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Candidate configurations or models; forcing and observed flow
# Outputs:      A pdm_forecast_comparison: scores by candidate, method and lead, and a ranking
# Dependencies: data.table
# ============================================================ #

#' Compare candidate models as forecasters
#'
#' A forecasting model's job is not to simulate a whole record but to forecast a few hours
#' ahead, with updating, against thresholds. This hindcasts every candidate the same way
#' ([pdm_hindcast()]: forecasts from regular origins, each with the updating methods asked
#' for, against persistence) and ranks them on what forecasting needs: skill over persistence
#' at the lead times that matter (`leads_h`), and, with `thresholds`, the threshold score. A
#' model that is a little worse over the whole record but warns earlier ranks higher here, as
#' it should for a forecasting model.
#'
#' Each candidate is judged with its best updating method at each lead (`method = "best"`), as
#' it would be run, or with one named method for all, such as `"none"` for open loop. The
#' ranking is by mean skill over `leads_h`, or by mean threshold score with
#' `rank_on = "threshold"`.
#'
#' @param candidates A named list of configurations or models.
#' @param forcing,observed The record to hindcast.
#' @param leads_h Lead times to rank on, hours; by default every lead the hindcast makes.
#' @param method `"best"`, or one updating method of [pdm_hindcast()] (such as `"none"`).
#' @param thresholds,threshold_score Named threshold flows (m3/s) for [hindcast_scores()], and
#'   the score (`csi`, `pod` or `far`) to rank on with `rank_on = "threshold"`.
#' @param rank_on `"skill"` or `"threshold"`.
#' @param ... Passed to [pdm_hindcast()]: `window`, `every_h`, `horizon_h`, `ar`,
#'   `state_correction` and so on.
#' @return A `pdm_forecast_comparison` list: `scores` (candidate, method, lead and every
#'   score), `ranking` (one row per candidate: mean skill, mean threshold score, rank) and the
#'   settings.
#' @examples
#' set.seed(1)
#' n <- 24 * 30
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.06, rgamma(n, 0.7, scale = 4), 0),
#'                       pet = 0.05)
#' truth <- pdm_model(area_km2 = 40, fc = 1.1)
#' observed <- run_pdm(truth, forcing)$output$q_m3s
#' cmp <- compare_forecasts(list(truth = truth, low = pdm_model(area_km2 = 40, fc = 0.9)),
#'                          forcing, observed, horizon_h = 12, every_h = 12)
#' cmp$ranking
#' plot(cmp)
#' @seealso [pdm_hindcast()], [hindcast_scores()]
#' @export
compare_forecasts <- function(candidates, forcing, observed, leads_h = NULL, method = "best",
                              thresholds = NULL, threshold_score = c("csi", "pod", "far"),
                              rank_on = c("skill", "threshold"), ...) {
  threshold_score <- match.arg(threshold_score)
  rank_on <- match.arg(rank_on)
  .check(is.list(candidates) && length(candidates) >= 1L && !is.null(names(candidates)) &&
           all(nzchar(names(candidates))) && !anyDuplicated(names(candidates)),
         "candidates must be a list with unique names")
  .check(rank_on == "skill" || length(thresholds) > 0,
         "rank_on = \"threshold\" needs thresholds")
  scores <- data.table::rbindlist(lapply(names(candidates), function(nm) {
    x <- candidates[[nm]]
    model <- if (S7::S7_inherits(x, FlodePdmModel)) x else pdm_from_config(x)
    s <- hindcast_scores(.quietly(pdm_hindcast(model, forcing, observed, ...)),
                         thresholds = thresholds)
    cbind(data.table::data.table(candidate = nm), s)
  }), fill = TRUE)
  leads <- leads_h %||% sort(unique(scores$lead_h))
  pick <- .forecast_rows(scores, leads, method)
  tcols <- if (length(thresholds)) {
    grep(paste0("^", threshold_score, ":"), names(scores), value = TRUE)
  }
  ranking <- .forecast_ranking(pick, tcols, rank_on, threshold_score)
  structure(list(scores = scores, chosen = pick, ranking = ranking, leads_h = leads,
                 method = method, rank_on = rank_on, threshold_score = threshold_score),
            class = c("pdm_forecast_comparison", "list"))
}

utils::globalVariables(c("skill", ".SD", ".N", "lead_h", "candidate"))

# One row per candidate: mean skill and mean threshold score over the rows it is judged on, and
# its rank, best first (a lower false alarm ratio is better; higher otherwise).
.forecast_ranking <- function(pick, tcols, rank_on, threshold_score) {
  ranking <- pick[, list(
    mean_skill = mean(skill, na.rm = TRUE),
    mean_threshold = if (length(tcols)) mean(unlist(.SD), na.rm = TRUE) else NA_real_,
    leads = .N
  ), by = "candidate", .SDcols = if (length(tcols)) tcols else "skill"]
  better <- if (rank_on == "skill") {
    -ranking$mean_skill
  } else if (threshold_score == "far") {
    ranking$mean_threshold
  } else {
    -ranking$mean_threshold
  }
  ranking$rank <- rank(better, ties.method = "min")
  ranking[order(ranking$rank)]
}

# The rows each candidate is judged on: at each lead, its best method by skill (persistence
# excluded), or the one method named.
.forecast_rows <- function(scores, leads, method) {
  s <- scores[scores$method != "persistence" & scores$lead_h %in% leads]
  if (!identical(method, "best")) {
    .check(method %in% s$method, paste("No hindcast method", method, "; methods are",
                                       toString(unique(s$method))))
    return(s[s$method == method])
  }
  s <- s[order(s$candidate, s$lead_h, -s$skill)]
  s[!duplicated(s[, c("candidate", "lead_h")])]
}

#' @export
print.pdm_forecast_comparison <- function(x, ...) {
  cat(sprintf("Forecast comparison of %d candidates on %d lead times, %s method, ranked on %s\n",
              nrow(x$ranking), length(x$leads_h), x$method, x$rank_on))
  print(as.data.frame(x$ranking), digits = 3, row.names = FALSE)
  invisible(x)
}

#' @rdname compare_forecasts
#' @param x,object A `pdm_forecast_comparison`.
#' @export
plot.pdm_forecast_comparison <- function(x, ...) {
  .draw_base(.forecast_compare_spec(x))
  invisible(x)
}

#' @rdname compare_forecasts
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_forecast_comparison <- function(object, ...) {
  .draw_gg(.forecast_compare_spec(object))
}

# Skill against lead time, one line per candidate, the best ranked first in the legend.
.forecast_compare_spec <- function(x) {
  ranked <- x$ranking$candidate
  colours <- unname(pdm_palette(max(2L, length(ranked))))[seq_along(ranked)]
  chosen <- as.data.frame(x$chosen)
  series <- do.call(rbind, lapply(seq_along(ranked), function(i) {
    s <- chosen[chosen$candidate == ranked[i], ]
    s <- s[order(s$lead_h), ]
    .layer(s$lead_h, s$skill, sprintf("%d. %s", i, ranked[i]), colours[i], lwd = 1.8)
  }))
  zero <- .layer(range(x$chosen$lead_h), c(0, 0), "Persistence", .pdm_roles[["reference"]],
                 lty = 2, lwd = 1)
  list(series = rbind(zero, series), zero = FALSE, xlab = "Lead time (h)",
       ylab = "Skill over persistence", title = "Candidates as forecasters",
       subtitle = sprintf("%s updating method at each lead; ranked on %s over %s h",
                          if (identical(x$method, "best")) "Each candidate's best" else
                            x$method, x$rank_on, toString(x$leads_h)))
}
