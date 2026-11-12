# ============================================================ #
# Tool:         pdm_inp
# Description:  Reading and writing PDM for PCs model input files (*.inp), so a model calibrated
#               there can be run, scored and compared here, and back
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-12
# Modified:     2026-11-12 - First version, from the PDM for PCs manual (UKCEH, version 3),
#                            Configuration Guide section 2.3 and Appendix A.1
# Tier:         1
# Inputs:       A *.inp text file, or a configuration
# Outputs:      A configuration list, or a *.inp text file
# Dependencies: none beyond the package
# ============================================================ #

#' Read and write PDM for PCs input files
#'
#' `read_pdm_inp()` reads the model of a PDM for PCs `*.inp` file into a configuration, so a
#' model calibrated in PDM for PCs can be run, scored and compared with one calibrated here
#' (see [compare_calibrations()]). `write_pdm_inp()` writes a configuration as a `*.inp` file
#' that PDM for PCs can load (Model > Load Previous PDM Configuration).
#'
#' **What is read.** The parameter list (by name, so its order does not matter), the model
#' structure line (`loss runoff surface base tdly`), the catchment area, the groundwater
#' extension block (`'GW'`) with its well datum, and, as attributes, the title, the stations,
#' the event periods and which parameters were marked for optimisation (`indx = 1`). Error
#' prediction, forecast and rating settings are not part of the simulation model; they are
#' noted in attribute `notes` and otherwise ignored, as are raingauge weights: give the
#' catchment rainfall in the forcing.
#'
#' **Conventions of PDM for PCs.** These follow the manual and are applied in both directions:
#' - the cubic store's `kb` in the file is the cube root of the time constant used (`kb` = 13
#'   in the file is 2197 h mm^2 here);
#' - `k2 = 0` means two equal surface reservoirs, `k2 = k1`;
#' - `tdly` in the structure line is either the delay in hours or, when negative, the position
#'   of the `tdly` parameter in the list;
#' - `rainfac` is the rainfall factor `fc`, `qconst` the constant flow `qc` (m3/s);
#' - lognormal (`loss` 5) reads `cmin` and `b` as the mean and standard deviation of log
#'   capacity, and exponential (`loss` 6) reads `cmin` as the mean capacity;
#' - the cubic store is stepped by Smith's method, as in PDM for PCs.
#'
#' **The time step is not in the file.** PDM for PCs takes it from the model set-up, so give
#' it as `dt` (15 minutes by default).
#'
#' **Not supported**, and refused with a message rather than guessed: several hydrological
#' zones; demand recharge and the unrestricted split (runoff models 2 to 4); the power
#' distribution (`loss` 4); exponential stores; a cubic surface store; and constant or
#' pass-through stores (types 0 and -1).
#'
#' @param path Path of the `*.inp` file.
#' @param dt Model time step, hours.
#' @return `read_pdm_inp()`: a configuration list for [pdm_from_config()], with attributes
#'   `title`, `stations`, `events` (a data frame of `start` and `end`), `optimised` (the file's
#'   names of the parameters marked for optimisation), `theta` (the initial soil fraction of a
#'   split model, if given) and `notes`. `write_pdm_inp()`: the path, invisibly.
#' @references UKCEH (2022). PDM for PCs, version 3.0.3: Configuration Guide, section 2.3 and
#'   Appendix A.1.
#' @examples
#' cfg <- pdm_presets("standard")
#' cfg$area_km2 <- 36.7
#' cfg$dt <- 0.25
#' path <- tempfile(fileext = ".inp")
#' write_pdm_inp(cfg, path, title = "Example Brook: standard PDM",
#'               event = c("2010-10-01 09:00", "2020-10-01 09:00"))
#' back <- read_pdm_inp(path, dt = 0.25)
#' back$groundwater
#' @export
read_pdm_inp <- function(path, dt = 0.25) {
  .check(is.character(path) && length(path) == 1L && file.exists(path),
         "path must name an existing *.inp file")
  .check(.scalar(dt, 0, strict = TRUE), "dt must be a positive number of hours")
  lines <- readLines(path, warn = FALSE)
  .check(length(lines) > 5, "This does not look like a PDM input file: too few lines")
  params <- .inp_parameters(lines)
  structure_line <- .inp_after(lines, "^\\s*loss\\s+runoff\\s+surface\\s+base", "model structure")
  codes <- suppressWarnings(as.numeric(.inp_tokens(structure_line)))
  .check(length(codes) >= 5 && all(is.finite(codes[1:5])),
         "The model structure line needs loss, runoff, surface, base and tdly")
  area <- as.numeric(.inp_tokens(.inp_after(lines, "Catchment area", "catchment area"))[1])
  .check(is.finite(area) && area > 0, "The catchment area must be a positive number")
  gw <- .inp_groundwater(lines)
  value <- function(name, default = NULL) {
    hit <- params$key == tolower(name)
    if (any(hit)) return(params$value[hit][1])
    .check(!is.null(default), paste0("The parameter list has no '", name, "'"))
    default
  }
  td <- if (codes[5] < 0) {
    i <- -codes[5]
    .check(i <= nrow(params), "tdly in the structure line points past the parameter list")
    params$value[i]
  } else {
    codes[5]
  }
  config <- list(
    distribution = .inp_distribution(codes[1], value),
    recharge = .inp_recharge(codes[2], value),
    surface = .inp_surface(codes[3], value),
    groundwater = .inp_groundwater_store(codes[4], value),
    be = value("be"), fc = value("rainfac"), td = td, qc = value("qconst", 0),
    area_km2 = area, dt = dt
  )
  if (!is.null(gw)) {
    .check(codes[4] %in% c(1, 2, 3), paste(
      "The groundwater extension needs a linear, quadratic or cubic baseflow store"
    ))
    config$groundwater$extension <- list(
      ku = value("ku"), dbu = value("dbu"), alpha_b = value("springfrac"),
      ca = value("abstcon"), fa = value("abstfac"), smax_b = value("gsmax"),
      ys = value("wellfac"), hw = gw$welldatum
    )
  }
  pdm_from_config(config)
  notes <- .inp_notes(lines, codes)
  structure(config, title = trimws(lines[1]), stations = .inp_stations(lines),
            events = .inp_events(lines), optimised = params$name[params$indx == 1],
            theta = if (codes[2] == 1) value("theta", NA_real_), notes = notes)
}

