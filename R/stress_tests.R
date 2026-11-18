# ============================================================ #
# Tool:         stress_tests
# Description:  Will the calibration hold when conditions change? The differential split-
#               sample test (calibrate on dry years, validate on wet, and the reverse) and
#               parameter drift (calibrate each period of the record on its own)
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       A configuration, forcing with times, observed flow and parameter bounds
# Outputs:      Tables of scores and parameters, with plot methods
# Dependencies: data.table
# ============================================================ #

# The water year of each time: October to September, named by the year it ends.
.water_year_end <- function(time) {
  lt <- as.POSIXlt(time, tz = "UTC")
  lt$year + 1900L + (lt$mon >= 9L)
}

# Water years with at least `min_share` of their steps observed, with their rain totals.
.usable_years <- function(forcing, observed, min_share = 0.9) {
  .check("time" %in% names(forcing), "The stress tests need a time column in forcing")
  wy <- .water_year_end(forcing$time)
  years <- sort(unique(wy))
  steps <- tabulate(match(wy, years))
  full <- max(steps)
  obs_share <- vapply(years, function(y) mean(is.finite(observed[wy == y])), numeric(1))
  rain <- vapply(years, function(y) sum(forcing$rain[wy == y]), numeric(1))
  ok <- steps >= 0.95 * full & obs_share >= min_share
  data.frame(water_year = years[ok], rain_mm = rain[ok])
}

# Observed flow blank outside the given water years.
.only_years <- function(observed, wy, years) {
  out <- observed
  out[!wy %in% years] <- NA_real_
  out
}

# NSE, 1 - Box-Cox NSE and the volume error of a simulation on the observed rows given.
.stress_scores <- function(sim, obs, log_offset) {
  ok <- is.finite(obs)
  s <- pdm_objectives(sim[ok], obs[ok], c("nse_loss", "boxcox_loss", "abs_bias"),
                      log_offset = log_offset)
  c(nse = 1 - s[["nse_loss"]], boxcox_nse = 1 - s[["boxcox_loss"]],
    volume_error = s[["abs_bias"]])
}

#' Stress tests of a calibration
#'
#' A calibration fitted to one climate can fail in another. These calibrate the same model on
#' different parts of the record and compare.
#'
#' **The differential split-sample test** (`split_sample_test()`, after Klemes, 1986) sorts the
#' complete water years by rain, calibrates on the drier half and validates on the wetter half,
#' then the reverse. A model fit for floods in a wetter future should keep its score from dry to
#' wet; a large drop means the calibration leans on conditions it will not always meet.
#' `split = "halves"` uses the first and second halves of the record instead, the classic split
#' sample, which tests change over time rather than climate.
#'
#' **Parameter drift** (`parameter_drift()`) cuts the record into `periods` runs of consecutive
#' water years and calibrates each on its own. Parameters that stay put are determined by the
#' data; a steady drift points to a change in the catchment or the record (a new rain gauge, a
#' rating change, land use, abstraction) that one long calibration would average away.
#'
#' Every calibration simulates the whole record and scores only its own years, so each starts
#' with the stores as they stand. Arguments in `...` go to [calibrate_pdm()] (`objective`,
#' `method`, `control`, `start` and so on).
#'
#' @param config,forcing,observed,lower,upper As in [calibrate_pdm()]; `forcing` needs `time`.
#' @param split `"climate"` (dry against wet years) or `"halves"` (early against late).
#' @param periods Number of periods for `parameter_drift()`.
#' @param min_share Share of a water year's flows that must be observed for it to count.
#' @param log_offset Offset for the logs and the Box-Cox scores, m3/s.
#' @param start,baseflow_fraction,soil_fraction How every run starts, as in [calibrate_pdm()];
#'   the scoring runs start the same way.
#' @param ... Passed to [calibrate_pdm()].
#' @return `split_sample_test()`: a `pdm_split_sample` list with `scores` (each calibration,
#'   on its own years and on the other years), `parameters` and `years`. `parameter_drift()`: a
#'   `pdm_parameter_drift` list with `parameters` (one row per period) and `scores`.
#' @examples
#' rain <- synthetic_rain("2010-10-01", years = 4, dt = 1, seed = 2)
#' cfg <- modifyList(pdm_presets("standard"), list(area_km2 = 20))
#' flow <- run_pdm(pdm_from_config(cfg), rain[c("rain", "pet")])$output$q_m3s
#' start <- modifyList(cfg, list(fc = 0.8))
#' sst <- split_sample_test(start, rain[c("time", "rain", "pet")], flow,
#'                          lower = c(fc = 0.5), upper = c(fc = 1.5), control = list(maxit = 20))
#' sst$scores
#' @seealso [calibrate_pdm()]
#' @export
split_sample_test <- function(config, forcing, observed, lower, upper,
                              split = c("climate", "halves"), min_share = 0.9,
                              log_offset = 0.01, start = c("flow", "soil"),
                              baseflow_fraction = 0.7, soil_fraction = 0.5, ...) {
  split <- match.arg(split)
  start <- match.arg(start)
  begin <- function(model) {
    suppressWarnings(.start_state(model, start, observed[is.finite(observed)][1L],
                                  baseflow_fraction, soil_fraction))
  }
  years <- .usable_years(forcing, observed, min_share)
  .check(nrow(years) >= 2L, "The split sample needs at least two complete water years")
  half <- floor(nrow(years) / 2)
  groups <- if (split == "climate") {
    o <- order(years$rain_mm)
    list(dry = sort(years$water_year[o[seq_len(half)]]),
         wet = sort(years$water_year[o[seq.int(half + 1L, nrow(years))]]))
  } else {
    list(early = years$water_year[seq_len(half)],
         late = years$water_year[seq.int(half + 1L, nrow(years))])
  }
  wy <- .water_year_end(forcing$time)
  fits <- lapply(names(groups), function(g) {
    calibrate_pdm(config, forcing, .only_years(observed, wy, groups[[g]]), lower, upper,
                  log_offset = log_offset, start = start, start_flow = .first_flow_of(observed),
                  baseflow_fraction = baseflow_fraction, soil_fraction = soil_fraction, ...)
  })
  names(fits) <- names(groups)
  rows <- list()
  for (g in names(groups)) {
    sim <- .run_flow(fits[[g]]$model, forcing, begin(fits[[g]]$model), "q_m3s")
    for (h in names(groups)) {
      sc <- .stress_scores(sim, .only_years(observed, wy, groups[[h]]), log_offset)
      rows[[length(rows) + 1L]] <- data.frame(calibrated_on = g, scored_on = h,
                                              own = g == h, t(sc))
    }
  }
  scores <- do.call(rbind, rows)
  params <- do.call(rbind, lapply(names(fits), function(g) {
    data.frame(calibrated_on = g, t(fits[[g]]$parameters))
  }))
  structure(list(scores = scores, parameters = params, years = groups, split = split,
                 fits = fits),
            class = c("pdm_split_sample", "list"))
}

