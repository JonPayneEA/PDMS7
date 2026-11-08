# Builds the demo project for the screenshots in vignettes/app-events.Rmd: a synthetic
# catchment calibrated in three stages from the standard preset with no time delay, which
# leaves the largest peaks low and early. Run from this folder: Rscript build.R
suppressMessages(library(pdmS7))
options(pdmS7.user = "A Hydrologist", pdmS7.role = "custodian")
rain <- synthetic_rain("2019-10-01", years = 4, dt = 1, seed = 11)
forcing <- data.frame(time = rain$time, rain = rain$rain, pet = rain$pet)
truth <- pdm_presets("standard")
truth$area_km2 <- 25
truth$td <- 3
model <- pdm_from_config(truth)
flow <- run_pdm(model, forcing, initial_state_from_flow(model, 0.5, 0.7))$output$q_m3s
unlink("demo-brook", recursive = TRUE)
start <- pdm_presets("standard")
start$area_km2 <- 25
calibrate_project("demo-brook", forcing, flow, area_km2 = 25, catchment = "Demo Brook",
                  gauge = "Demo Bridge", calibration = c("2020-04-01", "2022-03-31 23:00"),
                  validation = c("2022-04-01", "2023-09-30 23:00"), structure = start,
                  starts = 2L, control = list(maxit = 15L), wettest_years = 0)
