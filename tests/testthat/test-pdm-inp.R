# Tests for reading and writing PDM for PCs input files, and for compare_calibrations(), against
# the conventions of the PDM for PCs manual (Configuration Guide 2.3, Appendix A.1).

example_inp <- function(name) system.file("examples", paste0(name, ".inp"), package = "pdmS7")

# Writes text as a temporary *.inp file, with substitutions applied to the standard example.
edited_inp <- function(from, to) {
  text <- readLines(example_inp("standard"))
  for (i in seq_along(from)) text <- sub(from[i], to[i], text, fixed = TRUE)
  path <- tempfile(fileext = ".inp")
  writeLines(text, path)
  path
}

# Guards: the manual's example reads with its conventions: kb cubed for a cubic store, k2 = 0
# as k2 = k1, tdly found by its position, Smith's method, the optimised flags
test_that("the manual's standard example reads as documented", {
  cfg <- read_pdm_inp(example_inp("standard"))
  expect_equal(cfg$distribution, list(type = "pareto", cmin = 0, cmax = 135, b = 0.63))
  expect_equal(cfg$recharge, list(type = "standard", kg = 85000, bg = 2.42, st = 0))
  expect_equal(cfg$surface, list(type = "cascade", k1 = 3.1, k2 = 3.1))
  expect_equal(cfg$groundwater, list(type = "cubic", kb = 13^3, solver = "smith"))
  expect_equal(c(cfg$fc, cfg$be, cfg$td, cfg$qc, cfg$area_km2, cfg$dt),
               c(0.9, 2.5, 0.17, 0, 100.5, 0.25))
  expect_equal(attr(cfg, "optimised"), c("rainfac", "cmax", "b", "k1", "kb", "kg", "bg"))
  expect_equal(attr(cfg, "stations")[["flow"]], "57006")
  expect_equal(attr(cfg, "events")$start, "09:00 30 Mar 1991")
  expect_length(attr(cfg, "notes"), 0)
  expect_true(S7::S7_inherits(pdm_from_config(cfg), FlodePdmModel))
  # A positive tdly in the structure line is the delay itself, in hours
  direct <- read_pdm_inp(edited_inp("22     3     -13 /", "22     3     2 /"))
  expect_equal(direct$td, 2)
})

# Guards: the groundwater example reads the extension, its well datum and the gauge note
test_that("the manual's groundwater example reads the extension", {
  cfg <- read_pdm_inp(example_inp("groundwater"))
  expect_equal(cfg$groundwater$kb, 413.42^3)
  expect_equal(cfg$groundwater$extension,
               list(ku = 1e5, dbu = 0, alpha_b = 0, ca = 0, fa = 1, smax_b = 1000, ys = 0.1,
                    hw = 83.76))
  expect_equal(cfg$recharge$kg, 301535)
  expect_equal(cfg$td, 0)
  expect_match(attr(cfg, "notes"), "raingauges")
})

# Guards: writing then reading gives the same model, for every structure that can be written
test_that("write_pdm_inp and read_pdm_inp round-trip", {
  base <- read_pdm_inp(example_inp("standard"))
  variants <- list(
    standard = base,
    unequal = within(base, surface$k2 <- 7),
    lognormal = within(base, distribution <- list(type = "lognormal", meanlog = 4, sdlog = 0.7)),
    exponential = within(base, distribution <- list(type = "exponential", mean = 90)),
    split = within(base, recharge <- list(type = "split", alpha = 0.4)),
    quadratic = within(base, groundwater <- list(type = "quadratic", kb = 800)),
    linear_surface = within(base, surface <- list(type = "linear", kb = 6)),
    extended = read_pdm_inp(example_inp("groundwater"))
  )
  for (name in names(variants)) {
    path <- tempfile(fileext = ".inp")
    write_pdm_inp(variants[[name]], path, "Round trip", c("2010-10-01 09:00", "2011-10-01 09:00"),
                  optimised = c("cmax", "kb"))
    back <- read_pdm_inp(path)
    expect_equal(unclass(pdm_from_config(back)), unclass(pdm_from_config(variants[[name]])),
                 label = name)
    expect_equal(attr(back, "optimised"), c("cmax", "kb"), label = name)
    expect_equal(attr(back, "events")$end, "09:00 1 Oct 2011", label = name)
  }
  expect_error(write_pdm_inp(base, tempfile(), "x", c("2010-10-01", "2011-10-01"),
                             optimised = "nope"), "not in the file")
  expo <- within(base, groundwater <- list(type = "exponential", a = 0.05, gamma = -5))
  expect_error(write_pdm_inp(expo, tempfile(), "x", c("2010-10-01", "2011-10-01")),
               "exponential store cannot be written")
})

# Guards: what cannot be mapped faithfully is refused, not guessed
test_that("unsupported files are refused with a reason", {
  expect_error(read_pdm_inp(edited_inp("   1        0     22", "   4        0     22")),
               "power distribution")
  expect_error(read_pdm_inp(edited_inp("   1        0     22", "   1        3     22")),
               "demand recharge")
  expect_error(read_pdm_inp(edited_inp("22     3     -13", "22     4     -13")),
               "Baseflow model 4")
  expect_error(read_pdm_inp(edited_inp("'qconst'", "'rainfac'")), "several hydrological zones")
  expect_error(read_pdm_inp(edited_inp("indx", "index")), "parameter list")
})

# Guards: models are compared on the same data and start; identical models score identically,
# and the tables hold what the help page says
test_that("compare_calibrations sets models side by side", {
  set.seed(1)
  n <- 96 * 60
  forcing <- data.frame(time = as.POSIXct("2020-10-01", tz = "UTC") + 900 * (seq_len(n) - 1),
                        rain = ifelse(stats::runif(n) < 0.03, stats::rexp(n, 1), 0), pet = 0.02)
  inp <- example_inp("standard")
  other <- read_pdm_inp(inp)
  other$surface$k1 <- 5
  observed <- run_pdm(pdm_from_config(other), forcing[c("rain", "pet")])$output$q_m3s
  cmp <- compare_calibrations(list(pdm_for_pcs = inp, same = read_pdm_inp(inp), other = other),
                              forcing, observed, warmup = 96 * 5, markers = "Q5",
                              windows = list(early = c(1, n / 2), late = c(n / 2 + 1, n)))
  expect_s3_class(cmp, "pdm_comparison")
  expect_equal(cmp$parameters$parameter[cmp$parameters$differs], "surface.k1")
  expect_equal(cmp$scores$pdm_for_pcs, cmp$scores$same)
  expect_gt(cmp$scores$other[cmp$scores$window == "late" & cmp$scores$score == "nse"],
            cmp$scores$same[cmp$scores$window == "late" & cmp$scores$score == "nse"])
  expect_true(all(cmp$windows$early > 96 * 5))
  expect_setequal(unique(cmp$thresholds$model), c("pdm_for_pcs", "same", "other"))
  expect_true(all(c("other.peak_error", "same.timing_error_h") %in% names(cmp$events)))
  expect_output(print(cmp), "Parameters that differ")
  expect_silent(plot(cmp))
  expect_silent(plot(cmp, window = "late"))
  expect_error(compare_calibrations(list(a = inp), forcing, observed), "two or more")
  hourly <- read_pdm_inp(inp, dt = 1)
  expect_error(compare_calibrations(list(a = inp, b = hourly), forcing, observed), "step")
})
