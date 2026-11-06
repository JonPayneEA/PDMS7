// ============================================================ //
// Tool:         dmca
// Description:  DMCA correlation of rain and flow fluctuations over a range of windows
// Flode Module: standalone; target reach.hydro
// Author:       pdmS7 contributors
// Created:      2026-11-06
// Modified:     2026-11-06 - Add dmca_rho()
// Tier:         3
// Inputs:       Cumulative rain and flow series; the largest half-window
// Outputs:      The DMCA correlation for each half-window 1..h_max
// Dependencies: cpp11 (header only, build time)
// ============================================================ //
//
// The compiled form of the search in response_time_dmca() (R/events.R), which keeps an R
// version, .dmca_rho_r(), as the reference the tests compare against. For each half-window h,
// a series' fluctuation at step i is its value less the mean over the 2h + 1 steps centred on
// i; only steps with a full window are scored. Window means come from prefix sums, so each
// half-window costs one pass over the series.

#include <cpp11.hpp>

#include <cmath>
#include <vector>

using cpp11::doubles;

[[cpp11::register]]
doubles dmca_rho(doubles cum_rain, doubles cum_flow, int h_max) {
  const R_xlen_t n = cum_rain.size();
  if (cum_flow.size() != n) cpp11::stop("cum_rain and cum_flow must have the same length");
  // Prefix sums: prefix[i] is the sum of the first i values. In double, the correlations
  // agree with the R reference to about 1e-7 (R accumulates its sums in long double), which
  // never moves the minimum; long double here would double the time for no visible gain.
  std::vector<double> pr(n + 1, 0.0), pq(n + 1, 0.0);
  for (R_xlen_t i = 0; i < n; ++i) {
    pr[i + 1] = pr[i] + cum_rain[i];
    pq[i + 1] = pq[i] + cum_flow[i];
  }
  cpp11::writable::doubles out(h_max);
  for (int h = 1; h <= h_max; ++h) {
    const double width = 2.0 * h + 1.0;
    double rq = 0.0, rr = 0.0, qq = 0.0;
    for (R_xlen_t i = h; i < n - h; ++i) {
      const double fr = cum_rain[i] - (pr[i + h + 1] - pr[i - h]) / width;
      const double fq = cum_flow[i] - (pq[i + h + 1] - pq[i - h]) / width;
      rq += fr * fq;
      rr += fr * fr;
      qq += fq * fq;
    }
    out[h - 1] = rq / std::sqrt(rr * qq);
  }
  return out;
}
