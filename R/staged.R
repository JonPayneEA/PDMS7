# ============================================================ #
# Tool:         staged
# Description:  Staged calibration: water balance and slow response, then fast response,
#               then an optional joint polish over the full bounds
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-05 - The polish searches the full bounds by default
#               2026-11-10 - Progress: each logged stage says when it begins
# Tier:         1
# Inputs:       A configuration; forcing (mm per step); observed flow (m3/s)
# Outputs:      The fitted configuration and one calibration result per stage
# Dependencies: stats
# ============================================================ #

#' Calibration stages
#'
#' The stages of a staged calibration, following how a hydrologist calibrates by hand:
#' settle the water balance and the slow response first, then the fast response, then a short
#' joint polish over everything.
#'
#' | Stage | Fits | Objective |
#' |---|---|---|
#' | 1. Volume and baseflow | Soil, recharge, groundwater; `fc` if unlocked | 1 - log NSE + volume |
#' | 2. Fast response | Surface stores and the store shape `b` | 1 - NSE |
#' | 3. Polish | Everything, over the full bounds | 1 - NSE |
#' | 4. Events (optional) | Surface stores, `b` and the time delay `td` | events objective |
#'
#' Low flows and the total volume depend on the slow stores, and logs stop the floods
#' dominating stage 1. Peak size and timing depend on the fast stores, fitted in stage 2 with
#' stage 1's values fixed. Stage 3 starts from the stage 2 result and searches every parameter
#' over its full bounds, to fix interactions the stages missed.
#'
#' The polish must be free to move far. Stage 1 fits with the surface stores at their starting
#' values; where the true stores are much slower, stage 1 compensates with the wrong slow
#' stores, and a polish confined near that point cannot leave it. In a sample of 30 synthetic
#' catchments, a polish confined to a quarter of each range either side (the default before
#' version 0.8.0) left two catchments far below the score of their true parameters. Pass
#' `band` to confine it all the same.
#'
#' NSE over a long record weighs time steps, not events: the many hours of recession outweigh
#' the few hours around each flood peak, so a model can score well while its peaks are late and
#' low. `events = TRUE` adds stage 4, which refits the fast response and the time delay on the
#' largest events alone, with the `events` objective of [calibrate_pdm()]: pooled event NSE,
#' peak error and timing error. The slow stores stay as stage 3 left them, so the water balance
#' is kept. The time delay is not in the default bounds; stage 4 searches it from 0 to `td_max`
#' hours. Its timing term changes in steps, so stage 4 uses DDS with `event_budget` model runs
#' per start.
#'
#' `thresholds` adds a threshold term ([calibrate_pdm()]) to the last stage, which then also uses
#' DDS: a named vector of flows (m3/s) for [calibrate_staged()], or the names of thresholds
#' registered in the project for [log_staged_calibration()].
#'
#' Parameters come from [calibration_bounds()], so every structure gets its own lists: a split
#' recharge adds `recharge.alpha` to stage 1, an exponential store adds its two parameters.
#' A stage is a plain list, so you can write your own: `name`, `parameters` (configuration
#' paths), `objective` (as in [calibrate_pdm()]), `volume_weight` and `band` (`NULL`, or the
#' half-width of the narrowed search, as a fraction of each parameter's range). Optional
#' fields: `method` and `control`, replacing the calibration's own for this stage;
#' `event_weights` and `event_share` for the events objective; `thresholds`,
#' `threshold_weight` and `threshold_score`; and `extra_bounds`, rows like those of
#' [calibration_bounds()] for parameters not in the bounds table, such as `td`.
#'
#' @param config A configuration list.
#' @param overrides,exclude Passed to [calibration_bounds()].
#' @param polish Include stage 3.
#' @param volume_weight Weight of the volume penalty in stage 1.
#' @param band `NULL` (the default) for a stage 3 search over the full bounds, or the
#'   half-width of a narrowed search, as a fraction of each range.
#' @param events Add stage 4, the events stage.
#' @param event_weights,event_share,event_screen Passed to [calibrate_pdm()] in stage 4.
#' @param td_max Largest time delay searched in stage 4, hours; `NULL` holds `td` fixed.
#' @param event_budget Model runs per start for the DDS searches of stage 4 and of a last stage
#'   with thresholds.
#' @param thresholds,threshold_weight,threshold_score A threshold term for the last stage.
#'
#' @return A list of stages.
#' @examples
#' str(pdm_stages(pdm_presets("standard")), max.level = 2)
#' @seealso [calibrate_staged()], [log_staged_calibration()]
#' @export
pdm_stages <- function(config, overrides = NULL, exclude = NULL, polish = TRUE,
                       volume_weight = 1, band = NULL, events = FALSE,
                       event_weights = c(nse = 1, peak = 0.5, timing = 0.5), event_share = 0.5,
                       event_screen = list(),
                       td_max = 6, event_budget = 300L, thresholds = NULL, threshold_weight = 1,
                       threshold_score = "csi") {
  # Sort the structure's parameters by the part of the hydrograph they control. The store shape b
  # appears in both stages: it affects the water balance and how sharply runoff responds.
  paths <- calibration_bounds(config, overrides, exclude)$path
  # In a multi-zone model, each zone's parameters sort by their path within the zone; a fast
  # zone's share and delay go with the fast response.
  bare <- sub("^zones\\.[^.]+\\.", "", paths)
  slow <- paths[bare == "fc" | grepl("^(distribution|recharge|groundwater)\\.", bare)]
  fast <- paths[grepl("^surface\\.", bare) | bare == "distribution.b" |
                  grepl("^zones\\.[^.]+\\.(share|td)$", paths)]
  td_path <- if (.is_multizone_config(config)) paste0("zones.", names(config$zones)[1], ".td") else
    "td"
  stages <- list(
    list(name = "volume and baseflow", parameters = slow, objective = "log_nse",
         volume_weight = volume_weight, band = NULL),
    list(name = "fast response", parameters = fast, objective = "nse", volume_weight = 0,
         band = NULL)
  )
  if (polish) {
    stages[[3]] <- list(name = "polish", parameters = paths, objective = "nse",
                        volume_weight = 0, band = band)
  }
  if (events) {
    stages[[length(stages) + 1L]] <- .events_stage(fast, paths, exclude, td_max, event_budget,
                                                   event_weights, event_share, event_screen,
                                                   td_path)
  }
  # A structure may leave a stage with nothing to fit (everything excluded); drop it.
  stages <- stages[vapply(stages, function(s) length(s$parameters) > 0, logical(1))]
  .with_thresholds(stages, thresholds, threshold_weight, threshold_score, event_budget)
}

