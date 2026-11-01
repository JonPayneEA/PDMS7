# ============================================================ #
# Tool:         report_render
# Description:  Renders report blocks to self-contained HTML and to Markdown
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration report
# Tier:         3
# Inputs:       A list of report blocks
# Outputs:      HTML with embedded PNG figures; Markdown with PNG files
# Dependencies: grDevices
# ============================================================ #

# ---- Blocks ------------------------------------------------------------------------------

.blk_h <- function(text, level = 2L) list(kind = "heading", text = text, level = level)
.blk_p <- function(text) list(kind = "paragraph", text = paste(text, collapse = " "))
.blk_list <- function(items) list(kind = "list", items = as.character(items))
.blk_code <- function(text) list(kind = "code", text = paste(text, collapse = "\n"))
.blk_alert <- function(text, ok) list(kind = "alert", text = text, ok = isTRUE(ok))
.blk_table <- function(table, caption = NULL) {
  list(kind = "table", table = as.data.frame(table), caption = caption)
}
.blk_fig <- function(name, draw, caption, width = 9, height = 4.5) {
  list(kind = "figure", name = name, draw = draw, caption = caption, width = width,
       height = height)
}

# ---- Figures -----------------------------------------------------------------------------

.draw_png <- function(file, draw, width, height) {
  type <- if (isTRUE(capabilities("cairo"))) "cairo" else NULL
  args <- list(filename = file, width = width, height = height, units = "in", res = 110)
  if (!is.null(type)) args$type <- type
  do.call(grDevices::png, args)
  on.exit(grDevices::dev.off())
  old <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old), add = TRUE, after = FALSE)
  draw()
  invisible(file)
}

.base64 <- function(bytes) {
  chars <- c(LETTERS, letters, 0:9, "+", "/")
  n <- length(bytes)
  if (!n) return("")
  pad <- (3L - n %% 3L) %% 3L
  m <- matrix(c(as.integer(bytes), integer(pad)), nrow = 3L)
  v <- m[1L, ] * 65536L + m[2L, ] * 256L + m[3L, ]
  idx <- rbind(v %/% 262144L, (v %/% 4096L) %% 64L, (v %/% 64L) %% 64L, v %% 64L)
  out <- chars[idx + 1L]
  if (pad) out[(length(out) - pad + 1L):length(out)] <- "="
  paste(out, collapse = "")
}

# ---- Formatting --------------------------------------------------------------------------

.html_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

.cell_text <- function(x) {
  if (is.numeric(x)) {
    out <- ifelse(is.na(x), "", formatC(x, digits = 4, format = "g", flag = "-"))
    return(trimws(out))
  }
  out <- as.character(x)
  out[is.na(out)] <- ""
  out
}

.md_cell <- function(x) gsub("|", "\\|", gsub("\n", " ", x, fixed = TRUE), fixed = TRUE)

# ---- HTML --------------------------------------------------------------------------------

