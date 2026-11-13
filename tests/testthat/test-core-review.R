# Regression tests from the review of the compiled core: the cubic store's solver with negative
# input, underflow coupled with the main outlet, the Smith solver's accuracy, spring imports, the
# lognormal inverse, and the routing coefficient. Every expected value comes from a closed form or
# an independent fine-step integration written here, not from comparing C with R. Each case runs
# through the compiled core and through the R loop.

# A fine-step RK4 of dS/dt = u - k max(S, 0)^m - max(S + dbu, 0) / ku over dt hours, with the
# volumes through the main outlet and the underflow; written independently of the package.
reference_store <- function(s, u, k, m, dt, ku = Inf, dbu = 0, n = 40000L) {
  h <- dt / n
  rates <- function(x) {
    q <- k * max(x, 0)^m
    qu <- if (is.finite(ku)) max(x + dbu, 0) / ku else 0
    c(u - q - qu, q, qu)
  }
  main <- 0
  under <- 0
  for (i in seq_len(n)) {
    a <- rates(s)
    b <- rates(s + h / 2 * a[1])
    c <- rates(s + h / 2 * b[1])
    d <- rates(s + h * c[1])
    w <- h / 6 * (a + 2 * b + 2 * c + d)
    s <- s + w[1]
    main <- main + w[2]
    under <- under + w[3]
  }
  c(storage = s, main = main, under = under)
}

# A model in which the groundwater store sees exactly the abstraction given: no rain or PET, an
# empty soil store (so no recharge) and an empty surface store, starting from storage s0.
groundwater_model <- function(groundwater, extension, dt) {
  cfg <- pdm_presets("standard")
  cfg$area_km2 <- 1
  cfg$dt <- dt
  cfg$groundwater <- c(groundwater, list(extension = extension))
  pdm_from_config(cfg)
}
run_groundwater <- function(model, s0, abstraction_mm, engine) {
  state <- initial_state(model)
  state@soil <- 0
  state@groundwater <- s0
  forcing <- data.frame(rain = 0, pet = 0, abstraction = abstraction_mm)
  old <- options(pdmS7.engine = engine)
  on.exit(options(old))
  run_pdm(model, forcing, state)$output
}

# Guards: with the adaptive solver, a cubic store drained by abstraction follows the continuous
# equation through the moment flow ceases and on into deficit; with the Smith solver it follows
# Smith's published step. S0 = 1 mm, k = 1, u = -1 mm/h, dt = 1 h.
test_that("the cubic store's negative input follows its solver", {
  # dS/dt = -(1 + S^3) reaches zero after the integral of 1/(1 + S^3) from 0 to 1
  cease <- log(2) / 3 + pi / (3 * sqrt(3))
  expect_equal(cease, 0.835649, tolerance = 1e-6)
  exact <- -1 * (1 - cease)
  expect_equal(reference_store(1, -1, 1, 3, 1)[["storage"]], exact, tolerance = 1e-8)
  smith <- 1 + (-expm1(-3) / 3) * (-1 - 1)
  for (engine in c("auto", "r")) {
    adaptive <- groundwater_model(list(type = "cubic", kb = 1), list(ca = 0), 1)
    out <- run_groundwater(adaptive, 1, 1, engine)
    expect_equal(out$groundwater_mm, exact, tolerance = 1e-6, label = engine)
    expect_equal(out$baseflow_out_mm, 1 - 1 + (1 - cease), tolerance = 1e-6, label = engine)
    published <- groundwater_model(list(type = "cubic", kb = 1, solver = "smith"),
                                   list(ca = 0), 1)
    expect_equal(run_groundwater(published, 1, 1, engine)$groundwater_mm, smith,
                 tolerance = 1e-12, label = engine)
  }
  # Refilling within a step: from -0.5 mm with +1 mm/h the store refills after 0.5 h, then
  # routes from empty for the rest of the step by the continuous equation
  st <- power_routing(k = 1, m = 3)
  expect_equal(.extended_storage(st, -0.5, 1, 1), reference_store(0, 1, 1, 3, 0.5)[["storage"]],
               tolerance = 1e-7)
})