# Stage 4: the fast response and, unless it is excluded or td_max is NULL, the time delay, fitted
# by DDS on the largest events.
.events_stage <- function(fast, paths, exclude, td_max, budget, weights, share, screen,
                          td_path = "td") {
  .check(is.null(td_max) || .scalar(td_max, 0, strict = TRUE),
         "td_max must be a positive number of hours, or NULL")
  # The delay searched: the model's, or in a multi-zone model the first zone's.
  timing <- if (!is.null(td_max) && !td_path %in% paths && !td_path %in% exclude &&
                  !sub("^zones\\.[^.]+\\.", "", td_path) %in% exclude) td_path
  list(
    name = "events", parameters = c(fast, timing), objective = "events", volume_weight = 0,
    band = NULL, method = "dds", control = list(maxit = budget),
    event_weights = weights, event_share = share, event_screen = screen,
    extra_bounds = if (!is.null(timing)) {
      data.frame(path = timing, lower = 0, upper = td_max, scale = "linear",
                 note = "Time delay (h), searched by the events stage")
    }
  )
}

# A threshold term on the last stage, which then searches with DDS if it used L-BFGS-B, since
# threshold scores change in steps.
.with_thresholds <- function(stages, thresholds, weight, score, budget) {
  if (is.null(thresholds)) return(stages)
  .check((is.numeric(thresholds) || is.character(thresholds)) && length(thresholds) > 0,
         "thresholds must be named flows, or names of registered thresholds")
  last <- length(stages)
  stages[[last]]$thresholds <- thresholds
  stages[[last]]$threshold_weight <- weight
  stages[[last]]$threshold_score <- score
  if ((stages[[last]]$method %||% "lbfgsb") == "lbfgsb") {
    stages[[last]]$method <- "dds"
    stages[[last]]$control <- list(maxit = budget)
  }
  stages
}

