/* ============================================================ //
// Tool:         pdm_core
// Description:  PDM time loop behind a language-neutral C interface (see pdm_core.h)
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-11-01 - C99 rewrite; PACK snowpack and coupled snow-PDM runs added
// Tier:         3
// Inputs:       pdm_params, state array, rain and PET depths in mm per interval
// Outputs:      Flow in m3/s, optional flux table, updated state
// Dependencies: C99 standard library only; no R or Python headers
// ============================================================ //

   Every expression mirrors the R code in model_part2.R, distributions*.R, recharge.R and
   routing*.R, in the same evaluation order. Two R 4.3 conventions are reproduced:
     - x^y evaluates x * x when y == 2 and otherwise uses pow(), as R's arithmetic does;
     - sum() accumulates each argument in long double, then adds the arguments in double.
   Results are bit-identical to the R engine on R 4.3, except for the lognormal distribution,
   where C's erfc() and R's pnorm() differ in the last places. Later R versions changed both
   conventions, so there the engines differ in the last place; tests allow for this.
   Any change to the R model code must be repeated here; tests compare the two engines and
   check the golden files in inst/golden/.

   Errors propagate through a pdm_error record: a failing function records the first error and
   returns, and every caller checks it before continuing. dmin() and dmax() reproduce the
   comparisons of std::min and std::max, including their behaviour with NaN, which fmin() and
   fmax() do not.

   The code is reentrant: it holds no global state, so separate runs may execute in parallel
   threads. Working memory is allocated and freed inside each call.
*/

#include "pdm_core.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* ---- Utilities ----------------------------------------------------------------------------- */

typedef struct {
  int32_t code;
  char text[256];
} pdm_error;

static void set_error(pdm_error* e, int32_t code, const char* text) {
  if (e->code != PDM_OK) return;
  e->code = code;
  strncpy(e->text, text, sizeof(e->text) - 1);
  e->text[sizeof(e->text) - 1] = '\0';
}

/* A failed numerical check. Returns 1 when the check passed. */
static int check(pdm_error* e, int ok, const char* text) {
  if (!ok) set_error(e, PDM_ERR_NUMERICAL, text);
  return ok;
}

static double dmin(double a, double b) { return b < a ? b : a; }
static double dmax(double a, double b) { return a < b ? b : a; }

static double rpow(double x, double y) {
  if (y == 2.0) return x * x;
  if (x == 1.0 || y == 0.0) return 1.0;
  if (x == 0.0) {
    if (y > 0.0) return 0.0;
    if (y < 0.0) return INFINITY;
    return y;
  }
  return pow(x, y);
}

static double rsum(const double* x, size_t n) {
  long double s = 0.0L;
  size_t i;
  for (i = 0; i < n; ++i) s += x[i];
  return (double)s;
}

static double rsum2(double a, double b) {
  long double s = 0.0L;
  s += a;
  s += b;
  return (double)s;
}

/* ---- Capacity distributions ---------------------------------------------------------------- */

/* The rectangular distribution is computed as Pareto with b = 1, as in R (.as_uniform), and its
   capacity mean comes from the same Pareto formula. */
typedef struct {
  int type;
  double cmin, cmax, b, mean, meanlog, sdlog;
  double smax; /* capacity_mean(distribution) */
} dist_t;

static const double k_pi = 3.141592653589793;

/* Standard normal distribution function, and its upper tail, through erfc. */
static double pnorm_lower(double x) { return 0.5 * erfc(-x / sqrt(2.0)); }
static double pnorm_upper(double x) { return 0.5 * erfc(x / sqrt(2.0)); }

static dist_t make_dist(const pdm_params* in) {
  dist_t d;
  d.type = in->distribution;
  d.cmin = in->cmin;
  d.cmax = in->cmax;
  d.mean = in->mean;
  d.meanlog = in->meanlog;
  d.sdlog = in->sdlog;
  d.b = 0;
  switch (d.type) {
    case PDM_DIST_EXPONENTIAL:
      d.smax = in->mean;
      break;
    case PDM_DIST_TRIANGULAR:
      d.smax = (in->cmin + in->cmax) / 2;
      break;
    case PDM_DIST_LOGNORMAL:
      d.smax = exp(in->meanlog + rpow(in->sdlog, 2) / 2);
      break;
    default:
      d.b = d.type == PDM_DIST_RECTANGULAR ? 1.0 : in->b;
      d.smax = d.cmin + (d.cmax - d.cmin) / (d.b + 1);
  }
  return d;
}

/* distributions_part2.R, storage_from_capacity for FlodeTriangularCapacity. */
static double triangular_storage(const dist_t* d, double c) {
  double w = d->cmax - d->cmin;
  double z = dmin(d->cmax, dmax(d->cmin, c));
  double out = z <= d->smax ? z - 2 * rpow(z - d->cmin, 3) / (3 * rpow(w, 2))
                            : d->smax - 2 * rpow(d->cmax - z, 3) / (3 * rpow(w, 2));
  return c < d->cmin ? c : out;
}

/* distributions_part2.R, .triangular_inverse: exact, by cube root or the trigonometric form of
   the cubic, then one Newton step. */
static double triangular_inverse(const dist_t* d, double si) {
  double m, w, y, dd, theta, u, f;
  if (si <= d->cmin) return si;
  m = d->smax;
  if (si >= m) return d->cmax;
  w = d->cmax - d->cmin;
  if (si >= m - w / 12) {
    y = rpow(3 * w * w * (m - si) / 2, 1.0 / 3);
    return dmin(d->cmax, dmax(m, d->cmax - y));
  }
  dd = si - d->cmin;
  theta = acos(dmax(-1.0, dmin(1.0, -3 / sqrt(2.0) * dd / w)));
  u = sqrt(2.0) * w * cos(theta / 3 - 2 * k_pi / 3);
  f = u - 2 * u * u * u / (3 * w * w) - dd;
  u = u - f / (1 - 2 * u * u / (w * w));
  return d->cmin + dmin(w / 2, dmax(0.0, u));
}

/* distributions_part2.R, storage_from_capacity for FlodeLognormalCapacity. */
static double lognormal_storage(const dist_t* d, double c) {
  double z, out;
  if (!(c > 0)) return 0;
  if (isinf(c)) return d->smax;
  z = (log(c) - d->meanlog) / d->sdlog;
  out = d->smax * pnorm_lower(z - d->sdlog) + c * pnorm_upper(z);
  return dmin(d->smax, out);
}

/* distributions_2.R, .lognormal_inverse: safeguarded Newton iteration. */
static double lognormal_inverse(const dist_t* d, double si, pdm_error* e) {
  double m, lo, hi, c, f, slope, next;
  int i;
  if (si == 0) return 0;
  m = d->smax;
  if (si >= m) return INFINITY;
  lo = 0;
  hi = dmax(1.0, m);
  while (lognormal_storage(d, hi) < si) {
    hi = hi * 2;
    if (!check(e, isfinite(hi), "Could not bracket lognormal inverse")) return 0;
  }
  c = dmin(si, hi);
  for (i = 0; i < 200; ++i) {
    f = lognormal_storage(d, c) - si;
    if (f == 0) return c;
    if (f < 0) lo = c; else hi = c;
    slope = pnorm_upper((log(c) - d->meanlog) / d->sdlog);
    next = c - f / slope;
    if (!(isfinite(next) && next > lo && next < hi)) next = (lo + hi) / 2;
    if (fabs(next - c) <= 4 * DBL_EPSILON * next) return next;
    c = next;
  }
  return c;
}

/* distributions_part3.R and distributions_part2.R. */
static double cap_from_storage(const dist_t* d, double s, pdm_error* e) {
  double z, out;
  if (d->type == PDM_DIST_TRIANGULAR || d->type == PDM_DIST_LOGNORMAL) {
    if (!check(e, s >= 0.0 && s <= d->smax, "Soil storage exceeds capacity_mean(distribution)")) {
      return 0;
    }
    return d->type == PDM_DIST_TRIANGULAR ? triangular_inverse(d, s) : lognormal_inverse(d, s, e);
  }
  if (d->type == PDM_DIST_EXPONENTIAL) {
    if (!check(e, s >= 0.0 && s <= d->mean, "Soil storage exceeds capacity_mean(distribution)")) {
      return 0;
    }
    return -d->mean * log1p(-s / d->mean);
  }
  if (!check(e, s >= 0.0 && s <= d->smax, "Soil storage exceeds capacity_mean(distribution)")) {
    return 0;
  }
  z = dmin(1.0, dmax(0.0, (s - d->cmin) / (d->smax - d->cmin)));
  out = d->cmin + (d->cmax - d->cmin) * (-expm1(log1p(-z) / (d->b + 1)));
  return s < d->cmin ? s : out;
}

