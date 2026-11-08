# ============================================================ #
# Tool:         visuals
# Description:  The pdmS7 house style: Okabe-Ito colours with fixed roles, base and ggplot2
#               themes, figure presets, and the two renderers every standard plot shares
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-08
# Modified:     2026-11-08 - First version
# Tier:         3
# Inputs:       Plot descriptions built by each standard plot
# Outputs:      Base R graphics, ggplot objects, figure files
# Dependencies: graphics; grDevices; ggplot2 (suggested)
# ============================================================ #

# The Okabe-Ito colours (Okabe and Ito, 2008), chosen to stay distinct with the common forms of
# colour blindness.
.okabe_ito <- c(black = "#000000", orange = "#E69F00", sky_blue = "#56B4E9",
                bluish_green = "#009E73", yellow = "#F0E442", blue = "#0072B2",
                vermillion = "#D55E00", reddish_purple = "#CC79A7", grey = "#999999")

# One meaning per colour, on every plot.
.pdm_roles <- c(
  observed = "#000000", simulated = "#0072B2", rain = "#56B4E9", alternative = "#D55E00",
  calibration = "#999999", validation = "#E69F00", threshold = "#CC79A7", flag = "#D55E00",
  reference = "#999999", text = "#333333", grid = "#E5E5E5"
)

# How strongly the window bands are filled.
.band_alpha <- c(calibration = 0.18, validation = 0.2)

#' The pdmS7 colours
#'
#' Every standard pdmS7 plot uses the Okabe-Ito colours, which stay distinct with the common
#' forms of colour blindness, and gives each colour one meaning:
#'
#' | Role | Colour | Drawn as |
#' |---|---|---|
#' | `observed` | black | measured flow |
#' | `simulated` | blue | the model |
#' | `rain` | sky blue | bars hanging from the top |
#' | `alternative` | vermillion | a second run, or a change ("after") |
#' | `calibration` | grey | a light band over the calibration window |
#' | `validation` | orange | a light band over the validation window |
#' | `threshold` | reddish purple | dashed lines at warning thresholds |
#' | `flag` | vermillion | markers on anything flagged |
#' | `reference` | grey | guide lines |
#'
#' Use `pdm_colours()` in your own figures so they match. `pdm_palette()` gives colours in a
#' fixed order for plots with several series of equal standing, such as methods or catchments.
#'
#' @param roles Roles to return; by default all.
#' @param alpha Opacity, from 0 to 1.
#' @param n Number of colours.
#' @return A named character vector of hex colours.
#' @examples
#' pdm_colours()
#' pdm_colours(c("observed", "simulated"))
#' pdm_palette(4)
#' @seealso [theme_pdm()], [pdm_save()]
#' @export
pdm_colours <- function(roles = NULL, alpha = 1) {
  roles <- roles %||% names(.pdm_roles)
  .check(is.character(roles) && all(roles %in% names(.pdm_roles)),
         paste("Unknown role; roles are", paste(names(.pdm_roles), collapse = ", ")))
  .check(is.numeric(alpha) && length(alpha) == 1L && alpha >= 0 && alpha <= 1,
         "alpha must be a number from 0 to 1")
  out <- .pdm_roles[roles]
  if (alpha < 1) out[] <- grDevices::adjustcolor(out, alpha)
  out
}

#' @rdname pdm_colours
#' @export
pdm_palette <- function(n) {
  order <- c("blue", "vermillion", "bluish_green", "orange", "reddish_purple", "sky_blue",
             "black", "yellow")
  .check(.whole(n, 1, length(order)), paste("n must be from 1 to", length(order)))
  .okabe_ito[order[seq_len(n)]]
}

#' The pdmS7 ggplot2 theme
#'
#' A light theme with horizontal grid lines only, the legend below the plot and plain titles.
#' Every `autoplot()` method in pdmS7 uses it; add it to your own ggplot2 figures so they
#' match. Needs the ggplot2 package.
#'
#' @param base_size Base font size in points.
#' @param base_family Font family.
#' @return A ggplot2 theme.
#' @examples
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   ggplot2::ggplot(data.frame(x = 1:10, y = cumsum(rnorm(10))), ggplot2::aes(x, y)) +
#'     ggplot2::geom_line(colour = pdm_colours("simulated")) +
#'     theme_pdm()
#' }
#' @seealso [pdm_colours()]
#' @export
theme_pdm <- function(base_size = 11, base_family = "") {
  .need_ggplot()
  ink <- .pdm_roles[["text"]]
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      text = ggplot2::element_text(colour = ink),
      axis.text = ggplot2::element_text(colour = ink),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(colour = .pdm_roles[["grid"]], linewidth = 0.4),
      axis.line = ggplot2::element_line(colour = ink, linewidth = 0.4),
      axis.ticks = ggplot2::element_line(colour = ink, linewidth = 0.3),
      legend.position = "bottom",
      legend.title = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(size = base_size + 1, face = "plain"),
      plot.title.position = "plot",
      plot.subtitle = ggplot2::element_text(size = base_size - 1, colour = "#555555"),
      strip.text = ggplot2::element_text(size = base_size - 1, hjust = 0)
    )
}

