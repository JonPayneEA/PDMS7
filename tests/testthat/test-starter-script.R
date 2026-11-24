# ============================================================ #
# Tool:         test-starter-script
# Description:  The single-site starter script parses, and its example settings file carries
#               every setting the script requires
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-24
# Tier:         1
# Inputs:       inst/scripts/calibrate_site.R, inst/examples/site.yml
# Outputs:      None
# Dependencies: testthat, yaml
# ============================================================ #

test_that("the starter script parses", {
  script <- system.file("scripts", "calibrate_site.R", package = "pdmS7")
  expect_true(nzchar(script))
  expect_no_error(parse(script))
})

test_that("the example settings hold every required setting, with sound defaults", {
  settings <- yaml::read_yaml(system.file("examples", "site.yml", package = "pdmS7"))
  # The script stops without these: site, area, rain, calibration and validation windows.
  expect_true(is.numeric(settings$site$area_km2))
  expect_true(all(c("flow", "pet", "rain") %in% names(settings$data)))
  expect_length(settings$calibration, 2)
  expect_length(settings$validation, 2)
  # Validation follows calibration, so the windows do not overlap.
  expect_lt(as.POSIXct(settings$calibration[2], tz = "UTC"),
            as.POSIXct(settings$validation[1], tz = "UTC"))
  # A newcomer's first run checks the data and stops before calibrating.
  expect_true(settings$stop_after_checks)
  expect_true(settings$effort %in% c("quick", "standard", "thorough"))
})