/* distributions.R, distributions_part2.R and distributions_part3.R. */
static double storage_from_cap(const dist_t* d, double c) {
  double z, out;
  if (d->type == PDM_DIST_EXPONENTIAL) return d->mean * (-expm1(-c / d->mean));
  if (d->type == PDM_DIST_TRIANGULAR) return triangular_storage(d, c);
  if (d->type == PDM_DIST_LOGNORMAL) return lognormal_storage(d, c);
  z = dmin(1.0, dmax(0.0, (c - d->cmin) / (d->cmax - d->cmin)));
  out = d->cmin + (d->smax - d->cmin) * (-expm1((d->b + 1) * log1p(-z)));
  return c < d->cmin ? c : out;
}

static double cap_cdf(const dist_t* d, double c) {
  double z;
  if (d->type == PDM_DIST_EXPONENTIAL) return -expm1(-c / d->mean);
  if (d->type == PDM_DIST_TRIANGULAR) {
    z = dmin(1.0, dmax(0.0, (c - d->cmin) / (d->cmax - d->cmin)));
    return z <= 0.5 ? 2 * rpow(z, 2) : 1 - 2 * rpow(1 - z, 2);
  }
  if (d->type == PDM_DIST_LOGNORMAL) {
    if (!(c > 0)) return 0;
    if (isinf(c)) return 1;
    return pnorm_lower((log(c) - d->meanlog) / d->sdlog);
  }
  if (d->b == 0) return c >= d->cmax ? 1.0 : 0.0;
  z = dmin(1.0, dmax(0.0, (c - d->cmin) / (d->cmax - d->cmin)));
  return -expm1(d->b * log1p(-z));
}

/* ---- Routing ------------------------------------------------------------------------------- */

static int store_count(const pdm_route* r) {
  return r->type == PDM_ROUTE_CASCADE ? 2 : 1;
}

/* sum() over one route's storage vector, as R does for a vector argument. */
static double store_sum(const pdm_route* r, const double* s) {
  return store_count(r) == 2 ? rsum2(s[0], s[1]) : s[0];
}

typedef struct {
  double outflow, q_end;
} route_out;

/* routing_part3.R, .route_result. */
static route_out route_result(double old_sum, double old_abs, double new_sum, double u,
                              double dt, double q_end, pdm_error* e) {
  route_out r;
  double v = old_sum + u * dt - new_sum;
  double scale = dmax(1.0, dmax(old_abs, u * dt));
  r.outflow = 0;
  r.q_end = q_end;
  if (!check(e, isfinite(v) && v >= -1e-07 * scale,
             "FlodeRouting solver produced invalid volume")) {
    return r;
  }
  r.outflow = dmax(0.0, v);
  return r;
}

/* routing_part3.R, route_step for FlodeCascadeRouting. */
static route_out cascade_step(const pdm_route* p, double* s, double u, double dt, pdm_error* e) {
  route_out r = {0, 0};
  double e1, e2, z, cross, n1, n2, old_sum, old_abs, new_sum;
  if (!check(e, u >= 0.0 && isfinite(u), "inflow >= 0 and dt > 0 required")) return r;
  e1 = exp(-dt / p->k1);
  e2 = exp(-dt / p->k2);
  z = dt * (1 / p->k2 - 1 / p->k1);
  if (fabs(z) < 1e-06) {
    cross = e2 * dt / p->k1 * (1 + z / 2 + rpow(z, 2) / 6 + rpow(z, 3) / 24);
  } else {
    cross = p->k2 / (p->k1 - p->k2) * (e1 - e2);
  }
  n1 = s[0] * e1 + u * p->k1 * (-expm1(-dt / p->k1));
  n2 = s[1] * e2 + u * p->k2 * (-expm1(-dt / p->k2)) + (s[0] - u * p->k1) * cross;
  n1 = dmax(0.0, n1);
  n2 = dmax(0.0, n2);
  old_sum = rsum2(s[0], s[1]);
  old_abs = rsum2(fabs(s[0]), fabs(s[1]));
  new_sum = rsum2(n1, n2);
  r = route_result(old_sum, old_abs, new_sum, u, dt, n2 / p->k2, e);
  s[0] = n1;
  s[1] = n2;
  return r;
}

/* routing_2.R, .rk4. */
static double rk4_f(double z, double u, double k, double m) {
  return u - k * rpow(dmax(0.0, z), m);
}

static double rk4(double s, double h, double u, double k, double m) {
  double a = rk4_f(s, u, k, m);
  double b = rk4_f(s + h * a / 2, u, k, m);
  double c = rk4_f(s + h * b / 2, u, k, m);
  double d = rk4_f(s + h * c, u, k, m);
  return s + h * (a + 2 * b + 2 * c + d) / 6;
}

/* routing_2.R, .power_adaptive. */
static double power_adaptive(const pdm_route* p, double s, double u, double dt, pdm_error* e) {
  double target = rpow(u / p->k, 1 / p->m);
  double time = 0, h = dt, one, half, two, err, tol;
  int iterations = 0, inside;
  if (s == target) return s;
  while (time < dt) {
    iterations += 1;
    if (!check(e, iterations < 100000,
               "Routing integration did not converge; adjust tolerances/parameters")) {
      return s;
    }
    h = dmin(h, dt - time);
    one = rk4(s, h, u, p->k, p->m);
    half = rk4(s, h / 2, u, p->k, p->m);
    two = rk4(half, h / 2, u, p->k, p->m);
    err = fabs(two - one) / 15;
    tol = p->atol + p->rtol * dmax(fabs(s), fabs(two));
    inside = isfinite(two) && two >= dmin(s, target) && two <= dmax(s, target);
    if (isfinite(err) && inside && err <= tol) {
      s = two;
      time = time + h;
      if (dt - time < 1e-14 * dt) time = dt;
      h = h * (err == 0 ? 2 : dmin(2.0, dmax(0.2, 0.9 * rpow(tol / err, 0.2))));
    } else {
      h = h / 2;
    }
    if (!check(e, h > DBL_EPSILON * dmax(dt, 1.0), "Routing step underflow")) return s;
  }
  return s;
}

/* routing_2.R, route_step for FlodePowerRouting. */
static route_out power_step(const pdm_route* p, double* store, double u, double dt,
                            pdm_error* e) {
  route_out r = {0, 0};
  double s = store[0], k = p->k, m = p->m, next, lambda, phi, equilibrium, t;
  if (!check(e, u >= 0.0 && isfinite(u), "inflow >= 0 and dt > 0 required")) return r;
  if (p->smith) {
    lambda = 3 * k * rpow(s, 2);
    phi = lambda == 0 ? dt : -expm1(-lambda * dt) / lambda;
    next = s + phi * (u - k * rpow(s, 3));
  } else if (m == 1) {
    next = s * exp(-k * dt) + u * (-expm1(-k * dt)) / k;
  } else if (u == 0) {
    if (s == 0) {
      next = 0;
    } else if (m < 1) {
      next = rpow(dmax(0.0, rpow(s, 1 - m) - (1 - m) * k * dt), 1 / (1 - m));
    } else {
      next = rpow(rpow(s, 1 - m) + (m - 1) * k * dt, 1 / (1 - m));
    }
  } else if (m == 2) {
    equilibrium = sqrt(u / k);
    t = tanh(sqrt(u * k) * dt);
    next = equilibrium * (s + equilibrium * t) / (equilibrium + s * t);
  } else {
    next = power_adaptive(p, s, u, dt, e);
    if (e->code != PDM_OK) return r;
  }
  r = route_result(s, fabs(s), next, u, dt, k * rpow(next, m), e);
  store[0] = next;
  return r;
}

