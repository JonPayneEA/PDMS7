// ============================================================ //
// Tool:         pdm_core
// Description:  PDM time loop behind a language-neutral C interface (see pdm_core.h)
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-10-31 - Extracted from pdm_engine.cpp with no change to the arithmetic
// Tier:         3
// Inputs:       pdm_params, state array, rain and PET depths in mm per interval
// Outputs:      Flow in m3/s, optional flux table, updated state
// Dependencies: C++11 standard library only; no R or Python headers
// ============================================================ //
//
// Every expression mirrors the R code in model_part2.R, distributions*.R, recharge.R and
// routing*.R, in the same evaluation order. Two R 4.3 conventions are reproduced:
//   - x^y evaluates x * x when y == 2 and otherwise uses pow(), as R's arithmetic does;
//   - sum() accumulates each argument in long double, then adds the arguments in double.
// Results are bit-identical to the R engine on R 4.3. Later R versions changed both
// conventions, so there the engines differ in the last place; tests allow for this.
// Any change to the R model code must be repeated here; tests compare the two engines and
// check the golden files in inst/golden/.
//
// The code is reentrant: it holds no global state, so separate runs may execute in parallel
// threads.

#include "pdm_core.h"

#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstring>
#include <exception>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct ArgumentError : std::runtime_error {
  explicit ArgumentError(const std::string& what) : std::runtime_error(what) {}
};
struct NumericalError : std::runtime_error {
  explicit NumericalError(const std::string& what) : std::runtime_error(what) {}
};

void check(bool ok, const char* message) {
  if (!ok) throw NumericalError(message);
}