# Figure presets: size in inches, resolution, and text size in points.
.pdm_presets <- data.frame(
  preset = c("screen", "report", "report_half", "slide", "journal_single", "journal_double"),
  width = c(8, 6.3, 3.1, 10, 3.35, 6.9),
  height = c(4.5, 3.6, 2.6, 5.625, 2.6, 3.6),
  dpi = c(110, 300, 300, 200, 600, 600),
  pointsize = c(11, 10, 8, 14, 8, 9)
)

#' Save a pdmS7 figure at a standard size
#'
#' Writes a figure to PNG, PDF or SVG, chosen by the file's extension, at one of the standard
#' sizes:
#'
#' | Preset | Size (inches) | Resolution | Text | Use |
#' |---|---|---|---|---|
#' | `screen` | 8 x 4.5 | 110 dpi | 11 pt | screens, articles, the app |
#' | `report` | 6.3 x 3.6 | 300 dpi | 10 pt | full width of an A4 report |
#' | `report_half` | 3.1 x 2.6 | 300 dpi | 8 pt | half width of an A4 report |
#' | `slide` | 10 x 5.6 | 200 dpi | 14 pt | 16:9 slides |
#' | `journal_single` | 3.35 x 2.6 | 600 dpi | 8 pt | one journal column |
#' | `journal_double` | 6.9 x 3.6 | 600 dpi | 9 pt | two journal columns |
#'
#' `plot` may be a ggplot (from `autoplot()`), any object with a `plot()` method, such as a
#' [pdm_series()], or a function of no arguments that draws in base graphics.
#'
#' @param plot What to draw.
#' @param file Output path ending in `.png`, `.pdf` or `.svg`.
#' @param preset One of the presets above.
#' @param width,height Size in inches, overriding the preset.
#' @param dpi Resolution for PNG, overriding the preset.
#' @param ... Passed to `plot()` when `plot` is an object, such as `type = "duration"`.
#' @return `file`, invisibly.
#' @examples
#' s <- pdm_series(simulated = sin(1:200 / 10) + 2, observed = sin(1:200 / 10 + 0.2) + 2)
#' f <- tempfile(fileext = ".png")
#' pdm_save(s, f, preset = "report")
#' file.exists(f)
#' @seealso [pdm_colours()], [theme_pdm()]
#' @export
pdm_save <- function(plot, file, preset = "screen", width = NULL, height = NULL, dpi = NULL,
                     ...) {
  .check(is.character(file) && length(file) == 1L, "file must be a path")
  ext <- tolower(tools::file_ext(file))
  .check(ext %in% c("png", "pdf", "svg"), "file must end in .png, .pdf or .svg")
  .check(is.character(preset) && length(preset) == 1L && preset %in% .pdm_presets$preset,
         paste("preset must be one of", paste(.pdm_presets$preset, collapse = ", ")))
  p <- .pdm_presets[.pdm_presets$preset == preset, ]
  width <- width %||% p$width
  height <- height %||% p$height
  dpi <- dpi %||% p$dpi
  if (inherits(plot, "ggplot")) {
    plot <- plot + ggplot2::theme(text = ggplot2::element_text(size = p$pointsize))
    ggplot2::ggsave(file, plot, width = width, height = height, dpi = dpi, units = "in")
    return(invisible(file))
  }
  switch(ext,
    png = grDevices::png(file, width = width, height = height, units = "in", res = dpi,
                         pointsize = p$pointsize),
    pdf = grDevices::pdf(file, width = width, height = height, pointsize = p$pointsize,
                         useDingbats = FALSE),
    svg = grDevices::svg(file, width = width, height = height, pointsize = p$pointsize)
  )
  on.exit(grDevices::dev.off(), add = TRUE)
  if (is.function(plot)) plot() else graphics::plot(plot, ...)
  invisible(file)
}

