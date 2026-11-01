# ============================================================ #
# Tool:         test-staged
# Description:  Tests for staged calibration, log NSE and the volume penalty
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add staged calibration tests
# Tier:         3
# Inputs:       Synthetic forcing and flows; temporary projects and basin folders
# Outputs:      testthat expectations
# Dependencies: testthat
# ============================================================ #

test_that("default stages follow the structure", {
  standard <- pdm_stages(pdm_presets("standard"))
  expect_equal(vapply(standard, function(s) s$name, ""),
               c("volume and baseflow", "fast response", "polish"))
  expect_setequal(standard[[1]]$parameters,
                  c("fc", "distribution.cmax", "distribution.b", "recharge.kg",
                    "groundwater.kb"))
  expect_setequal(standard[[2]]$parameters, c("surface.k1", "surface.k2", "distribution.b"))
  expect_length(standard[[3]]$parameters, 7)
  expect_equal(c(standard[[1]]$objective, standard[[1]]$volume_weight), c("log_nse", "1"))
  expect_equal(standard[[3]]$band, 0.25)
  split <- structure_set("split")$split
  expect_true("recharge.alpha" %in% pdm_stages(split)[[1]]$parameters)
  short <- pdm_stages(pdm_presets("standard"), polish = FALSE,
                      exclude = c("surface.k1", "surface.k2", "distribution.b"))
  expect_length(short, 1)
})

test_that("the polish band is a quarter of each range on the search scale", {
  config <- pdm_presets("standard")
  bounds <- calibration_bounds(config)
  config$fc <- 1.1
  config$groundwater$kb <- 1e4
  stage <- list(parameters = c("fc", "groundwater.kb"), band = 0.25)
  b <- pdmS7:::.stage_bounds(stage, bounds, config)
  expect_equal(unname(b$lower["fc"]), 1.1 - 0.25)
  expect_equal(unname(b$upper["fc"]), 1.1 + 0.25)
  width <- log(1e6) - log(100)
  expect_equal(unname(log(b$upper["groundwater.kb"]) - log(1e4)), 0.25 * width)
  expect_equal(unname(log(1e4) - log(b$lower["groundwater.kb"])), 0.25 * width)
  config$fc <- 1.55
  edge <- pdmS7:::.stage_bounds(stage, bounds, config)
  expect_equal(unname(edge$upper["fc"]), 1.6)
  expect_error(pdmS7:::.stage_bounds(list(parameters = "nope"), bounds, config), "No bounds")
})

test_that("log NSE and the volume penalty score as documented", {
  config <- pdm_presets("standard")
  f <- data.frame(rain = c(0, 8, 3, 0, 0, 5, 0, 0), pet = 0.05)
  truth <- config
  truth$fc <- 1.2
  obs <- run_pdm(pdm_from_config(truth), f)$output$q_m3s
  sim <- run_pdm(pdm_from_config(config), f)$output$q_m3s
  one <- function(objective, weight = 0) {
    # Bounds so tight that the fit cannot move from the configured value.
    calibrate_pdm(config, f, obs, lower = c(fc = 1 - 1e-12), upper = c(fc = 1 + 1e-12),
                  objective = objective, control = list(maxit = 1), volume_weight = weight)
  }
  lo <- log(obs + 0.01)
  expect_equal(one("log_nse")$objective,
               sum((log(sim + 0.01) - lo)^2) / sum((lo - mean(lo))^2), tolerance = 1e-10)
  expect_equal(one("log_nse", 2)$objective - one("log_nse")$objective,
               2 * abs(sum(sim) / sum(obs) - 1), tolerance = 1e-10)
  expect_equal(one("log_nse", 2)$objective_name, "1-log NSE + 2 x |volume error|")
  expect_error(one("nse", -1), "volume_weight")
})

staged_data <- function() {
  set.seed(11)
  n <- 24 * 30
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.08, stats::rgamma(n, 0.7, scale = 4),
                                      0), pet = 0.05)
  truth <- pdm_presets("standard")
  truth$fc <- 1.2
  truth$surface$k1 <- 5
  list(forcing = forcing, observed = run_pdm(pdm_from_config(truth), forcing)$output$q_m3s)
}

