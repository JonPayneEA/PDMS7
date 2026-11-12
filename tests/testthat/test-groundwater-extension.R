# Tests for the groundwater extension: abstraction, negative storage and ephemeral flow,
# underflow, springs and well level, against the equations of the PDM for PCs scientific guide
# (UKCEH, 2022, section 3 and Appendix B) and an independent fine-step solution.

# A fine-step RK4 solution of dS/dt = u - k max(S, 0)^m over dt hours, with the time flow ceases.
fine_store <- function(k, m, s, u, dt, n = 20000L) {
  h <- dt / n
  f <- function(x) u - k * max(x, 0)^m
  cease <- Inf
  for (i in seq_len(n)) {
    k1 <- f(s)
    k2 <- f(s + h / 2 * k1)
    k3 <- f(s + h / 2 * k2)
    k4 <- f(s + h * k3)
    nxt <- s + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
    if (s > 0 && nxt <= 0) cease <- (i - 1) * h + h * s / (s - nxt)
    s <- nxt
  }
  list(storage = s, cease = cease)
}

ext_config <- function(...) {
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 20
  cfg$groundwater$extension <- list(...)
  cfg
}

ext_forcing <- function(n = 24 * 120, seed = 1) {
  set.seed(seed)
  data.frame(rain = ifelse(stats::runif(n) < 0.05, stats::rexp(n, 0.3), 0), pet = 0.08)
}

# Guards: the linear and quadratic stores cease flowing when and as the published Eqs. B.1-B.4
# say, matching the exact solution, and the storage then falls below zero by continuity
test_that("linear and quadratic stores cease flowing exactly", {
  for (m in 1:2) {
    k <- c(1 / 50, 1 / 500)[m]
    store <- power_routing(k = k, m = m)
    for (u in c(-0.1, -1)) {
      fine <- fine_store(k, m, 20, u, 48)
      cease <- .time_to_cessation(m, k, 20, k * 20^m, u)
      # A weak drain stops the flow only after the 48 hours checked here
      if (is.finite(fine$cease)) {
        expect_equal(cease, fine$cease, tolerance = 1e-5)
      } else {
        expect_gt(cease, 48)
      }
      expect_equal(.extended_storage(store, 20, u, 48), fine$storage, tolerance = 1e-5)
    }
  }
})

# Guards: the cubic store follows Smith's method (Eqs. 4, 6 and 7) as published, which at a
# 15-minute step matches the exact solution closely
test_that("the cubic store ceases flowing by Smith's method", {
  k <- 1 / 5000
  store <- power_routing(k = k, m = 3, solver = "smith")
  s <- 20
  for (i in 1:(48 * 4)) s <- .extended_storage(store, s, -1, 0.25)
  expect_equal(s, fine_store(k, 3, 20, -1, 48)$storage, tolerance = 1e-3)
  # Eq. 6 and the end storage of Eq. 7 agree: zero at T', then u (dt - T')
  q <- k * 30^3
  cease <- .time_to_cessation(3, k, 30, q, -100)
  expect_lt(cease, 1)
  expect_equal(.extended_storage(store, 30, -100, 1), -100 * (1 - cease))
  # Smith's step never reaches zero when the drain is weak against the outflow
  expect_identical(.time_to_cessation(3, k, 30, q, -1), Inf)
})

# Guards: below zero there is no outflow, and flow restarts once recharge refills the store
test_that("a store below zero refills and starts flowing again", {
  store <- power_routing(k = 1 / 50, m = 1)
  expect_equal(.extended_storage(store, -5, -1, 2), -7)
  expect_equal(.extended_storage(store, -5, 1, 4), -1)
  refilled <- .extended_storage(store, -5, 2, 4)
  expect_equal(refilled, route_step(store, 0, 2, 1.5)$storage)
  expect_gt(refilled, 0)
})

# Guards: with nothing switched on the extension changes nothing; with everything switched on
# the water balance still closes, losses included
test_that("the extended model reduces to the standard one and keeps its water balance", {
  forcing <- ext_forcing()
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 20
  standard <- run_pdm(pdm_from_config(cfg), forcing)$output$q_m3s
  idle <- run_pdm(pdm_from_config(ext_config()), forcing)$output
  expect_equal(idle$q_m3s, standard, tolerance = 1e-12)
  expect_true(all(c("abstraction_mm", "underflow_mm", "spring_mm", "groundwater_deficit_mm",
                    "well_level_m") %in% names(idle)))
  expect_true(all(idle$underflow_mm == 0 & idle$spring_mm == 0 & idle$abstraction_mm == 0))
  busy <- pdm_from_config(ext_config(ku = 3000, dbu = 50, alpha_b = 0.1, ca = 0.01,
                                     smax_b = 500, ys = 0.02, hw = 80))
  forcing$abstraction <- 0.05
  out <- run_pdm(busy, forcing)$output
  expect_lt(max(abs(out$balance_error_mm)), 1e-9)
  expect_lt(min(out$groundwater_mm), 0)
  dry <- out$groundwater_mm <= 0
  expect_true(all(out$baseflow_out_mm[dry & c(FALSE, utils::head(dry, -1))] == 0))
  expect_equal(out$abstraction_mm, rep(0.01 * 1 + 0.05, nrow(out)))
  expect_equal(out$well_level_m, 80 - 0.02 * (500 - out$groundwater_mm) / 1000)
  expect_true(is.na(run_pdm(pdm_from_config(ext_config(ku = 3000)), ext_forcing(48))$output$
                      well_level_m[1]))
})

