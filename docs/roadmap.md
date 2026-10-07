# Future extensions

Deferred at the user’s request:

- **River-network routing:** reach travel times, tributary assembly,
  reservoirs, conservative transfers and catchment identifiers. Existing
  within-catchment surface/groundwater routing remains available.
- **Additional state assimilation:** uncertainty-aware snow/soil/routing
  updates, ensemble filters, observation operators and explicit
  assimilation water budgets. The earlier PDM state-correction and
  error-updating APIs remain unchanged; the PACK report’s survey-based
  state updating is not implemented in this release.

Further operational extensions: versioned checkpoints, configuration
fingerprints, forcing QA policies, forecast-cycle orchestration and
uncertainty ensembles. Further scientific work: event-based peak timing
objectives, evolutionary Pareto search, abstractions/returns and
multi-zone snow/catchment models. Each requires its own acceptance
criteria, conservation tests and independent field validation.