# Bounds for one stage: the full bounds of its parameters, or a band around the current values
# on the search scale when the stage has one.
.stage_bounds <- function(stage, bounds, config) {
  .check(is.list(stage) && is.character(stage$parameters) && length(stage$parameters) > 0,
         "Each stage needs a parameters vector of configuration paths")
  if (!is.null(stage$extra_bounds)) {
    extra <- stage$extra_bounds[!stage$extra_bounds$path %in% bounds$path, ]
    bounds <- rbind(bounds[, c("path", "lower", "upper", "scale")],
                    extra[, c("path", "lower", "upper", "scale")])
  }
  missing <- setdiff(stage$parameters, bounds$path)
  .check(!length(missing), paste0(
    "No bounds for ", toString(missing), ". A parameter locked by default, such as fc, needs ",
    "bounds from calibration_bounds(config, overrides = list(fc = c(0.8, 1.2)))"
  ))
  b <- bounds[match(stage$parameters, bounds$path), ]
  lower <- stats::setNames(b$lower, b$path)
  upper <- stats::setNames(b$upper, b$path)
  logged <- b$path[b$scale == "log"]
  # Narrowing: map the current value onto [0, 1] across its bounds (in logs for log-scaled
  # parameters), take band either side, clip to [0, 1] and map back. The current value is always
  # kept inside, even if rounding puts it a hair outside the band.
  if (!is.null(stage$band)) {
    .check(.scalar(stage$band, 0, 0.5, strict = TRUE), "band must lie in (0, 0.5]")
    value <- vapply(b$path, function(p) .path_get(config, p), numeric(1))
    is_log <- b$path %in% logged
    tr <- function(x) ifelse(is_log, log(x), x)
    back <- function(x) ifelse(is_log, exp(x), x)
    lo <- tr(lower)
    width <- tr(upper) - lo
    z <- (tr(value) - lo) / width
    new_lo <- back(lo + pmax(0, z - stage$band) * width)
    new_hi <- back(lo + pmin(1, z + stage$band) * width)
    lower <- stats::setNames(pmin(new_lo, value), b$path)
    upper <- stats::setNames(pmax(new_hi, value), b$path)
  }
  list(lower = lower, upper = upper, log_scale = logged)
}

# The label recorded with a logged stage, such as "2 of 3: fast response". A resumed batch finds
# finished stages by this label.
.stage_label <- function(i, stages) {
  paste0(i, " of ", length(stages), ": ", stages[[i]]$name)
}

#' Staged calibration
#'
#' Calibrates in stages, each fitting some parameters with the others fixed at the values the
#' stage before left them: by default the water balance and slow response, then the fast
#' response, then a short joint polish. See [pdm_stages()] for the stages and how to change
#' them.
#'
#' `calibrate_staged()` works on data in memory. `log_staged_calibration()` does the same inside
#' a calibration project, writing one `auto_calibration` entry per stage, each the parent of
#' the next, with its stage recorded, so a reviewer can see what each stage changed.
#'
#' @param config A configuration list, the starting point.
#' @param forcing,observed,warmup,soil_fraction,log_offset,start,baseflow_fraction Passed to
#'   [calibrate_pdm()]: how the data are scored and how every trial starts.
#' @param stages Stages from [pdm_stages()], or your own.
#' @param bounds Bounds table from [calibration_bounds()].
#' @param starts,seed,control,method,cores Passed to [calibrate_pdm()] for every stage.
#'
#' @return `calibrate_staged()`: a list with `config`, `model`, `parameters` (every calibrated
#'   value), and `stages`, one [calibrate_pdm()] result per stage with its `label`.
#'   `log_staged_calibration()`: the stage entries, invisibly.
#' @examples
#' set.seed(2)
#' n <- 24 * 20
#' forcing <- data.frame(rain = ifelse(runif(n) < 0.08, rgamma(n, 0.7, scale = 4), 0),
#'                       pet = 0.05)
#' config <- pdm_presets("standard")
#' truth <- config
#' truth$fc <- 1.2
#' truth$surface$k1 <- 4
#' observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s
#' fit <- calibrate_staged(config, forcing, observed, warmup = 48,
#'                         control = list(maxit = 20))
#' round(fit$parameters, 2)
#' @seealso [pdm_stages()], [calibrate_pdm()], [calibrate_batch()]
#' @export
calibrate_staged <- function(config, forcing, observed, stages = pdm_stages(config),
                             bounds = calibration_bounds(config), warmup = 0, starts = 1L,
                             seed = NULL, control = list(maxit = 200),
                             method = c("lbfgsb", "nelder_mead", "dds"), soil_fraction = 0.5,
                             log_offset = 0.01, start = c("flow", "soil"),
                             baseflow_fraction = 0.7, cores = getOption("pdmS7.cores", 1L)) {
  method <- match.arg(method)
  start <- match.arg(start)
  .check(is.list(stages) && length(stages) > 0, "stages must be a non-empty list")
  results <- vector("list", length(stages))
  current <- config
  # Each stage starts from the configuration the previous stage left.
  for (i in seq_along(stages)) {
    stage <- stages[[i]]
    b <- .stage_bounds(stage, bounds, current)
    .check(is.null(stage$thresholds) || is.numeric(stage$thresholds), paste(
      "Threshold names refer to a project's registered thresholds; calibrate_staged() needs",
      "named flows"
    ))
    fit <- calibrate_pdm(
      current, forcing, observed, lower = b$lower, upper = b$upper, warmup = warmup,
      objective = stage$objective, control = stage$control %||% control,
      soil_fraction = soil_fraction, starts = starts, seed = seed,
      method = stage$method %||% method, log_scale = b$log_scale, log_offset = log_offset,
      volume_weight = stage$volume_weight %||% 0, start = start,
      baseflow_fraction = baseflow_fraction, thresholds = stage$thresholds,
      threshold_weight = stage$threshold_weight %||% 1,
      threshold_score = stage$threshold_score %||% "csi",
      event_weights = stage$event_weights %||% .default_event_weights,
      event_share = stage$event_share %||% 0.5,
      event_screen = if ("event_screen" %in% names(stage)) stage$event_screen else list(),
      cores = cores
    )
    fit$label <- .stage_label(i, stages)
    results[[i]] <- fit
    current <- fit$config
  }
  paths <- unique(unlist(lapply(stages, function(s) s$parameters)))
  list(
    config = current, model = pdm_from_config(current),
    parameters = vapply(paths, function(p) .path_get(current, p), numeric(1)),
    stages = results
  )
}

