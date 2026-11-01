# ============================================================ #
# Tool:         run_log
# Description:  Opt-in log of model runs, with approval against signed-off calibrations
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the run log and approval register
# Tier:         3
# Inputs:       options(pdmS7.run_log, pdmS7.register) or PDMS7_RUN_LOG, PDMS7_REGISTER
# Outputs:      One CSV row per run_pdm() call
# Dependencies: data.table; yaml; tools (MD5)
# ============================================================ #

.run_log_state <- new.env(parent = emptyenv())
.run_log_state$suppress <- 0L
.run_log_state$register <- NULL
.run_log_state$warned <- FALSE

# Runs expr without logging model runs: calibration evaluations, spin-up cycles and the
# calibration log's own reruns are not operational runs.
.quietly <- function(expr) {
  .run_log_state$suppress <- .run_log_state$suppress + 1L
  on.exit(.run_log_state$suppress <- .run_log_state$suppress - 1L)
  force(expr)
}

.run_log_path <- function() {
  path <- .setting("pdmS7.run_log", "PDMS7_RUN_LOG")
  if (is.na(path) || !nzchar(path)) NULL else path
}

.run_log_active <- function() .run_log_state$suppress == 0L && !is.null(.run_log_path())

# ---- Fingerprints ------------------------------------------------------------------------

.canonical <- function(x) {
  if (inherits(x, "S7_object")) {
    props <- S7::props(x)
    return(c(list(class = sub("^pdmS7::", "", class(x)[1L])), lapply(props, .canonical)))
  }
  if (is.numeric(x)) return(as.numeric(x))
  x
}

#' Fingerprint a model configuration
#'
#' An MD5 checksum of every component, parameter, area and time step of a model. Two models
#' share a fingerprint exactly when they would produce the same simulation, however they
#' were built: from a configuration list, a YAML file, a preset or code. The run log and the
#' approval register use it to recognise a signed-off parameter set.
#'
#' @param x A `FlodePdmModel` or a configuration list accepted by [pdm_from_config()].
#' @return A 32-character MD5 string.
#' @examples
#' pdm_fingerprint(pdm_presets("standard"))
#' identical(pdm_fingerprint(pdm_presets("standard")),
#'           pdm_fingerprint(pdm_from_config(pdm_presets("standard"))))
#' @export
pdm_fingerprint <- function(x) {
  .check(S7::S7_inherits(x, FlodePdmModel) || is.list(x),
         "x must be a model or a configuration list")
  model <- if (is.list(x)) pdm_from_config(x) else x
  .md5_text(yaml::as.yaml(.yaml_ready(.canonical(model))))
}

.data_md5 <- function(forcing) {
  values <- c(as.numeric(forcing$rain), as.numeric(forcing$pet))
  if ("time" %in% names(forcing)) values <- c(values, as.numeric(forcing$time))
  path <- tempfile()
  on.exit(unlink(path))
  writeBin(values, path, endian = "little")
  .md5_file(path)
}

# ---- Approval register -------------------------------------------------------------------

.register_projects <- function(register) {
  if (length(register) == 1L && grepl("\\.ya?ml$", register, ignore.case = TRUE)) {
    .check(file.exists(register), paste("Register file not found:", register))
    listed <- unlist(.read_yaml_file(register)$projects)
    .check(is.character(listed), "The register needs a 'projects:' list of folders")
    base <- dirname(normalizePath(register, winslash = "/"))
    relative <- !grepl("^(/|[A-Za-z]:|\\\\\\\\)", listed)
    listed[relative] <- file.path(base, listed[relative])
    return(listed)
  }
  register
}

