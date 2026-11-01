# ============================================================ #
# Tool:         helper-calibration
# Description:  Shared fixtures for calibration log and report tests
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-01
# Modified:     2026-11-01 - Add calibration log fixtures
# Tier:         3
# Inputs:       None
# Outputs:      Temporary calibration projects
# Dependencies: testthat
# ============================================================ #

all_reviewed <- c(integrity = TRUE, data = TRUE, calibration_path = TRUE, validation = TRUE)

# Runs f() when env exits, like withr::defer, without the dependency.
defer_to <- function(f, env) {
  do.call(base::on.exit, list(as.call(list(f)), add = TRUE), envir = env)
}

as_person <- function(name, role, login, env = parent.frame()) {
  old <- options(pdmS7.user = name, pdmS7.role = role)
  local_mocked_bindings(.login = function() login, .env = env) # nolint: object_usage_linter.
  defer_to(function() options(old), env)
}

log_data <- function(n = 24 * 40) {
  set.seed(7)
  time <- seq(as.POSIXct("2021-01-01", tz = "UTC"), by = 3600, length.out = n)
  forcing <- data.frame(
    time = time, rain = ifelse(stats::runif(n) < 0.06, stats::rexp(n, 0.3), 0), pet = 0.08
  )
  truth <- pdm_presets("standard")
  truth$area_km2 <- 20
  truth$recharge$kg <- 400
  observed <- run_pdm(pdm_from_config(truth), forcing)$output$q_m3s *
    exp(stats::rnorm(n, 0, 0.03))
  observed[200:210] <- NA
  list(forcing = forcing, observed = observed, truth = truth)
}

new_project <- function(env = parent.frame()) {
  folder <- tempfile("project-")
  defer_to(function() unlink(folder, recursive = TRUE), env)
  d <- log_data()
  as_person("Ann Custodian", "custodian", "ann", env)
  start_calibration_project(folder, "Test Brook", "99999", "Testing", 20, "A Director",
                            "Sam Steward")
  register_data(folder, d$forcing, d$observed, calibration = c(121, 700),
                validation = c("2021-01-31", "2021-02-09 23:00"))
  start <- d$truth
  start$fc <- 0.85
  select_structure(folder, start, "Standard structure")
  list(folder = folder, data = d)
}