/* routing_2.R, route_step for FlodeExponentialRouting. The storage is a signed coordinate. */
static route_out exponential_step(const pdm_route* p, double* store, double u, double dt,
                                  pdm_error* e) {
  route_out r = {0, 0};
  double s = store[0], logq, lognext, h, t1, t2, mx, next;
  if (!check(e, u >= 0.0 && isfinite(u), "inflow >= 0 and dt > 0 required")) return r;
  logq = p->gamma + p->a * s;
  if (!check(e, isfinite(exp(logq)) && exp(logq) > 0, "Exponential flow overflow/underflow")) {
    return r;
  }
  if (u == 0) {
    lognext = logq - log1p(p->a * exp(logq) * dt);
  } else {
    h = p->a * u * dt;
    /* 1/q_next = exp(-h)/q + (1-exp(-h))/u, using log-sum-exp. */
    t1 = -h - logq;
    t2 = log(-expm1(-h)) - log(u);
    mx = dmax(t1, t2);
    lognext = -(mx + log(rsum2(exp(t1 - mx), exp(t2 - mx))));
  }
  next = (lognext - p->gamma) / p->a;
  r = route_result(s, fabs(s), next, u, dt, exp(p->gamma + p->a * next), e);
  store[0] = next;
  return r;
}

static route_out route_step(const pdm_route* p, double* store, double u, double dt,
                            pdm_error* e) {
  switch (p->type) {
    case PDM_ROUTE_CASCADE: return cascade_step(p, store, u, dt, e);
    case PDM_ROUTE_POWER: return power_step(p, store, u, dt, e);
    default: return exponential_step(p, store, u, dt, e);
  }
}

/* routing.R, storage_for_flow for a single store (used by demand recharge). */
static double storage_for_flow(const pdm_route* p, double q) {
  if (p->type == PDM_ROUTE_POWER) return rpow(q / p->k, 1 / p->m);
  return (log(q) - p->gamma) / p->a;
}

/* ---- Validation ---------------------------------------------------------------------------- */

typedef struct {
  char text[256];
  int any;
} bad_list;

static void need(bad_list* b, int ok, const char* prefix, const char* name) {
  size_t used;
  if (ok) return;
  used = strlen(b->text);
  if (used + strlen(prefix) + strlen(name) + 3 >= sizeof(b->text)) return;
  if (b->any) strcat(b->text, ", ");
  strcat(b->text, prefix);
  strcat(b->text, name);
  b->any = 1;
}

static void validate_route(bad_list* b, const pdm_route* r, const char* prefix) {
  switch (r->type) {
    case PDM_ROUTE_CASCADE:
      need(b, isfinite(r->k1) && r->k1 > 0, prefix, "k1");
      need(b, isfinite(r->k2) && r->k2 > 0, prefix, "k2");
      break;
    case PDM_ROUTE_POWER:
      need(b, isfinite(r->k) && r->k > 0, prefix, "k");
      need(b, isfinite(r->m) && r->m > 0, prefix, "m");
      need(b, r->smith == 0 || r->smith == 1, prefix, "smith");
      need(b, r->smith == 0 || r->m == 3, prefix, "smith_cubic");
      need(b, isfinite(r->rtol) && r->rtol > 0, prefix, "rtol");
      need(b, isfinite(r->atol) && r->atol > 0, prefix, "atol");
      break;
    case PDM_ROUTE_EXPONENTIAL:
      need(b, isfinite(r->a) && r->a > 0, prefix, "a");
      need(b, isfinite(r->gamma), prefix, "gamma");
      break;
    default:
      need(b, 0, prefix, "type");
  }
}

/* The same rules as the S7 validators of each component and of FlodePdmModel, and no
   stricter. Fields not used by the chosen types are ignored. Returns 1 when valid. */
static int validate(const pdm_params* in, pdm_error* e) {
  bad_list b;
  double smax, m;
  b.text[0] = '\0';
  b.any = 0;
  switch (in->distribution) {
    case PDM_DIST_PARETO:
      need(&b, isfinite(in->cmin) && in->cmin >= 0, "", "cmin");
      need(&b, isfinite(in->cmax) && in->cmax > in->cmin, "", "cmax");
      need(&b, isfinite(in->b) && in->b >= 0, "", "b");
      break;
    case PDM_DIST_RECTANGULAR:
    case PDM_DIST_TRIANGULAR:
      need(&b, isfinite(in->cmin) && in->cmin >= 0, "", "cmin");
      need(&b, isfinite(in->cmax) && in->cmax > in->cmin, "", "cmax");
      break;
    case PDM_DIST_EXPONENTIAL:
      need(&b, isfinite(in->mean) && in->mean > 0, "", "mean");
      break;
    case PDM_DIST_LOGNORMAL:
      need(&b, isfinite(in->meanlog), "", "meanlog");
      need(&b, isfinite(in->sdlog) && in->sdlog > 0, "", "sdlog");
      if (isfinite(in->meanlog) && isfinite(in->sdlog)) {
        m = exp(in->meanlog + rpow(in->sdlog, 2) / 2);
        need(&b, isfinite(m) && m > 0, "", "finite_mean");
      }
      break;
    default:
      need(&b, 0, "", "distribution");
  }
  switch (in->recharge) {
    case PDM_RECHARGE_STANDARD:
      need(&b, isfinite(in->kg) && in->kg > 0, "", "kg");
      need(&b, isfinite(in->bg) && in->bg > 0, "", "bg");
      need(&b, isfinite(in->st) && in->st >= 0, "", "st");
      break;
    case PDM_RECHARGE_SPLIT:
      need(&b, isfinite(in->alpha) && in->alpha >= 0 && in->alpha <= 1, "", "alpha");
      break;
    case PDM_RECHARGE_DEMAND:
      need(&b, isfinite(in->alpha) && in->alpha > 0 && in->alpha <= 1, "", "alpha");
      need(&b, isfinite(in->beta) && in->beta > 0, "", "beta");
      need(&b, isfinite(in->qsat) && in->qsat > 0, "", "qsat");
      break;
    default:
      need(&b, 0, "", "recharge");
  }
  validate_route(&b, &in->surface, "surface.");
  validate_route(&b, &in->groundwater, "groundwater.");
  need(&b, isfinite(in->be) && in->be > 0, "", "be");
  need(&b, isfinite(in->fc) && in->fc >= 0, "", "fc");
  need(&b, isfinite(in->td) && in->td >= 0, "", "td");
  need(&b, isfinite(in->qc), "", "qc");
  need(&b, isfinite(in->area_km2) && in->area_km2 > 0, "", "area_km2");
  need(&b, isfinite(in->dt) && in->dt > 0, "", "dt");
  if (b.any) {
    char text[300];
    strcpy(text, "Invalid parameter(s): ");
    strncat(text, b.text, sizeof(text) - strlen(text) - 1);
    set_error(e, PDM_ERR_ARGUMENT, text);
    return 0;
  }

  /* FlodePdmModel validator. */
  smax = make_dist(in).smax;
  if (in->recharge == PDM_RECHARGE_STANDARD && in->st > smax) {
    set_error(e, PDM_ERR_ARGUMENT, "st cannot exceed Smax");
    return 0;
  }
  if (in->recharge == PDM_RECHARGE_DEMAND) {
    if (in->groundwater.type == PDM_ROUTE_CASCADE) {
      set_error(e, PDM_ERR_ARGUMENT, "Demand recharge requires a single groundwater store");
      return 0;
    }
    if (storage_for_flow(&in->groundwater, in->qsat) <= 0) {
      set_error(e, PDM_ERR_ARGUMENT, "Demand recharge requires Sgmax > 0");
      return 0;
    }
    if (in->qsat * in->dt > smax) {
      set_error(e, PDM_ERR_ARGUMENT, "Demand recharge requires qsat*dt <= Smax");
      return 0;
    }
  }
  return 1;
}

static int64_t pending_length(const pdm_params* in) {
  return (int64_t)floor(in->td / in->dt) + 1;
}

static int validate_route_state(const pdm_route* r, const double* s, pdm_error* e) {
  int signed_ok = r->type == PDM_ROUTE_EXPONENTIAL;
  if (!(isfinite(s[0]) && (signed_ok || s[0] >= 0))) {
    set_error(e, PDM_ERR_ARGUMENT, "FlodeRouting storage must be finite and nonnegative");
    return 0;
  }
  if (r->type == PDM_ROUTE_CASCADE) {
    if (!(isfinite(s[1]) && s[1] >= 0)) {
      set_error(e, PDM_ERR_ARGUMENT, "FlodeRouting storage must be finite and nonnegative");
      return 0;
    }
  } else if (s[1] != 0) {
    set_error(e, PDM_ERR_ARGUMENT, "The second store of a single-store route must be 0");
    return 0;
  }
  return 1;
}

