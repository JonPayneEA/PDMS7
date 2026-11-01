# ============================================================ #
# Tool:         project_read
# Description:  Calibration log: reading projects and verifying integrity
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration log
# Tier:         3
# Inputs:       Calibration project folders
# Outputs:      data.tables of entries, trials, projects and integrity checks
# Dependencies: data.table; tools (MD5)
# ============================================================ #

.text_or_na <- function(x) if (is.null(x) || !length(x)) NA_character_ else as.character(x)[1L]
.num_or_na <- function(x) if (is.null(x) || !length(x)) NA_real_ else as.numeric(x)[1L]

#' Read a calibration project
#'
#' `read_project()` gives the project details, status and a one-row-per-entry table.
#' `project_trials()` lists every run (structure, trial and automatic calibration) with its
#' parent, changes, scores, verdict and reasoning. `read_entry()` returns one entry in full,
#' for example an automatic calibration's table of starts. `read_projects()` summarises
#' several projects in one table, for example every basin of a large-sample calibration,
#' with the candidate's headline score on the calibration and validation windows.
#'
#' @param project Path of a calibration project folder.
#' @param projects Paths of calibration project folders.
#' @return `read_project()`: a list with `path`, `id`, `status` (`open`, `signed_off` or
#'   `reopened`), `project` (the `project_start` fields), `scorecard` (the latest) and
#'   `entries` (a data.table). `read_entry()`: the entry as a list. `project_trials()` and
#'   `read_projects()`: data.tables.
#' @seealso [calibration_log], [verify_project()]
#' @export
read_project <- function(project) {
  path <- .project_path(project)
  entries <- .read_entries(path)
  info <- .project_info(entries)
  registration <- .latest(entries, "data_registered")
  table <- data.table::data.table(
    id = vapply(entries, function(e) e$id, character(1)),
    type = vapply(entries, function(e) e$type, character(1)),
    timestamp = vapply(entries, function(e) e$timestamp, character(1)),
    author = vapply(entries, function(e) e$author$name, character(1)),
    role = vapply(entries, function(e) e$author$role, character(1)),
    login = vapply(entries, function(e) .text_or_na(e$author$login), character(1)),
    summary = vapply(entries, .entry_summary, character(1))
  )
  list(path = path, id = info$id, status = .project_status(entries), project = info,
       scorecard = registration$scorecard, entries = table)
}

.entry_summary <- function(e) {
  text <- switch(e$type,
    project_start = paste(e$project$catchment, "-", e$project$purpose),
    data_registered = paste(e$summary$rows, "rows"),
    structure_selected = e$reasoning,
    trial = paste0(.changes_text(e$changes), " (", e$verdict, ")"),
    auto_calibration = paste(e$objective, "calibration,", e$starts, "start(s)"),
    note = e$text,
    candidate = paste("Entry", e$entry),
    validation = paste("Candidate", e$candidate),
    sign_off = paste("Candidate", e$candidate, "signed off as", e$capacity),
    reopen = e$reason
  )
  .text_or_na(text)
}

.changes_text <- function(changes) {
  if (!length(changes)) return("")
  paste(vapply(names(changes), function(n) {
    sprintf("%s %s -> %s", n, format(changes[[n]]$from, digits = 6),
            format(changes[[n]]$to, digits = 6))
  }, character(1)), collapse = "; ")
}

#' @rdname read_project
#' @export
project_trials <- function(project) {
  path <- .project_path(project)
  entries <- .read_entries(path)
  nodes <- Filter(function(e) e$type %in% .model_entry_types, entries)
  if (!length(nodes)) return(data.table::data.table())
  rows <- lapply(nodes, function(e) {
    base <- data.table::data.table(
      id = e$id, type = e$type, parent = .text_or_na(e$parent), timestamp = e$timestamp,
      author = e$author$name, changes = .text_or_na(.changes_text(e$changes)),
      verdict = .text_or_na(e$verdict), reasoning = .text_or_na(e$reasoning)
    )
    scores <- data.table::as.data.table(lapply(e$scores, .num_or_na))
    cbind(base, scores)
  })
  data.table::rbindlist(rows, fill = TRUE)
}

.validation_score <- function(entries, candidate, headline) {
  validation <- .latest(entries, "validation")
  if (is.null(candidate) || is.null(validation) || is.na(headline) ||
        !identical(validation$candidate, candidate$id)) {
    return(NA_real_)
  }
  .num_or_na(validation$validation_scores[[headline]])
}

#' @rdname read_project
#' @param id An entry id, such as 4 or "0004".
#' @export
read_entry <- function(project, id) {
  entry <- .find_entry(.read_entries(.project_path(project)), id)
  entry[setdiff(names(entry), c(".file", ".md5"))]
}

#' @rdname read_project
#' @export
read_projects <- function(projects) {
  .check(is.character(projects) && length(projects) > 0, "projects must be folder paths")
  rows <- lapply(projects, function(p) {
    info <- read_project(p)
    entries <- .read_entries(info$path)
    sign_off <- .latest(entries, "sign_off")
    candidate <- .latest(entries, "candidate")
    headline <- if (is.null(info$scorecard)) NA_character_ else info$scorecard$headline
    data.table::data.table(
      project = info$id, catchment = info$project$catchment, gauge = info$project$gauge,
      status = info$status, entries = nrow(info$entries),
      runs = sum(info$entries$type %in% .model_entry_types),
      candidate = .text_or_na(candidate$id), headline = headline,
      candidate_score = if (is.null(candidate) || is.na(headline)) NA_real_ else
        .num_or_na(candidate$scores[[headline]]),
      validation_score = .validation_score(entries, candidate, headline),
      signed_off_by = .text_or_na(sign_off$author$name),
      signed_off_at = .text_or_na(sign_off$timestamp), path = info$path
    )
  })
  data.table::rbindlist(rows, fill = TRUE)
}

