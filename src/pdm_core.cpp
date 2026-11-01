// ============================================================ //
// Tool:         pdm_core
// Description:  PDM time loop behind a language-neutral C interface (see pdm_core.h)
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-11-01 - Triangular and lognormal distributions; one rectangular Smax
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

// ---- Capacity distributions ----------------------------------------------------------------

// The rectangular distribution is computed as Pareto with b = 1, as in R (.as_uniform), and its
// capacity mean comes from the same Pareto formula.
struct Dist {
  int type;
  double cmin, cmax, b, mean, meanlog, sdlog;
  double smax;  // capacity_mean(distribution)
};

const double kPi = 3.141592653589793;

// Standard normal distribution function, and its upper tail, through erfc.
double pnorm_lower(double x) { return 0.5 * std::erfc(-x / std::sqrt(2.0)); }
double pnorm_upper(double x) { return 0.5 * std::erfc(x / std::sqrt(2.0)); }

Dist make_dist(const pdm_params& in) {
  Dist d;
  d.type = in.distribution;
  d.cmin = in.cmin;
  d.cmax = in.cmax;
  d.mean = in.mean;
  d.meanlog = in.meanlog;
  d.sdlog = in.sdlog;
  d.b = 0;
  switch (d.type) {
    case PDM_DIST_EXPONENTIAL:
      d.smax = in.mean;
      break;
    case PDM_DIST_TRIANGULAR:
      d.smax = (in.cmin + in.cmax) / 2;
      break;
    case PDM_DIST_LOGNORMAL:
      d.smax = std::exp(in.meanlog + rpow(in.sdlog, 2) / 2);
      break;
    default:
      d.b = d.type == PDM_DIST_RECTANGULAR ? 1.0 : in.b;
      d.smax = d.cmin + (d.cmax - d.cmin) / (d.b + 1);
  }
  return d;
}

// distributions_part2.R, storage_from_capacity for FlodeTriangularCapacity.
double triangular_storage(const Dist& d, double c) {
  double w = d.cmax - d.cmin;
  double z = std::min(d.cmax, std::max(d.cmin, c));
  double out = z <= d.smax ? z - 2 * rpow(z - d.cmin, 3) / (3 * rpow(w, 2))
                           : d.smax - 2 * rpow(d.cmax - z, 3) / (3 * rpow(w, 2));
  return c < d.cmin ? c : out;
}

// distributions_part2.R, .triangular_inverse: exact, by cube root or the trigonometric form
// of the cubic, then one Newton step.
double triangular_inverse(const Dist& d, double si) {
  if (si <= d.cmin) return si;
  double m = d.smax;
  if (si >= m) return d.cmax;
  double w = d.cmax - d.cmin;
  if (si >= m - w / 12) {
    double y = rpow(3 * w * w * (m - si) / 2, 1.0 / 3);
    return std::min(d.cmax, std::max(m, d.cmax - y));
  }
  double dd = si - d.cmin;
  double theta = std::acos(std::max(-1.0, std::min(1.0, -3 / std::sqrt(2.0) * dd / w)));
  double u = std::sqrt(2.0) * w * std::cos(theta / 3 - 2 * kPi / 3);
  double f = u - 2 * u * u * u / (3 * w * w) - dd;
  u = u - f / (1 - 2 * u * u / (w * w));
  return d.cmin + std::min(w / 2, std::max(0.0, u));
}

// distributions_part2.R, storage_from_capacity for FlodeLognormalCapacity.
double lognormal_storage(const Dist& d, double c) {
  if (!(c > 0)) return 0;
  if (std::isinf(c)) return d.smax;
  double z = (std::log(c) - d.meanlog) / d.sdlog;
  double out = d.smax * pnorm_lower(z - d.sdlog) + c * pnorm_upper(z);
  return std::min(d.smax, out);
}