# ---- Shared drawing ----------------------------------------------------------------------

# Every standard plot builds a description and hands it to one of two renderers, so base R and
# ggplot2 always draw the same thing. A description is a list:
#   series  data frame: panel, x, y, label, colour, geom ("line", "point" or "step"), lty,
#           lwd; NA in y breaks a line
#   bands   data frame: panel, xmin, xmax, label, fill (shaded windows), or NULL
#   hlines  data frame: panel, y, label, colour (dashed lines, such as thresholds), or NULL
#   rain    data frame: panel, xmin, xmax, depth, top, scale (bars hanging from y = top, each
#           depth * scale tall), or NULL; rain_axis says whether to label depths on the right
#   panels  data frame: panel, title (panel titles), or NULL for a single panel
#   xlab, ylab, title, subtitle, log ("" or "y" or "xy"), ncol (panels per row), ylim
#   legend  labels in legend order, or NULL for their order of appearance
#   xlim    x range, or NULL for the data's
#   zero    FALSE to let a linear y axis start where the data do, rather than at zero
#   xticks, yticks  list(at, labels) for labelled positions, such as stages or parameter names
# geom "open" draws hollow points, used for screened-out or secondary values.
# Series are drawn in the order of their rows, so later rows sit on top.
# A series label starting with "." is drawn but left out of the legend.

.need_ggplot <- function() {
  .check(requireNamespace("ggplot2", quietly = TRUE),
         "autoplot() and theme_pdm() need the ggplot2 package; plot() draws in base R")
}

# A series layer for a description.
.layer <- function(x, y, label, colour, geom = "line", lty = 1, lwd = 1.5, panel = 1L) {
  n <- length(x)
  data.frame(panel = rep(panel, length.out = n), x = x, y = y, label = label, colour = colour,
             geom = geom, lty = lty, lwd = lwd, stringsAsFactors = FALSE)
}

# Bars of rain hanging from the top of a panel whose highest value is `peak`: the panel is
# raised by 45% and the rain takes the top 30%.
.rain_layer <- function(xmin, xmax, depth, peak, panel = 1L) {
  keep <- is.finite(depth) & depth > 0
  if (!any(keep)) return(NULL)
  top <- peak * 1.45
  data.frame(panel = panel, xmin = xmin[keep], xmax = xmax[keep], depth = depth[keep],
             top = top, scale = 0.3 * peak / max(depth[keep]))
}

# Base graphics settings for the house style; returns the old settings.
.pdm_par <- function(..., mar = c(3.4, 4.2, 2.6, 4.2)) {
  graphics::par(mar = mar, mgp = c(2.3, 0.6, 0), tcl = -0.25, las = 1,
                cex.axis = 0.85, cex.lab = 0.9, cex.main = 0.95, font.main = 1, bty = "l",
                col.axis = .pdm_roles[["text"]], col.lab = .pdm_roles[["text"]],
                fg = .pdm_roles[["text"]], ...)
}

# Draws a description in base graphics.
.draw_base <- function(spec) {
  panels <- sort(unique(spec$series$panel))
  ncol <- min(spec$ncol %||% 2L, length(panels))
  layout <- if (length(panels) > 1L) c(ceiling(length(panels) / ncol), ncol) else c(1, 1)
  single <- length(panels) == 1L
  old <- .pdm_par(mfrow = layout, oma = c(if (single) 0 else 2.4, 0, if (single) 0 else 2, 0),
                  mar = c(if (single) 5.2 else 2.6, .left_margin(spec), 2.6,
                          if (single) 4.2 else 1))
  on.exit(graphics::par(old), add = TRUE)
  for (p in panels) .draw_base_panel(spec, p, single = length(panels) == 1L)
  if (length(panels) > 1L && !is.null(spec$title)) {
    graphics::mtext(spec$title, outer = TRUE, line = 0.4, cex = 0.95)
  }
  .draw_base_legend(spec)
  invisible(spec)
}