#' @rdname calibrate_staged
#' @param project A calibration project folder.
#' @param parent Id of the entry to start from, usually the structure.
#' @param reasoning Free text recorded with every stage.
#' @export
log_staged_calibration <- function(project, parent, reasoning, stages = NULL, bounds = NULL,
                                   starts = 1L, seed = NULL, control = list(maxit = 200),
                                   method = c("lbfgsb", "nelder_mead", "dds")) {
  method <- match.arg(method)
  entries <- .read_entries(.project_path(project))
  node <- .model_node(entries, parent)
  stages <- stages %||% pdm_stages(node$configuration)
  bounds <- bounds %||% calibration_bounds(node$configuration)
  written <- list()
  for (i in seq_along(stages)) {
    node <- .log_stage(project, node$id, stages, i, bounds, reasoning, starts, seed, control,
                       method)
    written[[i]] <- node
  }
  invisible(written)
}

# Runs stage i as one automatic calibration entry in a project, starting from the parent entry's
# configuration. Shared by log_staged_calibration() and the batch's resumable staged step.
.log_stage <- function(project, parent, stages, i, bounds, reasoning, starts, seed, control,
                       method) {
  node <- .model_node(.read_entries(.project_path(project)), parent)
  stage <- stages[[i]]
  b <- .stage_bounds(stage, bounds, node$configuration)
  label <- paste("Stage", .stage_label(i, stages))
  old <- options(pdmS7.progress_label = label)
  on.exit(options(old), add = TRUE)
  .progress_say(sprintf("begun, searching %d parameters", length(b$lower)))
  .check(is.null(stage$thresholds) || is.character(stage$thresholds), paste(
    "In a project, thresholds are named by the thresholds registered with the data"
  ))
  log_auto_calibration(
    project, parent = node$id, lower = b$lower, upper = b$upper,
    objective = stage$objective, starts = starts, seed = seed,
    control = stage$control %||% control, method = stage$method %||% method,
    log_scale = b$log_scale, volume_weight = stage$volume_weight %||% 0,
    threshold_objective = stage$thresholds, threshold_weight = stage$threshold_weight %||% 1,
    threshold_score = stage$threshold_score %||% "csi",
    event_weights = stage$event_weights %||% .default_event_weights,
    event_share = stage$event_share %||% 0.5,
    event_screen = if ("event_screen" %in% names(stage)) stage$event_screen else list(),
    stage = .stage_label(i, stages),
    reasoning = paste0(reasoning, " Stage ", .stage_label(i, stages), ".")
  )
}
