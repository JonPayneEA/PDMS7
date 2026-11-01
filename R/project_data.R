# ============================================================ #
# Tool:         project_data
# Description:  Calibration log: registered data, scoring windows and model runs
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add the calibration log
# Tier:         3
# Inputs:       Forcing (rain, pet mm per interval; optional time) and flow (m3/s)
# Outputs:      Checked data, simulated flow and scorecards
# Dependencies: data.table; tools (MD5)
# ============================================================ #

# Accepts ISO 8601 date-times (T or space separated, optional seconds and Z) or dates, in UTC.
.parse_time <- function(x) {
  if (inherits(x, "POSIXt")) return(as.POSIXct(x, tz = "UTC"))
  text <- sub("Z$", "", sub("T", " ", trimws(as.character(x)), fixed = TRUE))
  formats <- c(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?$" = "%Y-%m-%d %H:%M:%OS",
    "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$" = "%Y-%m-%d %H:%M",
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" = "%Y-%m-%d"
  )
  out <- rep(as.POSIXct(NA, tz = "UTC"), length(text))
  for (pattern in names(formats)) {
    hit <- grepl(pattern, text)
    out[hit] <- as.POSIXct(text[hit], format = formats[[pattern]], tz = "UTC")
  }
  .check(all(is.finite(as.numeric(out))),
         "times must be ISO 8601 in UTC, such as 2020-01-31 or 2020-01-31T09:00:00Z")
  out
}

.format_time <- function(x) format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# Reads forcing from a path or data frame into a data.table with rain, pet, optional time.
.as_forcing <- function(forcing) {
  if (is.character(forcing)) {
    .check(length(forcing) == 1L && file.exists(forcing), "forcing file not found")
    forcing <- data.table::fread(forcing, colClasses = list(character = "time"))
  }
  .check(is.data.frame(forcing) && all(c("rain", "pet") %in% names(forcing)),
         "forcing needs rain and pet columns, mm per interval")
  out <- data.table::data.table(rain = as.numeric(forcing$rain), pet = as.numeric(forcing$pet))
  .nonnegative(out$rain, "rain")
  .nonnegative(out$pet, "pet")
  if ("time" %in% names(forcing)) {
    data.table::set(out, j = "time", value = .parse_time(forcing$time))
  }
  out
}

# Observed flow from a path, data frame (q_m3s column, or a single column) or vector.
.as_observed <- function(observed) {
  if (is.character(observed)) {
    .check(length(observed) == 1L && file.exists(observed), "observed file not found")
    observed <- data.table::fread(observed)
  }
  if (is.data.frame(observed)) {
    column <- if ("q_m3s" %in% names(observed)) "q_m3s" else setdiff(names(observed), "time")
    .check(length(column) == 1L, "observed needs a q_m3s column")
    observed <- observed[[column]]
  }
  .check(is.numeric(observed), "observed flow must be numeric, m3/s")
  q <- as.numeric(observed)
  .check(all(q[is.finite(q)] >= 0), "observed flow must be nonnegative")
  q
}

.longest_gap <- function(missing) {
  if (!any(missing)) return(0L)
  runs <- rle(missing)
  as.integer(max(runs$lengths[runs$values]))
}

.data_summary <- function(forcing, observed) {
  out <- list(rows = nrow(forcing))
  if ("time" %in% names(forcing)) {
    out$start <- .format_time(forcing$time[1L])
    out$end <- .format_time(forcing$time[nrow(forcing)])
    if (nrow(forcing) > 1L) {
      steps <- as.numeric(diff(forcing$time), units = "hours")
      .check(all(abs(steps - steps[1L]) < 1e-8), "time steps must be regular")
      out$step_hours <- steps[1L]
    }
  }
  missing <- !is.finite(observed)
  c(out, list(
    rain_total_mm = sum(forcing$rain), pet_total_mm = sum(forcing$pet),
    observed_missing = sum(missing), observed_longest_gap = .longest_gap(missing),
    observed_mean_m3s = mean(observed[!missing]), observed_max_m3s = max(observed[!missing])
  ))
}

