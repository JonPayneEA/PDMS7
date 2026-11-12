# ============================================================ #
# Tool:         test-report
# Description:  Tests for the calibration report
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add report tests
# Tier:         1
# Inputs:       Temporary calibration projects
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

# Guards: the embedded-image encoder matches RFC 4648 test vectors
test_that("base64 encoding matches the standard", {
  expect_equal(.base64(charToRaw("Man")), "TWFu")
  expect_equal(.base64(charToRaw("Ma")), "TWE=")
  expect_equal(.base64(charToRaw("M")), "TQ==")
  expect_equal(.base64(raw(0)), "")
  expect_equal(.base64(as.raw(0:255))[1], paste0(
    "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BB",
    "QkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKD",
    "hIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TF",
    "xsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w=="
  ))
})

# Guards: a report on an unfinished project still renders and says what is missing
test_that("an early report says what is missing and embeds its figures", {
  p <- new_project()
  file <- build_report(p$folder)
  expect_true(file.exists(file))
  html <- paste(readLines(file, warn = FALSE), collapse = "\n")
  expect_match(html, "All [0-9]+ integrity checks passed")
  expect_match(html, "No candidate proposed yet")
  expect_match(html, "Not yet signed off")
  expect_false(grepl("Parameter sensitivity", html))
  expect_false(grepl("src=\"(?!data:)", html, perl = TRUE))
  expect_match(html, "data:image/png;base64,")
  md <- readLines(file.path(p$folder, "report", "report.md"), warn = FALSE)
  links <- sub(".*\\((figures/[^)]+)\\).*", "\\1", grep("!\\[", md, value = TRUE))
  expect_true(length(links) >= 2)
  expect_true(all(file.exists(file.path(p$folder, "report", links))))
  expect_true(all(verify_project(p$folder)$ok))
})

# Guards: a complete project's report has every section
test_that("a validated project reports candidate, sensitivity and sign-off", {
  p <- new_project()
  log_trial(p$folder, 3, c(fc = 1), "better", "Volume too low")
  propose_candidate(p$folder, 4, "Best so far")
  validate_candidate(p$folder, "Holds up")
  as_person("Sam Steward", "steward", "sam")
  sign_off_project(p$folder, "Accepted", all_reviewed)
  file <- build_report(p$folder, sensitivity_steps = 3L)
  html <- paste(readLines(file, warn = FALSE), collapse = "\n")
  for (section in c("Integrity", "Data", "Model structure", "Calibration path", "Candidate",
                    "Validation window", "Parameter sensitivity", "Sign-off",
                    "Signed-off configuration")) {
    expect_match(html, paste0(">", section, "<"))
  }
  expect_match(html, "Sam Steward")
  expect_true(file.exists(file.path(p$folder, "report", "figures", "sensitivity.png")))
  quick <- build_report(p$folder, output = tempfile("report-"), sensitivity = FALSE,
                        rerun = FALSE)
  expect_false(grepl("Parameter sensitivity", paste(readLines(quick), collapse = "")))
  expect_match(paste(readLines(quick), collapse = ""), "runs not repeated")
})

# Guards: a tampered project is flagged at the head of its report
test_that("failed integrity is flagged at the top", {
  p <- new_project()
  log_trial(p$folder, 3, c(fc = 1), "better", "Volume too low")
  file <- file.path(p$folder, "entries", "0003-structure_selected.yml")
  writeLines(sub("Standard structure", "Edited", readLines(file)), file)
  html <- paste(readLines(build_report(p$folder, rerun = FALSE)), collapse = "\n")
  expect_match(html, "integrity checks FAILED")
  expect_lt(regexpr("FAILED", html), regexpr(">Data<", html))
})

# Guards: invalid report settings are refused
test_that("report arguments are checked", {
  p <- new_project()
  expect_error(build_report(p$folder, sensitivity_range = 1), "sensitivity_range")
  expect_error(build_report(p$folder, sensitivity_steps = 2), "sensitivity_steps")
})

# Guards: each window's figures show that window (they once all showed the last), the largest
# events are tabled and drawn, and each held-back wettest year gets its own hydrograph
test_that("the report's window, event and wettest-year figures", {
  p <- new_project()
  propose_candidate(p$folder, 3, "Starting structure")
  validate_candidate(p$folder, "Holds up")
  build_report(p$folder, sensitivity = FALSE, rerun = FALSE)
  figures <- file.path(p$folder, "report", "figures")
  hydro <- file.path(figures, paste0("hydrograph-", c("calibration", "validation"), ".png"))
  expect_true(all(file.exists(hydro)))
  expect_false(identical(unname(tools::md5sum(hydro[1])), unname(tools::md5sum(hydro[2]))))
  md <- paste(readLines(file.path(p$folder, "report", "report.md")), collapse = "\n")
  if (file.exists(file.path(figures, "top-events.png"))) {
    expect_match(md, "### Largest events")
    expect_match(md, "largest events of the record by observed peak")
  }

  folder <- file.path(tempfile("wet-"), "brook")
  on.exit(unlink(dirname(folder), recursive = TRUE), add = TRUE)
  rain <- synthetic_rain("2018-10-01", years = 6, dt = 1, seed = 4)
  forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 20
  model <- pdm_from_config(cfg)
  flow <- run_pdm(model, forcing, initial_state_from_flow(model, 0.3, 0.7))$output$q_m3s
  suppressWarnings(calibrate_project(
    folder, forcing, flow, 20, calibration = c("2018-10-01", "2021-09-30 23:00"),
    validation = c("2021-10-01", "2024-09-30 23:00"), structure = cfg, starts = 1L,
    control = list(maxit = 2L), stages = pdm_stages(cfg, polish = FALSE), wettest_years = 2,
    report = TRUE
  ))
  wet <- list.files(file.path(folder, "report", "figures"), "^hydrograph-wettest-")
  expect_length(wet, 2)
  md <- paste(readLines(file.path(folder, "report", "report.md")), collapse = "\n")
  expect_match(md, "### Held-back wettest years")
  expect_match(md, "### Largest events")
  expect_true(file.exists(file.path(folder, "report", "figures", "top-events.png")))
})