#' Verify a calibration project
#'
#' Checks that the log is complete and unaltered and that its evidence still stands:
#'
#' - **numbering**: entries are numbered 1, 2, 3 with no gaps, and each file name matches
#'   its content;
#' - **chain**: each entry holds the MD5 of the one before, so an edit, deletion or
#'   insertion breaks the chain at that point;
#' - **data**: every registered file exists and matches its MD5;
#' - **series**: every saved series file matches its MD5;
#' - **rerun** (optional): every run is repeated and its output compared with the recorded
#'   checksum. A mismatch reports which software has changed since the entry was written.
#'
#' Alteration of the newest entry is caught by the next entry, by sign-off, or by version
#' control; keep projects under version control or on a managed drive.
#'
#' @param project Path of a calibration project folder.
#' @param rerun If `TRUE`, repeat every run. Each takes about as long as one model run.
#' @return A data.table with one row per check: `check`, `entry`, `ok` and `detail`.
#' @seealso [calibration_log], [read_project()]
#' @export
verify_project <- function(project, rerun = FALSE) {
  path <- .project_path(project)
  entries <- .read_entries(path)
  rows <- c(
    .verify_numbering(path, entries), .verify_chain(entries), .verify_data(path, entries),
    .verify_series(path, entries), if (isTRUE(rerun)) .verify_reruns(path, entries)
  )
  data.table::rbindlist(rows)
}

.check_row <- function(check, entry, ok, detail = "") {
  list(data.table::data.table(check = check, entry = entry, ok = isTRUE(ok), detail = detail))
}

.verify_numbering <- function(path, entries) {
  files <- list.files(file.path(path, "entries"), all.files = TRUE, no.. = TRUE)
  stray <- setdiff(files, c(.entry_files(path), ".lock"))
  out <- if (length(stray)) {
    .check_row("numbering", NA_character_, FALSE, paste("Unexpected files:", toString(stray)))
  }
  for (i in seq_along(entries)) {
    e <- entries[[i]]
    expected <- sprintf("%04d", i)
    ok <- identical(e$id, expected) && identical(e$.file, paste0(e$id, "-", e$type, ".yml")) &&
      e$type %in% .entry_types && identical(as.integer(e$format), .log_format)
    out <- c(out, .check_row("numbering", e$.file, ok,
                             if (ok) "" else paste("Expected entry", expected)))
  }
  if (!length(entries)) out <- .check_row("numbering", NA_character_, FALSE, "No entries")
  out
}

.verify_chain <- function(entries) {
  out <- NULL
  previous <- "none"
  for (e in entries) {
    ok <- identical(e$previous, previous)
    out <- c(out, .check_row("chain", e$id, ok,
                             if (ok) "" else "Previous entry altered, removed or inserted"))
    previous <- e$.md5
  }
  out
}

.verify_data <- function(path, entries) {
  out <- NULL
  for (e in Filter(function(x) x$type == "data_registered", entries)) {
    for (name in names(e$data)) {
      item <- e$data[[name]]
      file <- .stored_file(path, item)
      ok <- file.exists(file) && identical(.md5_file(file), item$md5)
      detail <- ""
      if (!file.exists(file)) {
        detail <- paste("Missing:", file)
      } else if (!ok) {
        detail <- paste("Changed since registration:", file)
      }
      out <- c(out, .check_row(paste("data", name), e$id, ok, detail))
    }
  }
  out
}

.verify_series <- function(path, entries) {
  out <- NULL
  for (e in Filter(function(x) !is.null(x$series), entries)) {
    file <- file.path(path, e$series$file)
    ok <- file.exists(file) && identical(.md5_file(file), e$series$md5)
    out <- c(out, .check_row("series", e$id, ok, if (ok) "" else paste("Missing or changed:",
                                                                       e$series$file)))
  }
  out
}

.software_changes <- function(then) {
  now <- .software()
  changed <- names(now)[!vapply(names(now), function(n) identical(then[[n]], now[[n]]),
                                logical(1))]
  if (!length(changed)) return("no software change; data or platform arithmetic differ")
  paste(vapply(changed, function(n) paste0(n, " ", then[[n]], " -> ", now[[n]]), character(1)),
        collapse = ", ")
}

.verify_reruns <- function(path, entries) {
  info <- .project_info(entries)
  out <- NULL
  targets <- Filter(function(e) e$type %in% c(.model_entry_types, "validation"), entries)
  for (e in targets) {
    registration <- .find_entry(entries, e$registration)
    result <- tryCatch({
      if (e$type == "validation") {
        config <- .find_entry(entries, e$candidate)$configuration
        window <- "validation"
      } else {
        config <- e$configuration
        window <- "calibration"
      }
      .run_registered(path, info, registration, config, window)$output_md5
    }, error = function(err) paste("error:", conditionMessage(err)))
    ok <- identical(result, e$output_md5)
    detail <- if (ok) "" else if (startsWith(result, "error:")) result else
      paste("Output differs:", .software_changes(e$software))
    out <- c(out, .check_row("rerun", e$id, ok, detail))
  }
  out
}
