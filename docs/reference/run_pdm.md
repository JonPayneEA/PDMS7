# Run a forcing sequence

Run a forcing sequence

## Usage

``` r
run_pdm(model, forcing, state = initial_state(model))
```

## Arguments

- model:

  A FlodePdmModel compatible with the supplied state.

- forcing:

  Data frame with rain and pet interval depths in mm and optional
  POSIXct time.

- state:

  A compatible FlodePdmState; NULL in sim_pdm initializes the model.

## Value

A list containing output, final state, initial state, model and water
balance.