test_that("each stage moves only its own parameters and starts where the last ended", {
  d <- staged_data()
  config <- pdm_presets("standard")
  stages <- pdm_stages(config, exclude = c("groundwater.kb", "recharge.kg", "distribution.cmax"))
  fit <- calibrate_staged(config, d$forcing, d$observed, stages = stages, warmup = 48,
                          control = list(maxit = 15))
  expect_length(fit$stages, 3)
  expect_equal(fit$stages[[1]]$label, "1 of 3: volume and baseflow")
  first <- fit$stages[[1]]$config
  expect_equal(first$surface, config$surface)
  second <- fit$stages[[2]]$config
  expect_equal(second$fc, first$fc)
  expect_equal(fit$config, fit$stages[[3]]$config)
  expect_equal(unname(fit$parameters["fc"]), unname(fit$config$fc))
  nse <- function(cfg) {
    sim <- run_pdm(pdm_from_config(cfg), d$forcing)$output$q_m3s[-(1:48)]
    obs <- d$observed[-(1:48)]
    1 - sum((sim - obs)^2) / sum((obs - mean(obs))^2)
  }
  expect_gt(nse(fit$config), nse(config))
  expect_gte(nse(fit$config), nse(second) - 1e-9)
})

test_that("a logged staged calibration writes one entry per stage, chained", {
  p <- new_project()
  stages <- pdm_stages(p$data$truth, exclude = c("groundwater.kb", "distribution.cmax"),
                       polish = FALSE)
  out <- log_staged_calibration(p$folder, parent = "0003", reasoning = "Staged.",
                                stages = stages, control = list(maxit = 4))
  entries <- read_project(p$folder)$entries
  expect_equal(tail(entries$type, 2), rep("auto_calibration", 2))
  second <- read_entry(p$folder, out[[2]]$id)
  first <- read_entry(p$folder, out[[1]]$id)
  expect_equal(first$parent, "0003")
  expect_equal(second$parent, first$id)
  expect_equal(first$stage, "1 of 2: volume and baseflow")
  expect_equal(first$objective, "log_nse")
  expect_equal(first$volume_weight, 1)
  expect_null(second$volume_weight)
  expect_true(all(verify_project(p$folder)$ok))
})

test_that("a staged batch resumes from its last finished stage", {
  root <- tempfile("basins-")
  output <- tempfile("batch-")
  on.exit(unlink(c(root, output), recursive = TRUE), add = TRUE)
  folder <- file.path(root, "B01")
  dir.create(folder, recursive = TRUE)
  d <- staged_data()
  time <- seq(as.POSIXct("2023-10-01", tz = "UTC"), by = 3600, length.out = nrow(d$forcing))
  data.table::fwrite(cbind(time = format(time, "%Y-%m-%dT%H:%M:%SZ"), d$forcing),
                     file.path(folder, "forcing.csv"))
  data.table::fwrite(data.frame(q_m3s = d$observed), file.path(folder, "flow.csv"))
  writeLines(c("area_km2: 1", "calibration: [2023-10-03, 2023-10-22]",
               "validation: [2023-10-23, 2023-10-30]"), file.path(folder, "basin.yml"))
  as_person("Ann Custodian", "custodian", "ann")
  quick <- list(control = list(maxit = 3), exclude = c("groundwater.kb", "distribution.cmax"))
  # Interrupt after stage 1 by failing stage 2.
  local({
    real <- pdmS7:::.log_stage
    calls <- 0
    local_mocked_bindings(.log_stage = function(...) {
      calls <<- calls + 1
      if (calls == 2) stop("power cut")
      real(...)
    })
    status <- do.call(calibrate_batch, c(list(root, output, staged = TRUE), quick))
    expect_equal(status$state, "failed")
  })
  project <- file.path(output, "B01")
  expect_equal(sum(read_project(project)$entries$type == "auto_calibration"), 1L)
  status <- do.call(calibrate_batch, c(list(root, output, staged = TRUE), quick))
  expect_equal(status$state, "done")
  entries <- read_project(project)$entries
  expect_equal(sum(entries$type == "auto_calibration"), 3L)
  stages <- vapply(Filter(function(e) e$type == "auto_calibration",
                          lapply(entries$id, function(i) read_entry(project, i))),
                   function(e) e$stage, "")
  expect_equal(stages, paste(1:3, "of 3:", c("volume and baseflow", "fast response", "polish")))
  # A finished basin is left alone, staged or not.
  do.call(calibrate_batch, c(list(root, output), quick))
  expect_equal(nrow(read_project(project)$entries), nrow(entries))
})