# A window is c(start, end) as row numbers, or as times when the forcing has a time column.
.resolve_window <- function(window, forcing, name) {
  if (is.null(window)) return(NULL)
  .check(length(window) == 2L, paste(name, "must be c(start, end)"))
  if (is.numeric(window)) {
    rows <- as.integer(window)
    .check(all(rows == window), paste(name, "rows must be whole numbers"))
  } else {
    .check("time" %in% names(forcing), paste(name, "given as times but forcing has no time"))
    bounds <- .parse_time(window)
    rows <- c(which(forcing$time >= bounds[1L])[1L],
              utils::tail(which(forcing$time <= bounds[2L]), 1L))
  }
  .check(all(!is.na(rows)) && rows[1L] >= 1L && rows[2L] <= nrow(forcing) && rows[1L] < rows[2L],
         paste(name, "lies outside the data or is empty"))
  out <- list(first_row = rows[1L], last_row = rows[2L])
  if ("time" %in% names(forcing)) {
    out$start <- .format_time(forcing$time[rows[1L]])
    out$end <- .format_time(forcing$time[rows[2L]])
  }
  out
}

.window_rows <- function(window) seq.int(window$first_row, window$last_row)

# Stores a series: copies a file, writes a data frame, or references a path.
.store_series <- function(source, value, path, id, name, copy, writer) {
  folder <- file.path("data", id)
  if (is.character(source) && !copy) {
    stored <- normalizePath(source, winslash = "/", mustWork = TRUE)
    return(list(source = stored, stored = stored, copied = FALSE, md5 = .md5_file(stored)))
  }
  dir.create(file.path(path, folder), showWarnings = FALSE, recursive = TRUE)
  relative <- file.path(folder, paste0(name, ".csv"))
  target <- file.path(path, relative)
  if (is.character(source)) {
    .check(file.copy(source, target, overwrite = FALSE), paste("Could not copy", source))
    from <- normalizePath(source, winslash = "/")
  } else {
    writer(value, target)
    from <- "R session"
  }
  list(source = from, stored = relative, copied = TRUE, md5 = .md5_file(target))
}

.write_forcing <- function(forcing, target) {
  out <- data.table::copy(forcing)
  if ("time" %in% names(out)) data.table::set(out, j = "time", value = .format_time(out$time))
  data.table::fwrite(out, target)
}

.write_observed <- function(q, target) data.table::fwrite(data.table::data.table(q_m3s = q), target)

.stored_file <- function(path, item) {
  if (isTRUE(item$copied)) file.path(path, item$stored) else item$stored
}

# Loads a registration's data after checking every file against its MD5.
.load_registration <- function(path, registration) {
  files <- registration$data
  for (name in c("forcing", "observed")) {
    file <- .stored_file(path, files[[name]])
    .check(file.exists(file), paste("Registered", name, "file is missing:", file))
    .check(identical(.md5_file(file), files[[name]]$md5),
           paste("Registered", name, "file has changed since registration:", file))
  }
  forcing <- .as_forcing(.stored_file(path, files$forcing))
  observed <- .as_observed(.stored_file(path, files$observed))
  list(forcing = forcing, observed = observed)
}

# Runs a configuration over the whole registered record and scores the requested window.
.run_registered <- function(path, project, registration, config, window = "calibration",
                            data = NULL) {
  if (is.null(data)) data <- .load_registration(path, registration)
  model <- pdm_from_config(config)
  .check(abs(model@area_km2 - project$area_km2) < 1e-9 * project$area_km2, paste(
    "Configuration area_km2", model@area_km2, "differs from the project's", project$area_km2
  ))
  card <- registration$scorecard
  state <- initial_state(model, card$soil_fraction)
  sim <- .quietly(run_pdm(model, data$forcing, state))$output$q_m3s
  rows <- .window_rows(card[[window]])
  list(
    simulated = sim, observed = data$observed, rows = rows,
    time = if ("time" %in% names(data$forcing)) data$forcing$time else NULL,
    scores = as.list(pdm_scorecard(sim[rows], data$observed[rows], card$log_offset)),
    output_md5 = .series_md5(sim)
  )
}

# Keeps the full series for decision entries.
.save_series <- function(path, id, run) {
  dir.create(file.path(path, "series"), showWarnings = FALSE)
  relative <- file.path("series", paste0(id, ".csv"))
  out <- data.table::data.table(observed_m3s = run$observed, simulated_m3s = run$simulated)
  if (!is.null(run$time)) out <- cbind(data.table::data.table(time = .format_time(run$time)), out)
  data.table::fwrite(out, file.path(path, relative))
  list(file = relative, md5 = .md5_file(file.path(path, relative)))
}