.report_css <- "
:root { --ink: #1d2730; --muted: #5b6770; --rule: #d7dde2; --head: #236b83;
  --ok: #2f6b2f; --okbg: #e9f3e6; --bad: #a12a2a; --badbg: #f8e6e6; --bg: #ffffff;
  --code: #f4f6f8; }
@media (prefers-color-scheme: dark) { :root { --ink: #e3e8ec; --muted: #9aa7b0;
  --rule: #3a4650; --head: #7cc0d8; --ok: #9fd39a; --okbg: #1f3320; --bad: #f0a0a0;
  --badbg: #3a1f1f; --bg: #12181d; --code: #1c252c; } img { background: #fff; } }
body { font: 15px/1.5 system-ui, -apple-system, 'Segoe UI', sans-serif; color: var(--ink);
  background: var(--bg); max-width: 1000px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 1.7em; margin-bottom: 0.2em; }
h2 { color: var(--head); border-bottom: 1px solid var(--rule); padding-bottom: 4px;
  margin-top: 2em; }
h3 { margin-top: 1.5em; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 0.9em;
  display: block; overflow-x: auto; }
th, td { border-bottom: 1px solid var(--rule); padding: 5px 8px; text-align: left;
  vertical-align: top; }
th { color: var(--muted); font-weight: 600; }
td.num { text-align: right; font-variant-numeric: tabular-nums; }
caption { caption-side: top; text-align: left; color: var(--muted); padding-bottom: 4px; }
figure { margin: 16px 0; } figure img { max-width: 100%; height: auto; }
figcaption { color: var(--muted); font-size: 0.9em; }
pre { background: var(--code); padding: 12px; overflow-x: auto; font-size: 0.85em; }
.alert { padding: 10px 14px; border-radius: 4px; margin: 12px 0; font-weight: 600; }
.ok { background: var(--okbg); color: var(--ok); }
.bad { background: var(--badbg); color: var(--bad); }
@media print { body { max-width: none; } h2 { break-after: avoid; }
  figure { break-inside: avoid; } }
"

.html_table <- function(block) {
  df <- block$table
  if (!nrow(df)) return("<p><em>None.</em></p>")
  numeric <- vapply(df, is.numeric, logical(1))
  head <- paste0("<th>", .html_escape(names(df)), "</th>", collapse = "")
  body <- vapply(seq_len(nrow(df)), function(i) {
    cells <- vapply(seq_along(df), function(j) {
      cls <- if (numeric[[j]]) " class=\"num\"" else ""
      paste0("<td", cls, ">", .html_escape(.cell_text(df[[j]][i])), "</td>")
    }, character(1))
    paste0("<tr>", paste(cells, collapse = ""), "</tr>")
  }, character(1))
  caption <- if (is.null(block$caption)) "" else
    paste0("<caption>", .html_escape(block$caption), "</caption>")
  paste0("<table>", caption, "<thead><tr>", head, "</tr></thead><tbody>",
         paste(body, collapse = "\n"), "</tbody></table>")
}

.html_block <- function(block, figure_dir) {
  switch(block$kind,
    heading = sprintf("<h%d>%s</h%d>", block$level, .html_escape(block$text), block$level),
    paragraph = paste0("<p>", .html_escape(block$text), "</p>"),
    list = paste0("<ul>", paste0("<li>", .html_escape(block$items), "</li>", collapse = ""),
                  "</ul>"),
    code = paste0("<pre><code>", .html_escape(block$text), "</code></pre>"),
    alert = sprintf("<div class=\"alert %s\">%s</div>", if (block$ok) "ok" else "bad",
                    .html_escape(block$text)),
    table = .html_table(block),
    figure = {
      file <- file.path(figure_dir, paste0(block$name, ".png"))
      data <- .base64(readBin(file, "raw", file.info(file)$size))
      caption <- .html_escape(block$caption)
      paste0("<figure><img alt=\"", caption, "\" src=\"data:image/png;base64,", data,
             "\"><figcaption>", caption, "</figcaption></figure>")
    }
  )
}

# ---- Markdown ----------------------------------------------------------------------------

.md_table <- function(block) {
  df <- block$table
  if (!nrow(df)) return("*None.*")
  cells <- lapply(df, function(col) .md_cell(.cell_text(col)))
  rows <- vapply(seq_len(nrow(df)), function(i) {
    paste0("| ", paste(vapply(cells, `[`, character(1), i), collapse = " | "), " |")
  }, character(1))
  caption <- if (is.null(block$caption)) character(0) else paste0("*", block$caption, "*\n")
  paste(c(caption, paste0("| ", paste(names(df), collapse = " | "), " |"),
          paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"), rows),
        collapse = "\n")
}

.md_block <- function(block) {
  switch(block$kind,
    heading = paste(strrep("#", block$level), block$text),
    paragraph = block$text,
    list = paste0("- ", block$items, collapse = "\n"),
    code = paste0("```yaml\n", block$text, "\n```"),
    alert = paste0("> **", block$text, "**"),
    table = .md_table(block),
    figure = sprintf("![%s](figures/%s.png)\n\n*%s*", block$caption, block$name, block$caption)
  )
}

# ---- Writing -----------------------------------------------------------------------------

.render_report <- function(blocks, output, title) {
  figure_dir <- file.path(output, "figures")
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  for (b in Filter(function(x) x$kind == "figure", blocks)) {
    .draw_png(file.path(figure_dir, paste0(b$name, ".png")), b$draw, b$width, b$height)
  }
  html <- c(
    "<!DOCTYPE html>", "<html lang=\"en-GB\">", "<head>", "<meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    paste0("<title>", .html_escape(title), "</title>"),
    paste0("<style>", .report_css, "</style>"), "</head>", "<body>",
    vapply(blocks, .html_block, character(1), figure_dir = figure_dir), "</body>", "</html>"
  )
  md <- paste(vapply(blocks, .md_block, character(1)), collapse = "\n\n")
  html_file <- file.path(output, "report.html")
  writeBin(charToRaw(enc2utf8(paste0(paste(html, collapse = "\n"), "\n"))), html_file)
  writeBin(charToRaw(enc2utf8(paste0(md, "\n"))), file.path(output, "report.md"))
  html_file
}