static int validate_state(const pdm_params* in, const double* state, int64_t state_length,
                          pdm_error* e) {
  int64_t n_pending = pending_length(in), i;
  double smax;
  if (state == NULL) {
    set_error(e, PDM_ERR_ARGUMENT, "state must not be null");
    return 0;
  }
  if (state_length != 6 + 4 * n_pending) {
    set_error(e, PDM_ERR_ARGUMENT,
              "Delay state incompatible with td/dt; reinitialise after changing time step");
    return 0;
  }
  smax = make_dist(in).smax;
  if (!(isfinite(state[0]) && state[0] >= 0 && state[0] <= smax)) {
    set_error(e, PDM_ERR_ARGUMENT, "Soil storage exceeds capacity_mean(distribution)");
    return 0;
  }
  if (!validate_route_state(&in->surface, state + 1, e)) return 0;
  if (!validate_route_state(&in->groundwater, state + 3, e)) return 0;
  if (!(isfinite(state[5]) && state[5] >= 0 && state[5] == floor(state[5]))) {
    set_error(e, PDM_ERR_ARGUMENT, "Invalid state dimensions");
    return 0;
  }
  for (i = 6; i < state_length; ++i) {
    if (!(isfinite(state[i]) && state[i] >= 0)) {
      set_error(e, PDM_ERR_ARGUMENT, "Delay queues must be finite and nonnegative");
      return 0;
    }
  }
  return 1;
}

/* ---- Time loop ----------------------------------------------------------------------------- */

/* model.R, .delay. */
static double delay(double* pending, double* work, size_t len, double value, double ratio) {
  double n = floor(ratio);
  double fraction = ratio - n;
  size_t i, j;
  double out;
  for (i = 0; i < len; ++i) work[i] = pending[i];
  work[len] = 0;
  j = (size_t)n;
  work[j] = work[j] + (1 - fraction) * value;
  work[j + 1] = work[j + 1] + fraction * value;
  out = work[0];
  for (i = 0; i < len; ++i) pending[i] = work[i + 1];
  return out;
}

static const char* const k_flux_names[PDM_N_FLUX] = {
  "step", "rain_mm", "rain_corrected_mm", "pet_mm", "aet_mm", "aet_requested_mm",
  "recharge_mm", "recharge_requested_mm", "direct_runoff_mm", "surface_input_mm",
  "groundwater_input_mm", "surface_out_mm", "baseflow_out_mm", "q_natural_m3s", "q_m3s",
  "q_end_m3s", "qs_end_unlagged_mmh", "qb_end_unlagged_mmh", "soil_mm", "surface_mm",
  "groundwater_mm", "delay_mm", "saturated_fraction", "balance_error_mm"
};

/* recharge.R, recharge_depth. */
static double recharge_depth(const pdm_params* in, double soil, double smax, double groundwater,
                             double dt, pdm_error* e) {
  double sgmax, g, demand, dsat;
  switch (in->recharge) {
    case PDM_RECHARGE_STANDARD:
      return rpow(dmax(0.0, soil - in->st), in->bg) / in->kg * dt;
    case PDM_RECHARGE_SPLIT:
      return 0;
    default:
      sgmax = storage_for_flow(&in->groundwater, in->qsat);
      if (!check(e, isfinite(sgmax) && sgmax > 0,
                 "Demand recharge requires positive implied Sgmax")) {
        return 0;
      }
      g = dmin(1.0, dmax(0.0, (sgmax - groundwater) / sgmax));
      demand = dmin(1.0, rpow(g / in->alpha, in->beta));
      dsat = in->qsat * dt;
      if (!check(e, dsat <= smax, "qsat*dt must not exceed Smax for the Eq. 13 demand scheme")) {
        return 0;
      }
      return (dsat + (smax - dsat) * demand) * soil / smax;
  }
}

static double total_storage(double soil, const pdm_route* srf, const double* surface,
                            const pdm_route* gwr, const double* ground, const double* ds,
                            const double* dg, size_t n_pending) {
  double t = 0;
  t += soil;
  t += store_sum(srf, surface);
  t += store_sum(gwr, ground);
  t += rsum(ds, n_pending);
  t += rsum(dg, n_pending);
  return t;
}

/* model_part2.R, pdm_step, repeated for each interval. state is the caller's working copy. */
static void run(const pdm_params* in, const double* rain, const double* pet, int64_t n_steps,
                double* state, double* q, double* q_end, double* fluxes, double* buffer,
                pdm_error* e) {
  const dist_t dist = make_dist(in);
  const pdm_route* srf = &in->surface;
  const pdm_route* gwr = &in->groundwater;
  const double dt = in->dt, smax = dist.smax;
  const size_t n_pending = (size_t)pending_length(in);
  double* ds = buffer;
  double* dg = ds + n_pending;
  double* dse = dg + n_pending;
  double* dge = dse + n_pending;
  double* work = dge + n_pending;
  double soil = state[0];
  double surface[2], ground[2];
  double step = state[5];
  const double ratio = in->td / dt;
  const double factor = in->area_km2 / 3.6;
  size_t i;
  int64_t t;
  surface[0] = state[1];
  surface[1] = state[2];
  ground[0] = state[3];
  ground[1] = state[4];
  for (i = 0; i < n_pending; ++i) {
    ds[i] = state[6 + i];
    dg[i] = state[6 + n_pending + i];
    dse[i] = state[6 + 2 * n_pending + i];
    dge[i] = state[6 + 3 * n_pending + i];
  }

#define COL(j, k) fluxes[(int64_t)(j) * n_steps + (k)]
  for (t = 0; t < n_steps; ++t) {
    double r = rain[t], ev = pet[t], old, pr, et_requested, dr_requested, et, dr, net;
    double soil_next, runoff, fast, slow, d1, d2, e1, e2, natural;
    route_out surf, gw;
    if (!(isfinite(r) && r >= 0 && isfinite(ev) && ev >= 0)) {
      set_error(e, PDM_ERR_ARGUMENT, "rain and pet must be finite nonnegative depths");
      return;
    }
    if (!check(e, soil >= 0 && soil <= smax, "Soil storage exceeds capacity_mean(distribution)")) {
      return;
    }
    old = total_storage(soil, srf, surface, gwr, ground, ds, dg, n_pending);
    pr = r * in->fc;
    et_requested = ev * (-expm1(in->be * log1p(-soil / smax)));
    dr_requested = recharge_depth(in, soil, smax, ground[0], dt, e);
    if (e->code != PDM_OK) return;
    et = dmin(et_requested, soil + pr);
    dr = dmin(dr_requested, dmax(0.0, soil + pr - et));
    net = pr - et - dr;
    if (net <= 0) {
      soil_next = dmax(0.0, soil + net);
      runoff = 0;
    } else {
      double c = cap_from_storage(&dist, soil, e), next_s;
      if (e->code != PDM_OK) return;
      next_s = storage_from_cap(&dist, c + net);
      soil_next = dmin(soil + net, dmax(soil, next_s));
      runoff = dmax(0.0, net - (soil_next - soil));
    }
    fast = runoff;
    slow = dr;
    if (in->recharge == PDM_RECHARGE_SPLIT) {
      fast = runoff * in->alpha;
      slow = runoff * (1 - in->alpha);
    }
    surf = route_step(srf, surface, fast / dt, dt, e);
    if (e->code != PDM_OK) return;
    gw = route_step(gwr, ground, slow / dt, dt, e);
    if (e->code != PDM_OK) return;
    d1 = delay(ds, work, n_pending, surf.outflow, ratio);
    d2 = delay(dg, work, n_pending, gw.outflow, ratio);
    e1 = delay(dse, work, n_pending, surf.q_end, ratio);
    e2 = delay(dge, work, n_pending, gw.q_end, ratio);
    soil = soil_next;
    step = step + 1;
    if (!check(e, isfinite(soil) && isfinite(surface[0]) && isfinite(surface[1]) &&
                    isfinite(ground[0]) && isfinite(ground[1]),
               "Invalid parameter(s): non-finite model state")) {
      return;
    }
    natural = d1 + d2;
    q[t] = natural / dt * factor + in->qc;
    q_end[t] = (e1 + e2) * factor + in->qc;
    if (fluxes != NULL) {
      double residual = old + pr - et - natural -
        total_storage(soil, srf, surface, gwr, ground, ds, dg, n_pending);
      double c_now = cap_from_storage(&dist, soil, e);
      if (e->code != PDM_OK) return;
      COL(0, t) = step;
      COL(1, t) = r;
      COL(2, t) = pr;
      COL(3, t) = ev;
      COL(4, t) = et;
      COL(5, t) = et_requested;
      COL(6, t) = dr;
      COL(7, t) = dr_requested;
      COL(8, t) = runoff;
      COL(9, t) = fast;
      COL(10, t) = slow;
      COL(11, t) = d1;
      COL(12, t) = d2;
      COL(13, t) = natural / dt * factor;
      COL(14, t) = q[t];
      COL(15, t) = q_end[t];
      COL(16, t) = surf.q_end;
      COL(17, t) = gw.q_end;
      COL(18, t) = soil;
      COL(19, t) = store_sum(srf, surface);
      COL(20, t) = store_sum(gwr, ground);
      COL(21, t) = rsum(ds, n_pending) + rsum(dg, n_pending);
      COL(22, t) = cap_cdf(&dist, c_now);
      COL(23, t) = residual;
    }
  }
#undef COL

  state[0] = soil;
  state[1] = surface[0];
  state[2] = surface[1];
  state[3] = ground[0];
  state[4] = ground[1];
  state[5] = step;
  for (i = 0; i < n_pending; ++i) {
    state[6 + i] = ds[i];
    state[6 + n_pending + i] = dg[i];
    state[6 + 2 * n_pending + i] = dse[i];
    state[6 + 3 * n_pending + i] = dge[i];
  }
}

