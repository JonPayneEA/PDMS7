# ============================================================ #
# Tool:         project_log
# Description:  Calibration log internals: files, identity, locking, checksum chain
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration log
# Tier:         3
# Inputs:       A calibration project folder
# Outputs:      Append-only YAML entries
# Dependencies: yaml; tools (MD5); data.table
# ============================================================ #

.log_format <- 1L
.entry_types <- c(
  "project_start", "data_registered", "structure_selected", "trial", "auto_calibration",
  "note", "candidate", "validation", "test", "sign_off", "reopen"
)
.model_entry_types <- c("structure_selected", "trial", "auto_calibration")
.roles <- c("custodian", "steward", "delegated_steward")

# ---- Numbers -----------------------------------------------------------------------------

# Shortest decimal that reproduces the double exactly, in YAML float syntax.
.yaml_number <- function(x) {
  if (is.na(x)) return(".na.real")
  if (is.infinite(x)) return(if (x > 0) ".inf" else "-.inf")
  text <- NA_character_
  for (digits in 15:17) {
    text <- sprintf(paste0("%.", digits, "g"), x)
    if (as.numeric(text) == x) break
  }
  if (!grepl("[.e]", text)) text <- paste0(text, ".0")
  if (grepl("e", text, fixed = TRUE) && !grepl(".", text, fixed = TRUE)) {
    text <- sub("e", ".0e", text, fixed = TRUE)
  }
  text
}

# Prepares a value for yaml::as.yaml: doubles become exact verbatim text.
.yaml_ready <- function(x) {
  if (is.list(x)) {
    out <- lapply(x, .yaml_ready)
    if (is.data.frame(x)) out <- as.list(out)
    return(out)
  }
  if (is.double(x) && !inherits(x, "POSIXt")) {
    out <- vapply(x, .yaml_number, character(1))
    names(out) <- NULL
    if (!is.null(names(x)) && length(x) > 1) {
      return(stats::setNames(lapply(out, function(v) structure(v, class = "verbatim")),
                             names(x)))
    }
    return(structure(out, class = "verbatim"))
  }
  if (is.factor(x)) return(as.character(x))
  x
}

# ---- Checksums ---------------------------------------------------------------------------

# Line-ending insensitive: entries, CSV data and series are text, and git on Windows may
# convert LF to CRLF on checkout. Carriage returns are removed before hashing.
.md5_file <- function(path) {
  bytes <- readBin(path, "raw", file.info(path)$size)
  if (!any(bytes == as.raw(13L))) return(unname(tools::md5sum(path)))
  temp <- tempfile()
  on.exit(unlink(temp))
  writeBin(bytes[bytes != as.raw(13L)], temp)
  unname(tools::md5sum(temp))
}

.md5_text <- function(text) {
  path <- tempfile()
  on.exit(unlink(path))
  writeBin(charToRaw(enc2utf8(paste(text, collapse = "\n"))), path)
  .md5_file(path)
}

# Rounded to 10 significant figures, so last-digit differences between R versions vanish.
.series_md5 <- function(x) .md5_text(sprintf("%.9e", signif(x, 10)))

# ---- Identity and software ---------------------------------------------------------------

.setting <- function(option, variable) {
  value <- getOption(option)
  if (is.null(value) || !nzchar(value)) value <- Sys.getenv(variable)
  trimws(as.character(value)[1L])
}

.identity <- function(allowed = .roles) {
  name <- .setting("pdmS7.user", "PDMS7_USER")
  role <- tolower(.setting("pdmS7.role", "PDMS7_ROLE"))
  .check(nzchar(name), paste(
    "Declare who you are first: options(pdmS7.user = \"Your Name\", pdmS7.role = \"custodian\")",
    "or the environment variables PDMS7_USER and PDMS7_ROLE"
  ))
  .check(role %in% .roles, paste("Role must be one of", paste(.roles, collapse = ", ")))
  .check(role %in% allowed, paste0(
    "This entry needs the role ", paste(allowed, collapse = " or "), "; you are ", role
  ))
  list(name = name, role = role, login = .login())
}

.login <- function() unname(Sys.info()[["user"]])

.software <- function() {
  list(
    pdmS7 = as.character(utils::packageVersion("pdmS7")),
    r = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform,
    engine = if (.engine_wanted()) "c" else "r"
  )
}

.engine_wanted <- function() !identical(getOption("pdmS7.engine", "auto"), "r")

.timestamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# ---- Project folder ----------------------------------------------------------------------

.marker <- "pdms7-project.yml"

.project_path <- function(project) {
  .check(is.character(project) && length(project) == 1L && !is.na(project),
         "project must be the path of a calibration project folder")
  .check(file.exists(file.path(project, .marker)),
         paste("Not a calibration project (no", .marker, "):", project))
  normalizePath(project, winslash = "/", mustWork = TRUE)
}

.entry_files <- function(path) {
  files <- list.files(file.path(path, "entries"), pattern = "^[0-9]{4}-[a-z_]+\\.yml$")
  sort(files)
}

.read_yaml_file <- function(file) {
  text <- readLines(file, warn = FALSE, encoding = "UTF-8")
  .check(!any(grepl("!expr", text, fixed = TRUE)), paste("Refusing YAML with !expr:", file))
  yaml::yaml.load(paste(text, collapse = "\n"), eval.expr = FALSE)
}

# Reads every entry, oldest first. Each gains .file and .md5 fields.
.read_entries <- function(path) {
  files <- .entry_files(path)
  lapply(files, function(f) {
    full <- file.path(path, "entries", f)
    entry <- .read_yaml_file(full)
    entry$.file <- f
    entry$.md5 <- .md5_file(full)
    entry
  })
}

.find_entry <- function(entries, id) {
  id <- .entry_id(id)
  hit <- Filter(function(e) identical(e$id, id), entries)
  .check(length(hit) == 1L, paste("No entry", id, "in this project"))
  hit[[1L]]
}

.entry_id <- function(id) {
  .check(length(id) == 1L && !is.na(id) && grepl("^[0-9]{1,4}$", as.character(id)),
         "Entry ids are numbers such as 4 or \"0004\"")
  sprintf("%04d", as.integer(id))
}

.latest <- function(entries, types) {
  hits <- Filter(function(e) e$type %in% types, entries)
  if (length(hits)) hits[[length(hits)]] else NULL
}

.project_status <- function(entries) {
  last <- .latest(entries, c("sign_off", "reopen"))
  if (is.null(last)) "open" else if (last$type == "sign_off") "signed_off" else "reopened"
}

# ---- Locking and writing -----------------------------------------------------------------

.with_lock <- function(path, code, wait = 30, stale = 600) {
  lock <- file.path(path, "entries", ".lock")
  waited <- 0
  repeat {
    if (dir.create(lock, showWarnings = FALSE)) break
    age <- as.numeric(difftime(Sys.time(), file.mtime(lock), units = "secs"))
    if (is.finite(age) && age > stale) {
      logger::log_warn("Removing stale calibration-log lock {lock}")
      unlink(lock, recursive = TRUE)
      next
    }
    .check(waited < wait, paste("Another session is writing to this project; try again:", lock))
    Sys.sleep(0.2)
    waited <- waited + 0.2
  }
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  code()
}

# Appends one entry. build(id, entries) returns the type-specific fields; it runs under the
# lock, after the closed-project check, so it sees the entries as they will stand.
.append_entry <- function(path, type, author, build) {
  .with_lock(path, function() {
    entries <- .read_entries(path)
    status <- .project_status(entries)
    .check(type == "reopen" || status != "signed_off",
           "This project is signed off; a Steward must reopen it before anything else is logged")
    id <- sprintf("%04d", length(entries) + 1L)
    last_id <- if (length(entries)) entries[[length(entries)]]$id else "0000"
    .check(identical(last_id, sprintf("%04d", length(entries))),
           "Entry numbering is broken; run verify_project()")
    header <- list(
      format = .log_format, id = id, type = type, timestamp = .timestamp(),
      author = author, software = .software(),
      previous = if (length(entries)) entries[[length(entries)]]$.md5 else "none"
    )
    entry <- c(header, build(id, entries))
    text <- paste0(
      "# pdmS7 calibration log entry. Written once; never edit. verify_project() checks it.\n",
      yaml::as.yaml(.yaml_ready(entry), indent.mapping.sequence = TRUE)
    )
    file <- file.path(path, "entries", paste0(id, "-", type, ".yml"))
    temp <- tempfile(tmpdir = file.path(path, "entries"), fileext = ".tmp")
    writeBin(charToRaw(enc2utf8(text)), temp)
    .check(file.rename(temp, file), paste("Could not write", file))
    logger::log_debug("Logged {type} {id} in {path}")
    entry
  })
}