#' @rdname read_pdm_inp
#' @param config A configuration list, or a `FlodePdmModel`.
#' @param title First line of the file: the model or catchment name.
#' @param event Start and end of the calibration event (period), as two times (`POSIXct`, or
#'   text such as `"2010-10-01 09:00"`, in UTC). PDM for PCs needs at least one.
#' @param stations Named character vector of the series names PDM for PCs will ask for:
#'   `flow`, `rain`, `pet` and `daily_rain`.
#' @param optimised Names, as in the file (`rainfac`, `cmax`, `kb` and so on), of the
#'   parameters to mark for optimisation; none by default.
#' @export
write_pdm_inp <- function(config, path, title, event,
                          stations = c(flow = "FLOW", rain = "RAIN", pet = "SIN CURVE",
                                       daily_rain = "NULL"),
                          optimised = character(0)) {
  model <- if (S7::S7_inherits(config, FlodePdmModel) || .is_multizone(config)) config else
    pdm_from_config(config)
  .check(!.is_multizone(model),
         "A multi-zone model cannot be written to a PDM input file yet: write each zone")
  .check(is.character(title) && length(title) == 1L && nzchar(title), "title must be text")
  .check(length(event) == 2L, "event must be a start and an end")
  .check(is.character(stations) && all(c("flow", "rain", "pet", "daily_rain") %in%
                                         names(stations)),
         "stations must name flow, rain, pet and daily_rain")
  # The structure first: it refuses what a PDM input file cannot hold, before any parameter is
  # read.
  codes <- .inp_codes(model)
  rows <- .inp_rows(model)
  .check(all(optimised %in% rows$name),
         paste("optimised names parameters not in the file:",
               toString(setdiff(optimised, rows$name))))
  rows$indx <- as.integer(rows$name %in% optimised)
  num <- function(x) format(signif(x, 10), scientific = FALSE, trim = TRUE, drop0trailing = TRUE)
  par_lines <- sprintf("  %d  %14s  %10s  %8s  '%s'", rows$indx, vapply(rows$value, num, ""),
                       num(0.1), num(0.05), rows$name)
  ext <- if (S7::S7_inherits(model@groundwater, FlodeExtendedGroundwater)) model@groundwater
  gw_lines <- if (!is.null(ext)) {
    c("groundwater module", "'GW' /",
      "groundwater_type (0=well_level [AOD]; 1= Dip), obj fun type (1=flow, 2 = well level)",
      sprintf("0 1 %s /", num(ext@hw)), "numabs abstn1 abtsn2", "1 'ABS' /", "gwstn",
      "'WELL'/")
  }
  q <- function(x) paste0("'", x, "'")
  times <- vapply(.parse_time(event), .inp_time, "")
  text <- c(
    title, "objtyp maxfun konvge objtol", "  11  9999  4  8.",
    "analys qmin qmax pkmin pkrge", "  2  0.  1000.0  30.  -1",
    "prtfnf prtopt common file name of plot files (<= 64 chars)", "  0  3  'USER_EVPLOT'",
    "indx  xs  smpstp  smptol  xs name (<= 8 chars)", par_lines, "/",
    "PROBABILITY DISTRIBUTED LOSS MODEL", gw_lines,
    "Flow  Rainfall  Climate-station  Daily Rain",
    paste(q(stations[["flow"]]), q(stations[["rain"]]), q(stations[["pet"]]),
          q(stations[["daily_rain"]]), "/"),
    "loss runoff surface base tdly",
    sprintf("  %d  %d  %d  %d  %d /", codes[1], codes[2], codes[3], codes[4],
            -match("tdly", rows$name)),
    "Catchment area (km**2)", num(model@area_km2),
    "Event begin  Event end  noi End 15' Rain", paste(q(times[1]), q(times[2]), "/"), "/",
    "error parameters: 0(SIM) /, or 1(UPD) upd miter gaintyp, or 2(ARMA) p q", "0 /",
    "forecast mode: 0 = no forecast, 1 = fixed origin, 2 = fixed lead-time", "0 /",
    "forecast times ( 1 read-statement per event)", "/", "prtflg", " 0"
  )
  writeLines(text, path)
  invisible(path)
}

