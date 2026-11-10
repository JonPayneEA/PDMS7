# Tests for the progress messages of long calibrations: durations, the heartbeat, the progress
# file written by worker processes, and that a calibration gives the same answer with it on.

# Runs code with options set, restoring them after.
with_opts <- function(opts, code) {
  old <- options(opts)
  on.exit(options(old), add = TRUE)
  code
}

# Guards: durations read as seconds, minutes or hours
test_that("durations are written for people", {
  expect_equal(.duration_text(42), "42 s")
  expect_equal(.duration_text(600), "10 min")
  expect_equal(.duration_text(3 * 3600), "3.0 h")
  expect_equal(.duration_text(NA_real_), "unknown")
})

# Guards: progress goes to a named file, with the time and the label, when one is set
test_that("progress lines go to the progress file with their label", {
  file <- tempfile(fileext = ".log")
  on.exit(unlink(file), add = TRUE)
  with_opts(list(pdmS7.progress_file = file, pdmS7.progress_label = "Step 1"), {
    .progress_say("calibrating")
  })
  line <- readLines(file)
  expect_length(line, 1)
  expect_match(line, "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} Step 1: calibrating$")
})

# Guards: the heartbeat speaks once its interval has passed, with the runs out of the budget,
# and not at all when turned off
test_that("the heartbeat reports runs and the time left", {
  file <- tempfile(fileext = ".log")
  on.exit(unlink(file), add = TRUE)
  with_opts(list(pdmS7.progress_file = file, pdmS7.progress_every = 1e-6), {
    beat <- .heartbeat(2L, budget = 10)
    beat$start(1L)
    for (i in 1:3) beat$tick()
  })
  lines <- readLines(file)
  expect_length(lines, 3)
  expect_match(lines[3], "start 1 of 2: 3 model runs of 10, .* s a run\\), about .* left")
  unlink(file)
  with_opts(list(pdmS7.progress_file = file, pdmS7.progress_every = 0), {
    beat <- .heartbeat(1L)
    beat$start(1L)
    beat$tick()
  })
  expect_false(file.exists(file))
})

# Guards: a calibration with the heartbeat on still gives the same answer
test_that("the heartbeat does not change a calibration", {
  r <- synthetic_catchment(years = 1, dt = 1, seed = 2)
  b <- calibration_bounds(r$truth)[1:2, ]
  lo <- stats::setNames(b$lower, b$path)
  up <- stats::setNames(b$upper, b$path)
  fit <- function() {
    calibrate_pdm(r$truth, r$forcing, r$observed, lower = lo, upper = up, warmup = 200,
                  control = list(maxit = 5), method = "dds", seed = 3)$parameters
  }
  quiet <- with_opts(list(pdmS7.progress_every = 0), fit())
  file <- tempfile(fileext = ".log")
  on.exit(unlink(file), add = TRUE)
  loud <- with_opts(list(pdmS7.progress_every = 1e-6, pdmS7.progress_file = file), fit())
  expect_equal(loud, quiet)
  expect_gt(length(readLines(file)), 1)
})