// distributions_2.R, .lognormal_inverse: safeguarded Newton iteration.
double lognormal_inverse(const Dist& d, double si) {
  if (si == 0) return 0;
  double m = d.smax;
  if (si >= m) return std::numeric_limits<double>::infinity();
  double lo = 0;
  double hi = std::max(1.0, m);
  while (lognormal_storage(d, hi) < si) {
    hi = hi * 2;
    check(std::isfinite(hi), "Could not bracket lognormal inverse");
  }
  double c = std::min(si, hi);
  for (int i = 0; i < 200; ++i) {
    double f = lognormal_storage(d, c) - si;
    if (f == 0) return c;
    if (f < 0) lo = c; else hi = c;
    double slope = pnorm_upper((std::log(c) - d.meanlog) / d.sdlog);
    double next = c - f / slope;
    if (!(std::isfinite(next) && next > lo && next < hi)) next = (lo + hi) / 2;
    if (std::fabs(next - c) <= 4 * DBL_EPSILON * next) return next;
    c = next;
  }
  return c;
}

// distributions_part3.R (Pareto, rectangular, exponential).
double cap_from_storage(const Dist& d, double s) {
  if (d.type == PDM_DIST_TRIANGULAR || d.type == PDM_DIST_LOGNORMAL) {
    check(s >= 0.0 && s <= d.smax, "Soil storage exceeds capacity_mean(distribution)");
    return d.type == PDM_DIST_TRIANGULAR ? triangular_inverse(d, s) : lognormal_inverse(d, s);
  }
  if (d.type == PDM_DIST_EXPONENTIAL) {
    check(s >= 0.0 && s <= d.mean, "Soil storage exceeds capacity_mean(distribution)");
    return -d.mean * std::log1p(-s / d.mean);
  }
  check(s >= 0.0 && s <= d.smax, "Soil storage exceeds capacity_mean(distribution)");
  double z = std::min(1.0, std::max(0.0, (s - d.cmin) / (d.smax - d.cmin)));
  double out = d.cmin + (d.cmax - d.cmin) * (-std::expm1(std::log1p(-z) / (d.b + 1)));
  return s < d.cmin ? s : out;
}

// distributions.R and distributions_part3.R.
double storage_from_cap(const Dist& d, double c) {
  if (d.type == PDM_DIST_EXPONENTIAL) return d.mean * (-std::expm1(-c / d.mean));
  if (d.type == PDM_DIST_TRIANGULAR) return triangular_storage(d, c);
  if (d.type == PDM_DIST_LOGNORMAL) return lognormal_storage(d, c);
  double z = std::min(1.0, std::max(0.0, (c - d.cmin) / (d.cmax - d.cmin)));
  double out = d.cmin + (d.smax - d.cmin) * (-std::expm1((d.b + 1) * std::log1p(-z)));
  return c < d.cmin ? c : out;
}

double cap_cdf(const Dist& d, double c) {
  if (d.type == PDM_DIST_EXPONENTIAL) return -std::expm1(-c / d.mean);
  if (d.type == PDM_DIST_TRIANGULAR) {
    double z = std::min(1.0, std::max(0.0, (c - d.cmin) / (d.cmax - d.cmin)));
    return z <= 0.5 ? 2 * rpow(z, 2) : 1 - 2 * rpow(1 - z, 2);
  }
  if (d.type == PDM_DIST_LOGNORMAL) {
    if (!(c > 0)) return 0;
    if (std::isinf(c)) return 1;
    return pnorm_lower((std::log(c) - d.meanlog) / d.sdlog);
  }
  if (d.b == 0) return c >= d.cmax ? 1.0 : 0.0;
  double z = std::min(1.0, std::max(0.0, (c - d.cmin) / (d.cmax - d.cmin)));
  return -std::expm1(d.b * std::log1p(-z));
}

// ---- Routing -------------------------------------------------------------------------------

int store_count(const pdm_route& r) {
  return r.type == PDM_ROUTE_CASCADE ? 2 : 1;
}