# Guards: underflow follows Eq. 10 from the start-of-step storage, and springs take their share
test_that("underflow and springs follow the published rules", {
  store <- groundwater_extension(linear_routing(100), ku = 1000, dbu = 30, alpha_b = 0.25)
  step <- .extended_step(store, 70, 0.2, 0, 1)
  expect_equal(step$underflow, (70 + 30) / 1000)
  expect_equal(step$spring / (step$spring + step$outflow), 0.25)
  expect_equal(70 + 0.2 - step$underflow - step$spring - step$outflow, step$storage)
  # Below the underflow outlet there is no underflow
  expect_equal(.extended_step(store, -40, 0, 0, 1)$underflow, 0)
  # Underflow never draws the store below its outlet within a step
  quick <- groundwater_extension(linear_routing(100), ku = 0.1, dbu = 10)
  expect_gte(.extended_step(quick, -5, 0, 0, 1)$storage, -10)
})

# Guards: configurations, validation, forcing and calibration bounds for the extension
test_that("the extension is configured, checked and calibrated", {
  model <- pdm_from_config(ext_config(ku = 12000, dbu = 400))
  expect_true(S7::S7_inherits(model@groundwater, FlodeExtendedGroundwater))
  expect_equal(model@groundwater@ku, 12000)
  other <- ext_config(ku = 12001, dbu = 400)
  expect_false(identical(pdm_fingerprint(model), pdm_fingerprint(other)))
  expect_error(groundwater_extension(FlodeExponentialRouting(0.05, -5)), "store")
  expect_error(groundwater_extension(power_routing(m = 1.5)), "linear, quadratic or cubic")
  expect_error(groundwater_extension(linear_routing(), alpha_b = 1), "alpha_b")
  expect_error(groundwater_extension(linear_routing(), ku = 0), "ku")
  demand <- ext_config(ku = 1000)
  demand$recharge <- list(type = "demand", alpha = 0.5, beta = 1, qsat = 0.05)
  expect_error(pdm_from_config(demand), "Demand recharge")
  plain <- pdm_presets("standard")
  forcing <- ext_forcing(48)
  forcing$abstraction <- 0.01
  expect_error(run_pdm(pdm_from_config(plain), forcing), "groundwater extension")
  bounds <- calibration_bounds(ext_config(ku = 12000, dbu = 400))
  expect_true(all(c("groundwater.extension.ku", "groundwater.extension.dbu") %in% bounds$path))
  expect_false("groundwater.extension.alpha_b" %in% bounds$path)
  expect_false(any(grepl("extension", calibration_bounds(ext_config())$path)))
  stages <- pdm_stages(ext_config(ku = 12000, dbu = 400))
  expect_true("groundwater.extension.ku" %in% stages[[1]]$parameters)
})

# Guards: a calibration can fit the extension's parameters
test_that("calibrate_pdm fits an underflow", {
  # A wet record at a 3-hour step with a linear store and fast recharge, so the store fills, the
  # underflow shows in the flow, and the R loop the extension runs in stays quick
  wet <- function(ku) {
    cfg <- ext_config(ku = ku, dbu = 100)
    cfg$recharge$kg <- 400
    cfg$groundwater <- list(type = "linear", kb = 300, extension = list(ku = ku, dbu = 100))
    cfg$dt <- 3
    cfg
  }
  set.seed(3)
  n <- 8 * 150
  forcing <- data.frame(rain = ifelse(stats::runif(n) < 0.15, stats::rexp(n, 0.15), 0),
                        pet = 0.15)
  observed <- run_pdm(pdm_from_config(wet(2000)), forcing)$output$q_m3s
  fit <- calibrate_pdm(wet(6000), forcing, observed, lower = c(groundwater.extension.ku = 500),
                       upper = c(groundwater.extension.ku = 20000), start = "soil",
                       soil_fraction = 0.5, log_scale = "groundwater.extension.ku",
                       method = "dds", seed = 1, control = list(maxit = 25))
  expect_equal(fit$parameters[["groundwater.extension.ku"]], 2000, tolerance = 0.1)
})