static int32_t finish(pdm_error* e, char* message, int64_t message_length) {
  if (message != NULL && message_length > 0) {
    size_t room = (size_t)(message_length - 1);
    size_t n = strlen(e->text);
    if (n > room) n = room;
    memcpy(message, e->text, n);
    message[n] = '\0';
  }
  return e->code;
}

/* ---- Interface ----------------------------------------------------------------------------- */

int32_t pdm_core_abi_version(void) {
  return PDM_CORE_ABI_VERSION;
}

int64_t pdm_state_length(const pdm_params* params) {
  if (params == NULL || !(isfinite(params->dt) && params->dt > 0) ||
      !(isfinite(params->td) && params->td >= 0)) {
    return -1;
  }
  return 6 + 4 * pending_length(params);
}

int32_t pdm_initial_state(const pdm_params* params, double soil_fraction, double* state,
                          int64_t state_length, char* message, int64_t message_length) {
  pdm_error e;
  int64_t i;
  e.code = PDM_OK;
  e.text[0] = '\0';
  if (params == NULL) {
    set_error(&e, PDM_ERR_ARGUMENT, "params must not be null");
  } else if (validate(params, &e)) {
    if (!(isfinite(soil_fraction) && soil_fraction >= 0 && soil_fraction <= 1)) {
      set_error(&e, PDM_ERR_ARGUMENT, "soil_fraction must lie in [0,1]");
    } else if (state == NULL || state_length != 6 + 4 * pending_length(params)) {
      set_error(&e, PDM_ERR_ARGUMENT, "state must hold pdm_state_length() values");
    } else {
      for (i = 0; i < state_length; ++i) state[i] = 0;
      state[0] = soil_fraction * make_dist(params).smax;
    }
  }
  return finish(&e, message, message_length);
}

const char* pdm_flux_name(int32_t j) {
  if (j < 0 || j >= PDM_N_FLUX) return NULL;
  return k_flux_names[j];
}

/* Validates and runs PDM on a state array updated in place. Used by pdm_run() and
   pdm_snow_run(), which pass a working copy. */
static void pdm_simulate(const pdm_params* params, const double* rain, const double* pet,
                         int64_t n, double* state, int64_t state_length, double* q_m3s,
                         double* q_end_m3s, double* fluxes, pdm_error* e) {
  size_t n_pending;
  double* buffer;
  if (params == NULL) {
    set_error(e, PDM_ERR_ARGUMENT, "params must not be null");
    return;
  }
  if (!validate(params, e) || !validate_state(params, state, state_length, e)) return;
  if (n < 0) {
    set_error(e, PDM_ERR_ARGUMENT, "n must be nonnegative");
    return;
  }
  if (n > 0 && (rain == NULL || pet == NULL || q_m3s == NULL || q_end_m3s == NULL)) {
    set_error(e, PDM_ERR_ARGUMENT, "rain, pet, q_m3s and q_end_m3s must not be null");
    return;
  }
  /* Four delay queues and a scratch queue. */
  n_pending = (size_t)pending_length(params);
  buffer = (double*)malloc(sizeof(double) * (5 * n_pending + 1));
  if (buffer == NULL) {
    set_error(e, PDM_ERR_NUMERICAL, "Out of memory");
    return;
  }
  run(params, rain, pet, n, state, q_m3s, q_end_m3s, fluxes, buffer, e);
  free(buffer);
}

int32_t pdm_run(const pdm_params* params, const double* rain, const double* pet, int64_t n,
                double* state, int64_t state_length, double* q_m3s, double* q_end_m3s,
                double* fluxes, char* message, int64_t message_length) {
  pdm_error e;
  double* copy = NULL;
  e.code = PDM_OK;
  e.text[0] = '\0';
  if (state != NULL && state_length > 0) {
    copy = (double*)malloc(sizeof(double) * (size_t)state_length);
    if (copy == NULL) {
      set_error(&e, PDM_ERR_NUMERICAL, "Out of memory");
      return finish(&e, message, message_length);
    }
    memcpy(copy, state, sizeof(double) * (size_t)state_length);
  }
  /* Run on a copy so that the caller's state is unchanged if the run fails. */
  pdm_simulate(params, rain, pet, n, copy, state_length, q_m3s, q_end_m3s, fluxes, &e);
  if (e.code == PDM_OK) memcpy(state, copy, sizeof(double) * (size_t)state_length);
  free(copy);
  return finish(&e, message, message_length);
}

/* ---- PACK snowpack ------------------------------------------------------------------------- */

static const char* const k_pack_flux_names[PDM_PACK_N_FLUX] = {
  "snowfall_mm", "rainfall_mm", "melt_mm", "drainage_mm", "bypass_mm", "effective_rain_mm",
  "precipitation_corrected_mm", "dry_snow_mm", "wet_snow_mm", "snow_cover_fraction",
  "snow_balance_error_mm"
};

/* The same rules as the FlodePackModel validator. */
static int validate_pack(const pdm_pack_params* in, pdm_error* e) {
  bad_list b;
  b.text[0] = '\0';
  b.any = 0;
  need(&b, isfinite(in->precipitation_factor) && in->precipitation_factor >= 0, "",
       "precipitation_factor");
  need(&b, isfinite(in->lower_rate_h) && in->lower_rate_h >= 0, "", "lower_rate_h");
  need(&b, isfinite(in->upper_rate_h) && in->upper_rate_h >= 0, "", "upper_rate_h");
  need(&b, isfinite(in->retention_fraction) && in->retention_fraction >= 0 &&
             in->retention_fraction < 1, "", "retention_fraction");
  need(&b, isfinite(in->melt_factor_mmh_c) && in->melt_factor_mmh_c >= 0, "",
       "melt_factor_mmh_c");
  need(&b, isfinite(in->adc_alpha) && in->adc_alpha > 0 && in->adc_alpha <= 1, "", "adc_alpha");
  need(&b, isfinite(in->adc_depth_mm) && in->adc_depth_mm > 0, "", "adc_depth_mm");
  need(&b, isfinite(in->melt_threshold_c), "", "melt_threshold_c");
  need(&b, isfinite(in->snow_threshold_c), "", "snow_threshold_c");
  need(&b, isfinite(in->drain_threshold_c), "", "drain_threshold_c");
  need(&b, in->areal_depletion == 0 || in->areal_depletion == 1, "", "areal_depletion");
  need(&b, isfinite(in->max_step_min) && in->max_step_min > 0, "", "max_step_min");
  if (b.any) {
    char text[300];
    strcpy(text, "Invalid parameter(s): ");
    strncat(text, b.text, sizeof(text) - strlen(text) - 1);
    set_error(e, PDM_ERR_ARGUMENT, text);
    return 0;
  }
  return 1;
}