#' List the configurations approved in a register
#'
#' A register names the calibration projects whose signed-off configurations count as
#' approved: either a YAML file with a `projects:` list of folders (relative to the file),
#' or a character vector of folders. Every sign-off in those projects is listed with its
#' fingerprint. A sign-off is `current` when it is the project's latest decision, and
#' `superseded` when the project was later reopened or signed off again.
#'
#' Set `options(pdmS7.register = "path/to/register.yml")` or the environment variable
#' `PDMS7_REGISTER`, and the run log marks every run as `approved`, `superseded` or
#' `unapproved`. Runs are never blocked.
#'
#' @param register Path of a register YAML file, or project folders. Defaults to the
#'   `pdmS7.register` option or `PDMS7_REGISTER`.
#' @return A data.table: `project`, `path`, `entry`, `fingerprint`, `status`,
#'   `signed_off_by`, `signed_off_at`. Unreadable projects are listed with status
#'   `unreadable`.
#' @seealso [pdm_fingerprint()], [read_run_log()], [calibration_log]
#' @export
approved_configurations <- function(register = .setting("pdmS7.register", "PDMS7_REGISTER")) {
  .check(is.character(register) && length(register) > 0 && all(nzchar(register)),
         "Name a register file or project folders")
  rows <- lapply(.register_projects(register), function(folder) {
    tryCatch(.project_approvals(folder), error = function(e) {
      data.table::data.table(project = NA_character_, path = folder, entry = NA_character_,
                             fingerprint = NA_character_, status = "unreadable",
                             signed_off_by = NA_character_,
                             signed_off_at = conditionMessage(e))
    })
  })
  out <- data.table::rbindlist(rows, fill = TRUE)
  if (!nrow(out)) {
    out <- data.table::data.table(project = character(), path = character(), entry = character(),
                                  fingerprint = character(), status = character(),
                                  signed_off_by = character(), signed_off_at = character())
  }
  out
}

.project_approvals <- function(folder) {
  path <- .project_path(folder)
  entries <- .read_entries(path)
  info <- .project_info(entries)
  decisions <- Filter(function(e) e$type %in% c("sign_off", "reopen"), entries)
  signoffs <- Filter(function(e) e$type == "sign_off", decisions)
  last <- if (length(decisions)) decisions[[length(decisions)]]$id else NA_character_
  approval_row <- function(e) {
    data.table::data.table(
      project = info$id, path = path, entry = e$id,
      fingerprint = pdm_fingerprint(e$configuration),
      status = if (identical(e$id, last)) "current" else "superseded",
      signed_off_by = e$author$name, signed_off_at = e$timestamp
    )
  }
  data.table::rbindlist(lapply(signoffs, approval_row))
}

# Cached for a minute so that loops of runs do not reread every project.
.cached_approvals <- function(register) {
  cache <- .run_log_state$register
  now <- Sys.time()
  fresh <- !is.null(cache) && identical(cache$key, register) &&
    as.numeric(difftime(now, cache$time, units = "secs")) < 60
  if (fresh) {
    return(cache$table)
  }
  table <- approved_configurations(register)
  .run_log_state$register <- list(key = register, time = now, table = table)
  table
}

.approval <- function(fingerprint) {
  register <- .setting("pdmS7.register", "PDMS7_REGISTER")
  if (is.na(register) || !nzchar(register)) {
    return(list(approval = NA_character_, project = NA_character_, sign_off = NA_character_))
  }
  # A plain data frame: inside data.table's [ the names below would mean columns.
  table <- as.data.frame(.cached_approvals(register))
  hits <- table[!is.na(table$fingerprint) & table$fingerprint == fingerprint, , drop = FALSE]
  if (!nrow(hits)) {
    return(list(approval = "unapproved", project = NA_character_, sign_off = NA_character_))
  }
  current <- hits[hits$status == "current", , drop = FALSE]
  hit <- if (nrow(current)) current[1L, ] else hits[1L, ]
  list(approval = if (hit$status == "current") "approved" else "superseded",
       project = hit$project, sign_off = hit$entry)
}

# ---- Writing -----------------------------------------------------------------------------

.time_text <- function(forcing, i) {
  if ("time" %in% names(forcing) && nrow(forcing)) .format_time(forcing$time[i]) else NA_character_
}

