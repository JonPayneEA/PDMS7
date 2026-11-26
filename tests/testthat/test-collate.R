# ============================================================ #
# Tool:         test-collate
# Description:  Every file in R/ is named in DESCRIPTION's Collate field, so the package builds
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-26
# Tier:         1
# Inputs:       DESCRIPTION and the R/ folder of the source tree
# Outputs:      None
# Dependencies: testthat
# ============================================================ #

# Guards (regression): report_blocks.R was added to R/ but not to Collate. Loading the package
# from its source for the tests read every file regardless, so the tests passed, but installing
# it refused to build: "files in R missing from 'Collate' field: report_blocks.R".
test_that("every R file is collated", {
  root <- testthat::test_path("..", "..")
  skip_if_not(file.exists(file.path(root, "DESCRIPTION")) && dir.exists(file.path(root, "R")),
              "not run from the source tree")
  collate <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Collate")[1, 1]
  collated <- scan(text = gsub("\n", " ", collate), what = "", quiet = TRUE)
  files <- list.files(file.path(root, "R"), pattern = "[.]R$")
  expect_identical(setdiff(files, collated), character(0))
  expect_identical(setdiff(collated, files), character(0))
})
