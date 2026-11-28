# ============================================================ #
# Tool:         coarse
# Description:  A record collapsed to a coarser time step, for calibration stages whose
#               parameters do not depend on the timing within the coarse step
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-18
# Modified:     2026-11-18 - First version
# Tier:         1
# Inputs:       Forcing (mm per step) and observed flow (m3/s) on the model's time step
# Outputs:      The same on a coarser step, with the configuration and warm-up to match
# Dependencies: stats
# ============================================================ #

# A record in blocks of `factor` steps: rain, evaporation and abstraction (mm per step) summed
# over each block, observed flow (m3/s) averaged, and missing where any step of the block is
# missing, so a gap is never filled; times are the block's first. Steps left over after the last
# whole block are dropped.
.coarsen <- function(forcing, observed, factor) {
  known <- c("time", "rain", "pet", "abstraction")
  extra <- setdiff(names(forcing), known)
  .check(!length(extra), paste0(
    "A coarse stage can only sum rain, pet and abstraction; the forcing also has ",
    toString(extra)
  ))
  n <- (nrow(forcing) %/% factor) * factor
  .check(n >= 2L * factor, "The record is too short for the coarse step")
  first <- seq.int(1L, n, by = factor)
  block_sum <- function(x) colSums(matrix(x[seq_len(n)], nrow = factor))
  out <- data.frame(row.names = seq_along(first))
  if ("time" %in% names(forcing)) out$time <- forcing$time[first]
  for (col in intersect(c("rain", "pet", "abstraction"), names(forcing))) {
    out[[col]] <- block_sum(forcing[[col]])
  }
  list(forcing = out, observed = colMeans(matrix(observed[seq_len(n)], nrow = factor)))
}

# Forcing, observed flow, warm-up and configuration on the coarse step `coarse_dt` (hours). The
# model's own step must divide it a whole number of times; a coarse step equal to the model's
# changes nothing.
.coarse_inputs <- function(config, forcing, observed, warmup, coarse_dt) {
  dt <- config$dt %||% 1
  .check(.scalar(coarse_dt, 0, strict = TRUE), "coarse_dt must be a positive number of hours")
  factor <- coarse_dt / dt
  .check(abs(factor - round(factor)) < 1e-9 && round(factor) >= 1,
         "coarse_dt must be a whole number of the model's time steps")
  factor <- as.integer(round(factor))
  if (factor == 1L) {
    return(list(config = config, forcing = forcing, observed = observed, warmup = warmup,
                factor = 1L))
  }
  c2 <- .coarsen(as.data.frame(forcing), observed, factor)
  config$dt <- coarse_dt
  list(config = config, forcing = c2$forcing, observed = c2$observed,
       warmup = as.integer(ceiling(warmup / factor)), factor = factor)
}

# The mask and the peak band on the coarse step: a coarse step is scored only if every fine step
# in it is, and its band is the mean of theirs. The record is cut to whole coarse steps, as
# .coarsen() cuts it.
.coarse_mask <- function(mask, factor, n) {
  if (is.null(mask) || factor == 1L) return(mask)
  apply(matrix(mask[seq_len(n * factor)], nrow = factor), 2, all)
}
.coarse_band <- function(band, factor, n) {
  if (is.null(band) || factor == 1L) return(band)
  rows <- seq_len(n * factor)
  data.frame(lower = colMeans(matrix(band$lower[rows], nrow = factor)),
             upper = colMeans(matrix(band$upper[rows], nrow = factor)))
}