# The first observed flow, from which a flow start begins: the whole record's, so every
# calibration and its scoring run start alike whichever years they score.
.first_flow_of <- function(observed) observed[is.finite(observed)][1L]

#' @rdname split_sample_test
#' @export
parameter_drift <- function(config, forcing, observed, lower, upper, periods = 3L,
                            min_share = 0.9, log_offset = 0.01, start = c("flow", "soil"),
                            baseflow_fraction = 0.7, soil_fraction = 0.5, ...) {
  .check(.whole(periods, 2, 50), "periods must be a whole number of at least 2")
  start <- match.arg(start)
  begin <- function(model) {
    suppressWarnings(.start_state(model, start, .first_flow_of(observed), baseflow_fraction,
                                  soil_fraction))
  }
  years <- .usable_years(forcing, observed, min_share)$water_year
  .check(length(years) >= periods, "Fewer complete water years than periods")
  block <- cut(seq_along(years), periods, labels = FALSE)
  wy <- .water_year_end(forcing$time)
  rows <- lapply(seq_len(periods), function(p) {
    yrs <- years[block == p]
    obs <- .only_years(observed, wy, yrs)
    fit <- calibrate_pdm(config, forcing, obs, lower, upper, log_offset = log_offset,
                         start = start, start_flow = .first_flow_of(observed),
                         baseflow_fraction = baseflow_fraction, soil_fraction = soil_fraction,
                         ...)
    sim <- .run_flow(fit$model, forcing, begin(fit$model), "q_m3s")
    list(parameters = data.frame(period = p, from = min(yrs), to = max(yrs),
                                 t(fit$parameters)),
         scores = data.frame(period = p, from = min(yrs), to = max(yrs),
                             t(.stress_scores(sim, obs, log_offset))))
  })
  params <- do.call(rbind, lapply(rows, `[[`, "parameters"))
  # Each parameter's change from the first period, as a share of its search range
  span <- upper - lower
  change <- sweep(sweep(as.matrix(params[names(lower)]), 2, unlist(params[1, names(lower)])),
                  2, span, "/")
  structure(list(parameters = params, scores = do.call(rbind, lapply(rows, `[[`, "scores")),
                 change = cbind(params[c("period", "from", "to")], as.data.frame(change)),
                 lower = lower, upper = upper),
            class = c("pdm_parameter_drift", "list"))
}

#' @export
print.pdm_split_sample <- function(x, ...) {
  cat(sprintf("Split-sample test (%s): %s\n", x$split,
              paste(sprintf("%s %s", names(x$years),
                            vapply(x$years, function(y) paste(range(y), collapse = "-"),
                                   character(1))), collapse = ", ")))
  print(x$scores, digits = 3, row.names = FALSE)
  invisible(x)
}

#' @export
print.pdm_parameter_drift <- function(x, ...) {
  cat("Parameters calibrated period by period\n")
  print(x$parameters, digits = 4, row.names = FALSE)
  cat("Change from the first period, as a share of each parameter's range\n")
  print(x$change, digits = 2, row.names = FALSE)
  invisible(x)
}

#' @rdname split_sample_test
#' @param x A result.
#' @export
plot.pdm_parameter_drift <- function(x, ...) {
  .draw_base(.drift_spec(x))
  invisible(x)
}

#' @rdname split_sample_test
#' @param object A result.
#' @exportS3Method ggplot2::autoplot
autoplot.pdm_parameter_drift <- function(object, ...) {
  .draw_gg(.drift_spec(object))
}

# Each parameter's place in its range, period by period, one line each.
.drift_spec <- function(x) {
  p <- names(x$lower)
  colours <- unname(pdm_palette(max(2L, length(p))))[seq_along(p)]
  series <- do.call(rbind, lapply(seq_along(p), function(i) {
    v <- (x$parameters[[p[i]]] - x$lower[[i]]) / (x$upper[[i]] - x$lower[[i]])
    .layer(x$parameters$period, v, p[i], colours[i], lwd = 1.8)
  }))
  list(series = series, ylim = c(0, 1), xlab = "Period",
       xticks = list(at = x$parameters$period,
                     labels = paste0(x$parameters$from, "-", x$parameters$to)),
       ylab = "Place in the search range (0 lower bound, 1 upper)",
       title = "Parameters calibrated period by period",
       subtitle = "Flat lines: determined by the data; steady slopes: something changed")
}