.draw_base_panel <- function(spec, p, single) {
  s <- spec$series[spec$series$panel == p, ]
  hlines <- .panel_rows(spec$hlines, p)
  rain <- .panel_rows(spec$rain, p)
  log <- spec$log %||% ""
  xlim <- spec$xlim %||% range(s$x[is.finite(as.numeric(s$x))])
  .base_frame(spec, p, single, xlim, .base_ylim(spec, s, hlines, rain))
  .draw_base_bands(.panel_rows(spec$bands, p), log)
  if (!is.null(rain)) .draw_base_rain(rain, axis = single && isTRUE(spec$rain_axis))
  .draw_base_series(s)
  if (!is.null(hlines)) {
    graphics::abline(h = hlines$y, col = hlines$colour, lty = 2, lwd = 1.2)
    graphics::text(xlim[1], hlines$y, hlines$label, adj = c(0, -0.4), cex = 0.7,
                   col = hlines$colour)
  }
  if (single && !is.null(spec$subtitle)) {
    graphics::mtext(spec$subtitle, side = 3, line = 0.2, cex = 0.75, col = "#555555")
  }
}

# The y range of a panel: its values and thresholds, up to the top of any rain, from zero on a
# linear axis, unless the description fixes it.
.base_ylim <- function(spec, s, hlines, rain) {
  if (!is.null(spec$ylim)) return(spec$ylim)
  log <- spec$log %||% ""
  ok <- is.finite(s$y) & (!grepl("y", log) | s$y > 0)
  ylim <- range(c(s$y[ok], hlines$y), na.rm = TRUE)
  if (!is.null(rain)) ylim[2] <- rain$top[1]
  if (log == "" && !isFALSE(spec$zero)) ylim[1] <- min(0, ylim[1])
  ylim
}

# An empty panel with its axes, plain-number labels on log axes, the y title and the grid.
.base_frame <- function(spec, p, single, xlim, ylim) {
  log <- spec$log %||% ""
  title <- if (single) spec$title else spec$panels$title[spec$panels$panel == p]
  custom <- c(grepl("x", log) || !is.null(spec$xticks), grepl("y", log) || !is.null(spec$yticks))
  graphics::plot(xlim, ylim, type = "n", log = log, xlab = if (single) spec$xlab else "",
                 ylab = "", main = title %||% "", xaxt = if (custom[1]) "n" else "s",
                 yaxt = if (custom[2]) "n" else "s")
  for (side in which(custom)) .base_axis(side, list(spec$xticks, spec$yticks)[[side]])
  if (single || (p - 1L) %% (spec$ncol %||% 2L) == 0L) .base_ylab(spec$ylab)
  .base_grid(log)
}

# An axis with given labelled positions, or plain-number labels on a log axis.
.base_axis <- function(side, ticks) {
  if (is.null(ticks)) {
    at <- graphics::axTicks(side)
    return(graphics::axis(side, at = at, labels = .plain_numbers(at)))
  }
  graphics::axis(side, at = ticks$at, labels = ticks$labels, cex.axis = 0.75,
                 las = if (side == 2) 1 else 0, tick = side == 1)
}

# Room on the left for the y labels: wider for log axes, wider still for named positions.
.left_margin <- function(spec) {
  if (!is.null(spec$yticks)) return(max(4.2, 0.45 * max(nchar(spec$yticks$labels)) + 1))
  if (grepl("y", spec$log %||% "")) 5.4 else 4.2
}

.draw_base_bands <- function(bands, log) {
  if (is.null(bands)) return(invisible())
  usr <- graphics::par("usr")[3:4]
  if (grepl("y", log)) usr <- 10^usr
  graphics::rect(bands$xmin, usr[1], bands$xmax, usr[2], col = bands$fill, border = NA)
}

# Labels that appear in a legend: not empty and not starting with ".".
.shown <- function(label) nzchar(label) & !startsWith(label, ".")

.panel_rows <- function(df, p) {
  if (is.null(df)) return(NULL)
  out <- df[df$panel == p, , drop = FALSE]
  if (nrow(out)) out else NULL
}

# The y-axis title, set just clear of the widest tick label.
.base_ylab <- function(ylab) {
  if (is.null(ylab) || !nzchar(ylab)) return(invisible())
  labels <- graphics::axTicks(2)
  if (graphics::par("ylog")) labels <- .plain_numbers(labels)
  width <- max(graphics::strwidth(as.character(labels), units = "inches", cex = 0.85))
  line <- min(width / graphics::par("csi") + 1, graphics::par("mar")[2] - 1)
  graphics::title(ylab = ylab, line = line)
}

.base_grid <- function(log) {
  at <- graphics::axTicks(2)
  graphics::abline(h = at, col = .pdm_roles[["grid"]], lwd = 0.8)
}

