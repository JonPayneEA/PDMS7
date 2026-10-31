// ============================================================ //
// Tool:         pdm_engine
// Description:  Compiled PDM time loop for Pareto, standard recharge, cascade and power routing
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-10-31 - Initial compiled engine
// Tier:         3
// Inputs:       Rain and PET depths in mm per interval; parameters in R/engine.R order
// Outputs:      Flux columns identical to pdm_step(); final state vectors
// Dependencies: cpp11 (header only, build time)
// ============================================================ //
//
// Every expression mirrors the R code in model_part2.R, distributions*.R, recharge.R and
// routing*.R, in the same evaluation order, so results match the R engine bit for bit.
// Two R conventions are reproduced deliberately:
//   - x^y evaluates x * x when y == 2 and otherwise uses pow(), as R's arithmetic does;
//   - sum() accumulates each argument in long double, then adds the arguments in double.
// Any change to the R model code must be repeated here; tests compare the two engines.

#include <cpp11.hpp>
#include <cfloat>
#include <cmath>
#include <string>
#include <vector>

using cpp11::doubles;

namespace {

double rpow(double x, double y) {
  if (y == 2.0) return x * x;
  if (x == 1.0 || y == 0.0) return 1.0;
  if (x == 0.0) {
    if (y > 0.0) return 0.0;
    if (y < 0.0) return R_PosInf;
    return y;
  }
  return std::pow(x, y);
}

double rsum(const std::vector<double>& x) {
  long double s = 0.0L;
  for (double v : x) s += v;
  return static_cast<double>(s);
}

double rsum2(double a, double b) {
  long double s = 0.0L;
  s += a;
  s += b;
  return static_cast<double>(s);
}

void check(bool ok, const char* message) {
  if (!ok) cpp11::stop("%s", message);
}

struct Params {
  double cmin, cmax, b, kg, bg, st, k1, k2, k, m, rtol, atol, be, fc, td, qc, area, dt;
  int smith;
  double smax;
};

// Pareto capacity, distributions.R and distributions_part3.R.
double cap_from_storage(const Params& p, double s) {
  check(s >= 0.0 && s <= p.smax, "Soil storage exceeds capacity_mean(distribution)");
  double z = std::min(1.0, std::max(0.0, (s - p.cmin) / (p.smax - p.cmin)));
  double out = p.cmin + (p.cmax - p.cmin) * (-std::expm1(std::log1p(-z) / (p.b + 1)));
  return s < p.cmin ? s : out;
}

double storage_from_cap(const Params& p, double c) {
  double z = std::min(1.0, std::max(0.0, (c - p.cmin) / (p.cmax - p.cmin)));
  double out = p.cmin + (p.smax - p.cmin) * (-std::expm1((p.b + 1) * std::log1p(-z)));
  return c < p.cmin ? c : out;
}

double cap_cdf(const Params& p, double c) {
  if (p.b == 0) return c >= p.cmax ? 1.0 : 0.0;
  double z = std::min(1.0, std::max(0.0, (c - p.cmin) / (p.cmax - p.cmin)));
  return -std::expm1(p.b * std::log1p(-z));
}

struct Route {
  double outflow, q_end;
};

Route route_result(double old_sum, double old_abs, double new_sum, double u, double dt,
                   double q_end) {
  double v = old_sum + u * dt - new_sum;
  double scale = std::max(1.0, std::max(old_abs, u * dt));
  check(std::isfinite(v) && v >= -1e-07 * scale, "FlodeRouting solver produced invalid volume");
  v = std::max(0.0, v);
  return {v, q_end};
}

// routing_part3.R, route_step for FlodeCascadeRouting.
Route cascade_step(const Params& p, double* s, double u, double dt) {
  check(u >= 0.0 && std::isfinite(u), "inflow >= 0 and dt > 0 required");
  double e1 = std::exp(-dt / p.k1);
  double e2 = std::exp(-dt / p.k2);
  double z = dt * (1 / p.k2 - 1 / p.k1);
  double cross;
  if (std::fabs(z) < 1e-06) {
    cross = e2 * dt / p.k1 * (1 + z / 2 + rpow(z, 2) / 6 + rpow(z, 3) / 24);
  } else {
    cross = p.k2 / (p.k1 - p.k2) * (e1 - e2);
  }
  double n1 = s[0] * e1 + u * p.k1 * (-std::expm1(-dt / p.k1));
  double n2 = s[1] * e2 + u * p.k2 * (-std::expm1(-dt / p.k2)) + (s[0] - u * p.k1) * cross;
  n1 = std::max(0.0, n1);
  n2 = std::max(0.0, n2);
  double old_sum = rsum2(s[0], s[1]);
  double old_abs = rsum2(std::fabs(s[0]), std::fabs(s[1]));
  double new_sum = rsum2(n1, n2);
  Route r = route_result(old_sum, old_abs, new_sum, u, dt, n2 / p.k2);
  s[0] = n1;
  s[1] = n2;
  return r;
}

// routing_2.R, .rk4 and .power_adaptive.
double rk4(double s, double h, double u, double k, double m) {
  auto f = [&](double z) { return u - k * rpow(std::max(0.0, z), m); };
  double a = f(s);
  double b = f(s + h * a / 2);
  double c = f(s + h * b / 2);
  double d = f(s + h * c);
  return s + h * (a + 2 * b + 2 * c + d) / 6;
}

double power_adaptive(const Params& p, double s, double u, double dt) {
  double target = rpow(u / p.k, 1 / p.m);
  if (s == target) return s;
  double time = 0;
  double h = dt;
  int iterations = 0;
  while (time < dt) {
    iterations += 1;
    check(iterations < 100000,
          "Routing integration did not converge; adjust tolerances/parameters");
    h = std::min(h, dt - time);
    double one = rk4(s, h, u, p.k, p.m);
    double half = rk4(s, h / 2, u, p.k, p.m);
    double two = rk4(half, h / 2, u, p.k, p.m);
    double err = std::fabs(two - one) / 15;
    double tol = p.atol + p.rtol * std::max(std::fabs(s), std::fabs(two));
    bool inside = std::isfinite(two) && two >= std::min(s, target) &&
      two <= std::max(s, target);
    if (std::isfinite(err) && inside && err <= tol) {
      s = two;
      time = time + h;
      if (dt - time < 1e-14 * dt) time = dt;
      h = h * (err == 0 ? 2 : std::min(2.0, std::max(0.2, 0.9 * rpow(tol / err, 0.2))));
    } else {
      h = h / 2;
    }
    check(h > DBL_EPSILON * std::max(dt, 1.0), "Routing step underflow");
  }
  return s;
}

// routing_2.R, route_step for FlodePowerRouting.
Route power_step(const Params& p, double* store, double u, double dt) {
  check(u >= 0.0 && std::isfinite(u), "inflow >= 0 and dt > 0 required");
  double s = store[0];
  double k = p.k;
  double m = p.m;
  double next;
  if (p.smith) {
    double lambda = 3 * k * rpow(s, 2);
    double phi = lambda == 0 ? dt : -std::expm1(-lambda * dt) / lambda;
    next = s + phi * (u - k * rpow(s, 3));
  } else if (m == 1) {
    next = s * std::exp(-k * dt) + u * (-std::expm1(-k * dt)) / k;
  } else if (u == 0) {
    if (s == 0) {
      next = 0;
    } else if (m < 1) {
      next = rpow(std::max(0.0, rpow(s, 1 - m) - (1 - m) * k * dt), 1 / (1 - m));
    } else {
      next = rpow(rpow(s, 1 - m) + (m - 1) * k * dt, 1 / (1 - m));
    }
  } else if (m == 2) {
    double equilibrium = std::sqrt(u / k);
    double t = std::tanh(std::sqrt(u * k) * dt);
    next = equilibrium * (s + equilibrium * t) / (equilibrium + s * t);
  } else {
    next = power_adaptive(p, s, u, dt);
  }
  Route r = route_result(s, std::fabs(s), next, u, dt, k * rpow(next, m));
  store[0] = next;
  return r;
}

// model.R, .delay.
double delay(std::vector<double>& pending, std::vector<double>& work, double value,
             double ratio) {
  double n = std::floor(ratio);
  double fraction = ratio - n;
  std::size_t len = pending.size();
  for (std::size_t i = 0; i < len; ++i) work[i] = pending[i];
  work[len] = 0;
  std::size_t j = static_cast<std::size_t>(n);
  work[j] = work[j] + (1 - fraction) * value;
  work[j + 1] = work[j + 1] + fraction * value;
  double out = work[0];
  for (std::size_t i = 0; i < len; ++i) pending[i] = work[i + 1];
  return out;
}

}  // namespace

