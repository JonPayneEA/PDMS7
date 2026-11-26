# ============================================================ #
# Tool:         report_blocks
# Description:  Building blocks for a self-contained HTML report, for scripts: headings, text,
#               lists, tables, alerts, figures drawn or already on disk; and the HOW TO READ
#               notes of a script, read back as text for the report
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-26
# Tier:         1
# Inputs:       Text, data frames, plotting functions or PNG files; a script's source
# Outputs:      report.html (figures embedded) and report.md in a folder
# Dependencies: grDevices
# ============================================================ #

#' Build a report from blocks
#'
#' A report is a list of blocks, written by [write_report()] as one self-contained HTML file,
#' with every figure embedded so it can be emailed or archived, and as Markdown beside it. The
#' blocks:
#'
#' - `report_heading()`: a section heading (level 1 for the title, 2 for a section, 3 below).
#' - `report_text()`: a paragraph; several strings are joined with spaces.
#' - `report_list()`: a bulleted list, one item a string.
#' - `report_table()`: a data frame, numbers to four significant figures, with a caption.
#' - `report_alert()`: a highlighted line, green when `ok` is `TRUE`, red otherwise.
#' - `report_figure()`: a plot, drawn by a function when the report is written.
#' - `report_image()`: a PNG already on disk, such as one a script has drawn.
#'
#' Text is written as plain text: it is escaped, so it cannot break the page.
#'
#' @param text Text: one string, or several for a paragraph.
#' @param level Heading level, 1 to 3.
#' @param items Character vector, one item each.
#' @param table A data frame.
#' @param caption Caption text.
#' @param ok `TRUE` for a good outcome, `FALSE` for one to check.
#' @param name File name for the figure, without `.png`.
#' @param draw A function of no arguments that draws the figure.
#' @param width,height Figure size in inches.
#' @param file Path of an existing PNG file.
#' @param ... Strings joined into one paragraph.
#' @return A block: a list for [write_report()].
#' @examples
#' blocks <- list(
#'   report_heading("A short report", 1),
#'   report_text("Two numbers and", "a plot."),
#'   report_table(data.frame(x = 1:2, y = c(0.5, 0.25)), caption = "The numbers"),
#'   report_figure("line", function() plot(1:10), "A line", width = 5, height = 3)
#' )
#' write_report(blocks, tempfile("report"), "A short report")
#' @seealso [write_report()], [read_plot_notes()]
#' @name report_blocks
NULL

#' @rdname report_blocks
#' @export
report_heading <- function(text, level = 2L) {
  .check(is.character(text) && length(text) == 1, "text must be one string")
  .check(level %in% 1:3, "level must be 1, 2 or 3")
  .blk_h(text, as.integer(level))
}

#' @rdname report_blocks
#' @export
report_text <- function(...) {
  text <- unlist(list(...))
  .check(is.character(text) && length(text) > 0, "text must be strings")
  .blk_p(text)
}

#' @rdname report_blocks
#' @export
report_list <- function(items) {
  .check(is.character(items) && length(items) > 0, "items must be strings")
  .blk_list(items)
}

#' @rdname report_blocks
#' @export
report_table <- function(table, caption = NULL) {
  .check(is.data.frame(table), "table must be a data frame")
  .blk_table(table, caption)
}

#' @rdname report_blocks
#' @export
report_alert <- function(text, ok) {
  .check(is.character(text) && length(text) == 1, "text must be one string")
  .blk_alert(text, ok)
}

#' @rdname report_blocks
#' @export
report_figure <- function(name, draw, caption, width = 9, height = 4.5) {
  .check(is.character(name) && length(name) == 1 && grepl("^[A-Za-z0-9_.-]+$", name),
         "name must be a file name of letters, digits, '_', '.' or '-'")
  .check(is.function(draw), "draw must be a function that draws the figure")
  .blk_fig(name, draw, caption, width, height)
}

#' @rdname report_blocks
#' @export
report_image <- function(file, caption) {
  .check(is.character(file) && length(file) == 1 && file.exists(file),
         paste("No image", file))
  list(kind = "image", file = normalizePath(file), caption = caption)
}

#' Write a report
#'
#' Writes the blocks as `report.html`, one self-contained file with every figure embedded,
#' and `report.md` beside it, in `folder`. Figures from [report_figure()] are drawn into
#' `figures/` in the folder; images from [report_image()] are embedded from where they are.
#'
#' @param blocks A list of blocks from [report_heading()] and the like; `NULL` entries are
#'   dropped, so a block can be left out with `if`.
#' @param folder The folder to write into; made if missing.
#' @param title The page's title.
#' @return The path of `report.html`, invisibly.
#' @seealso [report_blocks]
#' @export
write_report <- function(blocks, folder, title) {
  blocks <- Filter(Negate(is.null), blocks)
  .check(is.list(blocks) && length(blocks) > 0 &&
           all(vapply(blocks, function(b) is.list(b) && !is.null(b$kind), logical(1))),
         "blocks must be a list of report blocks")
  .check(is.character(title) && length(title) == 1, "title must be one string")
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  invisible(.render_report(blocks, folder, title))
}

#' Read a script's HOW TO READ notes
#'
#' pdmS7's scripts put a note beside each plot they draw: a line `# HOW TO READ <file>`, then
#' comment lines saying what the plot shows, what good looks like (`Good:`) and what should
#' worry you (`Worry if:`). `read_plot_notes()` reads them back, so a report can print the
#' same words under the plot, and the script and the report never disagree.
#'
#' @param script Path of the script.
#' @return A named list, one entry per plot file: `text` (the description, one string) and
#'   `points` (the `Good:`, `Worry if:` and like items, each one string).
#' @examples
#' notes <- read_plot_notes(system.file("scripts", "compare_rain.R", package = "pdmS7"))
#' names(notes)
#' @export
read_plot_notes <- function(script) {
  .check(is.character(script) && length(script) == 1 && file.exists(script),
         paste("No script", script))
  code <- readLines(script, warn = FALSE)
  starts <- grep("^\\s*# HOW TO READ ", code)
  notes <- lapply(starts, function(i) {
    j <- i + 1
    while (j <= length(code) && grepl("^\\s*#", code[j]) && !grepl("HOW TO READ", code[j])) {
      j <- j + 1
    }
    lines <- if (j > i + 1) sub("^\\s*# ?", "", code[seq.int(i + 1, j - 1)]) else character(0)
    # A line starting "Good:", "Worry if:" and the like starts a point; the indented lines
    # after it continue it. Lines before the first point are the description.
    text <- character(0)
    points <- character(0)
    for (line in lines) {
      if (grepl("^(Good|Worry if|What it shows|Typical):", line)) {
        points <- c(points, line)
      } else if (length(points)) {
        points[length(points)] <- paste(points[length(points)], trimws(line))
      } else {
        text <- c(text, trimws(line))
      }
    }
    list(text = paste(text, collapse = " "), points = points)
  })
  stats::setNames(notes, sub("^\\s*# HOW TO READ ", "", code[starts]))
}
