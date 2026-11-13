# Read and write PDM for PCs input files

`read_pdm_inp()` reads the model of a PDM for PCs `*.inp` file into a
configuration, so a model calibrated in PDM for PCs can be run, scored
and compared with one calibrated here (see
[`compare_calibrations()`](https://jonpayneea.github.io/PDMS7/reference/compare_calibrations.md)).
`write_pdm_inp()` writes a configuration as a `*.inp` file that PDM for
PCs can load (Model \> Load Previous PDM Configuration).

## Usage

``` r
read_pdm_inp(path, dt = 0.25)

write_pdm_inp(
  config,
  path,
  title,
  event,
  stations = c(flow = "FLOW", rain = "RAIN", pet = "SIN CURVE", daily_rain = "NULL"),
  optimised = character(0)
)
```

## Arguments

- path:

  Path of the `*.inp` file.

- dt:

  Model time step, hours.

- config:

  A configuration list, or a `FlodePdmModel`.

- title:

  First line of the file: the model or catchment name.

- event:

  Start and end of the calibration event (period), as two times
  (`POSIXct`, or text such as `"2010-10-01 09:00"`, in UTC). PDM for PCs
  needs at least one.

- stations:

  Named character vector of the series names PDM for PCs will ask for:
  `flow`, `rain`, `pet` and `daily_rain`.

- optimised:

  Names, as in the file (`rainfac`, `cmax`, `kb` and so on), of the
  parameters to mark for optimisation; none by default.

## Value

`read_pdm_inp()`: a configuration list for
[`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md),
with attributes `title`, `stations`, `events` (a data frame of `start`
and `end`), `optimised` (the file's names of the parameters marked for
optimisation), `theta` (the initial soil fraction of a split model, if
given) and `notes`. `write_pdm_inp()`: the path, invisibly.

## Details

**What is read.** The parameter list (by name, so its order does not
matter), the model structure line (`loss runoff surface base tdly`), the
catchment area, the groundwater extension block (`'GW'`) with its well
datum, and, as attributes, the title, the stations, the event periods
and which parameters were marked for optimisation (`indx = 1`). Error
prediction, forecast and rating settings are not part of the simulation
model; they are noted in attribute `notes` and otherwise ignored, as are
raingauge weights: give the catchment rainfall in the forcing.

**Conventions of PDM for PCs.** These follow the manual and are applied
in both directions:

- the cubic store's `kb` in the file is the cube root of the time
  constant used (`kb` = 13 in the file is 2197 h mm^2 here);

- `k2 = 0` means two equal surface reservoirs, `k2 = k1`;

- `tdly` in the structure line is either the delay in hours or, when
  negative, the position of the `tdly` parameter in the list;

- `rainfac` is the rainfall factor `fc`, `qconst` the constant flow `qc`
  (m3/s);

- lognormal (`loss` 5) reads `cmin` and `b` as the mean and standard
  deviation of log capacity, and exponential (`loss` 6) reads `cmin` as
  the mean capacity;

- the cubic store is stepped by Smith's method, as in PDM for PCs.

**The time step is not in the file.** PDM for PCs takes it from the
model set-up, so give it as `dt` (15 minutes by default).

**Not supported**, and refused with a message rather than guessed:
several hydrological zones; demand recharge and the unrestricted split
(runoff models 2 to 4); the power distribution (`loss` 4); exponential
stores; a cubic surface store; and constant or pass-through stores
(types 0 and -1).

**To do: the exponential store.** It is a PDM option (Moore, 2007), and
pdmS7 runs, calibrates and forecasts with it, and the structure
recommendation may choose it. Its code and parameter layout in a PDM for
PCs input file are still to be confirmed, so `write_pdm_inp()` refuses
it for now. It will be added once an example file with an exponential
store has been checked.

## References

UKCEH (2022). PDM for PCs, version 3.0.3: Configuration Guide, section
2.3 and Appendix A.1.

## Examples

``` r
cfg <- pdm_presets("standard")
cfg$area_km2 <- 36.7
cfg$dt <- 0.25
path <- tempfile(fileext = ".inp")
write_pdm_inp(cfg, path, title = "Example Brook: standard PDM",
              event = c("2010-10-01 09:00", "2020-10-01 09:00"))
back <- read_pdm_inp(path, dt = 0.25)
back$groundwater
#> $type
#> [1] "cubic"
#> 
#> $kb
#> [1] 10000
#> 
#> $solver
#> [1] "smith"
#> 
```