// Runs the time loop. par holds, in order: cmin, cmax, b, kg, bg, st, k1, k2, k, m, rtol,
// atol, be, fc, td, qc, area_km2, dt, smith (0 or 1). state holds soil, surface[2],
// groundwater, step, then the four delay vectors of equal length in model.R order.
// With full = FALSE only q_m3s and q_end_m3s are filled; the other columns are left empty.
[[cpp11::register]]
cpp11::list pdm_engine_run(doubles rain, doubles pet, doubles par, doubles state, bool full) {
  Params p;
  p.cmin = par[0]; p.cmax = par[1]; p.b = par[2]; p.kg = par[3]; p.bg = par[4]; p.st = par[5];
  p.k1 = par[6]; p.k2 = par[7]; p.k = par[8]; p.m = par[9]; p.rtol = par[10]; p.atol = par[11];
  p.be = par[12]; p.fc = par[13]; p.td = par[14]; p.qc = par[15]; p.area = par[16];
  p.dt = par[17]; p.smith = par[18] != 0;
  p.smax = p.cmin + (p.cmax - p.cmin) / (p.b + 1);

  const double dt = p.dt;
  const R_xlen_t n_steps = rain.size();
  const std::size_t n_pending = static_cast<std::size_t>((state.size() - 5) / 4);
  double soil = state[0];
  double surface[2] = {state[1], state[2]};
  double ground[1] = {state[3]};
  double step = state[4];
  std::vector<double> ds(n_pending), dg(n_pending), dse(n_pending), dge(n_pending);
  for (std::size_t i = 0; i < n_pending; ++i) {
    ds[i] = state[5 + i];
    dg[i] = state[5 + n_pending + i];
    dse[i] = state[5 + 2 * n_pending + i];
    dge[i] = state[5 + 3 * n_pending + i];
  }
  std::vector<double> work(n_pending + 1);
  const double ratio = p.td / dt;
  const double factor = p.area / 3.6;

  const int n_cols = 24;
  const R_xlen_t rows = full ? n_steps : 0;
  std::vector<std::vector<double>> cols(n_cols, std::vector<double>(rows));
  std::vector<double> q(n_steps), q_end(n_steps);

  auto total_storage = [&]() {
    double t = 0;
    t += soil;
    t += rsum2(surface[0], surface[1]);
    t += ground[0];
    t += rsum(ds);
    t += rsum(dg);
    return t;
  };

  for (R_xlen_t i = 0; i < n_steps; ++i) {
    double r = rain[i];
    double e = pet[i];
    check(std::isfinite(r) && r >= 0 && std::isfinite(e) && e >= 0,
          "rain and pet must be finite nonnegative depths");
    check(soil >= 0 && soil <= p.smax, "Soil storage exceeds capacity_mean(distribution)");
    double old = total_storage();
    double pr = r * p.fc;
    double et_requested = e * (-std::expm1(p.be * std::log1p(-soil / p.smax)));
    double dr_requested = rpow(std::max(0.0, soil - p.st), p.bg) / p.kg * dt;
    double et = std::min(et_requested, soil + pr);
    double dr = std::min(dr_requested, std::max(0.0, soil + pr - et));
    double net = pr - et - dr;
    double soil_next, runoff;
    if (net <= 0) {
      soil_next = std::max(0.0, soil + net);
      runoff = 0;
    } else {
      double c = cap_from_storage(p, soil);
      double next_s = storage_from_cap(p, c + net);
      soil_next = std::min(soil + net, std::max(soil, next_s));
      runoff = std::max(0.0, net - (soil_next - soil));
    }
    double fast = runoff;
    double slow = dr;
    Route surf = cascade_step(p, surface, fast / dt, dt);
    Route gw = power_step(p, ground, slow / dt, dt);
    double d1 = delay(ds, work, surf.outflow, ratio);
    double d2 = delay(dg, work, gw.outflow, ratio);
    double e1 = delay(dse, work, surf.q_end, ratio);
    double e2 = delay(dge, work, gw.q_end, ratio);
    soil = soil_next;
    step = step + 1;
    check(std::isfinite(soil) && std::isfinite(surface[0]) && std::isfinite(surface[1]) &&
            std::isfinite(ground[0]),
          "Invalid parameter(s): non-finite model state");
    double natural = d1 + d2;
    q[i] = natural / dt * factor + p.qc;
    q_end[i] = (e1 + e2) * factor + p.qc;
    if (full) {
      double residual = old + pr - et - natural - total_storage();
      cols[0][i] = step;
      cols[1][i] = r;
      cols[2][i] = pr;
      cols[3][i] = e;
      cols[4][i] = et;
      cols[5][i] = et_requested;
      cols[6][i] = dr;
      cols[7][i] = dr_requested;
      cols[8][i] = runoff;
      cols[9][i] = fast;
      cols[10][i] = slow;
      cols[11][i] = d1;
      cols[12][i] = d2;
      cols[13][i] = natural / dt * factor;
      cols[14][i] = q[i];
      cols[15][i] = q_end[i];
      cols[16][i] = surf.q_end;
      cols[17][i] = gw.q_end;
      cols[18][i] = soil;
      cols[19][i] = rsum2(surface[0], surface[1]);
      cols[20][i] = ground[0];
      cols[21][i] = rsum(ds) + rsum(dg);
      cols[22][i] = cap_cdf(p, cap_from_storage(p, soil));
      cols[23][i] = residual;
    }
  }

  cpp11::writable::doubles final_state(5 + 4 * n_pending);
  final_state[0] = soil;
  final_state[1] = surface[0];
  final_state[2] = surface[1];
  final_state[3] = ground[0];
  final_state[4] = step;
  for (std::size_t j = 0; j < n_pending; ++j) {
    final_state[5 + j] = ds[j];
    final_state[5 + n_pending + j] = dg[j];
    final_state[5 + 2 * n_pending + j] = dse[j];
    final_state[5 + 3 * n_pending + j] = dge[j];
  }
  cpp11::writable::list columns(n_cols);
  for (int j = 0; j < n_cols; ++j) {
    columns[j] = cpp11::writable::doubles(cols[j].begin(), cols[j].end());
  }
  using namespace cpp11::literals;
  return cpp11::writable::list({
    "columns"_nm = columns,
    "q_m3s"_nm = cpp11::writable::doubles(q.begin(), q.end()),
    "q_end_m3s"_nm = cpp11::writable::doubles(q_end.begin(), q_end.end()),
    "state"_nm = final_state
  });
}