.draw_base_rain <- function(rain, axis) {
  graphics::rect(rain$xmin, rain$top - rain$depth * rain$scale, rain$xmax, rain$top,
                 col = .pdm_roles[["rain"]], border = NA)
  if (!axis) return(invisible())
  at <- .rain_breaks(rain$depth)
  graphics::axis(4, at = rain$top[1] - at * rain$scale[1], labels = at)
  graphics::mtext("Rain (mm)", side = 4, line = 2.6, cex = 0.9, las = 0,
                  col = .pdm_roles[["text"]])
}

# Numbers as a hydrologist writes them: 0.01, 1, 100, not 1e-02.
.plain_numbers <- function(x) {
  format(x, scientific = FALSE, drop0trailing = TRUE, trim = TRUE, big.mark = ",")
}

# Rain axis ticks, no further than the deepest bar.
.rain_breaks <- function(depth) {
  at <- pretty(c(0, max(depth)), 3)
  at[at <= max(depth) * 1.05]
}

.draw_base_series <- function(s) {
  for (label in unique(s$label)) {
    one <- s[s$label == label, ]
    if (one$geom[1] %in% c("point", "open")) {
      graphics::points(one$x, one$y, pch = if (one$geom[1] == "open") 1 else 16,
                       cex = 0.45 * one$lwd[1], col = one$colour[1])
    } else {
      graphics::lines(one$x, one$y, col = one$colour[1], lty = one$lty[1], lwd = one$lwd[1],
                      type = if (one$geom[1] == "step") "s" else "l")
    }
  }
}

# The legend runs along the foot of the figure, on an overlay of the whole device.
.draw_base_legend <- function(spec) {
  keys <- .legend_keys(spec)
  bands <- if (is.null(spec$bands)) NULL else unique(spec$bands[, c("label", "fill")])
  labels <- c(keys$label, bands$label)
  if (!length(labels)) return(invisible())
  point <- keys$geom %in% c("point", "open")
  nb <- length(bands$label)
  graphics::par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0.3, 0, 0, 0), new = TRUE)
  graphics::plot.new()
  graphics::legend(
    "bottom", legend = paste0(labels, "    "), horiz = TRUE, bty = "n", cex = 0.8, xpd = NA,
    text.width = NA,
    col = c(keys$colour, bands$fill), lty = c(ifelse(point, NA, keys$lty), rep(NA, nb)),
    lwd = c(keys$lwd, rep(NA, nb)),
    pch = c(ifelse(point, ifelse(keys$geom == "open", 1, 16), NA), rep(15, nb)),
    pt.cex = c(rep(1, nrow(keys)), rep(1.8, nb))
  )
}

# One row per legend entry, in the description's legend order.
.legend_keys <- function(spec) {
  keys <- spec$series[!duplicated(spec$series$label), c("label", "colour", "geom", "lty", "lwd")]
  keys <- keys[.shown(keys$label), ]
  if (!is.null(spec$legend)) keys <- keys[order(match(keys$label, spec$legend)), ]
  keys
}

# Columns named inside ggplot2::aes().
utils::globalVariables(c("x", "y", "xmin", "xmax", "label", "segment", "panel", "depth",
                         "top", "scale"))