// sum() over one route's storage vector, as R does for a vector argument.
double store_sum(const pdm_route& r, const double* s) {
  return store_count(r) == 2 ? rsum2(s[0], s[1]) : s[0];
}

struct Route {
  double outflow, q_end;
};

// routing_part3.R, .route_result.
Route route_result(double old_sum, double old_abs, double new_sum, double u, double dt,
                   double q_end) {
  double v = old_sum + u * dt - new_sum;
  double scale = std::max(1.0, std::max(old_abs, u * dt));
  check(std::isfinite(v) && v >= -1e-07 * scale, "FlodeRouting solver produced invalid volume");
  v = std::max(0.0, v);
  return {v, q_end};
}

// routing_part3.R, route_step for FlodeCascadeRouting.
Route cascade_step(const pdm_route& p, double* s, double u, double dt) {
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

double power_adaptive(const pdm_route& p, double s, double u, double dt) {
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
Route power_step(const pdm_route& p, double* store, double u, double dt) {
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

// routing_2.R, route_step for FlodeExponentialRouting. The storage is a signed coordinate.
Route exponential_step(const pdm_route& p, double* store, double u, double dt) {
  check(u >= 0.0 && std::isfinite(u), "inflow >= 0 and dt > 0 required");
  double s = store[0];
  double logq = p.gamma + p.a * s;
  check(std::isfinite(std::exp(logq)) && std::exp(logq) > 0,
        "Exponential flow overflow/underflow");
  double lognext;
  if (u == 0) {
    lognext = logq - std::log1p(p.a * std::exp(logq) * dt);
  } else {
    double h = p.a * u * dt;
    // 1/q_next = exp(-h)/q + (1-exp(-h))/u, using log-sum-exp.
    double t1 = -h - logq;
    double t2 = std::log(-std::expm1(-h)) - std::log(u);
    double mx = std::max(t1, t2);
    lognext = -(mx + std::log(rsum2(std::exp(t1 - mx), std::exp(t2 - mx))));
  }
  double next = (lognext - p.gamma) / p.a;
  Route r = route_result(s, std::fabs(s), next, u, dt, std::exp(p.gamma + p.a * next));
  store[0] = next;
  return r;
}

Route route_step(const pdm_route& p, double* store, double u, double dt) {
  switch (p.type) {
    case PDM_ROUTE_CASCADE: return cascade_step(p, store, u, dt);
    case PDM_ROUTE_POWER: return power_step(p, store, u, dt);
    default: return exponential_step(p, store, u, dt);
  }
}

// routing.R, storage_for_flow for a single store (used by demand recharge).
double storage_for_flow(const pdm_route& p, double q) {
  if (p.type == PDM_ROUTE_POWER) return rpow(q / p.k, 1 / p.m);
  return (std::log(q) - p.gamma) / p.a;
}

// ---- Validation ----------------------------------------------------------------------------

// The same rules as the S7 validators of each component and of FlodePdmModel, and no
// stricter. Fields not used by the chosen types are ignored.
void validate(const pdm_params& in) {
  std::string bad;
  auto need = [&](bool ok, const std::string& name) {
    if (!ok) bad += bad.empty() ? name : ", " + name;
  };
  auto fin = [](double x) { return std::isfinite(x); };
  auto route = [&](const pdm_route& r, const std::string& prefix) {
    switch (r.type) {
      case PDM_ROUTE_CASCADE:
        need(fin(r.k1) && r.k1 > 0, prefix + "k1");
        need(fin(r.k2) && r.k2 > 0, prefix + "k2");
        break;
      case PDM_ROUTE_POWER:
        need(fin(r.k) && r.k > 0, prefix + "k");
        need(fin(r.m) && r.m > 0, prefix + "m");
        need(r.smith == 0 || r.smith == 1, prefix + "smith");
        need(r.smith == 0 || r.m == 3, prefix + "smith_cubic");
        need(fin(r.rtol) && r.rtol > 0, prefix + "rtol");
        need(fin(r.atol) && r.atol > 0, prefix + "atol");
        break;
      case PDM_ROUTE_EXPONENTIAL:
        need(fin(r.a) && r.a > 0, prefix + "a");
        need(fin(r.gamma), prefix + "gamma");
        break;
      default:
        need(false, prefix + "type");
    }
  };
  switch (in.distribution) {
    case PDM_DIST_PARETO:
      need(fin(in.cmin) && in.cmin >= 0, "cmin");
      need(fin(in.cmax) && in.cmax > in.cmin, "cmax");
      need(fin(in.b) && in.b >= 0, "b");
      break;
    case PDM_DIST_RECTANGULAR:
      need(fin(in.cmin) && in.cmin >= 0, "cmin");
      need(fin(in.cmax) && in.cmax > in.cmin, "cmax");
      break;
    case PDM_DIST_EXPONENTIAL:
      need(fin(in.mean) && in.mean > 0, "mean");
      break;
    case PDM_DIST_TRIANGULAR:
      need(fin(in.cmin) && in.cmin >= 0, "cmin");
      need(fin(in.cmax) && in.cmax > in.cmin, "cmax");
      break;
    case PDM_DIST_LOGNORMAL:
      need(fin(in.meanlog), "meanlog");
      need(fin(in.sdlog) && in.sdlog > 0, "sdlog");
      if (fin(in.meanlog) && fin(in.sdlog)) {
        double m = std::exp(in.meanlog + rpow(in.sdlog, 2) / 2);
        need(fin(m) && m > 0, "finite_mean");
      }
      break;
    default:
      need(false, "distribution");
  }
  switch (in.recharge) {
    case PDM_RECHARGE_STANDARD:
      need(fin(in.kg) && in.kg > 0, "kg");
      need(fin(in.bg) && in.bg > 0, "bg");
      need(fin(in.st) && in.st >= 0, "st");
      break;
    case PDM_RECHARGE_SPLIT:
      need(fin(in.alpha) && in.alpha >= 0 && in.alpha <= 1, "alpha");
      break;
    case PDM_RECHARGE_DEMAND:
      need(fin(in.alpha) && in.alpha > 0 && in.alpha <= 1, "alpha");
      need(fin(in.beta) && in.beta > 0, "beta");
      need(fin(in.qsat) && in.qsat > 0, "qsat");
      break;
    default:
      need(false, "recharge");
  }
  route(in.surface, "surface.");
  route(in.groundwater, "groundwater.");
  need(fin(in.be) && in.be > 0, "be");
  need(fin(in.fc) && in.fc >= 0, "fc");
  need(fin(in.td) && in.td >= 0, "td");
  need(fin(in.qc), "qc");
  need(fin(in.area_km2) && in.area_km2 > 0, "area_km2");
  need(fin(in.dt) && in.dt > 0, "dt");
  if (!bad.empty()) throw ArgumentError("Invalid parameter(s): " + bad);

  // FlodePdmModel validator.
  double smax = make_dist(in).smax;
  if (in.recharge == PDM_RECHARGE_STANDARD && in.st > smax) {
    throw ArgumentError("st cannot exceed Smax");
  }
  if (in.recharge == PDM_RECHARGE_DEMAND) {
    if (in.groundwater.type == PDM_ROUTE_CASCADE) {
      throw ArgumentError("Demand recharge requires a single groundwater store");
    }
    if (storage_for_flow(in.groundwater, in.qsat) <= 0) {
      throw ArgumentError("Demand recharge requires Sgmax > 0");
    }
    if (in.qsat * in.dt > smax) {
      throw ArgumentError("Demand recharge requires qsat*dt <= Smax");
    }
  }
}

int64_t pending_length(const pdm_params& in) {
  return static_cast<int64_t>(std::floor(in.td / in.dt)) + 1;
}

void validate_route_state(const pdm_route& r, const double* s) {
  bool signed_ok = r.type == PDM_ROUTE_EXPONENTIAL;
  if (!(std::isfinite(s[0]) && (signed_ok || s[0] >= 0))) {
    throw ArgumentError("FlodeRouting storage must be finite and nonnegative");
  }
  if (r.type == PDM_ROUTE_CASCADE) {
    if (!(std::isfinite(s[1]) && s[1] >= 0)) {
      throw ArgumentError("FlodeRouting storage must be finite and nonnegative");
    }
  } else if (s[1] != 0) {
    throw ArgumentError("The second store of a single-store route must be 0");
  }
}

void validate_state(const pdm_params& in, const double* state, int64_t state_length) {
  if (state == nullptr) throw ArgumentError("state must not be null");
  int64_t n_pending = pending_length(in);
  if (state_length != 6 + 4 * n_pending) {
    throw ArgumentError(
      "Delay state incompatible with td/dt; reinitialise after changing time step");
  }
  double smax = make_dist(in).smax;
  if (!(std::isfinite(state[0]) && state[0] >= 0 && state[0] <= smax)) {
    throw ArgumentError("Soil storage exceeds capacity_mean(distribution)");
  }
  validate_route_state(in.surface, state + 1);
  validate_route_state(in.groundwater, state + 3);
  if (!(std::isfinite(state[5]) && state[5] >= 0 && state[5] == std::floor(state[5]))) {
    throw ArgumentError("Invalid state dimensions");
  }
  for (int64_t i = 6; i < state_length; ++i) {
    if (!(std::isfinite(state[i]) && state[i] >= 0)) {
      throw ArgumentError("Delay queues must be finite and nonnegative");
    }
  }
}

// ---- Time loop -----------------------------------------------------------------------------

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

// recharge.R, recharge_depth.
double recharge_depth(const pdm_params& in, double soil, double smax, double groundwater,
                      double dt) {
  switch (in.recharge) {
    case PDM_RECHARGE_STANDARD:
      return rpow(std::max(0.0, soil - in.st), in.bg) / in.kg * dt;
    case PDM_RECHARGE_SPLIT:
      return 0;
    default: {
      double sgmax = storage_for_flow(in.groundwater, in.qsat);
      check(std::isfinite(sgmax) && sgmax > 0, "Demand recharge requires positive implied Sgmax");
      double g = std::min(1.0, std::max(0.0, (sgmax - groundwater) / sgmax));
      double demand = std::min(1.0, rpow(g / in.alpha, in.beta));
      double dsat = in.qsat * dt;
      check(dsat <= smax, "qsat*dt must not exceed Smax for the Eq. 13 demand scheme");
      return (dsat + (smax - dsat) * demand) * soil / smax;
    }
  }
}

// model_part2.R, pdm_step, repeated for each interval. Works on a copy of the state and
// writes it back only on success.
void run(const pdm_params& in, const double* rain, const double* pet, int64_t n_steps,
         double* state, int64_t state_length, double* q, double* q_end, double* fluxes) {
  validate(in);
  validate_state(in, state, state_length);
  if (n_steps < 0) throw ArgumentError("n must be nonnegative");
  if (n_steps > 0 && (rain == nullptr || pet == nullptr || q == nullptr || q_end == nullptr)) {
    throw ArgumentError("rain, pet, q_m3s and q_end_m3s must not be null");
  }
  const Dist dist = make_dist(in);
  const pdm_route& srf = in.surface;
  const pdm_route& gwr = in.groundwater;
  const double dt = in.dt;
  const double smax = dist.smax;
  const std::size_t n_pending = static_cast<std::size_t>(pending_length(in));
  double soil = state[0];
  double surface[2] = {state[1], state[2]};
  double ground[2] = {state[3], state[4]};
  double step = state[5];
  std::vector<double> ds(n_pending), dg(n_pending), dse(n_pending), dge(n_pending);
  for (std::size_t i = 0; i < n_pending; ++i) {
    ds[i] = state[6 + i];
    dg[i] = state[6 + n_pending + i];
    dse[i] = state[6 + 2 * n_pending + i];
    dge[i] = state[6 + 3 * n_pending + i];
  }
  std::vector<double> work(n_pending + 1);
  const double ratio = in.td / dt;
  const double factor = in.area_km2 / 3.6;

  auto total_storage = [&]() {
    double t = 0;
    t += soil;
    t += store_sum(srf, surface);
    t += store_sum(gwr, ground);
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
    check(soil >= 0 && soil <= smax, "Soil storage exceeds capacity_mean(distribution)");
    double old = total_storage();
    double pr = r * in.fc;
    double et_requested = e * (-std::expm1(in.be * std::log1p(-soil / smax)));
    double dr_requested = recharge_depth(in, soil, smax, ground[0], dt);
    double et = std::min(et_requested, soil + pr);
    double dr = std::min(dr_requested, std::max(0.0, soil + pr - et));
    double net = pr - et - dr;
    double soil_next, runoff;
    if (net <= 0) {
      soil_next = std::max(0.0, soil + net);
      runoff = 0;
    } else {
      double c = cap_from_storage(dist, soil);
      double next_s = storage_from_cap(dist, c + net);
      soil_next = std::min(soil + net, std::max(soil, next_s));
      runoff = std::max(0.0, net - (soil_next - soil));
    }
    double fast = runoff;
    double slow = dr;
    if (in.recharge == PDM_RECHARGE_SPLIT) {
      fast = runoff * in.alpha;
      slow = runoff * (1 - in.alpha);
    }
    Route surf = route_step(srf, surface, fast / dt, dt);
    Route gw = route_step(gwr, ground, slow / dt, dt);
    double d1 = delay(ds, work, surf.outflow, ratio);
    double d2 = delay(dg, work, gw.outflow, ratio);
    double e1 = delay(dse, work, surf.q_end, ratio);
    double e2 = delay(dge, work, gw.q_end, ratio);
    soil = soil_next;
    step = step + 1;
    check(std::isfinite(soil) && std::isfinite(surface[0]) && std::isfinite(surface[1]) &&
            std::isfinite(ground[0]) && std::isfinite(ground[1]),
          "Invalid parameter(s): non-finite model state");
    double natural = d1 + d2;
    q[i] = natural / dt * factor + in.qc;
    q_end[i] = (e1 + e2) * factor + in.qc;
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
      col(19, i) = store_sum(srf, surface);
      col(20, i) = store_sum(gwr, ground);
      col(21, i) = rsum(ds) + rsum(dg);
      col(22, i) = cap_cdf(dist, cap_from_storage(dist, soil));
      col(23, i) = residual;
    }
  }

  state[0] = soil;
  state[1] = surface[0];
  state[2] = surface[1];
  state[3] = ground[0];
  state[4] = ground[1];
  state[5] = step;
  for (std::size_t j = 0; j < n_pending; ++j) {
    state[6 + j] = ds[j];
    state[6 + n_pending + j] = dg[j];
    state[6 + 2 * n_pending + j] = dse[j];
    state[6 + 3 * n_pending + j] = dge[j];
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
  return 6 + 4 * pending_length(*params);
}

int32_t pdm_initial_state(const pdm_params* params, double soil_fraction, double* state,
                          int64_t state_length, char* message, int64_t message_length) {
  return guarded(message, message_length, [&]() {
    if (params == nullptr) throw ArgumentError("params must not be null");
    validate(*params);
    if (!(std::isfinite(soil_fraction) && soil_fraction >= 0 && soil_fraction <= 1)) {
      throw ArgumentError("soil_fraction must lie in [0,1]");
    }
    if (state == nullptr || state_length != 6 + 4 * pending_length(*params)) {
      throw ArgumentError("state must hold pdm_state_length() values");
    }
    for (int64_t i = 0; i < state_length; ++i) state[i] = 0;
    state[0] = soil_fraction * make_dist(*params).smax;
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
