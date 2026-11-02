# ============================================================ #
# Tool:         read_pdm_config
# Description:  Reading and writing YAML configurations safely and exactly
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

#' Read pdm config
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param path Character scalar identifying a YAML file. Executable expressions are rejected.
#'
#' @return A validated named configuration list.
#'
#' @examples
#' read_pdm_config(system.file('config', 'standard.yml', package = 'pdmS7'))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
# Reads a YAML configuration. Two safeguards: YAML's !expr tag, which would run R code, is refused
# outright, and the configuration is built once as a model, so a file that cannot make a valid
# model fails here rather than later. Returns the list, not the model.
read_pdm_config <- function(path) {
  .check(
    is.character(path) && length(path) == 1L && !is.na(path) && file.exists(path),
    "path must identify an existing YAML file"
  )
  text <- readLines(path, warn = FALSE)
  .check(
    !any(grepl("!expr", text, fixed = TRUE)),
    "YAML !expr expressions are not permitted"
  )
  config <- yaml::yaml.load(
    paste(text, collapse = "\n"),
    eval.expr = FALSE
  )
  pdm_from_config(config)
  config
}
#' Load pdm model
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param path Character scalar identifying a YAML file. Executable expressions are rejected.
#'
#' @return A validated FlodePdmModel.
#'
#' @examples
#' load_pdm_model(system.file('config', 'standard.yml', package = 'pdmS7'))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
load_pdm_model <- function(path) pdm_from_config(read_pdm_config(path))

#' Write a PDM configuration to a YAML file
#'
#' Writes a configuration list so that [read_pdm_config()] reads back exactly the same
#' numbers. `yaml::write_yaml()` rounds to seven significant figures by default, which can
#' change a calibrated model; this function writes each number with the fewest digits that
#' reproduce it exactly.
#'
#' @param config A configuration list accepted by [pdm_from_config()].
#' @param path File to write.
#' @return `path`, invisibly.
#' @examples
#' path <- tempfile(fileext = ".yml")
#' config <- pdm_presets("standard")
#' config$fc <- 1 / 3
#' write_pdm_config(config, path)
#' identical(read_pdm_config(path)$fc, 1 / 3)
#' @export
# Writes a configuration that read_pdm_config() reads back exactly. .yaml_ready() writes each
# number with the fewest digits that reproduce it, because yaml::as.yaml() would round to seven
# significant figures and the model read back would differ from the one calibrated. The file is
# written as raw UTF-8 bytes, so line endings and encoding do not depend on the platform.
write_pdm_config <- function(config, path) {
  pdm_from_config(config)
  .check(is.character(path) && length(path) == 1L && !is.na(path), "path must be a file path")
  text <- yaml::as.yaml(.yaml_ready(config))
  writeBin(charToRaw(enc2utf8(paste0("# pdmS7 configuration\n", text))), path)
  invisible(path)
}
