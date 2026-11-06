# ============================================================ #
# Tool:         generate_golden_events
# Description:  Write golden test files for the event functions of the C core from the R
#               reference implementation
# Flode Module: standalone; target reach.hydro
# Author:       pdmS7 contributors
# Created:      2026-11-06
# Modified:     2026-11-06 - Initial event golden files
# Tier:         3
# Inputs:       None; synthetic records from fixed seeds
# Outputs:      events_*.csv and <case>_events_*.csv in inst/golden/ (see README.md there)
# Dependencies: pdmS7
# ============================================================ #
# Usage, from the package root:
#   Rscript inst/golden/generate_golden_events.R
# Regenerate only when the event method changes, and review the diff before committing.

if (requireNamespace("pkgload", quietly = TRUE) && file.exists("DESCRIPTION")) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  library(pdmS7)
}
out_dir <- file.path("inst", "golden")
options(pdmS7.engine = "r")  # expected values come from the R reference implementation
fmt <- function(x) sprintf("%.17g", x)
write_table <- function(df, name) {
  df[] <- lapply(df, function(col) if (is.numeric(col)) fmt(col) else col)
  utils::write.csv(df, file.path(out_dir, name), row.names = FALSE, quote = FALSE)
}

# Three records: half a year hourly, four years daily, and half a year hourly with gaps in
# both rain and flow, which count as zero in the cumulative series.
record <- function(years, dt, seed, rows) {
  river <- synthetic_catchment(synthetic_rain("2010-10-01", years = years, dt = dt, seed = seed),
                               seed = seed)
  keep <- seq_len(min(rows, nrow(river$forcing)))
  list(rain = river$forcing$rain[keep], flow = river$observed[keep],
       simulated = river$true_flow[keep], area = river$truth$area_km2)
}
records <- list(
  hourly = record(1, 1, 101, 4380),
  daily = record(4, 24, 102, 1461),
  gaps = record(1, 1, 103, 4380)
)
# A long gap in flow, a short one inside the busy wet season (inside events), and a gap in rain.
records$gaps$flow[c(1000:1150, 3000:3012)] <- NaN
records$gaps$rain[2000:2005] <- NaN
steps <- c(hourly = 1, daily = 24, gaps = 1)

cases <- data.frame(case = names(records), dt = unname(steps), rain_min = 0.2 * steps^-0.5,
                    h_max = pmin(floor(150 / steps), floor((4380 - 2) / 2)),
                    area_km2 = vapply(records, function(r) r$area, numeric(1)),
                    row.names = NULL)
write_table(cases, "events_cases.csv")

for (i in seq_len(nrow(cases))) {
  name <- cases$case[i]
  r <- records[[name]]
  write_table(data.frame(rain_mm = r$rain, flow_m3s = r$flow, simulated_m3s = r$simulated),
              paste0(name, "_events_series.csv"))
  ev <- find_events(r$rain, r$flow, dt = cases$dt[i], rain_min = cases$rain_min[i],
                    max_response_h = cases$h_max[i] * cases$dt[i], area_km2 = cases$area_km2[i])
  scored <- event_scores(ev, r$simulated, r$flow)
  # Positions are 0-based, as at the C interface.
  expected <- data.frame(
    rain_start = ev$rain_start - 1, rain_end = ev$rain_end - 1, flow_start = ev$flow_start - 1,
    flow_end = ev$flow_end - 1, rain_mm = ev$rain_mm, peak_row = ev$peak_row - 1,
    peak_flow = ev$peak_flow, flow_mm = ev$flow_mm, quickflow_mm = ev$quickflow_mm,
    runoff_ratio = ev$runoff_ratio, scored[c("observed_peak", "simulated_peak", "peak_error",
                                             "timing_error_h", "volume_error", "nse")]
  )
  write_table(expected, paste0(name, "_events_expected.csv"))
  write_table(data.frame(rho = attr(ev, "response")$curve$rho), paste0(name, "_events_rho.csv"))
  write_table(data.frame(baseflow_m3s = attr(ev, "baseflow")),
              paste0(name, "_events_baseflow.csv"))
  cat(name, ":", nrow(ev), "events, response", attr(ev, "response")$response_steps, "steps\n")
}
