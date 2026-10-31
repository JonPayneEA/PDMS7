# ============================================================ #
# Tool:         generate_golden
# Description:  Write golden test files for the PDM core from the R reference loop
# Flode Module: standalone; target reach.hydro
# Author:       Claude Code (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-31
# Modified:     2026-10-31 - Initial golden file generator
# Tier:         3
# Inputs:       None; fixed synthetic forcing and parameter sets
# Outputs:      CSV files in inst/golden/ (see README.md there)
# Dependencies: pdmS7
# ============================================================ #
# Usage, from the package root:
#   Rscript inst/golden/generate_golden.R
# Regenerate only when the model equations change, and review the diff before committing.

if (requireNamespace("pkgload", quietly = TRUE) && file.exists("DESCRIPTION")) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  library(pdmS7)
}
out_dir <- file.path("inst", "golden")
options(pdmS7.engine = "r")  # expected values come from the R reference loop
fmt <- function(x) sprintf("%.17g", x)
write_table <- function(df, name) {
  df[] <- lapply(df, function(col) if (is.numeric(col)) fmt(col) else col)
  utils::write.csv(df, file.path(out_dir, name), row.names = FALSE, quote = FALSE)
}

# Forcing: dry spells, ordinary rain and two large storms that saturate the soil store.
set.seed(20261031)
n <- 150L
rain <- ifelse(stats::runif(n) < 0.35, stats::rgamma(n, shape = 0.6, scale = 6), 0)
rain[c(30, 31, 32)] <- c(60, 120, 80)
rain[100] <- 250
pet <- pmax(0, 0.15 + 0.1 * sin(seq_len(n) / 12))
write_table(data.frame(rain_mm = rain, pet_mm = pet), "forcing.csv")

# Column names and order follow pdm_params in src/pdm_core.h; state arrays follow its layout.
model_params <- function(model) pdmS7:::.engine_params(model)
pack_state <- function(state) pdmS7:::.engine_pack_state(state)

cases <- list(
  default = list(model = pdm_model(), fraction = 0.5),
  smith = list(model = pdm_model(groundwater = cubic_routing(solver = "smith")),
               fraction = 0.5),
  quarter_hour_delay = list(model = pdm_model(dt = 0.25, td = 1.1, area_km2 = 44, qc = 0.3),
                            fraction = 0.3),
  daily = list(model = pdm_model(dt = 24, area_km2 = 100), fraction = 0.6),
  varied = list(
    model = pdm_model(
      distribution = FlodeParetoCapacity(cmin = 20, cmax = 300, b = 0.9),
      recharge = FlodeStandardRecharge(kg = 9000, bg = 2.5, st = 30),
      surface = FlodeCascadeRouting(k1 = 3, k2 = 3.000001),
      groundwater = power_routing(k = 1 / 500, m = 2.5), be = 2, fc = 1.2
    ),
    fraction = 0.8
  ),
  linear = list(model = pdm_model(groundwater = linear_routing(30)), fraction = 0.5),
  quadratic = list(model = pdm_model(groundwater = quadratic_routing(300)), fraction = 0.5),
  point_mass = list(model = pdm_model(distribution = FlodeParetoCapacity(0, 140, 0)),
                    fraction = 0.4),
  custom_state = list(model = pdm_model(td = 2.5), fraction = 0.9,
                      surface = c(3, 4), groundwater = 20),
  rectangular = list(
    model = pdm_model(distribution = FlodeRectangularCapacity(cmin = 0.4, cmax = 170.7)),
    fraction = 0.5
  ),
  exponential_capacity = list(
    model = pdm_model(distribution = FlodeExponentialCapacity(mean = 110)), fraction = 0.7
  ),
  split = list(model = pdm_model(recharge = FlodeSplitRecharge(alpha = 0.7)), fraction = 0.5),
  demand_power = list(
    model = pdm_model(recharge = FlodeDemandRecharge(alpha = 0.5, beta = 1.5, qsat = 0.5)),
    fraction = 0.6, groundwater = 40
  ),
  demand_exponential = list(
    model = pdm_model(
      recharge = FlodeDemandRecharge(alpha = 0.4, beta = 2, qsat = 0.3),
      groundwater = FlodeExponentialRouting(a = 0.02, gamma = -2)
    ),
    fraction = 0.9, groundwater = 150
  ),
  exponential_routes = list(
    model = pdm_model(
      surface = FlodeExponentialRouting(a = 0.05, gamma = -5),
      groundwater = FlodeExponentialRouting(a = 0.02, gamma = -8)
    ),
    fraction = 0.5, surface = -30, groundwater = -60
  ),
  power_surface = list(model = pdm_model(surface = power_routing(k = 0.01, m = 1.7)),
                       fraction = 0.5),
  smith_surface = list(
    model = pdm_model(surface = power_routing(k = 1e-3, m = 3, solver = "smith")),
    fraction = 0.5
  ),
  cascade_groundwater = list(
    model = pdm_model(groundwater = FlodeCascadeRouting(k1 = 30, k2 = 200)), fraction = 0.5,
    groundwater = c(10, 25)
  )
)

rows <- list()
for (name in names(cases)) {
  case <- cases[[name]]
  state <- initial_state(case$model, case$fraction, surface = case$surface,
                         groundwater = case$groundwater)
  result <- run_pdm(case$model, data.frame(rain = rain, pet = pet), state)
  write_table(data.frame(value = pack_state(state)), paste0(name, "_initial_state.csv"))
  write_table(data.frame(value = pack_state(result$state)), paste0(name, "_final_state.csv"))
  write_table(result$output, paste0(name, "_fluxes.csv"))
  rows[[name]] <- data.frame(case = name, t(model_params(case$model)), check.names = FALSE)
}
write_table(do.call(rbind, rows), "cases.csv")

# Invalid parameter sets: every binding must return PDM_ERR_ARGUMENT (1) for each.
base <- model_params(pdm_model())
invalid <- function(reason, ...) {
  p <- base
  changes <- list(...)
  p[names(changes)] <- unlist(changes)
  data.frame(case = reason, t(p), expected_code = 1L, check.names = FALSE)
}
write_table(
  rbind(
    invalid("kg_zero", kg = 0),
    invalid("cmax_below_cmin", cmin = 50, cmax = 40),
    invalid("negative_b", b = -0.1),
    invalid("smith_not_cubic", groundwater.m = 2.5, groundwater.smith = 1),
    invalid("st_above_smax", st = 500),
    invalid("dt_zero", dt = 0),
    invalid("area_negative", area_km2 = -1),
    invalid("rtol_negative", groundwater.rtol = -1e-8),
    invalid("unknown_distribution", distribution = 7),
    invalid("exponential_mean_zero", distribution = 2, cmin = 0, cmax = 0, b = 0, mean = 0),
    invalid("split_alpha_above_one", recharge = 1, kg = 0, bg = 0, alpha = 1.5),
    invalid("demand_cascade_groundwater", recharge = 2, kg = 0, bg = 0, alpha = 0.5, beta = 1,
            qsat = 0.5, groundwater.type = 0, groundwater.k = 0, groundwater.m = 0,
            groundwater.rtol = 0, groundwater.atol = 0, groundwater.k1 = 30, groundwater.k2 = 200),
    invalid("exponential_route_a_zero", surface.type = 2, surface.k1 = 0, surface.k2 = 0,
            surface.a = 0, surface.gamma = -5)
  ),
  "invalid_cases.csv"
)
cat("Golden files written to", normalizePath(out_dir), "\n")
