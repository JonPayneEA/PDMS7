# Plain Markdown guides

These are ordinary `.md` files. Read them directly in a Markdown viewer or your
version-control workspace; no R Markdown rendering, pkgdown or renv is needed.
The equations use standard dollar-delimited LaTeX, so visual maths rendering
depends on your viewer. All diagram and chart images are included in `figures/`.

1. [PDM explained](pdm-explained.md): functions, distributions, water accounting,
   recharge, routing equations and a short simulation.
2. [PACK snowpack explained](snowpack-explained.md): dry/wet stores, melt,
   drainage, partial cover, parameter defaults and numerical assumptions.
3. [Example workflow](example-workflow.md): synthetic inputs, coupled simulation,
   multi-objective calibration, held-out validation and saved-state restart.

Code blocks contain executed examples and their recorded outputs. The original
executable `.Rmd` sources remain in `../../vignettes/` for reproducible package
vignette builds; these plain Markdown copies do not require a build to read.

## Where the PACK implementation lives

| File, relative to the package root | Contents |
|---|---|
| `R/pack_model.R` | S7 PACK model/state classes, presets, configuration and cover calculation |
| `R/pack_step.R` | Snow partition, accumulation, melt and drainage accounting |
| `R/sim_pack.R` | `sim_pack()` and coupled `sim_snow_pdm()` simulation/restart |
| `inst/config/pack.yml` | Image defaults and separate report-typical parameter set |
| `tests/testthat/test-pack.R` | Snow accounting, conservation and restart tests |

The image preset uses explicitly assumed hourly units; confirm these before
operational use. The implementation and source interpretations are also described
in [the snow model notes](../snow-model.md).
