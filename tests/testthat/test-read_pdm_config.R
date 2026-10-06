# ============================================================ #
# Tool:         test-read_pdm_config
# Description:  Configurable PDM framework: test-read_pdm_config
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

test_that(
  "YAML builds the same model as the list configuration",
  {
    path <- tempfile(fileext = ".yml")
    on.exit(unlink(path))
    yaml::write_yaml(
      pdm_presets("standard"),
      path
    )
    expect_equal(
      read_pdm_config(path),
      pdm_presets("standard")
    )
    expect_true(
      S7::S7_inherits(
        load_pdm_model(path),
        FlodePdmModel
      )
    )
  }
)

test_that(
  "YAML rejects unknown fields and executable expressions",
  {
    path <- tempfile(fileext = ".yml")
    on.exit(unlink(path))
    writeLines("unknown: 1", path)
    expect_error(
      read_pdm_config(path),
      "unknown"
    )
    writeLines("fc: !expr 1 + 1", path)
    expect_error(
      read_pdm_config(path),
      "expr"
    )
  }
)
