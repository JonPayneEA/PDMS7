# Tests for the house style (pdm_colours(), pdm_palette(), theme_pdm(), pdm_save()) and the
# standard run plots (pdm_series()).

# A year of hourly flow with a second run, rain, both windows and a threshold.
visuals_series <- function() {
  set.seed(3)
  n <- 24 * 365
  time <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600, length.out = n)
  rain <- ifelse(stats::runif(n) < 0.05, stats::rexp(n, 0.4), 0)
  sim <- as.numeric(stats::filter(rain, 0.97, method = "recursive")) / 10 + 0.3
  obs <- sim * exp(stats::rnorm(n, 0, 0.1))
  obs[100:150] <- NA
  pdm_series(sim, obs, rain = rain, time = time,
             windows = list(calibration = c(1, 6000), validation = time[c(6001, n)]),
             thresholds = c(Alert = 2), alternative = sim * 0.9,
             labels = c(simulated = "Model"))
}

# Guards: every role has one Okabe-Ito colour, and bad requests are refused
test_that("pdm_colours gives fixed roles and pdm_palette a fixed order", {
  all <- pdm_colours()
  expect_true(all(c("observed", "simulated", "rain", "alternative", "calibration", "validation",
                    "threshold", "flag", "reference") %in% names(all)))
  expect_equal(unname(pdm_colours("observed")), "#000000")
  expect_equal(unname(pdm_colours("simulated")), "#0072B2")
  expect_match(unname(pdm_colours("rain", alpha = 0.5)), "^#56B4E9[0-9A-F]{2}$")
  expect_error(pdm_colours("nope"), "Unknown role")
  expect_error(pdm_colours(alpha = 2), "alpha")
  expect_equal(unname(pdm_palette(3)), c("#0072B2", "#D55E00", "#009E73"))
  expect_error(pdm_palette(9), "n must be")
})

# Guards: inputs are checked, windows given as times become rows, and print summarises
test_that("pdm_series checks its inputs and normalises windows", {
  s <- visuals_series()
  expect_s3_class(s, "pdm_series")
  expect_equal(s$windows$validation, c(6001L, 8760L))
  expect_equal(unname(s$labels), c("Observed", "Model", "Alternative"))
  expect_output(print(s), "windows: calibration, validation")
  expect_error(pdm_series(1:10, observed = 1:5), "as long as")
  expect_error(pdm_series(1:10, windows = list(c(1, 3))), "named list")
  expect_error(pdm_series(1:10, windows = list(a = c(5, 2))), "end before")
  expect_error(pdm_series(1:10, windows = list(a = Sys.time() + 0:1)), "need time")
  expect_error(pdm_series(1:10, thresholds = 3), "named numeric")
  expect_error(plot(pdm_series(1:10), type = "duration"), "needs observed")
})

# Guards: the hydrograph draws every run under the observed line, clips windows to the period,
# thins rain to at most 1,500 bars and dashes the thresholds
test_that("the hydrograph description holds what the plot shows", {
  s <- visuals_series()
  spec <- .series_spec(s, "hydrograph", NULL)
  expect_equal(unique(spec$series$label), c("Alternative", "Model", "Observed"))
  expect_equal(spec$legend, c("Observed", "Model", "Alternative"))
  expect_lte(nrow(spec$rain), 1500)
  expect_equal(sum(spec$rain$depth), sum(s$rain), tolerance = 1e-9)
  expect_equal(spec$hlines$y, 2)
  expect_equal(spec$bands$label, c("Calibration", "Validation"))
  zoom <- .series_spec(s, "hydrograph", c(5900, 6100))
  expect_equal(nrow(zoom$series), 3 * 201)
  expect_equal(zoom$bands$xmin[2], s$time[6001])
  expect_null(zoom$subtitle)
  valid <- .series_spec(s, "hydrograph", "validation")
  expect_equal(range(valid$series$x), range(s$time[6001:8760]))
  expect_error(.series_spec(s, "hydrograph", "nope"), "No window")
})

# Guards: duration curves fall with exceedance; cumulative volumes add only shared steps;
# residual means are centred running means
test_that("duration, volume and residual descriptions are computed correctly", {
  s <- visuals_series()
  d <- .series_spec(s, "duration", NULL)
  expect_equal(d$log, "y")
  for (label in unique(d$series$label)) {
    expect_true(all(diff(d$series$y[d$series$label == label]) <= 0))
  }
  v <- .series_spec(s, "volume", NULL)
  ok <- is.finite(s$observed)
  last <- function(label) utils::tail(v$series$y[v$series$label == label], 1)
  expect_equal(last("Observed"), sum(s$observed[ok]) * 3600 / 1e6)
  expect_equal(last("Model"), sum(s$simulated[ok]) * 3600 / 1e6)
  change <- 100 * (sum(s$alternative[ok]) / sum(s$observed[ok]) - 1)
  expect_match(v$subtitle, sprintf("Alternative %+.1f%%", change), fixed = TRUE)
  expect_equal(.running_mean(c(1, 2, 3, 4, 5), 3), c(NA, 2, 3, 4, NA))
  # Half the window must be present: one value in three is not enough.
  expect_equal(.running_mean(c(1, NA, 3, NA, NA, NA), 3), c(NA, 2, NA, NA, NA, NA))
  r <- .series_spec(s, "residuals", NULL)
  expect_true(all(c("Model 30-day mean", "Alternative 30-day mean") %in% r$series$label))
  expect_true(r$ylim[1] <= 0 && r$ylim[2] >= 0)
})

# Guards: every type draws in base R, and in ggplot2 when it is installed
test_that("plot and autoplot draw every type", {
  s <- visuals_series()
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  for (type in c("hydrograph", "duration", "volume", "residuals")) {
    expect_identical(plot(s, type = type), s)
  }
  expect_identical(plot(s, period = "calibration"), s)
  expect_identical(plot(pdm_series(1:50 / 10)), pdm_series(1:50 / 10))
  skip_if_not_installed("ggplot2")
  for (type in c("hydrograph", "duration", "volume", "residuals")) {
    g <- ggplot2::autoplot(s, type = type)
    expect_s3_class(g, "ggplot")
    expect_silent(ggplot2::ggplot_build(g))
  }
  expect_s3_class(theme_pdm(), "theme")
})

# Guards: figures are written at the preset size, in the format of the file's extension
test_that("pdm_save writes PNG, PDF and SVG at the presets", {
  s <- visuals_series()
  dir <- tempfile("figures-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  png <- pdm_save(s, file.path(dir, "a.png"), preset = "report_half")
  expect_true(file.exists(png))
  # A PNG's width and height are the two 4-byte integers after its 16-byte header.
  head <- readBin(png, "raw", 24)
  size <- readBin(head[17:24], "integer", 2, size = 4, endian = "big")
  expect_equal(size, c(3.1, 2.6) * 300)
  expect_true(file.exists(pdm_save(s, file.path(dir, "b.pdf"), type = "volume")))
  expect_true(file.exists(pdm_save(function() plot(1:3), file.path(dir, "c.svg"))))
  expect_error(pdm_save(s, file.path(dir, "d.jpg")), "must end in")
  expect_error(pdm_save(s, file.path(dir, "e.png"), preset = "poster"), "preset must be")
  skip_if_not_installed("ggplot2")
  expect_true(file.exists(pdm_save(ggplot2::autoplot(s), file.path(dir, "f.png"),
                                   preset = "slide")))
})
