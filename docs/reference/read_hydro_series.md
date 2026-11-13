# Read a hydrometric series from a CSV file

Reads one series of rain, evaporation or flow from the layouts
hydrometric exports use:

## Usage

``` r
read_hydro_series(
  file,
  value_col = NULL,
  time_col = NULL,
  time_formats = .time_formats,
  tz = "UTC",
  na_strings = c("", "NA", "NaN", "-", "---", "-9999")
)
```

## Arguments

- file:

  Path of the CSV file.

- value_col:

  Name of the value column; by default the last numeric column.

- time_col:

  Name of the time column, or of a date and a time column; by default
  found.

- time_formats:

  Formats to try, in order; the first that reads 99% of the times is
  used.

- tz:

  Time zone of the times in the file. EA telemetry is in GMT all year:
  `"UTC"`.

- na_strings:

  Strings read as missing.

## Value

A `pdm_hydro_series`: a data frame of `time` (POSIXct, UTC) and `value`,
with the file, the columns used and the median step in minutes as
attribute `source`.

## Details

- **Split date columns**: year, month and day columns, with hour, minute
  and second if present, in any of their usual spellings (`hour` or
  `hours`, `min` or `minute`).

- **One time column**, or a date column and a time column side by side,
  in any of the common formats (`2021-03-01 09:15`, `01/03/2021 09:15`,
  ISO 8601 and others).

The value is the last numeric column unless named. Times are read in
`tz` and returned in UTC. Rows whose time cannot be read are dropped,
and a file whose timestamps repeat is refused: repeats mean a time
column was missed, and keeping one value per time would calibrate on a
fraction of the record.

## See also

[`align_series()`](https://jonpayneea.github.io/PDMS7/reference/align_series.md),
[`check_inputs()`](https://jonpayneea.github.io/PDMS7/reference/check_inputs.md)

## Examples

``` r
f <- tempfile(fileext = ".csv")
writeLines(c("year,month,day,hour,minute,flow", "2021,3,1,9,0,1.2", "2021,3,1,9,15,1.3"), f)
read_hydro_series(f)
#> Hydrometric series from file5e9752db148.csv: 2 rows, 2021-03-01 09:00 to 2021-03-01 09:15, step 15 min, 0 missing
#> Columns used: time year + month + day + hour + minute, value flow
```
