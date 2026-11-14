# ============================================================ #
# Tool:         well_level
# Description:  Fits the groundwater extension's well factor and datum to an observed well,
#               by regression of the observed level on the modelled groundwater storage
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-13
# Modified:     2026-11-13 - First version
# Tier:         1
# Inputs:       A run_pdm() result or its output; observed well levels (m), NA where unread
# Outputs:      A pdm_well_fit: ys, hw, the fit's scores and the modelled level at every step
# Dependencies: stats; graphics
# ============================================================ #

#' Fit the well level to an observed well
#'
#' The groundwater extension's well level is a straight line in the modelled storage `S`:
#' `hw - Ys (Smax_b - S)`, in m. `Ys` (m of water table per mm of storage deficit) and `hw` (the
#' datum, m) do not change the flow, so they need no calibration run: once the flow is
#' calibrated, a least-squares line of the observed well level on `S` gives `Ys` as its slope and
#' `hw` from its intercept and `Smax_b`. `Smax_b` itself only shifts the datum, so any value
#' serves, provided the same one goes into the model.
#'
#' Dip readings are often weekly or monthly: give `well` one value per step of the run, with
#' `NA` where there is no reading. A slope at or below zero means the well falls as the modelled
#' store fills, and the function stops: the store is not following the aquifer this well sees.
#' A good fit is necessary, not sufficient: a well a long way from the river can lag the store
#' by weeks, which shows as loops in `plot(fit, type = "scatter")`.
#'
#' @param x A [run_pdm()] result, or its `output` data frame, with a `groundwater_mm` column.
#' @param well Observed well levels, m, one per row of the output, `NA` where not read.
#' @param smax_b Maximum groundwater storage, mm. By default read from the output's
#'   `groundwater_deficit_mm` (a model with the groundwater extension); otherwise required.
#' @param time Optional times of the rows, for the plot.
#' @return A list, classed `pdm_well_fit`: `ys` (m/mm), `hw` (m), `smax_b` (mm),
#'   `specific_yield` (`1 / (1000 ys)`), `n` (readings used), `rmse_m`, `r2`, `bias_m`, and
#'   `modelled`, `observed` and `time`, one per row.
#' @examples
#' cfg <- pdm_presets("standard")
#' cfg$area_km2 <- 20
#' cfg$groundwater$extension <- list(smax_b = 800, ys = 0.02, hw = 60)
#' model <- pdm_from_config(cfg)
#' forcing <- synthetic_rain("2020-01-01", years = 1, dt = 1, seed = 1)
#' out <- run_pdm(model, forcing)$output
#' readings <- rep(NA_real_, nrow(out))
#' weekly <- seq(1, nrow(out), by = 168)
#' readings[weekly] <- out$well_level_m[weekly] + rnorm(length(weekly), sd = 0.05)
#' fit <- fit_well_level(out, readings)
#' fit
#' @export
fit_well_level <- function(x, well, smax_b = NULL, time = NULL) {
  out <- if (is.data.frame(x)) x else x$output
  .check(is.data.frame(out) && "groundwater_mm" %in% names(out),
         "x needs a run_pdm() result or output with a groundwater_mm column")
  s <- out$groundwater_mm
  .check(is.numeric(well) && length(well) == length(s),
         paste0("well needs one value per row of the output (", length(s), "), NA where unread"))
  if (is.null(smax_b)) {
    .check("groundwater_deficit_mm" %in% names(out),
           "smax_b is needed: the output has no groundwater_deficit_mm column")
    smax_b <- stats::median(out$groundwater_deficit_mm + s)
  }
  .check(is.numeric(smax_b) && length(smax_b) == 1L && is.finite(smax_b) && smax_b >= 0,
         "smax_b must be one nonnegative number, mm")
  .check(is.null(time) || length(time) == length(s), "time needs one value per row")
  use <- is.finite(well) & is.finite(s)
  .check(sum(use) >= 3L, "At least three well readings are needed")
  .check(stats::var(s[use]) > 0, "The modelled storage does not change at the readings")
  line <- stats::lm.fit(cbind(1, s[use]), well[use])$coefficients
  ys <- unname(line[2])
  .check(ys > 0, paste(
    "The observed well falls as the modelled store fills (slope", signif(ys, 3), "m/mm):",
    "the store does not follow the aquifer this well sees"
  ))
  hw <- unname(line[1]) + ys * smax_b
  modelled <- hw - ys * (smax_b - s)
  residual <- well[use] - modelled[use]
  structure(list(
    ys = ys, hw = hw, smax_b = smax_b, specific_yield = 1 / (1000 * ys), n = sum(use),
    rmse_m = sqrt(mean(residual^2)),
    r2 = 1 - sum(residual^2) / sum((well[use] - mean(well[use]))^2),
    bias_m = mean(residual), modelled = modelled, observed = well, time = time
  ), class = "pdm_well_fit")
}

#' @export
print.pdm_well_fit <- function(x, ...) {
  cat("Well level fitted to", x$n, "readings\n")
  cat(sprintf("  ys %.4g m/mm (specific yield %.3g)\n", x$ys, x$specific_yield))
  cat(sprintf("  hw %.3f m, with smax_b %.6g mm\n", x$hw, x$smax_b))
  cat(sprintf("  RMSE %.3f m, R2 %.3f\n", x$rmse_m, x$r2))
  cat("Set extension ys and hw to these values, with the same smax_b.\n")
  invisible(x)
}

#' @param type `"series"`, the modelled level through time with the readings, or `"scatter"`,
#'   the readings against the modelled level.
#' @param ... Passed to [graphics::plot()].
#' @rdname fit_well_level
#' @export
plot.pdm_well_fit <- function(x, type = c("series", "scatter"), ...) {
  type <- match.arg(type)
  read <- is.finite(x$observed)
  if (type == "series") {
    at <- x$time %||% seq_along(x$modelled)
    span <- range(x$modelled, x$observed[read])
    # Headroom above the data for the legend
    graphics::plot(at, x$modelled, type = "l", col = "#1f5f7a", lwd = 1.5, las = 1,
                   ylim = span + c(0, 0.18 * diff(span)), xlab = "",
                   ylab = "Well level (m)", ...)
    graphics::points(at[read], x$observed[read], pch = 16, cex = 0.6, col = "#b5651d")
    graphics::legend("top", c("modelled", "observed"), col = c("#1f5f7a", "#b5651d"),
                     lty = c(1, NA), pch = c(NA, 16), bty = "n", horiz = TRUE, cex = 0.85)
  } else {
    graphics::plot(x$modelled[read], x$observed[read], pch = 16, cex = 0.6, col = "#b5651d",
                   las = 1, xlab = "Modelled well level (m)", ylab = "Observed well level (m)",
                   ...)
    graphics::abline(0, 1, col = "#1f5f7a", lwd = 1.5)
  }
  invisible(x)
}
