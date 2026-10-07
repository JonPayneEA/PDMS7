# ============================================================ #
# Tool:         vignette_diagrams
# Description:  Draw labelled process diagrams for package vignettes
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-06
# Modified:     2026-10-06 - CX: Add reproducible documentation diagrams
# Tier:         3
# Inputs:       Diagram name: pdm, snow or workflow
# Outputs:      Base graphics process diagram
# Dependencies: graphics (R bundled)
# ============================================================ #

draw_process <- function(kind) {
  graphics::par(mar = c(0.5, 0.5, 0.5, 0.5))
  graphics::plot.new()
  graphics::plot.window(c(0, 10), c(0, 10))
  box <- function(x, y, label, fill = "#e7f2f5", width = 2.8) {
    graphics::rect(x - width / 2, y - 0.55, x + width / 2, y + 0.55,
      col = fill, border = "#255a6c", lwd = 1.4
    )
    graphics::text(x, y, label, cex = 0.88, col = "#163747")
  }
  arrow <- function(x1, y1, x2, y2, label = "", tx = (x1 + x2) / 2,
                    ty = (y1 + y2) / 2) {
    graphics::arrows(x1, y1, x2, y2, length = 0.09, col = "#476876", lwd = 1.3)
    if (nzchar(label)) graphics::text(tx, ty, label, cex = 0.73, pos = 4)
  }
  if (kind == "pdm") {
    box(5, 9, "Rain / snow drainage")
    box(5, 6.7, "Distributed soil\nwater storage")
    box(1.7, 6.7, "Evaporation", "#f9efd9")
    box(3, 3.8, "Fast routing")
    box(7.5, 3.8, "Groundwater routing")
    box(5, 1.2, "Delay + outlet flow")
    arrow(5, 8.45, 5, 7.25, "corrected input")
    arrow(3.6, 6.7, 3.1, 6.7)
    arrow(4.5, 6.15, 3, 4.35, "runoff", 2.3, 5.4)
    arrow(5.8, 6.15, 7.5, 4.35, "recharge", 6.7, 5.4)
    arrow(3, 3.25, 4.5, 1.75)
    arrow(7.5, 3.25, 5.7, 1.75)
  } else if (kind == "snow") {
    box(5, 9, "Corrected precipitation")
    box(2, 6.7, "Dry snow W")
    box(7.7, 6.7, "Rain")
    box(3.7, 3.8, "Liquid water S")
    box(6, 1.2, "Effective rain to PDM")
    arrow(4.1, 8.45, 2, 7.25, "T < Ts", 1.8, 8.1)
    arrow(5.9, 8.45, 7.7, 7.25, "T >= Ts", 7.3, 8.1)
    arrow(2, 6.15, 3.3, 4.35, "melt", 1.7, 5.1)
    arrow(7.3, 6.15, 4.6, 4.35, "F x rain", 5.8, 5.25)
    arrow(8.7, 6.15, 7.1, 1.75, "bare-area\nbypass", 8.1, 3.5)
    arrow(3.7, 3.25, 5.4, 1.75, "two-outlet drainage", 1.1, 2.1)
  } else {
    box(5, 9, "Check forcing + units")
    box(5, 6.8, "Simulate warm-up\nand calibration period")
    box(2.3, 4.3, "Fit several objectives")
    box(7.7, 4.3, "Inspect balances\nand snow behaviour")
    box(5, 1.4, "Choose candidate; validate\non held-out period", width = 3.8)
    arrow(5, 8.45, 5, 7.35)
    arrow(4.4, 6.25, 2.3, 4.85)
    arrow(5.6, 6.25, 7.7, 4.85)
    arrow(2.3, 3.75, 4.3, 1.95)
    arrow(7.7, 3.75, 5.7, 1.95)
  }
}
