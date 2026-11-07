# Gridded H19 radar for merging with gauges

H19 radar comes as daily NetCDF files, each holding that day's 15-minute
accumulations on British National Grid, in year and month folders.
Sixteen years of it will not fit in memory at once. `h19_radar()`
indexes the files (the time of every layer in every file), crops them to
an extent around the catchment and its gauges, and returns a reader that
gives one step's grid when asked, loading each daily file once as the
steps are read in order. Pass its `radar` and `grid` to
[`merge_rainfall()`](https://jonpayneea.github.io/PDMS7/reference/merge_rainfall.md).

## Usage

``` r
h19_radar(files, extent, varname = NULL, fallback_crs = "EPSG:27700")
```

## Arguments

- files:

  Paths of the daily NetCDF files, in any order; they are sorted by
  time.

- extent:

  Numeric `c(xmin, xmax, ymin, ymax)` in British National Grid metres.

- varname:

  Name of the radar variable; by default found in each file among the
  H19 names.

- fallback_crs:

  Coordinate reference system assumed when a file does not state one.

## Value

A list of class `pdm_h19` with `grid` (cell-centre `x` and `y`, both
increasing), `time` (the time of every step, POSIXct in UTC), `radar` (a
function of the step number returning that step's grid, mm, as a matrix
of `length(grid$x)` rows by `length(grid$y)` columns) and `index` (the
file and layer of every step).

## Details

**Variable names.** The archive uses `"radar rain-accum H19"` for 2010
to 2019 and `"rainfall_radar_amount"` from 2021. By default each file's
variable is found among these; name another with `varname`.

**Times** are read from each file's `time` variable and its units, such
as `"minutes since 1970-01-01 00:00:00"`, in UTC. Check whether they
mark the start or the end of each accumulation, and align the gauges to
match: an hour's offset moves every peak.

**Extent.** Crop to a box that holds the catchment and the gauges used
with it, with a margin: the merged field needs radar at every gauge.
Cells with no radar value are `NA`, and a merged step that needs one is
`NA`.

## See also

[`merge_rainfall()`](https://jonpayneea.github.io/PDMS7/reference/merge_rainfall.md),
[`catchment_mask()`](https://jonpayneea.github.io/PDMS7/reference/merge_rainfall.md)

## Examples

``` r
if (FALSE) { # \dontrun{
files <- list.files("F:/.../01_H19", pattern = "\\.nc$", recursive = TRUE, full.names = TRUE)
h19 <- h19_radar(files, extent = c(290000, 330000, 120000, 160000))
mask <- catchment_mask(h19$grid$x, h19$grid$y, boundary)
merged <- merge_rainfall(gauges, gauge_rain, h19$grid, mask, radar = h19$radar,
                         method = "conditional")
} # }
```