.run_record <- function(model, forcing, seconds, error) {
  fingerprint <- tryCatch(pdm_fingerprint(model), error = function(e) NA_character_)
  approval <- .approval(fingerprint)
  user <- .setting("pdmS7.user", "PDMS7_USER")
  n <- if (is.data.frame(forcing)) nrow(forcing) else NA_integer_
  data.table::data.table(
    timestamp = .timestamp(), user = if (nzchar(user)) user else NA_character_,
    login = .login(), tag = .text_or_na(getOption("pdmS7.run_tag")),
    fingerprint = fingerprint,
    data_md5 = tryCatch(.data_md5(forcing), error = function(e) NA_character_),
    rows = n, start = .time_text(forcing, 1L), end = .time_text(forcing, n),
    dt_hours = tryCatch(model@dt, error = function(e) NA_real_),
    area_km2 = tryCatch(model@area_km2, error = function(e) NA_real_),
    engine = if (.engine_wanted()) "c" else "r",
    pdmS7 = as.character(utils::packageVersion("pdmS7")),
    r = paste(R.version$major, R.version$minor, sep = "."),
    seconds = round(seconds, 3), status = if (is.null(error)) "ok" else "error",
    message = if (is.null(error)) NA_character_ else conditionMessage(error),
    approval = approval$approval, project = approval$project, sign_off = approval$sign_off
  )
}

.write_run <- function(record) .append_csv(.run_log_path(), record, "Run log")

# Appends rows to a CSV shared by several sessions, under a lock beside it.
.append_csv <- function(path, record, label = "File") {
  folder <- dirname(path)
  .check(dir.exists(folder) || suppressWarnings(dir.create(folder, recursive = TRUE)),
         paste("Cannot create the folder", folder))
  lock <- paste0(path, ".lock")
  waited <- 0
  while (!dir.create(lock, showWarnings = FALSE)) {
    age <- as.numeric(difftime(Sys.time(), file.mtime(lock), units = "secs"))
    if (is.finite(age) && age > 60) {
      unlink(lock, recursive = TRUE)
      next
    }
    .check(waited < 10, paste(label, "is locked:", lock))
    Sys.sleep(0.05)
    waited <- waited + 0.05
  }
  on.exit(unlink(lock, recursive = TRUE))
  data.table::fwrite(record, path, append = file.exists(path))
}

# Logging must never break a run: failures warn once per session and are otherwise ignored.
.log_run <- function(model, forcing, started, error = NULL) {
  tryCatch(
    .write_run(.run_record(model, forcing, proc.time()[["elapsed"]] - started, error)),
    error = function(e) {
      if (!.run_log_state$warned) {
        warning("pdmS7 run log not written: ", conditionMessage(e), call. = FALSE)
        .run_log_state$warned <- TRUE
      }
    }
  )
}

#' Read the run log
#'
#' With `options(pdmS7.run_log = "path/to/runs.csv")` or the environment variable
#' `PDMS7_RUN_LOG` set, every call of [run_pdm()], and so [sim_pdm()] and
#' [sim_snow_pdm()], appends one row to that CSV file: when, who (declared name and login),
#' an optional `tag` from `options(pdmS7.run_tag = )`, the model's [pdm_fingerprint()], a
#' checksum of the forcing, the period, engine and versions, run time, and whether the run
#' succeeded, with the error message if not. With a register set (see
#' [approved_configurations()]), `approval` is `approved`, `superseded` or `unapproved`, with
#' the project and sign-off entry matched. Without one it is empty.
#'
#' Calibration evaluations, spin-up cycles and the calibration log's own reruns are not
#' logged. Logging is off unless the option or variable is set, and a logging failure warns
#' once without stopping the run. A lock serialises writers, so a team can share one file.
#'
#' @param path Path of the run log.
#' @return A data.table, one row per run; `timestamp`, `start` and `end` are UTC date-times.
#' @examples
#' log <- tempfile(fileext = ".csv")
#' old <- options(pdmS7.run_log = log, pdmS7.run_tag = "example")
#' run_pdm(pdm_model(), data.frame(rain = c(0, 5, 0), pet = 0.1))
#' options(old)
#' read_run_log(log)
#' @export
read_run_log <- function(path = .run_log_path()) {
  .check(is.character(path) && length(path) == 1L && file.exists(path),
         "No run log found; set options(pdmS7.run_log = ) or pass its path")
  text <- c("fingerprint", "data_md5", "message", "project", "sign_off", "tag")
  data.table::fread(path, colClasses = list(character = text))
}