# Guards: underflow and the main outlet drain the store together, each down to its own outlet,
# as the continuous equation does
test_that("underflow is coupled with the main outlet", {
  # Linear outlet k = 1 /h and underflow ku = 1 h at the same level: S = 10 exp(-2 t)
  for (engine in c("auto", "r")) {
    model <- groundwater_model(list(type = "linear", kb = 1), list(ku = 1, dbu = 0), 2)
    out <- run_groundwater(model, 10, 0, engine)
    expect_equal(out$groundwater_mm, 10 * exp(-4), tolerance = 1e-6, label = engine)
    expect_equal(out$underflow_mm, (10 - 10 * exp(-4)) / 2, tolerance = 1e-6, label = engine)
    expect_equal(out$baseflow_out_mm, (10 - 10 * exp(-4)) / 2, tolerance = 1e-6, label = engine)
    expect_lt(abs(out$balance_error_mm), 1e-9)
  }
  # The threshold crossing: the underflow outlet 10 mm below the main one. Above zero
  # dS/dt = -2 S - 10, so S = 10 exp(-2 t) - 5, reaching zero at t1 = log(2) / 2; below it only
  # the underflow runs, S + 10 = 10 exp(-(t - t1)), which never reaches its outlet.
  t1 <- log(2) / 2
  end <- 10 * exp(-(10 - t1)) - 10
  main <- 5 * (1 - exp(-2 * t1)) - 5 * t1
  for (engine in c("auto", "r")) {
    model <- groundwater_model(list(type = "linear", kb = 1), list(ku = 1, dbu = 10), 10)
    out <- run_groundwater(model, 5, 0, engine)
    expect_equal(out$groundwater_mm, end, tolerance = 1e-6, label = engine)
    expect_gt(out$groundwater_mm, -10)
    expect_equal(out$baseflow_out_mm, main, tolerance = 1e-6, label = engine)
    expect_equal(out$underflow_mm, 5 - end - main, tolerance = 1e-6, label = engine)
  }
  # A quadratic main outlet with abstraction, against the independent fine-step solution
  ref <- reference_store(30, -0.5, 1 / 400, 2, 24, ku = 50, dbu = 20)
  for (engine in c("auto", "r")) {
    model <- groundwater_model(list(type = "quadratic", kb = 400), list(ku = 50, dbu = 20), 24)
    out <- run_groundwater(model, 30, 0.5 * 24, engine)
    expect_equal(out$groundwater_mm, ref[["storage"]], tolerance = 1e-6, label = engine)
    expect_equal(out$baseflow_out_mm, ref[["main"]], tolerance = 1e-6, label = engine)
    expect_equal(out$underflow_mm, ref[["under"]], tolerance = 1e-6, label = engine)
  }
})

# Guards: Smith's cubic step is an approximation that converges to the continuous solution as
# the step shrinks; the adaptive solver matches it at any step
test_that("the Smith solver converges with the step and the adaptive solver is exact", {
  exact <- reference_store(0, 1, 1, 3, 1)[["storage"]]
  expect_equal(exact, 0.823041, tolerance = 1e-6)
  smith <- power_routing(k = 1, m = 3, solver = "smith")
  expect_equal(route_step(smith, 0, 1, 1)$storage, 1)
  errors <- vapply(2^(0:7), function(n) {
    s <- 0
    for (i in seq_len(n)) s <- route_step(smith, s, 1, 1 / n)$storage
    abs(s - exact)
  }, numeric(1))
  expect_true(all(diff(errors) < 0))
  expect_lt(errors[8], 2e-3)
  adaptive <- power_routing(k = 1, m = 3)
  expect_equal(route_step(adaptive, 0, 1, 1)$storage, exact, tolerance = 1e-6)
})

# Guards: a negative spring fraction is an import, counted as a gain in the water balance
test_that("a negative spring fraction imports water and the balance closes", {
  for (engine in c("auto", "r")) {
    model <- groundwater_model(list(type = "linear", kb = 10), list(alpha_b = -0.2), 1)
    out <- run_groundwater(model, 20, rep(0, 24), engine)
    released <- 20 * exp(-(0:23) / 10) * (1 - exp(-1 / 10))
    expect_equal(out$baseflow_out_mm, 1.2 * released, tolerance = 1e-10, label = engine)
    expect_equal(out$spring_mm, -0.2 * released, tolerance = 1e-10, label = engine)
    expect_lt(max(abs(out$balance_error_mm)), 1e-9)
  }
  expect_error(groundwater_extension(linear_routing(), alpha_b = 1), "alpha_b")
})

# Guards: the lognormal inverse returns only an estimate whose storage matches, and says so when
# it cannot find one
test_that("the lognormal inverse converges or fails", {
  d <- pdmS7:::.component(list(type = "lognormal", meanlog = 4.1, sdlog = 0.8),
                          pdmS7:::.dist_registry())
  smax <- capacity_mean(d)
  for (s in c(1e-6, 0.5, 10, 0.5 * smax, 0.99 * smax, smax * (1 - 1e-9))) {
    c <- capacity_from_storage(d, s)
    expect_lte(abs(storage_from_capacity(d, c) - s), 1e-12 * max(1, s))
  }
  expect_error(.lognormal_inverse(d, 0.5 * smax, max_iter = 1L), "did not converge")
})

# Guards: kb converts to the core's coefficient k = 1 / kb with q = k S^m, so recessions follow
# their closed forms: S0 exp(-t / kb), S0 / (1 + S0 t / kb) and (S0^-2 + 2 t / kb)^(-1/2)
test_that("routing coefficients follow q = S^m / kb", {
  t <- 1:48
  cases <- list(
    list(g = list(type = "linear", kb = 24), s = 50 * exp(-t / 24)),
    list(g = list(type = "quadratic", kb = 2000), s = 50 / (1 + 50 * t / 2000)),
    list(g = list(type = "cubic", kb = 20000), s = (50^-2 + 2 * t / 20000)^-0.5)
  )
  for (case in cases) {
    for (engine in c("auto", "r")) {
      cfg <- pdm_presets("standard")
      cfg$groundwater <- case$g
      model <- pdm_from_config(cfg)
      state <- initial_state(model)
      state@soil <- 0
      state@groundwater <- 50
      old <- options(pdmS7.engine = engine)
      out <- run_pdm(model, data.frame(rain = rep(0, 48), pet = 0), state)$output
      options(old)
      expect_equal(out$groundwater_mm, case$s, tolerance = 1e-6, label = case$g$type)
    }
  }
})