/* The same rules as the FlodePackState validator. */
static int validate_pack_state(const double* s, pdm_error* e) {
  if (s == NULL) {
    set_error(e, PDM_ERR_ARGUMENT, "pack state must not be null");
    return 0;
  }
  if (!(isfinite(s[0]) && s[0] >= 0 && isfinite(s[1]) && s[1] >= 0 && isfinite(s[2]) &&
        s[2] >= 0 && isfinite(s[3]) && s[3] >= 0 && s[3] <= 1 && isfinite(s[4]) && s[4] >= 0)) {
    set_error(e, PDM_ERR_ARGUMENT,
              "Invalid PACK state: stores must be finite and nonnegative, fraction in [0,1]");
    return 0;
  }
  return 1;
}

/* pack_model.R, .pack_cover. s: dry, wet, anchor, anchor fraction, fresh. */
static double pack_cover(const pdm_pack_params* m, const double* s) {
  double theta = s[0] + s[1], base, fresh;
  if (theta <= 0) return 0;
  if (!m->areal_depletion) return 1;
  base = dmin(1.0, log1p(theta) / log1p(m->adc_depth_mm));
  if (s[4] == 0 || theta <= s[2]) return base;
  fresh = s[3] + (1 - s[3]) * dmin(1.0, (theta - s[2]) / (m->adc_alpha * s[4]));
  return dmax(base, fresh);
}

/* pack_step.R, pack_step: one interval of dt hours. flux receives PDM_PACK_N_FLUX values. */
static void pack_step(const pdm_pack_params* m, double* s, double precipitation,
                      double temperature, double dt, double* flux, pdm_error* e) {
  double rate = m->lower_rate_h + m->upper_rate_h;
  double steps = ceil(dmax(dmax(dt * 60 / m->max_step_min, dt * rate), 1.0));
  double h, corrected, p, old, totals[6] = {0, 0, 0, 0, 0, 0};
  int64_t i, k;
  if (!check(e, isfinite(steps) && steps <= 100000,
             "Too many snow substeps; inspect dt and rates")) {
    return;
  }
  h = dt / steps;
  corrected = precipitation * m->precipitation_factor;
  if (!check(e, isfinite(corrected), "Corrected precipitation overflow")) return;
  p = corrected / steps;
  old = s[0] + s[1];
  for (i = 0; i < (int64_t)steps; ++i) {
    double theta = s[0] + s[1];
    double cover = pack_cover(m, s);
    double snow = temperature < m->snow_threshold_c ? p : 0;
    double rain = p - snow, dry, melt, wet, threshold, drainage, bypass;
    double add[6];
    if (snow > 0) {
      /* Consecutive snowfall grows one excursion; a depleted excursion starts anew. */
      if (s[4] == 0 || theta < s[2] + s[4] - 1e-10) {
        s[2] = theta;
        s[3] = cover;
        s[4] = snow;
      } else {
        s[4] = s[4] + snow;
      }
      cover = 1;
    }
    dry = s[0] + snow;
    melt = dmin(dry, m->melt_factor_mmh_c * dmax(0.0, temperature - m->melt_threshold_c) * h *
                       cover);
    dry = dry - melt;
    wet = s[1] + rain * cover + melt;
    threshold = m->retention_fraction * (wet + dry);
    drainage = temperature < m->drain_threshold_c
      ? 0
      : dmin(wet, h * (m->lower_rate_h * wet + m->upper_rate_h * dmax(0.0, wet - threshold)));
    bypass = rain * (1 - cover);
    s[0] = dry;
    s[1] = wet - drainage;
    if (dry + s[1] <= s[2]) s[4] = 0;
    add[0] = snow;
    add[1] = rain;
    add[2] = melt;
    add[3] = drainage;
    add[4] = bypass;
    add[5] = drainage + bypass;
    for (k = 0; k < 6; ++k) totals[k] = totals[k] + add[k];
  }
  for (k = 0; k < 6; ++k) flux[k] = totals[k];
  flux[6] = corrected;
  flux[7] = s[0];
  flux[8] = s[1];
  flux[9] = pack_cover(m, s);
  flux[10] = old + corrected - (s[0] + s[1]) - totals[5];
}

/* Validates and runs PACK on a state array updated in place. */
static void pack_simulate(const pdm_pack_params* params, const double* precipitation,
                          const double* temperature, int64_t n, double dt, double* state,
                          double* effective_rain, double* fluxes, pdm_error* e) {
  double flux[PDM_PACK_N_FLUX];
  int64_t t;
  int j;
  if (params == NULL) {
    set_error(e, PDM_ERR_ARGUMENT, "pack params must not be null");
    return;
  }
  if (!validate_pack(params, e) || !validate_pack_state(state, e)) return;
  if (!(isfinite(dt) && dt > 0)) {
    set_error(e, PDM_ERR_ARGUMENT, "dt must be positive and finite");
    return;
  }
  if (n < 0) {
    set_error(e, PDM_ERR_ARGUMENT, "n must be nonnegative");
    return;
  }
  if (n > 0 && (precipitation == NULL || temperature == NULL || effective_rain == NULL)) {
    set_error(e, PDM_ERR_ARGUMENT,
              "precipitation, temperature and effective_rain must not be null");
    return;
  }
  for (t = 0; t < n; ++t) {
    if (!(isfinite(precipitation[t]) && precipitation[t] >= 0)) {
      set_error(e, PDM_ERR_ARGUMENT, "precipitation_mm must be finite and nonnegative");
      return;
    }
    if (!isfinite(temperature[t])) {
      set_error(e, PDM_ERR_ARGUMENT, "temperature_c must be finite");
      return;
    }
    pack_step(params, state, precipitation[t], temperature[t], dt, flux, e);
    if (e->code != PDM_OK) return;
    effective_rain[t] = flux[5];
    if (fluxes != NULL) {
      for (j = 0; j < PDM_PACK_N_FLUX; ++j) fluxes[(int64_t)j * n + t] = flux[j];
    }
  }
}

const char* pdm_pack_flux_name(int32_t j) {
  if (j < 0 || j >= PDM_PACK_N_FLUX) return NULL;
  return k_pack_flux_names[j];
}

int32_t pdm_pack_run(const pdm_pack_params* params, const double* precipitation,
                     const double* temperature, int64_t n, double dt, double* state,
                     double* effective_rain, double* fluxes, char* message,
                     int64_t message_length) {
  pdm_error e;
  double copy[PDM_PACK_STATE_LENGTH];
  e.code = PDM_OK;
  e.text[0] = '\0';
  if (state == NULL) {
    set_error(&e, PDM_ERR_ARGUMENT, "pack state must not be null");
    return finish(&e, message, message_length);
  }
  memcpy(copy, state, sizeof(copy));
  pack_simulate(params, precipitation, temperature, n, dt, copy, effective_rain, fluxes, &e);
  if (e.code == PDM_OK) memcpy(state, copy, sizeof(copy));
  return finish(&e, message, message_length);
}

int32_t pdm_snow_run(const pdm_params* pdm, const pdm_pack_params* pack,
                     const double* precipitation, const double* temperature,
                     const double* pet, int64_t n, double* pdm_state, int64_t pdm_state_length,
                     double* pack_state, double* q_m3s, double* q_end_m3s, double* pdm_fluxes,
                     double* pack_fluxes, char* message, int64_t message_length) {
  pdm_error e;
  double pack_copy[PDM_PACK_STATE_LENGTH];
  double* pdm_copy = NULL;
  double* effective = NULL;
  e.code = PDM_OK;
  e.text[0] = '\0';
  if (pdm == NULL || pack_state == NULL || pdm_state == NULL || pdm_state_length <= 0 || n < 0) {
    set_error(&e, PDM_ERR_ARGUMENT,
              "pdm, pdm_state and pack_state must not be null, and n must be nonnegative");
    return finish(&e, message, message_length);
  }
  memcpy(pack_copy, pack_state, sizeof(pack_copy));
  pdm_copy = (double*)malloc(sizeof(double) * (size_t)pdm_state_length);
  effective = (double*)malloc(sizeof(double) * (size_t)(n > 0 ? n : 1));
  if (pdm_copy == NULL || effective == NULL) {
    set_error(&e, PDM_ERR_NUMERICAL, "Out of memory");
  } else {
    memcpy(pdm_copy, pdm_state, sizeof(double) * (size_t)pdm_state_length);
    /* Check PDM before spending time on the snowpack. */
    if (validate(pdm, &e) && validate_state(pdm, pdm_copy, pdm_state_length, &e)) {
      pack_simulate(pack, precipitation, temperature, n, pdm->dt, pack_copy, effective,
                    pack_fluxes, &e);
      if (e.code == PDM_OK) {
        pdm_simulate(pdm, effective, pet, n, pdm_copy, pdm_state_length, q_m3s, q_end_m3s,
                     pdm_fluxes, &e);
      }
    }
    if (e.code == PDM_OK) {
      memcpy(pack_state, pack_copy, sizeof(pack_copy));
      memcpy(pdm_state, pdm_copy, sizeof(double) * (size_t)pdm_state_length);
    }
  }
  free(pdm_copy);
  free(effective);
  return finish(&e, message, message_length);
}