double rpow(double x, double y) {
  if (y == 2.0) return x * x;
  if (x == 1.0 || y == 0.0) return 1.0;
  if (x == 0.0) {
    if (y > 0.0) return 0.0;
    if (y < 0.0) return std::numeric_limits<double>::infinity();
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

struct Params {
  double cmin, cmax, b, kg, bg, st, k1, k2, k, m, rtol, atol, be, fc, td, qc, area, dt;
  int smith;
  double smax;
};

Params unpack(const pdm_params& in) {
  Params p;
  p.cmin = in.cmin; p.cmax = in.cmax; p.b = in.b; p.kg = in.kg; p.bg = in.bg; p.st = in.st;
  p.k1 = in.k1; p.k2 = in.k2; p.k = in.k; p.m = in.m; p.rtol = in.rtol; p.atol = in.atol;
  p.be = in.be; p.fc = in.fc; p.td = in.td; p.qc = in.qc; p.area = in.area_km2; p.dt = in.dt;
  p.smith = in.smith != 0;
  p.smax = p.cmin + (p.cmax - p.cmin) / (p.b + 1);
  return p;
}

// The same rules as the S7 validators of FlodeParetoCapacity, FlodeStandardRecharge,
// FlodeCascadeRouting, FlodePowerRouting and FlodePdmModel, and no stricter.
void validate(const pdm_params& in) {
  std::string bad;
  auto need = [&](bool ok, const char* name) {
    if (!ok) bad += bad.empty() ? name : std::string(", ") + name;
  };
  auto fin = [](double x) { return std::isfinite(x); };
  need(fin(in.cmin) && in.cmin >= 0, "cmin");
  need(fin(in.cmax) && in.cmax > in.cmin, "cmax");
  need(fin(in.b) && in.b >= 0, "b");
  need(fin(in.kg) && in.kg > 0, "kg");
  need(fin(in.bg) && in.bg > 0, "bg");
  need(fin(in.st) && in.st >= 0, "st");
  need(fin(in.k1) && in.k1 > 0, "k1");
  need(fin(in.k2) && in.k2 > 0, "k2");
  need(fin(in.k) && in.k > 0, "k");
  need(fin(in.m) && in.m > 0, "m");
  need(in.smith == 0 || in.smith == 1, "smith");
  need(in.smith == 0 || in.m == 3, "smith_cubic");
  need(fin(in.rtol) && in.rtol > 0, "rtol");
  need(fin(in.atol) && in.atol > 0, "atol");
  need(fin(in.be) && in.be > 0, "be");
  need(fin(in.fc) && in.fc >= 0, "fc");
  need(fin(in.td) && in.td >= 0, "td");
  need(fin(in.qc), "qc");
  need(fin(in.area_km2) && in.area_km2 > 0, "area_km2");
  need(fin(in.dt) && in.dt > 0, "dt");
  if (!bad.empty()) throw ArgumentError("Invalid parameter(s): " + bad);
  double smax = in.cmin + (in.cmax - in.cmin) / (in.b + 1);
  if (in.st > smax) throw ArgumentError("st cannot exceed Smax");
}

int64_t pending_length(const pdm_params& in) {
  return static_cast<int64_t>(std::floor(in.td / in.dt)) + 1;
}

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

const char* const kFluxNames[PDM_N_FLUX] = {
  "step", "rain_mm", "rain_corrected_mm", "pet_mm", "aet_mm", "aet_requested_mm",
  "recharge_mm", "recharge_requested_mm", "direct_runoff_mm", "surface_input_mm",
  "groundwater_input_mm", "surface_out_mm", "baseflow_out_mm", "q_natural_m3s", "q_m3s",
  "q_end_m3s", "qs_end_unlagged_mmh", "qb_end_unlagged_mmh", "soil_mm", "surface_mm",
  "groundwater_mm", "delay_mm", "saturated_fraction", "balance_error_mm"
};

void validate_state(const pdm_params& in, const double* state, int64_t state_length) {
  if (state == nullptr) throw ArgumentError("state must not be null");
  int64_t n_pending = pending_length(in);
  if (state_length != 5 + 4 * n_pending) {
    throw ArgumentError(
      "Delay state incompatible with td/dt; reinitialise after changing time step");
  }
  double smax = in.cmin + (in.cmax - in.cmin) / (in.b + 1);
  if (!(std::isfinite(state[0]) && state[0] >= 0 && state[0] <= smax)) {
    throw ArgumentError("Soil storage exceeds capacity_mean(distribution)");
  }
  for (int64_t i = 1; i < 4; ++i) {
    if (!(std::isfinite(state[i]) && state[i] >= 0)) {
      throw ArgumentError("FlodeRouting storage must be finite and nonnegative");
    }
  }
  if (!(std::isfinite(state[4]) && state[4] >= 0 && state[4] == std::floor(state[4]))) {
    throw ArgumentError("Invalid state dimensions");
  }
  for (int64_t i = 5; i < state_length; ++i) {
    if (!(std::isfinite(state[i]) && state[i] >= 0)) {
      throw ArgumentError("Delay queues must be finite and nonnegative");
    }
  }
}

// The time loop. Works on a copy of the state and writes it back only on success.
void run(const pdm_params& in, const double* rain, const double* pet, int64_t n_steps,
         double* state, int64_t state_length, double* q, double* q_end, double* fluxes) {
  validate(in);
  validate_state(in, state, state_length);
  if (n_steps < 0) throw ArgumentError("n must be nonnegative");
  if (n_steps > 0 && (rain == nullptr || pet == nullptr || q == nullptr || q_end == nullptr)) {
    throw ArgumentError("rain, pet, q_m3s and q_end_m3s must not be null");
  }
  Params p = unpack(in);
  const double dt = p.dt;
  const std::size_t n_pending = static_cast<std::size_t>(pending_length(in));
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

  auto total_storage = [&]() {
    double t = 0;
    t += soil;
    t += rsum2(surface[0], surface[1]);
    t += ground[0];
    t += rsum(ds);
    t += rsum(dg);
    return t;
  };
  auto col = [&](int j, int64_t i) -> double& { return fluxes[j * n_steps + i]; };

  for (int64_t i = 0; i < n_steps; ++i) {
    double r = rain[i];
    double e = pet[i];
    if (!(std::isfinite(r) && r >= 0 && std::isfinite(e) && e >= 0)) {
      throw ArgumentError("rain and pet must be finite nonnegative depths");
    }
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
    if (fluxes != nullptr) {
      double residual = old + pr - et - natural - total_storage();
      col(0, i) = step;
      col(1, i) = r;
      col(2, i) = pr;
      col(3, i) = e;
      col(4, i) = et;
      col(5, i) = et_requested;
      col(6, i) = dr;
      col(7, i) = dr_requested;
      col(8, i) = runoff;
      col(9, i) = fast;
      col(10, i) = slow;
      col(11, i) = d1;
      col(12, i) = d2;
      col(13, i) = natural / dt * factor;
      col(14, i) = q[i];
      col(15, i) = q_end[i];
      col(16, i) = surf.q_end;
      col(17, i) = gw.q_end;
      col(18, i) = soil;
      col(19, i) = rsum2(surface[0], surface[1]);
      col(20, i) = ground[0];
      col(21, i) = rsum(ds) + rsum(dg);
      col(22, i) = cap_cdf(p, cap_from_storage(p, soil));
      col(23, i) = residual;
    }
  }

  state[0] = soil;
  state[1] = surface[0];
  state[2] = surface[1];
  state[3] = ground[0];
  state[4] = step;
  for (std::size_t j = 0; j < n_pending; ++j) {
    state[5 + j] = ds[j];
    state[5 + n_pending + j] = dg[j];
    state[5 + 2 * n_pending + j] = dse[j];
    state[5 + 3 * n_pending + j] = dge[j];
  }
}

void write_message(char* message, int64_t length, const char* text) {
  if (message == nullptr || length <= 0) return;
  std::size_t room = static_cast<std::size_t>(length - 1);
  std::size_t n = std::min(room, std::strlen(text));
  std::memcpy(message, text, n);
  message[n] = '\0';
}

// Converts any exception into a return code, so none crosses the C interface.
template <typename F>
int32_t guarded(char* message, int64_t length, F body) {
  try {
    body();
    write_message(message, length, "");
    return PDM_OK;
  } catch (const ArgumentError& e) {
    write_message(message, length, e.what());
    return PDM_ERR_ARGUMENT;
  } catch (const NumericalError& e) {
    write_message(message, length, e.what());
    return PDM_ERR_NUMERICAL;
  } catch (const std::exception& e) {
    write_message(message, length, e.what());
    return PDM_ERR_NUMERICAL;
  } catch (...) {
    write_message(message, length, "Unknown error in pdm_core");
    return PDM_ERR_NUMERICAL;
  }
}

}  // namespace

extern "C" {

int32_t pdm_core_abi_version(void) {
  return PDM_CORE_ABI_VERSION;
}

int64_t pdm_state_length(const pdm_params* params) {
  if (params == nullptr || !(std::isfinite(params->dt) && params->dt > 0) ||
      !(std::isfinite(params->td) && params->td >= 0)) {
    return -1;
  }
  return 5 + 4 * pending_length(*params);
}

int32_t pdm_initial_state(const pdm_params* params, double soil_fraction, double* state,
                          int64_t state_length, char* message, int64_t message_length) {
  return guarded(message, message_length, [&]() {
    if (params == nullptr) throw ArgumentError("params must not be null");
    validate(*params);
    if (!(std::isfinite(soil_fraction) && soil_fraction >= 0 && soil_fraction <= 1)) {
      throw ArgumentError("soil_fraction must lie in [0,1]");
    }
    if (state == nullptr || state_length != 5 + 4 * pending_length(*params)) {
      throw ArgumentError("state must hold pdm_state_length() values");
    }
    double smax = params->cmin + (params->cmax - params->cmin) / (params->b + 1);
    for (int64_t i = 0; i < state_length; ++i) state[i] = 0;
    state[0] = soil_fraction * smax;
  });
}

const char* pdm_flux_name(int32_t j) {
  if (j < 0 || j >= PDM_N_FLUX) return nullptr;
  return kFluxNames[j];
}

int32_t pdm_run(const pdm_params* params, const double* rain, const double* pet, int64_t n,
                double* state, int64_t state_length, double* q_m3s, double* q_end_m3s,
                double* fluxes, char* message, int64_t message_length) {
  return guarded(message, message_length, [&]() {
    if (params == nullptr) throw ArgumentError("params must not be null");
    // Run on a copy so that the caller's state is unchanged if the run fails.
    std::vector<double> work_state;
    if (state != nullptr && state_length > 0) {
      work_state.assign(state, state + state_length);
    }
    run(*params, rain, pet, n, work_state.empty() ? nullptr : work_state.data(), state_length,
        q_m3s, q_end_m3s, fluxes);
    std::copy(work_state.begin(), work_state.end(), state);
  });
}

}  // extern "C"
