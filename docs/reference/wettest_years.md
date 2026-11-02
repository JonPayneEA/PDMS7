# Wettest water years

Ranks the water years (1 October to 30 September) of a record by their
highest observed flow and marks the `n` largest. A calibration project
holds these years back: they are left out of calibration and validation
scoring and scored once, with the test, so the record shows how the
calibration does on floods larger than those it was fitted to. This is
Klemes's (1986) differential split-sample test.

## Usage

``` r
wettest_years(time, observed, n = 2, rows = seq_along(observed), min_left = 3)
```

## Arguments

- time:

  Times of the record (POSIXct or ISO 8601 text, UTC), regularly spaced.

- observed:

  Observed flow, m3/s, aligned with `time`.

- n:

  Number of years to hold back.

- rows:

  Rows to consider, by default the whole record.

- min_left:

  Fewest counted years that must remain once `n` are held back.

## Value

A data frame with one row per counted year, wettest first: `water_year`,
`first_row`, `last_row` (within `rows`), `start`, `end`, `peak_m3s` and
`held`.

## Details

The ranking holds even where the rating is extrapolated: a rating rises
with stage, so it keeps the order of floods even when it gets their size
wrong.

A year counts only if its rows within `rows` hold at least half a year
of observed flow, so a sliver of a year at the edge of a window cannot
be held back or count towards those left.

## References

Klemes, V. (1986) Operational testing of hydrological simulation models.
Hydrological Sciences Journal 31(1), 13-24.

## Examples

``` r
time <- seq(as.POSIXct("2010-10-01", tz = "UTC"), by = 86400, length.out = 5 * 365)
set.seed(1)
flow <- rgamma(length(time), 2)
flow[400] <- 60
wettest_years(time, flow, n = 1)
#>   water_year first_row last_row                start                  end
#> 1    2011-12       366      731 2011-10-01T00:00:00Z 2012-09-30T00:00:00Z
#> 2    2010-11         1      365 2010-10-01T00:00:00Z 2011-09-30T00:00:00Z
#> 3    2012-13       732     1096 2012-10-01T00:00:00Z 2013-09-30T00:00:00Z
#> 4    2014-15      1462     1825 2014-10-01T00:00:00Z 2015-09-29T00:00:00Z
#> 5    2013-14      1097     1461 2013-10-01T00:00:00Z 2014-09-30T00:00:00Z
#>    peak_m3s  held
#> 1 60.000000  TRUE
#> 2  9.796169 FALSE
#> 3  8.112583 FALSE
#> 4  7.821749 FALSE
#> 5  7.488669 FALSE
```