/* ---- Forecast updating --------------------------------------------------------------------- */

/* routing.R, routing_flow: endpoint flow of a route's stores, mm/h. */
static double routing_flow(const pdm_route* r, const double* s) {
  switch (r->type) {
    case PDM_ROUTE_CASCADE: return s[1] / r->k2;
    case PDM_ROUTE_POWER: return r->k * rpow(s[0], r->m);
    default: return exp(r->gamma + r->a * s[0]);
  }
}

/* updating.R, .change_flow: sets a route's stores to give flow q, mm/h. A cascade keeps its
   first store and sets the second. */
static void change_flow(const pdm_route* r, double* s, double q) {
  switch (r->type) {
    case PDM_ROUTE_CASCADE:
      s[1] = q * r->k2;
      break;
    case PDM_ROUTE_POWER:
      s[0] = rpow(q / r->k, 1 / r->m);
      break;
    default:
      s[0] = (log(q) - r->gamma) / r->a;
  }
}

/* The same rules as the FlodeStateUpdater validator. */
static int validate_updater(const pdm_state_updater* u, pdm_error* e) {
  bad_list b;
  b.text[0] = '\0';
  b.any = 0;
  need(&b, u->scheme >= PDM_UPDATE_PROPORTIONAL && u->scheme <= PDM_UPDATE_NON_PROPORTIONAL, "",
       "scheme");
  need(&b, isfinite(u->gb) && u->gb >= 0, "", "gb");
  need(&b, isfinite(u->gs) && u->gs >= 0, "", "gs");
  need(&b, isfinite(u->gg) && u->gg >= 0, "", "gg");
  need(&b, isfinite(u->beta1) && u->beta1 > 0, "", "beta1");
  need(&b, isfinite(u->beta2) && u->beta2 >= 1, "", "beta2");
  need(&b, u->soil_proportional == 0 || u->soil_proportional == 1, "", "soil_proportional");
  if (b.any) {
    char text[300];
    strcpy(text, "Invalid parameter(s): ");
    strncat(text, b.text, sizeof(text) - strlen(text) - 1);
    set_error(e, PDM_ERR_ARGUMENT, text);
    return 0;
  }
  return 1;
}

/* updating.R, correct_state, on a state array updated in place. */
static void correct(const pdm_params* m, const pdm_state_updater* u, double observed,
                    double* st, int64_t state_length, pdm_correction* out, pdm_error* e) {
  const pdm_route* srf = &m->surface;
  const pdm_route* gwr = &m->groundwater;
  size_t n_pending = (size_t)pending_length(m);
  const double* ds = st + 6;
  const double* dg = st + 6 + n_pending;
  double qb, qs, epsilon, alpha, wb, ws, newb, news, old, weight, smax;
  int64_t i;
  qb = routing_flow(gwr, st + 3);
  qs = routing_flow(srf, st + 1);
  epsilon = (observed - m->qc) * 3.6 / m->area_km2 - qb - qs;
  if (qb + qs == 0) {
    alpha = 0;
  } else if (u->scheme == PDM_UPDATE_SUPER_PROPORTIONAL) {
    alpha = qb / (u->beta1 * qs + u->beta2 * qb);
  } else {
    alpha = qb / (qb + qs);
  }
  wb = u->scheme == PDM_UPDATE_NON_PROPORTIONAL ? 1 : alpha;
  ws = u->scheme == PDM_UPDATE_NON_PROPORTIONAL ? 1 : 1 - alpha;
  newb = dmax(0.0, qb + wb * u->gb * epsilon);
  news = dmax(0.0, qs + ws * u->gs * epsilon);
  if ((gwr->type == PDM_ROUTE_EXPONENTIAL && newb == 0) ||
      (srf->type == PDM_ROUTE_EXPONENTIAL && news == 0)) {
    set_error(e, PDM_ERR_NUMERICAL, "Exponential storage cannot be corrected to zero flow");
    return;
  }
  old = total_storage(st[0], srf, st + 1, gwr, st + 3, ds, dg, n_pending);
  change_flow(gwr, st + 3, newb);
  change_flow(srf, st + 1, news);
  weight = u->soil_proportional ? alpha : 1;
  smax = make_dist(m).smax;
  st[0] = dmin(smax, dmax(0.0, st[0] + weight * u->gg * epsilon));
  for (i = 0; i < 6; ++i) {
    if (!isfinite(st[i])) {
      set_error(e, PDM_ERR_NUMERICAL, "State correction produced a non-finite state");
      return;
    }
  }
  (void)state_length;
  out->correction_mm = total_storage(st[0], srf, st + 1, gwr, st + 3, ds, dg, n_pending) - old;
  out->q_corrected_m3s = (newb + news) * m->area_km2 / 3.6 + m->qc;
  out->innovation_mmh = epsilon;
  out->alpha = alpha;
}

int32_t pdm_correct_state(const pdm_params* params, const pdm_state_updater* updater,
                          double observed_m3s, double* state, int64_t state_length,
                          pdm_correction* out, char* message, int64_t message_length) {
  pdm_error e;
  double* copy = NULL;
  pdm_correction result;
  e.code = PDM_OK;
  e.text[0] = '\0';
  if (params == NULL || updater == NULL || out == NULL) {
    set_error(&e, PDM_ERR_ARGUMENT, "params, updater and out must not be null");
  } else if (validate(params, &e) && validate_state(params, state, state_length, &e)) {
    if (params->td != 0) {
      set_error(&e, PDM_ERR_ARGUMENT,
                "State correction requires td=0; delayed observations need a lag-aware smoother");
    } else if (!isfinite(observed_m3s)) {
      set_error(&e, PDM_ERR_ARGUMENT, "observed_m3s must be finite");
    } else if (validate_updater(updater, &e)) {
      copy = (double*)malloc(sizeof(double) * (size_t)state_length);
      if (copy == NULL) {
        set_error(&e, PDM_ERR_NUMERICAL, "Out of memory");
      } else {
        memcpy(copy, state, sizeof(double) * (size_t)state_length);
        correct(params, updater, observed_m3s, copy, state_length, &result, &e);
        if (e.code == PDM_OK) {
          memcpy(state, copy, sizeof(double) * (size_t)state_length);
          *out = result;
        }
      }
    }
  }
  free(copy);
  return finish(&e, message, message_length);
}