# ---- Reading ----------------------------------------------------------------------------------

# The tokens of one line, quoted strings kept whole, up to a "/" that ends the record.
.inp_tokens <- function(line) {
  tokens <- scan(text = line, what = "", quiet = TRUE, quote = "'", sep = "")
  end <- match("/", tokens)
  if (!is.na(end)) tokens <- tokens[seq_len(end - 1L)]
  sub("/$", "", tokens)
}

# The line after the first line matching a header.
.inp_after <- function(lines, header, what) {
  i <- grep(header, lines, ignore.case = TRUE)[1]
  .check(!is.na(i) && i < length(lines), paste("The file has no", what, "line"))
  lines[i + 1L]
}

# The parameter list: one row per line between the "indx xs ..." header and "/", with the
# file's name and a lower-case key (the part of a name such as "kg/qsat" before the slash).
.inp_parameters <- function(lines) {
  h <- grep("^\\s*indx\\s+xs", lines, ignore.case = TRUE)[1]
  .check(!is.na(h), "The file has no parameter list (the line starting indx xs)")
  rows <- list()
  for (line in lines[-seq_len(h)]) {
    if (grepl("^\\s*/", line)) break
    t <- .inp_tokens(line)
    if (length(t) < 5) next
    rows[[length(rows) + 1L]] <- data.frame(indx = as.integer(t[1]), value = as.numeric(t[2]),
                                            name = t[5])
  }
  .check(length(rows) > 0, "The parameter list is empty")
  out <- do.call(rbind, rows)
  out$key <- tolower(sub("/.*$", "", out$name))
  .check(all(is.finite(out$value)), "Every parameter value must be a number")
  .check(!anyDuplicated(out$key), paste(
    "The parameter list repeats", toString(unique(out$key[duplicated(out$key)])),
    "- a model of several hydrological zones, which is not supported yet"
  ))
  out
}

# The groundwater extension block after the loss-model line: NULL without 'GW', else the well
# datum from its values line.
.inp_groundwater <- function(lines) {
  start <- grep("PROBABILITY DISTRIBUTED LOSS MODEL", lines, fixed = TRUE)[1]
  if (is.na(start)) return(NULL)
  rest <- lines[-seq_len(start)]
  g <- which(vapply(rest, function(l) identical(.inp_tokens(l)[1], "GW"), logical(1)))[1]
  if (is.na(g)) return(NULL)
  values <- suppressWarnings(as.numeric(.inp_tokens(rest[g + 2L])))
  .check(length(values) >= 3 && is.finite(values[3]),
         "The groundwater block needs groundwater type, objective type and well datum")
  list(welldatum = values[3])
}

