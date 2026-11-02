# ============================================================ #
# Tool:         zzz
# Description:  Configurable PDM framework: zzz
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# S7 methods defined in this package for generics in other packages (such as print) must be
# registered when the namespace loads, or they are silently ignored.
.onLoad <- function(libname, pkgname) S7::methods_register()

# Package-level imports for roxygen: all of S7, and data.table() for building tables.
#' @import S7
#' @importFrom data.table data.table
NULL
