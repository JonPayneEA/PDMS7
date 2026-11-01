// ============================================================ //
// Tool:         pdm_engine
// Description:  R binding for the PDM core (pdm_core.h) through cpp11
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-10-31 - Interface version 2 parameter layout
// Tier:         3
// Inputs:       Rain and PET depths in mm per interval; parameters in R/engine.R order
// Outputs:      Flux columns equal to pdm_step() to rounding; final state vector
// Dependencies: cpp11 (header only, build time); pdm_core
// ============================================================ //
//
// The model arithmetic lives in pdm_core.c, plain C99 with no R dependency. This file only
// converts between R vectors and the C interface, and turns error codes into R errors.

#include <cpp11.hpp>

#include <string>
#include <vector>

#include "pdm_core.h"

using cpp11::doubles;

namespace {

void fill_route(pdm_route& r, const doubles& par, int at) {
  r.type = static_cast<int32_t>(par[at]);
  r.smith = static_cast<int32_t>(par[at + 1]);
  r.k1 = par[at + 2];
  r.k2 = par[at + 3];
  r.k = par[at + 4];
  r.m = par[at + 5];
  r.rtol = par[at + 6];
  r.atol = par[at + 7];
  r.a = par[at + 8];
  r.gamma = par[at + 9];
}

}  // namespace

// Runs the time loop. par holds the 40 fields of pdm_params in struct order, as built by
// .engine_params() in R/engine.R. state uses the layout documented in pdm_core.h. With
// full = FALSE only q_m3s and q_end_m3s are filled; the flux columns are returned empty.
[[cpp11::register]]
cpp11::list pdm_engine_run(doubles rain, doubles pet, doubles par, doubles state, bool full) {
  if (par.size() != 40) cpp11::stop("pdm_engine_run expects 40 parameters");
  if (rain.size() != pet.size()) cpp11::stop("rain and pet must have equal length");
  pdm_params p;
  p.distribution = static_cast<int32_t>(par[0]);
  p.recharge = static_cast<int32_t>(par[1]);
  p.cmin = par[2]; p.cmax = par[3]; p.b = par[4]; p.mean = par[5];
  p.meanlog = par[6]; p.sdlog = par[7];
  p.kg = par[8]; p.bg = par[9]; p.st = par[10];
  p.alpha = par[11]; p.beta = par[12]; p.qsat = par[13];
  fill_route(p.surface, par, 14);
  fill_route(p.groundwater, par, 24);
  p.be = par[34]; p.fc = par[35]; p.td = par[36]; p.qc = par[37]; p.area_km2 = par[38];
  p.dt = par[39];

  const int64_t n = static_cast<int64_t>(rain.size());
  std::vector<double> rain_v(rain.begin(), rain.end());
  std::vector<double> pet_v(pet.begin(), pet.end());
  std::vector<double> state_v(state.begin(), state.end());
  std::vector<double> q(n), q_end(n);
  std::vector<double> fluxes(full ? static_cast<std::size_t>(n) * PDM_N_FLUX : 0);
  char message[512];

  int32_t code = pdm_run(&p, rain_v.data(), pet_v.data(), n, state_v.data(),
                         static_cast<int64_t>(state_v.size()), q.data(), q_end.data(),
                         full ? fluxes.data() : nullptr, message, sizeof(message));
  if (code != PDM_OK) cpp11::stop("%s", message);

  cpp11::writable::list columns(PDM_N_FLUX);
  for (int j = 0; j < PDM_N_FLUX; ++j) {
    if (full) {
      auto first = fluxes.begin() + static_cast<std::ptrdiff_t>(j) * n;
      columns[j] = cpp11::writable::doubles(first, first + n);
    } else {
      columns[j] = cpp11::writable::doubles(static_cast<R_xlen_t>(0));
    }
  }
  using namespace cpp11::literals;
  return cpp11::writable::list({
    "columns"_nm = columns,
    "q_m3s"_nm = cpp11::writable::doubles(q.begin(), q.end()),
    "q_end_m3s"_nm = cpp11::writable::doubles(q_end.begin(), q_end.end()),
    "state"_nm = cpp11::writable::doubles(state_v.begin(), state_v.end())
  });
}

// Runs the PACK snowpack. par holds the 12 fields of pdm_pack_params in struct order, as built
// by .pack_engine_params() in R/engine.R; state holds the five PACK state values.
[[cpp11::register]]
cpp11::list pack_engine_run(doubles precipitation, doubles temperature, doubles par,
                            doubles state, double dt) {
  if (par.size() != 12) cpp11::stop("pack_engine_run expects 12 parameters");
  if (state.size() != PDM_PACK_STATE_LENGTH) cpp11::stop("PACK state must hold 5 values");
  if (precipitation.size() != temperature.size()) {
    cpp11::stop("precipitation and temperature must have equal length");
  }
  pdm_pack_params p;
  p.precipitation_factor = par[0]; p.lower_rate_h = par[1]; p.upper_rate_h = par[2];
  p.retention_fraction = par[3]; p.melt_factor_mmh_c = par[4]; p.adc_alpha = par[5];
  p.adc_depth_mm = par[6]; p.melt_threshold_c = par[7]; p.snow_threshold_c = par[8];
  p.drain_threshold_c = par[9]; p.max_step_min = par[10];
  p.areal_depletion = par[11] != 0 ? 1 : 0;
  p.reserved = 0;

  const int64_t n = static_cast<int64_t>(precipitation.size());
  std::vector<double> precip_v(precipitation.begin(), precipitation.end());
  std::vector<double> temp_v(temperature.begin(), temperature.end());
  std::vector<double> state_v(state.begin(), state.end());
  std::vector<double> effective(n);
  std::vector<double> fluxes(static_cast<std::size_t>(n) * PDM_PACK_N_FLUX);
  char message[512];
  int32_t code = pdm_pack_run(&p, precip_v.data(), temp_v.data(), n, dt, state_v.data(),
                              effective.data(), fluxes.data(), message, sizeof(message));
  if (code != PDM_OK) cpp11::stop("%s", message);

  cpp11::writable::list columns(PDM_PACK_N_FLUX);
  for (int j = 0; j < PDM_PACK_N_FLUX; ++j) {
    auto first = fluxes.begin() + static_cast<std::ptrdiff_t>(j) * n;
    columns[j] = cpp11::writable::doubles(first, first + n);
  }
  using namespace cpp11::literals;
  return cpp11::writable::list({
    "columns"_nm = columns,
    "state"_nm = cpp11::writable::doubles(state_v.begin(), state_v.end())
  });
}