# Series names: the line after the "Flow  Rainfall ..." header.
.inp_stations <- function(lines) {
  i <- grep("^\\s*Flow.*Rainfall", lines, ignore.case = TRUE)[1]
  if (is.na(i)) return(NULL)
  t <- .inp_tokens(lines[i + 1L])
  stats::setNames(t[seq_len(min(4, length(t)))],
                  c("flow", "rain", "pet", "daily_rain")[seq_len(min(4, length(t)))])
}

# Event periods: the quoted pairs after the "Event begin" header, until a line of "/".
.inp_events <- function(lines) {
  i <- grep("^\\s*Event begin", lines, ignore.case = TRUE)[1]
  if (is.na(i)) return(NULL)
  out <- list()
  for (line in lines[-seq_len(i)]) {
    if (grepl("^\\s*/", line)) break
    t <- .inp_tokens(line)
    if (length(t) >= 1) {
      out[[length(out) + 1L]] <- data.frame(start = t[1], end = if (length(t) > 1) t[2] else t[1])
    }
  }
  if (length(out)) do.call(rbind, out)
}

# What the file sets that a simulation here does not use.
.inp_notes <- function(lines, codes) {
  notes <- character(0)
  if (length(codes) >= 6 && is.finite(codes[6]) && codes[6] > 0) {
    notes <- c(notes, "A rating converts levels to flows in PDM for PCs; give flows here")
  }
  e <- grep("^\\s*error parameters", lines, ignore.case = TRUE)[1]
  if (!is.na(e) && !identical(.inp_tokens(lines[e + 1L])[1], "0")) {
    notes <- c(notes, "Error prediction or state updating is set; the simulation model is read")
  }
  if (any(grepl("MULTIPLE", lines, fixed = TRUE))) {
    notes <- c(notes, "Several raingauges are weighted in PDM for PCs; give catchment rainfall")
  }
  notes
}

.inp_distribution <- function(code, value) {
  switch(as.character(code),
    "1" = list(type = "pareto", cmin = value("cmin"), cmax = value("cmax"), b = value("b")),
    "2" = list(type = "rectangular", cmin = value("cmin"), cmax = value("cmax")),
    "3" = list(type = "triangular", cmin = value("cmin"), cmax = value("cmax")),
    "5" = list(type = "lognormal", meanlog = value("cmin"), sdlog = value("b")),
    "6" = list(type = "exponential", mean = value("cmin")),
    stop("Loss model ", code, " is not supported (the power distribution, 4, has no ",
         "equivalent here)", call. = FALSE)
  )
}

.inp_recharge <- function(code, value) {
  switch(as.character(code),
    "0" = list(type = "standard", kg = value("kg"), bg = value("bg"), st = value("st")),
    "1" = list(type = "split",
               alpha = .first_known(value("alpha", NA_real_), function() value("alpha_r"))),
    stop("Runoff model ", code, " is not supported yet (2: unrestricted split; 3 and 4: ",
         "demand recharge)", call. = FALSE)
  )
}

.inp_surface <- function(code, value) {
  k1 <- value("k1")
  switch(as.character(code),
    "22" = list(type = "cascade", k1 = k1, k2 = if (value("k2", 0) == 0) k1 else value("k2")),
    "1" = list(type = "linear", kb = k1),
    "2" = list(type = "quadratic", kb = k1),
    stop("Surface model ", code, " is not supported (linear 1, quadratic 2 and the cascade ",
         "22 are)", call. = FALSE)
  )
}

.inp_groundwater_store <- function(code, value) {
  kb <- value("kb")
  switch(as.character(code),
    "1" = list(type = "linear", kb = kb),
    "2" = list(type = "quadratic", kb = kb),
    "3" = list(type = "cubic", kb = kb^3, solver = "smith"),
    "22" = list(type = "cascade", k1 = kb, k2 = kb),
    stop("Baseflow model ", code, " is not supported (linear 1, quadratic 2, cubic 3 and the ",
         "cascade 22 are)", call. = FALSE)
  )
}

# x unless it is NA, else the value of fallback(), called only then.
.first_known <- function(x, fallback) if (length(x) && !is.na(x)) x else fallback()

