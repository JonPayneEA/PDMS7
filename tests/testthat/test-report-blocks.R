# ============================================================ #
# Tool:         test-report-blocks
# Description:  The report blocks write one self-contained HTML page (text escaped, figures and
#               images embedded) and Markdown beside it; read_plot_notes() reads a script's
#               HOW TO READ notes back as text and points
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-26
# Tier:         1
# Inputs:       Blocks and a small script written to a temporary folder
# Outputs:      None
# Dependencies: testthat
# ============================================================ #

test_that("write_report() writes every block, escaped, with figures and images embedded", {
  folder <- tempfile("report")
  png_file <- tempfile(fileext = ".png")
  grDevices::png(png_file, width = 200, height = 200)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  grDevices::dev.off()
  blocks <- list(
    report_heading("A <title>", 1),
    report_text("Two", "words."),
    report_list(c("first", "second")),
    report_table(data.frame(series = c("a", "b"), ratio = c(0.5, 0.25)), caption = "Ratios"),
    report_alert("All well", TRUE),
    report_alert("Check this", FALSE),
    NULL,
    report_figure("drawn", function() plot(1:3), "A drawn figure", width = 3, height = 2),
    report_image(png_file, "An image on disk")
  )
  file <- write_report(blocks, folder, "A report")
  html <- paste(readLines(file), collapse = "\n")
  # The heading's markup is escaped, so it shows as text and cannot break the page.
  expect_match(html, "<h1>A &lt;title&gt;</h1>", fixed = TRUE)
  expect_match(html, "<p>Two words.</p>", fixed = TRUE)
  expect_match(html, "<li>first</li><li>second</li>", fixed = TRUE)
  expect_match(html, "<caption>Ratios</caption>", fixed = TRUE)
  expect_match(html, "<td class=\"num\">0.25</td>", fixed = TRUE)
  expect_match(html, "alert ok\">All well", fixed = TRUE)
  expect_match(html, "alert bad\">Check this", fixed = TRUE)
  # Two images, both embedded: the drawn figure and the one already on disk.
  expect_identical(lengths(regmatches(html, gregexpr("data:image/png;base64,", html))), 2L)
  expect_true(file.exists(file.path(folder, "figures", "drawn.png")))
  md <- readLines(file.path(folder, "report.md"))
  expect_true(any(md == "| series | ratio |"))
  expect_true(any(grepl(sprintf("](%s)", basename(png_file)), md, fixed = TRUE)))
})

test_that("write_report() makes no figures folder when nothing is drawn, and checks blocks", {
  folder <- tempfile("report")
  write_report(list(report_text("Only text.")), folder, "Text")
  expect_false(dir.exists(file.path(folder, "figures")))
  expect_error(write_report(list(), folder, "Empty"), "list of report blocks")
  expect_error(report_image(file.path(tempdir(), "none.png"), "Missing"), "No image")
  expect_error(report_figure("a b", function() NULL, "Bad name"), "file name")
})

test_that("read_plot_notes() reads each note's description and its points", {
  script <- tempfile(fileext = ".R")
  writeLines(c("x <- 1",
               "# HOW TO READ one.png",
               "# What the plot shows,",
               "# over two lines.",
               "# Good: lines together.",
               "# Worry if: a line apart",
               "#   from the rest.",
               "png('one.png')",
               "  # HOW TO READ two.png",
               "  # Only a description.",
               "y <- 2"), script)
  notes <- read_plot_notes(script)
  expect_identical(names(notes), c("one.png", "two.png"))
  expect_identical(notes[["one.png"]]$text, "What the plot shows, over two lines.")
  # The indented line continues the point before it.
  expect_identical(notes[["one.png"]]$points,
                   c("Good: lines together.", "Worry if: a line apart from the rest."))
  expect_identical(notes[["two.png"]]$points, character(0))
  # The rain comparison's own notes: one for each plot it can draw.
  shipped <- read_plot_notes(system.file("scripts", "compare_rain.R", package = "pdmS7"))
  expect_true("largest_floods_cumulative.png" %in% names(shipped))
})
