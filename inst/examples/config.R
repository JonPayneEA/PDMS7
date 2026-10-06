# ============================================================ #
# Tool:         config
# Description:  Configurable PDM framework: config
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# Every number except the Figure 5 Pareto triplet is illustrative, not calibrated.
config <- list(
  distribution = list(type = "pareto", cmin = 0, cmax = 140, b = 0.4),
  recharge = list(type = "standard", kg = 24, bg = 1, st = 0),
  surface = list(type = "cascade", k1 = 2, k2 = 4),
  groundwater = list(type = "cubic", kb = 10000, solver = "adaptive"),
  be = 1, fc = 1, td = 0, qc = 0, area_km2 = 44, dt = 1
)
# Other choices: pdm_presets(); parameter definitions: parameter_catalog().  All 5
# distributions and all 3 recharge options are available through config.
