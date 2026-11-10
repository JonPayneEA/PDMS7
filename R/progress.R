# ============================================================ #
# Tool:         progress
# Description:  Progress messages for long calibrations: what is running, how far it has got
#               and how long it is taking, from the main session and from worker processes
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-10
# Modified:     2026-11-10 - First version
# Tier:         3
# Inputs:       Options pdmS7.progress_every, pdmS7.progress_label, pdmS7.progress_file
# Outputs:      INFO log lines, or lines appended to a progress file from worker processes
# Dependencies: logger
# ============================================================ #

# One progress line. In the main session it goes to the log at INFO level, as the package's
# other messages do. Worker processes have no console the user can see, so there it is appended
# to the progress file the main session named, with the time, for the user to open.
.progress_say <- function(text) {
  label <- getOption("pdmS7.progress_label")
  line <- if (is.null(label)) text else paste0(label, ": ", text)
  file <- getOption("pdmS7.progress_file")
  if (is.null(file)) {
    logger::log_info("{line}")
  } else {
    try(cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", line, "\n", file = file,
            append = TRUE, sep = ""), silent = TRUE)
  }
  invisible(line)
}

# Runs code with a progress label, so its messages say which part of the work they belong to.
.with_progress_label <- function(label, code) {
  old <- options(pdmS7.progress_label = label)
  on.exit(options(old), add = TRUE)
  code
}

# Seconds since a time.
.seconds_since <- function(t) as.numeric(difftime(Sys.time(), t, units = "secs"))

# A duration for people: seconds under 90 s, minutes under 90 min, then hours.
.duration_text <- function(seconds) {
  if (!is.finite(seconds)) return("unknown")
  if (seconds < 90) return(sprintf("%.0f s", seconds))
  if (seconds < 5400) return(sprintf("%.0f min", seconds / 60))
  sprintf("%.1f h", seconds / 3600)
}

# The heartbeat of one calibration: start() at each start of the search, tick() at each model
# run. Every pdmS7.progress_every seconds (60 by default; 0 turns it off) it says how many model
# runs the current start has made, out of how many when the method has a fixed budget, and how
# long a run takes, so a long search shows it is alive and roughly how far it has to go.
.heartbeat <- function(n_starts, budget = NULL) {
  every <- getOption("pdmS7.progress_every", 60)
  h <- new.env(parent = emptyenv())
  h$t0 <- h$last <- h$t_start <- Sys.time()
  h$start <- 0L
  h$calls <- 0L
  since <- .seconds_since
  list(
    start = function(i) {
      h$start <- i
      h$calls <- 0L
      h$t_start <- Sys.time()
      # A new start is worth a line only once the search has run long enough to be watched.
      if (every > 0 && i > 1L && since(h$t0) >= every) {
        .progress_say(sprintf("start %d of %d begun, %s in", i, n_starts,
                              .duration_text(since(h$t0))))
      }
    },
    tick = function() {
      h$calls <- h$calls + 1L
      if (every <= 0 || since(h$last) < every) return(invisible())
      h$last <- Sys.time()
      per_run <- since(h$t_start) / h$calls
      of <- ""
      left <- ""
      if (!is.null(budget)) {
        of <- sprintf(" of %d", as.integer(budget))
        left <- sprintf(", about %s left in this start",
                        .duration_text(per_run * max(0, budget - h$calls)))
      }
      .progress_say(sprintf("start %d of %d: %d model runs%s, %s in (%s s a run)%s",
                            h$start, n_starts, h$calls, of, .duration_text(since(h$t0)),
                            format(signif(per_run, 2)), left))
    }
  )
}
