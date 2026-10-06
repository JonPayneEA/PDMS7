# ============================================================ #
# Tool:         demo
# Description:  Configurable PDM framework: demo
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

library(pdmS7)
config <- pdm_presets("standard")
config$area_km2 <- 44
model <- pdm_from_config(config)
set.seed(7)
forcing <- data.frame(
  time = seq(
    as.POSIXct("2000-01-01", tz = "UTC"),
    by = "hour", length.out = 240
  ),
  rain = ifelse(
    runif(240) <
      0.18, rexp(240, 1 / 3),
    0
  ),
  pet = rep(0.04, 240)
)
run <- run_pdm(model, forcing)
logger::log_info("Maximum balance error: {run$water_balance[[2]]} mm")

plot(run$output$time, run$output$q_m3s, type = "l", xlab = "Time", ylab = "Mean flow (m3/s)")
# Restart without losing routing or delay memory:
first <- run_pdm(model, forcing[1:120, ])
second <- run_pdm(model, forcing[121:240, ], state = first$state)
stopifnot(isTRUE(all.equal(second$output$q_m3s, run$output$q_m3s[121:240])))
# Save configuration and restart state using base R: saveRDS(list(config=config,
# state=run$state), 'checkpoint.rds')

# Reproduce the Figure 5 runoff-production family (before routing).
d <- ParetoCapacity(cmin = 0, cmax = 140, b = 0.4)
net <- seq(0, 250, by = 2)
curves <- vapply(
  seq(0, 100, by = 20),
  function(s) {
    vapply(
      net, function(p) soil_step(d, s, p)$runoff,
      numeric(1)
    )
  }, numeric(length(net))
)
matplot(net, curves, type = "l", lty = 1, xlab = "Net rain (mm)", ylab = "Direct runoff (mm)")
legend(
  "topleft",
  legend = paste("Initial storage", seq(0, 100, by = 20)),
  col = 1:6, lty = 1
)

# Calibration, supplying real gauged observations in m3/s in actual use: fit <-
# calibrate_pdm(config, forcing, observed, lower = c(distribution.b=0.05,
# surface.k1=0.1), upper = c(distribution.b=2, surface.k1=10), warmup=48)

# External forecast correction; ar = -phi in the notation of the paper.
u <- error_updater(ar = 0.7)
updated <- update_forecast(
  u, c(2, 2.5, 3),
  c(1.8, 2.2, 2.6),
  c(2.7, 2.8)
)
logger::log_info("Produced {length(updated$forecast)} updated forecast values")
