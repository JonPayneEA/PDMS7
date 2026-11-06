// ============================================================ //
// Tool:         dmca
// Description:  R binding for the event functions of the C core (pdm_core.h) through cpp11
// Flode Module: standalone; target reach.hydro
// Author:       pdmS7 contributors
// Created:      2026-11-06
// Modified:     2026-11-06 - Bind pdm_dmca_rho, pdm_find_events, pdm_event_summary and
//                            pdm_event_scores
// Tier:         3
// Inputs:       Rain (mm per step), flow, events as 1-based positions from R
// Outputs:      The correlation curve; events; event totals; event scores
// Dependencies: cpp11 (header only, build time); pdm_core
// ============================================================ //
//
// The arithmetic lives in pdm_core.c, plain C99 with no R dependency, so Python, Scala and
// other languages share it. This file only converts between R vectors and the C interface:
// R positions are 1-based, the core's 0-based. R/events.R keeps the R reference
// implementation the tests compare against.

#include <cpp11.hpp>

#include <string>
#include <vector>

#include "pdm_core.h"

using cpp11::doubles;

namespace {

void stop_on(int32_t code, const std::vector<char>& msg) {
  if (code != PDM_OK) cpp11::stop("%s", msg.data());
}

// Events as an n x 4 matrix of 1-based positions (doubles, as R passes them) to the core's
// row-major 0-based int64 layout.
std::vector<int64_t> events_in(const doubles& events) {
  const R_xlen_t n = events.size() / 4;
  std::vector<int64_t> out(4 * n);
  for (R_xlen_t i = 0; i < n; ++i) {
    for (R_xlen_t j = 0; j < 4; ++j) {
      out[4 * i + j] = static_cast<int64_t>(events[i + j * n]) - 1;
    }
  }
  return out;
}

}  // namespace

[[cpp11::register]]
doubles dmca_rho(doubles rain, doubles flow, int h_max) {
  std::vector<char> msg(512, '\0');
  cpp11::writable::doubles rho(h_max);
  int32_t code = pdm_dmca_rho(REAL(rain), REAL(flow), rain.size(), h_max, REAL(rho),
                              msg.data(), static_cast<int64_t>(msg.size()));
  stop_on(code, msg);
  return rho;
}

[[cpp11::register]]
cpp11::list find_events_engine(doubles rain, doubles flow, double dt, double rain_min,
                               int h_max) {
  std::vector<char> msg(512, '\0');
  const int64_t n = rain.size();
  const int64_t capacity = n / 2 + 1;
  std::vector<int64_t> events(4 * capacity);
  int32_t steps = 0;
  int64_t count = 0;
  cpp11::writable::doubles rho(h_max);
  int32_t code = pdm_find_events(REAL(rain), REAL(flow), n, dt, rain_min, h_max, &steps,
                                 REAL(rho), capacity, &count, events.data(), msg.data(),
                                 static_cast<int64_t>(msg.size()));
  stop_on(code, msg);
  // Column-major n_events x 4 matrix of 1-based positions.
  cpp11::writable::doubles out(4 * count);
  for (int64_t i = 0; i < count; ++i) {
    for (int64_t j = 0; j < 4; ++j) {
      out[i + j * count] = static_cast<double>(events[4 * i + j] + 1);
    }
  }
  using namespace cpp11::literals;
  return cpp11::writable::list({"response_steps"_nm = steps, "rho"_nm = rho, "events"_nm = out});
}

[[cpp11::register]]
cpp11::list event_summary_engine(doubles rain, doubles flow, double dt, double area_km2,
                                 doubles events) {
  std::vector<char> msg(512, '\0');
  const int64_t n = rain.size();
  std::vector<int64_t> ev = events_in(events);
  const int64_t count = static_cast<int64_t>(ev.size() / 4);
  std::vector<double> summary(6 * count);
  cpp11::writable::doubles baseflow(n);
  int32_t code = pdm_event_summary(REAL(rain), REAL(flow), n, dt, area_km2,
                                   count ? ev.data() : nullptr, count, REAL(baseflow),
                                   count ? summary.data() : nullptr, msg.data(),
                                   static_cast<int64_t>(msg.size()));
  stop_on(code, msg);
  cpp11::writable::doubles out(6 * count);
  for (int64_t i = 0; i < count; ++i) {
    for (int64_t j = 0; j < 6; ++j) out[i + j * count] = summary[6 * i + j];
  }
  using namespace cpp11::literals;
  return cpp11::writable::list({"summary"_nm = out, "baseflow"_nm = baseflow});
}

[[cpp11::register]]
doubles event_scores_engine(doubles simulated, doubles observed, double dt, doubles events) {
  std::vector<char> msg(512, '\0');
  std::vector<int64_t> ev = events_in(events);
  const int64_t count = static_cast<int64_t>(ev.size() / 4);
  std::vector<double> scores(6 * count);
  int32_t code = pdm_event_scores(REAL(simulated), REAL(observed), simulated.size(), dt,
                                  count ? ev.data() : nullptr, count,
                                  count ? scores.data() : nullptr, msg.data(),
                                  static_cast<int64_t>(msg.size()));
  stop_on(code, msg);
  cpp11::writable::doubles out(6 * count);
  for (int64_t i = 0; i < count; ++i) {
    for (int64_t j = 0; j < 6; ++j) out[i + j * count] = scores[6 * i + j];
  }
  return out;
}