/* updating_part2.R, update_forecast, with .errors from updating.R. */
int32_t pdm_update_forecast(const double* ar, int32_t p, const double* ma, int32_t q,
                            int32_t scale, double offset, const double* observed,
                            const double* simulated, int64_t n_history, const double* forecast,
                            int64_t n_forecast, double* updated, double* error_forecast,
                            double* innovations, char* message, int64_t message_length) {
  pdm_error e;
  double *errors = NULL, *innov = NULL, *predicted = NULL;
  int64_t i, t, total;
  e.code = PDM_OK;
  e.text[0] = '\0';
  if (p < 0 || q < 0 || (p > 0 && ar == NULL) || (q > 0 && ma == NULL)) {
    set_error(&e, PDM_ERR_ARGUMENT, "ar and ma must hold p and q coefficients");
    return finish(&e, message, message_length);
  }
  for (i = 0; i < p; ++i) {
    if (!isfinite(ar[i])) set_error(&e, PDM_ERR_ARGUMENT, "Invalid parameter(s): ar");
  }
  for (i = 0; i < q; ++i) {
    if (!isfinite(ma[i])) set_error(&e, PDM_ERR_ARGUMENT, "Invalid parameter(s): ma");
  }
  if (scale != 0 && scale != 1) set_error(&e, PDM_ERR_ARGUMENT, "Invalid parameter(s): scale");
  if (!(isfinite(offset) && offset >= 0)) {
    set_error(&e, PDM_ERR_ARGUMENT, "Invalid parameter(s): offset");
  }
  if (e.code != PDM_OK) return finish(&e, message, message_length);
  if (n_forecast <= 0 || forecast == NULL || updated == NULL) {
    set_error(&e, PDM_ERR_ARGUMENT, "forecast must be finite");
    return finish(&e, message, message_length);
  }
  for (t = 0; t < n_forecast; ++t) {
    if (!isfinite(forecast[t])) {
      set_error(&e, PDM_ERR_ARGUMENT, "forecast must be finite");
      return finish(&e, message, message_length);
    }
  }
  if (n_history <= 0 || observed == NULL || simulated == NULL) {
    set_error(&e, PDM_ERR_ARGUMENT,
              "Error history needs equal-length, complete finite numeric vectors");
    return finish(&e, message, message_length);
  }
  for (t = 0; t < n_history; ++t) {
    if (!(isfinite(observed[t]) && isfinite(simulated[t]))) {
      set_error(&e, PDM_ERR_ARGUMENT,
                "Error history needs equal-length, complete finite numeric vectors");
      return finish(&e, message, message_length);
    }
    if (scale == 1 && !(observed[t] + offset > 0 && simulated[t] + offset > 0)) {
      set_error(&e, PDM_ERR_ARGUMENT, "Log updating requires positive flows plus offset");
      return finish(&e, message, message_length);
    }
  }
  total = n_history + n_forecast;
  errors = (double*)calloc((size_t)total, sizeof(double));
  innov = (double*)calloc((size_t)total, sizeof(double));
  predicted = (double*)calloc((size_t)total, sizeof(double));
  if (errors == NULL || innov == NULL || predicted == NULL) {
    set_error(&e, PDM_ERR_NUMERICAL, "Out of memory");
  } else {
    for (t = 0; t < n_history; ++t) {
      errors[t] = scale == 0 ? observed[t] - simulated[t]
                             : log(observed[t] + offset) - log(simulated[t] + offset);
    }
    /* R convention eta[t] = sum(ar*eta[t-i]) + sum(ma*a[t-j]) + a[t], 1-based as in R. */
    for (t = 1; t <= total; ++t) {
      for (i = 1; i <= p; ++i) {
        if (t > i) predicted[t - 1] = predicted[t - 1] + ar[i - 1] * errors[t - 1 - i];
      }
      for (i = 1; i <= q; ++i) {
        if (t > i) predicted[t - 1] = predicted[t - 1] + ma[i - 1] * innov[t - 1 - i];
      }
      if (t <= n_history) {
        innov[t - 1] = errors[t - 1] - predicted[t - 1];
      } else {
        errors[t - 1] = predicted[t - 1];
      }
    }
    for (t = 0; t < n_forecast && e.code == PDM_OK; ++t) {
      double correction = errors[n_history + t];
      if (scale == 0) {
        updated[t] = forecast[t] + correction;
      } else if (!(forecast[t] + offset > 0)) {
        set_error(&e, PDM_ERR_ARGUMENT, "Log forecast must be positive plus offset");
      } else {
        updated[t] = (forecast[t] + offset) * exp(correction) - offset;
      }
      if (error_forecast != NULL) error_forecast[t] = correction;
    }
    if (e.code == PDM_OK && innovations != NULL) {
      memcpy(innovations, innov, sizeof(double) * (size_t)n_history);
    }
  }
  free(errors);
  free(innov);
  free(predicted);
  return finish(&e, message, message_length);
}

/* ---- Steady-state start from an observed flow ---------------------------------------------- */

/* initial_flow.R, .steady_storage: stores giving flow q (mm/h) in equilibrium. */
static int steady_storage(const pdm_route* r, double q, double* s, const char* text,
                          pdm_error* e) {
  if (r->type == PDM_ROUTE_EXPONENTIAL && !(q > 0)) {
    set_error(e, PDM_ERR_ARGUMENT, text);
    return 0;
  }
  s[1] = 0;
  switch (r->type) {
    case PDM_ROUTE_CASCADE:
      s[0] = q * r->k1;
      s[1] = q * r->k2;
      break;
    case PDM_ROUTE_POWER:
      s[0] = rpow(q / r->k, 1 / r->m);
      break;
    default:
      s[0] = (log(q) - r->gamma) / r->a;
  }
  return 1;
}

/* initial_flow.R, .steady_queue: n full values of v, then the fractional remainder. */
static void steady_queue(double* queue, size_t len, double ratio, double v) {
  double n = floor(ratio);
  size_t i;
  for (i = 0; i < len; ++i) queue[i] = v;
  queue[len - 1] = (ratio - n) * v;
}

int32_t pdm_state_from_flow(const pdm_params* params, double observed_m3s,
                            double baseflow_fraction, double soil_fraction, double* state,
                            int64_t state_length, char* message, int64_t message_length) {
  pdm_error e;
  double q, qb, qs, smax, soil, sgmax, g, demand, dsat;
  double surface[2], ground[2];
  size_t n_pending, i;
  e.code = PDM_OK;
  e.text[0] = '\0';
  if (params == NULL || state == NULL) {
    set_error(&e, PDM_ERR_ARGUMENT, "params and state must not be null");
    return finish(&e, message, message_length);
  }
  if (!validate(params, &e)) return finish(&e, message, message_length);
  if (state_length != 6 + 4 * pending_length(params)) {
    set_error(&e, PDM_ERR_ARGUMENT, "state must hold pdm_state_length() values");
  } else if (!isfinite(observed_m3s)) {
    set_error(&e, PDM_ERR_ARGUMENT, "observed_m3s must be finite");
  } else if (!(isfinite(baseflow_fraction) && baseflow_fraction >= 0 && baseflow_fraction <= 1)) {
    set_error(&e, PDM_ERR_ARGUMENT, "baseflow_fraction must lie in [0,1]");
  } else if (!(isfinite(soil_fraction) && soil_fraction >= 0 && soil_fraction <= 1)) {
    set_error(&e, PDM_ERR_ARGUMENT, "soil_fraction must lie in [0,1]");
  }
  if (e.code != PDM_OK) return finish(&e, message, message_length);

  q = (observed_m3s - params->qc) * 3.6 / params->area_km2;
  if (!(q >= 0)) {
    set_error(&e, PDM_ERR_ARGUMENT, "observed_m3s is below the constant flow qc");
    return finish(&e, message, message_length);
  }
  qb = baseflow_fraction * q;
  qs = (1 - baseflow_fraction) * q;
  if (!steady_storage(&params->groundwater, qb, ground,
                      "An exponential groundwater store cannot start at zero flow", &e) ||
      !steady_storage(&params->surface, qs, surface,
                      "An exponential surface store cannot start at zero flow", &e)) {
    return finish(&e, message, message_length);
  }
  smax = make_dist(params).smax;
  switch (params->recharge) {
    case PDM_RECHARGE_STANDARD:
      soil = params->st + rpow(params->kg * qb, 1 / params->bg);
      break;
    case PDM_RECHARGE_DEMAND:
      sgmax = storage_for_flow(&params->groundwater, params->qsat);
      g = dmin(1.0, dmax(0.0, (sgmax - ground[0]) / sgmax));
      demand = dmin(1.0, rpow(g / params->alpha, params->beta));
      dsat = params->qsat * params->dt;
      soil = qb * params->dt * smax / (dsat + (smax - dsat) * demand);
      break;
    default:
      soil = soil_fraction * smax;
  }
  soil = dmin(smax, dmax(0.0, soil));

  n_pending = (size_t)pending_length(params);
  state[0] = soil;
  state[1] = surface[0];
  state[2] = surface[1];
  state[3] = ground[0];
  state[4] = ground[1];
  state[5] = 0;
  steady_queue(state + 6, n_pending, params->td / params->dt, qs * params->dt);
  steady_queue(state + 6 + n_pending, n_pending, params->td / params->dt, qb * params->dt);
  steady_queue(state + 6 + 2 * n_pending, n_pending, params->td / params->dt, qs);
  steady_queue(state + 6 + 3 * n_pending, n_pending, params->td / params->dt, qb);
  for (i = 0; i < 6; ++i) {
    if (!isfinite(state[i])) {
      set_error(&e, PDM_ERR_NUMERICAL, "Steady-state start produced a non-finite state");
      break;
    }
  }
  return finish(&e, message, message_length);
}