# Draws a description as a ggplot.
.draw_gg <- function(spec) {
  .need_ggplot()
  s <- spec$series
  s$segment <- stats::ave(is.na(s$y), s$panel, s$label, FUN = cumsum)
  s <- s[is.finite(s$y) & (!grepl("y", spec$log %||% "") | s$y > 0), ]
  keys <- s[!duplicated(s$label), ]
  g <- ggplot2::ggplot()
  if (!is.null(spec$bands)) {
    g <- g + ggplot2::geom_rect(
      data = spec$bands,
      ggplot2::aes(xmin = xmin, xmax = xmax, fill = label),
      ymin = -Inf, ymax = Inf
    ) + ggplot2::scale_fill_manual(values = stats::setNames(spec$bands$fill, spec$bands$label))
  }
  if (!is.null(spec$rain)) {
    g <- g + ggplot2::geom_rect(
      data = spec$rain,
      ggplot2::aes(xmin = xmin, xmax = xmax, ymin = top - depth *
                     scale, ymax = top),
      fill = .pdm_roles[["rain"]], colour = NA
    )
  }
  g <- .gg_series(g, s)
  if (!is.null(spec$hlines)) {
    g <- g + ggplot2::geom_hline(data = spec$hlines, ggplot2::aes(yintercept = y),
                                 colour = spec$hlines$colour, linetype = 2)
    named <- spec$hlines[nzchar(spec$hlines$label), ]
    if (nrow(named)) {
      g <- g + ggplot2::geom_text(data = named, ggplot2::aes(y = y, label = label), x = -Inf,
                                  hjust = -0.05, vjust = -0.4, size = 2.6,
                                  colour = named$colour)
    }
  }
  shown <- .legend_keys(spec)$label
  # Both scales get the same limits and breaks, so their legends merge into one.
  g <- g + ggplot2::scale_colour_manual(values = stats::setNames(keys$colour, keys$label),
                                        breaks = shown, limits = keys$label)
  # The same breaks as the colour scale, so the two legends merge; none at all for a plot of
  # points only, which has no line types to map.
  if (any(keys$geom %in% c("line", "step"))) {
    g <- g + ggplot2::scale_linetype_manual(values = stats::setNames(keys$lty, keys$label),
                                            breaks = shown, limits = keys$label)
  }
  g <- .gg_scales(g, spec)
  if (!is.null(spec$ylim) || !is.null(spec$xlim)) {
    g <- g + ggplot2::coord_cartesian(xlim = spec$xlim, ylim = spec$ylim)
  }
  g + ggplot2::labs(x = spec$xlab, y = spec$ylab, title = spec$title, subtitle = spec$subtitle) +
    theme_pdm()
}

# Each label is its own layer, added in row order, so the stacking matches base R.
.gg_series <- function(g, s) {
  for (label in unique(s$label)) {
    one <- s[s$label == label, ]
    if (one$geom[1] %in% c("point", "open")) {
      g <- g + ggplot2::geom_point(data = one, ggplot2::aes(x, y, colour = label),
                                   size = 0.5 * one$lwd[1],
                                   shape = if (one$geom[1] == "open") 1 else 16)
    } else {
      g <- g + ggplot2::geom_line(
        data = one,
        ggplot2::aes(x, y, colour = label, linetype = label,
                     group = interaction(segment, panel)),
        linewidth = 0.4 * one$lwd[1]
      )
    }
  }
  g
}

.gg_scales <- function(g, spec) {
  panels <- unique(spec$series$panel)
  log_x <- grepl("x", spec$log %||% "")
  log_y <- grepl("y", spec$log %||% "")
  if (log_x) g <- g + ggplot2::scale_x_log10(labels = .plain_numbers)
  if (!is.null(spec$xticks)) {
    g <- g + ggplot2::scale_x_continuous(breaks = spec$xticks$at, labels = spec$xticks$labels)
  }
  if (length(panels) > 1L) {
    titles <- stats::setNames(spec$panels$title, spec$panels$panel)
    g <- g + ggplot2::facet_wrap(ggplot2::vars(panel), scales = "free",
                                 ncol = spec$ncol %||% 2L,
                                 labeller = ggplot2::as_labeller(titles))
    if (log_y) g <- g + ggplot2::scale_y_log10(labels = .plain_numbers)
    return(g)
  }
  rain <- spec$rain
  if (log_y) return(g + ggplot2::scale_y_log10(labels = .plain_numbers))
  if (!is.null(rain) && isTRUE(spec$rain_axis)) {
    # Depth back from the flow axis: the bars hang from top, depth * scale tall.
    to_depth <- function(v) (rain$top[1] - v) / rain$scale[1]
    return(g + ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(mult = c(0, 0.02)),
      sec.axis = ggplot2::sec_axis(to_depth, name = "Rain (mm)",
                                   breaks = .rain_breaks(rain$depth))
    ))
  }
  .gg_linear_y(g, spec)
}

# A linear y axis: named positions if given; otherwise flows start at zero, as in base R, and
# scores and errors get a margin below.
.gg_linear_y <- function(g, spec) {
  if (!is.null(spec$yticks)) {
    return(g + ggplot2::scale_y_continuous(breaks = spec$yticks$at,
                                           labels = spec$yticks$labels))
  }
  y <- spec$series$y[is.finite(spec$series$y)]
  floor <- !isFALSE(spec$zero) && length(y) && min(y) >= 0
  if (floor) g <- g + ggplot2::expand_limits(y = 0)
  below <- if (floor) 0 else 0.04
  g + ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(below, 0.04)))
}
