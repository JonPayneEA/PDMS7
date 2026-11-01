# ============================================================ #
# Tool:         staged
# Description:  Staged calibration: water balance and slow response, then fast response,
#               then an optional joint polish within narrowed bounds
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add pdm_stages(), calibrate_staged(), log_staged_calibration()
# Tier:         3
# Inputs:       A configuration; forcing (mm per step); observed flow (m3/s)
# Outputs:      The fitted configuration and one calibration result per stage
# Dependencies: stats
# ============================================================ #

#' Calibration stages
#'
#' The stages of a staged calibration, following how a hydrologist calibrates by hand:
#' settle the water balance and the slow response first, then the fast response, then a short
#' joint polish.
#'
#' | Stage | Fits | Objective |
#' |---|---|---|
#' | 1. Volume and baseflow | `fc`, soil store, recharge, groundwater | 1 - log NSE + volume error |
#' | 2. Fast response | Surface stores and the store shape `b` | 1 - NSE |
#' | 3. Polish | Everything, within narrowed bounds | 1 - NSE |
#'
#' Low flows and the total volume depend on the slow stores, and logs stop the floods
#' dominating stage 1. Peak size and timing depend on the fast stores, fitted in stage 2 with
#' stage 1's values fixed. Stage 3 starts from the stage 2 result and searches a band of a
#' quarter of each parameter's range either side, on the search scale, to fix interactions the
#' stages missed without drifting far.
#'
#' Parameters come from [calibration_bounds()], so every structure gets its own lists: a split
#' recharge adds `recharge.alpha` to stage 1, an exponential store adds its two parameters.
#' A stage is a plain list, so you can write your own: `name`, `parameters` (configuration
#' paths), `objective` (as in [calibrate_pdm()]), `volume_weight` and `band` (`NULL`, or the
#' half-width of the narrowed search, as a fraction of each parameter's range).
#'
#' @param config A configuration list.
#' @param overrides,exclude Passed to [calibration_bounds()].
#' @param polish Include stage 3.
#' @param volume_weight Weight of the volume penalty in stage 1.
#' @param band Half-width of the stage 3 search, as a fraction of each range.
#'
#' @return A list of stages.
#' @examples
#' str(pdm_stages(pdm_presets("standard")), max.level = 2)
#' @seealso [calibrate_staged()], [log_staged_calibration()]
#' @export
pdm_stages <- function(config, overrides = NULL, exclude = NULL, polish = TRUE,
                       volume_weight = 1, band = 0.25) {
  paths <- calibration_bounds(config, overrides, exclude)$path
  slow <- paths[paths == "fc" | grepl("^(distribution|recharge|groundwater)\\.", paths)]
  fast <- paths[grepl("^surface\\.", paths) | paths == "distribution.b"]
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
  stages[vapply(stages, function(s) length(s$parameters) > 0, logical(1))]
}

# Bounds for one stage: the full bounds of its parameters, or a band around the current values
# on the search scale when the stage has one.
.stage_bounds <- function(stage, bounds, config) {
  .check(is.list(stage) && is.character(stage$parameters) && length(stage$parameters) > 0,
         "Each stage needs a parameters vector of configuration paths")
  missing <- setdiff(stage$parameters, bounds$path)
  .check(!length(missing), paste("No bounds for", toString(missing)))
  b <- bounds[match(stage$parameters, bounds$path), ]
  lower <- stats::setNames(b$lower, b$path)
  upper <- stats::setNames(b$upper, b$path)
  logged <- b$path[b$scale == "log"]
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
#' @param forcing,observed,warmup,soil_fraction,log_offset Passed to [calibrate_pdm()].
#' @param stages Stages from [pdm_stages()], or your own.
#' @param bounds Bounds table from [calibration_bounds()].
#' @param starts,seed,control,method Passed to [calibrate_pdm()] for every stage.
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
                             method = c("lbfgsb", "nelder_mead"), soil_fraction = 0.5,
                             log_offset = 0.01) {
  method <- match.arg(method)
  .check(is.list(stages) && length(stages) > 0, "stages must be a non-empty list")
  results <- vector("list", length(stages))
  current <- config
  for (i in seq_along(stages)) {
    b <- .stage_bounds(stages[[i]], bounds, current)
    fit <- calibrate_pdm(
      current, forcing, observed, lower = b$lower, upper = b$upper, warmup = warmup,
      objective = stages[[i]]$objective, control = control, soil_fraction = soil_fraction,
      starts = starts, seed = seed, method = method, log_scale = b$log_scale,
      log_offset = log_offset, volume_weight = stages[[i]]$volume_weight %||% 0
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
                                   method = c("lbfgsb", "nelder_mead")) {
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

.log_stage <- function(project, parent, stages, i, bounds, reasoning, starts, seed, control,
                       method) {
  node <- .model_node(.read_entries(.project_path(project)), parent)
  b <- .stage_bounds(stages[[i]], bounds, node$configuration)
  log_auto_calibration(
    project, parent = node$id, lower = b$lower, upper = b$upper,
    objective = stages[[i]]$objective, starts = starts, seed = seed, control = control,
    method = method, log_scale = b$log_scale,
    volume_weight = stages[[i]]$volume_weight %||% 0, stage = .stage_label(i, stages),
    reasoning = paste0(reasoning, " Stage ", .stage_label(i, stages), ".")
  )
}
