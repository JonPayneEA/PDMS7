# Package index

## Building a model

Construct a PDM from components, presets or a configuration file.

- [`pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/pdm_model.md)
  : Pdm model
- [`pdm_presets()`](https://jonpayneea.github.io/PDMS7/reference/pdm_presets.md)
  : Pdm presets
- [`pdm_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pdm_from_config.md)
  : Pdm from config
- [`read_pdm_config()`](https://jonpayneea.github.io/PDMS7/reference/read_pdm_config.md)
  : Read pdm config
- [`write_pdm_config()`](https://jonpayneea.github.io/PDMS7/reference/write_pdm_config.md)
  : Write a PDM configuration to a YAML file
- [`load_pdm_model()`](https://jonpayneea.github.io/PDMS7/reference/load_pdm_model.md)
  : Load pdm model
- [`parameter_catalog()`](https://jonpayneea.github.io/PDMS7/reference/parameter_catalog.md)
  : Parameter catalog
- [`FlodePdmModel()`](https://jonpayneea.github.io/PDMS7/reference/FlodePdmModel.md)
  : Create FlodePdmModel
- [`PDMModel()`](https://jonpayneea.github.io/PDMS7/reference/PDMModel.md)
  : Compatibility alias for FlodePdmModel

## Soil moisture capacity distributions

The probability-distributed store that gives the model its name.

- [`FlodeCapacityDistribution()`](https://jonpayneea.github.io/PDMS7/reference/FlodeCapacityDistribution.md)
  : Create FlodeCapacityDistribution
- [`CapacityDistribution()`](https://jonpayneea.github.io/PDMS7/reference/CapacityDistribution.md)
  : Compatibility alias for FlodeCapacityDistribution
- [`FlodeParetoCapacity()`](https://jonpayneea.github.io/PDMS7/reference/FlodeParetoCapacity.md)
  : Create FlodeParetoCapacity
- [`ParetoCapacity()`](https://jonpayneea.github.io/PDMS7/reference/ParetoCapacity.md)
  : Compatibility alias for FlodeParetoCapacity
- [`FlodeRectangularCapacity()`](https://jonpayneea.github.io/PDMS7/reference/FlodeRectangularCapacity.md)
  : Create FlodeRectangularCapacity
- [`RectangularCapacity()`](https://jonpayneea.github.io/PDMS7/reference/RectangularCapacity.md)
  : Compatibility alias for FlodeRectangularCapacity
- [`FlodeExponentialCapacity()`](https://jonpayneea.github.io/PDMS7/reference/FlodeExponentialCapacity.md)
  : Create FlodeExponentialCapacity
- [`ExponentialCapacity()`](https://jonpayneea.github.io/PDMS7/reference/ExponentialCapacity.md)
  : Compatibility alias for FlodeExponentialCapacity
- [`FlodeTriangularCapacity()`](https://jonpayneea.github.io/PDMS7/reference/FlodeTriangularCapacity.md)
  : Create FlodeTriangularCapacity
- [`TriangularCapacity()`](https://jonpayneea.github.io/PDMS7/reference/TriangularCapacity.md)
  : Compatibility alias for FlodeTriangularCapacity
- [`FlodeLognormalCapacity()`](https://jonpayneea.github.io/PDMS7/reference/FlodeLognormalCapacity.md)
  : Create FlodeLognormalCapacity
- [`LognormalCapacity()`](https://jonpayneea.github.io/PDMS7/reference/LognormalCapacity.md)
  : Compatibility alias for FlodeLognormalCapacity
- [`capacity_cdf()`](https://jonpayneea.github.io/PDMS7/reference/capacity_cdf.md)
  : Capacity cdf
- [`capacity_pdf()`](https://jonpayneea.github.io/PDMS7/reference/capacity_pdf.md)
  : Capacity pdf
- [`capacity_mean()`](https://jonpayneea.github.io/PDMS7/reference/capacity_mean.md)
  : Capacity mean
- [`capacity_from_storage()`](https://jonpayneea.github.io/PDMS7/reference/capacity_from_storage.md)
  : Capacity from storage
- [`storage_from_capacity()`](https://jonpayneea.github.io/PDMS7/reference/storage_from_capacity.md)
  : Storage from capacity

## Recharge

Drainage from the soil store to groundwater.

- [`FlodeRecharge()`](https://jonpayneea.github.io/PDMS7/reference/FlodeRecharge.md)
  : Create FlodeRecharge
- [`Recharge()`](https://jonpayneea.github.io/PDMS7/reference/Recharge.md)
  : Compatibility alias for FlodeRecharge
- [`FlodeStandardRecharge()`](https://jonpayneea.github.io/PDMS7/reference/FlodeStandardRecharge.md)
  : Create FlodeStandardRecharge
- [`StandardRecharge()`](https://jonpayneea.github.io/PDMS7/reference/StandardRecharge.md)
  : Compatibility alias for FlodeStandardRecharge
- [`FlodeSplitRecharge()`](https://jonpayneea.github.io/PDMS7/reference/FlodeSplitRecharge.md)
  : Create FlodeSplitRecharge
- [`SplitRecharge()`](https://jonpayneea.github.io/PDMS7/reference/SplitRecharge.md)
  : Compatibility alias for FlodeSplitRecharge
- [`FlodeDemandRecharge()`](https://jonpayneea.github.io/PDMS7/reference/FlodeDemandRecharge.md)
  : Create FlodeDemandRecharge
- [`DemandRecharge()`](https://jonpayneea.github.io/PDMS7/reference/DemandRecharge.md)
  : Compatibility alias for FlodeDemandRecharge
- [`recharge_depth()`](https://jonpayneea.github.io/PDMS7/reference/recharge_depth.md)
  : Recharge depth

## Routing

Surface and groundwater stores.

- [`FlodeRouting()`](https://jonpayneea.github.io/PDMS7/reference/FlodeRouting.md)
  : Create FlodeRouting
- [`Routing()`](https://jonpayneea.github.io/PDMS7/reference/Routing.md)
  : Compatibility alias for FlodeRouting
- [`FlodeCascadeRouting()`](https://jonpayneea.github.io/PDMS7/reference/FlodeCascadeRouting.md)
  : Create FlodeCascadeRouting
- [`CascadeRouting()`](https://jonpayneea.github.io/PDMS7/reference/CascadeRouting.md)
  : Compatibility alias for FlodeCascadeRouting
- [`FlodePowerRouting()`](https://jonpayneea.github.io/PDMS7/reference/FlodePowerRouting.md)
  : Create FlodePowerRouting
- [`PowerRouting()`](https://jonpayneea.github.io/PDMS7/reference/PowerRouting.md)
  : Compatibility alias for FlodePowerRouting
- [`FlodeExponentialRouting()`](https://jonpayneea.github.io/PDMS7/reference/FlodeExponentialRouting.md)
  : Create FlodeExponentialRouting
- [`ExponentialRouting()`](https://jonpayneea.github.io/PDMS7/reference/ExponentialRouting.md)
  : Compatibility alias for FlodeExponentialRouting
- [`linear_routing()`](https://jonpayneea.github.io/PDMS7/reference/linear_routing.md)
  : Linear routing
- [`quadratic_routing()`](https://jonpayneea.github.io/PDMS7/reference/quadratic_routing.md)
  : Quadratic routing
- [`cubic_routing()`](https://jonpayneea.github.io/PDMS7/reference/cubic_routing.md)
  : Cubic routing
- [`power_routing()`](https://jonpayneea.github.io/PDMS7/reference/power_routing.md)
  : Power routing
- [`routing_flow()`](https://jonpayneea.github.io/PDMS7/reference/routing_flow.md)
  : Routing flow
- [`storage_for_flow()`](https://jonpayneea.github.io/PDMS7/reference/storage_for_flow.md)
  : Storage for flow
- [`transfer_coefficients()`](https://jonpayneea.github.io/PDMS7/reference/transfer_coefficients.md)
  : Transfer coefficients

## Running the model

States, starts and simulation.

- [`FlodePdmState()`](https://jonpayneea.github.io/PDMS7/reference/FlodePdmState.md)
  : Create FlodePdmState
- [`PDMState()`](https://jonpayneea.github.io/PDMS7/reference/PDMState.md)
  : Compatibility alias for FlodePdmState
- [`initial_state()`](https://jonpayneea.github.io/PDMS7/reference/initial_state.md)
  : Initial state
- [`initial_state_from_flow()`](https://jonpayneea.github.io/PDMS7/reference/initial_state_from_flow.md)
  : Initial state in equilibrium with an observed flow
- [`spin_up()`](https://jonpayneea.github.io/PDMS7/reference/spin_up.md)
  : Spin up
- [`run_pdm()`](https://jonpayneea.github.io/PDMS7/reference/run_pdm.md)
  : Run a forcing sequence
- [`sim_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_pdm.md)
  : Sim pdm
- [`pdm_step()`](https://jonpayneea.github.io/PDMS7/reference/pdm_step.md)
  : Pdm step
- [`soil_step()`](https://jonpayneea.github.io/PDMS7/reference/soil_step.md)
  : Soil step
- [`route_step()`](https://jonpayneea.github.io/PDMS7/reference/route_step.md)
  : Route step

## Snowpack

The PACK snow model, alone or feeding the PDM.

- [`FlodePackModel()`](https://jonpayneea.github.io/PDMS7/reference/FlodePackModel.md)
  : PACK snow model
- [`FlodePackState()`](https://jonpayneea.github.io/PDMS7/reference/FlodePackState.md)
  : PACK state including fresh-snow cover memory
- [`pack_presets()`](https://jonpayneea.github.io/PDMS7/reference/pack_presets.md)
  : PACK parameter presets
- [`pack_from_config()`](https://jonpayneea.github.io/PDMS7/reference/pack_from_config.md)
  : Build PACK from a configuration
- [`pack_step()`](https://jonpayneea.github.io/PDMS7/reference/pack_step.md)
  : Advance a PACK snow state
- [`sim_pack()`](https://jonpayneea.github.io/PDMS7/reference/sim_pack.md)
  : Simulate PACK snow
- [`sim_snow_pdm()`](https://jonpayneea.github.io/PDMS7/reference/sim_snow_pdm.md)
  : Simulate coupled PACK and PDM

## Calibration

- [`calibrate_pdm()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm.md)
  : Calibrate pdm
- [`calibrate_pdm_multi()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_pdm_multi.md)
  : Calibrate PDM or coupled snow-PDM against multiple objectives
- [`pdm_objectives()`](https://jonpayneea.github.io/PDMS7/reference/pdm_objectives.md)
  : Evaluate hydrological calibration losses
- [`pdm_scorecard()`](https://jonpayneea.github.io/PDMS7/reference/pdm_scorecard.md)
  : Score a simulation against observed flow
- [`pdm_threshold_scores()`](https://jonpayneea.github.io/PDMS7/reference/pdm_threshold_scores.md)
  : Score threshold crossings
- [`pareto_front()`](https://jonpayneea.github.io/PDMS7/reference/pareto_front.md)
  : Identify nondominated loss vectors

## Batch calibration

The same logged protocol for many basins, resumable after any
interruption.

- [`calibrate_batch()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  [`batch_status()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  [`batch_results()`](https://jonpayneea.github.io/PDMS7/reference/calibrate_batch.md)
  : Calibrate many basins in one batch

## Comparing structures

Calibrate several model structures alike and rank them on held-out data.

- [`compare_structures()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md)
  [`structure_comparison()`](https://jonpayneea.github.io/PDMS7/reference/compare_structures.md)
  : Compare model structures
- [`structure_set()`](https://jonpayneea.github.io/PDMS7/reference/structure_set.md)
  : Model structures to compare
- [`calibration_bounds()`](https://jonpayneea.github.io/PDMS7/reference/calibration_bounds.md)
  : Calibration bounds for a model structure

## Calibration log

An append-only, tamper-evident record of manual and automatic
calibration.

- [`start_calibration_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`register_data()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`select_structure()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`preview_trial()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`log_trial()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`log_auto_calibration()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`log_note()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`propose_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`validate_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`test_candidate()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`sign_off_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  [`reopen_project()`](https://jonpayneea.github.io/PDMS7/reference/calibration_log.md)
  : Calibration log
- [`read_project()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  [`project_trials()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  [`read_entry()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  [`read_projects()`](https://jonpayneea.github.io/PDMS7/reference/read_project.md)
  : Read a calibration project
- [`verify_project()`](https://jonpayneea.github.io/PDMS7/reference/verify_project.md)
  : Verify a calibration project
- [`build_report()`](https://jonpayneea.github.io/PDMS7/reference/build_report.md)
  : Build the calibration report
- [`calibration_app()`](https://jonpayneea.github.io/PDMS7/reference/calibration_app.md)
  : Calibration app

## Run log

An opt-in record of every model run, checked against signed-off
calibrations.

- [`read_run_log()`](https://jonpayneea.github.io/PDMS7/reference/read_run_log.md)
  : Read the run log
- [`approved_configurations()`](https://jonpayneea.github.io/PDMS7/reference/approved_configurations.md)
  : List the configurations approved in a register
- [`pdm_fingerprint()`](https://jonpayneea.github.io/PDMS7/reference/pdm_fingerprint.md)
  : Fingerprint a model configuration

## Forecast updating

State correction and ARMA error prediction (Moore 2007, Eq. 28-42).

- [`FlodeStateUpdater()`](https://jonpayneea.github.io/PDMS7/reference/FlodeStateUpdater.md)
  : Create FlodeStateUpdater
- [`StateUpdater()`](https://jonpayneea.github.io/PDMS7/reference/StateUpdater.md)
  : Compatibility alias for FlodeStateUpdater
- [`state_updater()`](https://jonpayneea.github.io/PDMS7/reference/state_updater.md)
  : State updater
- [`correct_state()`](https://jonpayneea.github.io/PDMS7/reference/correct_state.md)
  : Correct state
- [`FlodeErrorUpdater()`](https://jonpayneea.github.io/PDMS7/reference/FlodeErrorUpdater.md)
  : Create FlodeErrorUpdater
- [`ErrorUpdater()`](https://jonpayneea.github.io/PDMS7/reference/ErrorUpdater.md)
  : Compatibility alias for FlodeErrorUpdater
- [`error_updater()`](https://jonpayneea.github.io/PDMS7/reference/error_updater.md)
  : Error updater
- [`fit_error_updater()`](https://jonpayneea.github.io/PDMS7/reference/fit_error_updater.md)
  : Fit error updater
- [`update_forecast()`](https://jonpayneea.github.io/PDMS7/reference/update_forecast.md)
  : Update forecast
