// ============================================================ //
// Tool:         pdm_engine
// Description:  R binding for the PDM core (pdm_core.h) through cpp11
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-10-31 - Reduced to a thin wrapper over the C interface in pdm_core.h
// Tier:         3
// Inputs:       Rain and PET depths in mm per interval; parameters in R/engine.R order
// Outputs:      Flux columns equal to pdm_step() to rounding; final state vector
// Dependencies: cpp11 (header only, build time); pdm_core
// ============================================================ //
//
// The model arithmetic lives in pdm_core.cpp, which has no R dependency. This file only
// converts between R vectors and the C interface, and turns error codes into R errors.

#include <cpp11.hpp>

#include <string>
#include <vector>

#include "pdm_core.h"

using cpp11::doubles;

// Runs the time loop. par holds, in order: cmin, cmax, b, kg, bg, st, k1, k2, k, m, rtol,
// atol, be, fc, td, qc, area_km2, dt, smith (0 or 1). state uses the layout documented in
// pdm_core.h. With full = FALSE only q_m3s and q_end_m3s are filled; the flux columns are
// returned empty.
[[cpp11::register]]
cpp11::list pdm_engine_run(doubles rain, doubles pet, doubles par, doubles state, bool full) {
  if (par.size() != 19) cpp11::stop("pdm_engine_run expects 19 parameters");
  if (rain.size() != pet.size()) cpp11::stop("rain and pet must have equal length");
  pdm_params p;
  p.cmin = par[0]; p.cmax = par[1]; p.b = par[2]; p.kg = par[3]; p.bg = par[4];
  p.st = par[5]; p.k1 = par[6]; p.k2 = par[7]; p.k = par[8]; p.m = par[9];
  p.rtol = par[10]; p.atol = par[11]; p.be = par[12]; p.fc = par[13]; p.td = par[14];
  p.qc = par[15]; p.area_km2 = par[16]; p.dt = par[17];
  p.smith = par[18] != 0 ? 1 : 0;
  p.reserved = 0;

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