# ---- Writing ----------------------------------------------------------------------------------

# The parameter list of a model in the order of the PDM for PCs input file: the standard 12,
# theta and alpha for a split, the seven extension parameters, then tdly.
.inp_rows <- function(model) {
  d <- model@distribution
  dist <- switch(class(d)[1L],
    "pdmS7::FlodeParetoCapacity" = c(cmin = d@cmin, cmax = d@cmax, b = d@b),
    "pdmS7::FlodeRectangularCapacity" = c(cmin = d@cmin, cmax = d@cmax, b = 1),
    "pdmS7::FlodeTriangularCapacity" = c(cmin = d@cmin, cmax = d@cmax, b = 1),
    "pdmS7::FlodeLognormalCapacity" = c(cmin = d@meanlog, cmax = 0, b = d@sdlog),
    "pdmS7::FlodeExponentialCapacity" = c(cmin = d@mean, cmax = 0, b = 1),
    stop("This distribution cannot be written to a PDM input file", call. = FALSE)
  )
  r <- model@recharge
  standard <- S7::S7_inherits(r, FlodeStandardRecharge)
  split <- S7::S7_inherits(r, FlodeSplitRecharge)
  .check(standard || split, "Only standard and split recharge can be written to a PDM input file")
  s <- model@surface
  k <- if (S7::S7_inherits(s, FlodeCascadeRouting)) c(s@k1, s@k2) else c(1 / s@k, 0)
  g <- model@groundwater
  store <- if (S7::S7_inherits(g, FlodeExtendedGroundwater)) g@store else g
  kb <- if (S7::S7_inherits(store, FlodeCascadeRouting)) {
    store@k1
  } else if (store@m == 3) {
    (1 / store@k)^(1 / 3)
  } else {
    1 / store@k
  }
  values <- c(rainfac = model@fc, dist, be = model@be, k1 = k[1], k2 = k[2], kb = kb,
              kg = if (standard) r@kg else 0, St = if (standard) r@st else 0,
              bg = if (standard) r@bg else 0, qconst = model@qc)
  if (split) values <- c(values, theta = 0.7, alpha = r@alpha)
  if (S7::S7_inherits(g, FlodeExtendedGroundwater)) {
    values <- c(values, ku = g@ku, Dbu = g@dbu, springfrac = g@alpha_b, abstcon = g@ca,
                abstfac = g@fa, Gsmax = g@smax_b, wellfac = g@ys)
  }
  values <- c(values, tdly = model@td)
  data.frame(name = names(values), value = unname(values))
}

# The structure codes loss, runoff, surface and base of a model.
.inp_codes <- function(model) {
  loss <- c("pdmS7::FlodeParetoCapacity" = 1, "pdmS7::FlodeRectangularCapacity" = 2,
            "pdmS7::FlodeTriangularCapacity" = 3, "pdmS7::FlodeLognormalCapacity" = 5,
            "pdmS7::FlodeExponentialCapacity" = 6)[[class(model@distribution)[1L]]]
  runoff <- if (S7::S7_inherits(model@recharge, FlodeSplitRecharge)) 1L else 0L
  # A surface cascade may have unequal stores, a baseflow cascade not; only the baseflow store
  # may be cubic.
  route <- function(x, surface) {
    if (S7::S7_inherits(x, FlodeCascadeRouting)) {
      .check(surface || x@k1 == x@k2,
             "A cascade baseflow store needs equal time constants in a PDM input file")
      return(22L)
    }
    .check(S7::S7_inherits(x, FlodePowerRouting) && x@m %in% c(1, 2, if (!surface) 3),
           "Only linear, quadratic, cubic (baseflow) and cascade stores can be written")
    as.integer(x@m)
  }
  g <- model@groundwater
  store <- if (S7::S7_inherits(g, FlodeExtendedGroundwater)) g@store else g
  c(as.integer(loss), runoff, route(model@surface, TRUE), route(store, FALSE))
}

# A time as PDM for PCs writes it, such as "09:00 30 Mar 1991".
.inp_time <- function(t) {
  lt <- as.POSIXlt(t, tz = "UTC")
  sprintf("%02d:%02d %d %s %d", lt$hour, lt$min, lt$mday, month.abb[lt$mon + 1L],
          lt$year + 1900L)
}
