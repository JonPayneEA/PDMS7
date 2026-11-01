/* ============================================================ //
// Tool:         pdm_core
// Description:  Language-neutral C interface to the PDM time loop
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-10-31 - Interface version 2: selectable distribution, recharge, routes
// Tier:         3
// Inputs:       Parameters, state, rain and PET depths in mm per interval
// Outputs:      Flow in m3/s, optional flux table, updated state
// Dependencies: C99 standard library only
// ============================================================ //

   One source of truth for the PDM equations, callable from any language with a C foreign
   function interface: R (via the cpp11 wrapper in pdm_engine.cpp), Python (ctypes or cffi),
   the JVM (Java Foreign Function and Memory API, or JNA, from Java or Scala), Scala Native,
   Julia (ccall), MATLAB (loadlibrary) and Fortran (iso_c_binding).

   Design rules, which keep every binding simple:
   - only fixed-width integers, doubles, pointers to arrays of doubles and a char buffer cross
     the interface;
   - the core never allocates memory that the caller must free;
   - every function reports errors by return code and an optional message buffer;
   - on error, outputs are unspecified and the caller's state array is left unchanged.

   Components covered, as described by Moore (2007), doi:10.5194/hess-11-483-2007:
   - capacity distribution: Pareto, rectangular, exponential, triangular or lognormal;
   - recharge: standard, split or demand;
   - surface and groundwater routes, chosen independently: two-store cascade, power-law store
     (linear, quadratic, cubic or any positive exponent) or exponential store.
   Not covered: PACK snow. Units: depths in mm, time in hours, flow in m3/s.

   Golden test files in inst/golden/ hold inputs and expected outputs from the R reference
   implementation. Every binding should reproduce them within 1e-12 of each column's magnitude.
*/

#ifndef PDM_CORE_H
#define PDM_CORE_H

#include <stdint.h>

#if defined(_WIN32) && defined(PDM_CORE_BUILD_SHARED)
#define PDM_CORE_API __declspec(dllexport)
#else
#define PDM_CORE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Version of this interface. It changes only when a signature, struct layout, state layout,
   type code or flux column order changes. */
#define PDM_CORE_ABI_VERSION 2

/* Return codes. */
#define PDM_OK 0
#define PDM_ERR_ARGUMENT 1   /* invalid parameter, state, input or buffer size */
#define PDM_ERR_NUMERICAL 2  /* the solver failed during the run */

/* Number of columns in the optional flux table. */
#define PDM_N_FLUX 24

/* Capacity distribution types (pdm_params.distribution). */
#define PDM_DIST_PARETO 0       /* uses cmin, cmax, b */
#define PDM_DIST_RECTANGULAR 1  /* uses cmin, cmax */
#define PDM_DIST_EXPONENTIAL 2  /* uses mean */
#define PDM_DIST_TRIANGULAR 3   /* uses cmin, cmax; symmetric, mode at the midpoint */
#define PDM_DIST_LOGNORMAL 4    /* uses meanlog, sdlog */

/* Recharge types (pdm_params.recharge). */
#define PDM_RECHARGE_STANDARD 0  /* uses kg, bg, st */
#define PDM_RECHARGE_SPLIT 1     /* uses alpha: the fraction of soil runoff sent to the surface */
#define PDM_RECHARGE_DEMAND 2    /* uses alpha, beta, qsat; groundwater must not be a cascade */

/* Route types (pdm_route.type). */
#define PDM_ROUTE_CASCADE 0      /* uses k1, k2; two stores */
#define PDM_ROUTE_POWER 1        /* uses k, m, rtol, atol, smith; one store */
#define PDM_ROUTE_EXPONENTIAL 2  /* uses a, gamma; one store, signed storage coordinate */

/* One routing store or cascade. Fields not used by the chosen type are ignored.
   Layout: two 32-bit integers, then 8 doubles; 72 bytes with no padding. */
typedef struct pdm_route {
  int32_t type;   /* PDM_ROUTE_* */
  int32_t smith;  /* power only: 0 adaptive solver (recommended); 1 Smith (needs m = 3) */
  double k1;      /* cascade: first store time constant, h; > 0 */
  double k2;      /* cascade: second store time constant, h; > 0 */
  double k;       /* power: rate, q = k S^m; > 0. Cubic routing with kb uses k = 1 / kb */
  double m;       /* power: exponent; > 0. 1 linear, 2 quadratic, 3 cubic */
  double rtol;    /* power: adaptive solver relative tolerance; > 0. Default 1e-8 */
  double atol;    /* power: adaptive solver absolute tolerance, mm; > 0. Default 1e-10 */
  double a;       /* exponential: slope, per mm; > 0. q = exp(gamma + a S) */
  double gamma;   /* exponential: log-flow intercept; any finite value */
} pdm_route;

/* Model parameters. Fields not used by the chosen types are ignored; used fields must be
   finite. Layout: two 32-bit integers, 12 doubles, two pdm_route, 6 doubles; 296 bytes with
   no padding on common platforms. */
typedef struct pdm_params {
  int32_t distribution;  /* PDM_DIST_* */
  int32_t recharge;      /* PDM_RECHARGE_* */
  double cmin;           /* Pareto, rectangular, triangular: minimum capacity, mm; >= 0 */
  double cmax;           /* Pareto, rectangular, triangular: maximum capacity, mm; > cmin */
  double b;              /* Pareto: shape; >= 0 */
  double mean;           /* exponential: mean capacity, mm; > 0 */
  double meanlog;        /* lognormal: mean of log capacity; any finite value */
  double sdlog;          /* lognormal: standard deviation of log capacity; > 0 */
  double kg;             /* standard: time constant, h mm^(bg-1); > 0 */
  double bg;             /* standard: exponent; > 0 */
  double st;             /* standard: tension threshold, mm; >= 0 and <= Smax */
  double alpha;          /* split: surface fraction in [0, 1]; demand: threshold in (0, 1] */
  double beta;           /* demand: exponent; > 0 */
  double qsat;           /* demand: saturation recharge rate, mm/h; > 0 */
  pdm_route surface;     /* fast route */
  pdm_route groundwater; /* slow route */
  double be;             /* evaporation exponent; > 0 */
  double fc;             /* rainfall correction factor; >= 0 */
  double td;             /* outlet delay, h; >= 0 */
  double qc;             /* constant flow added at the outlet, m3/s; any finite value */
  double area_km2;       /* catchment area, km2; > 0 */
  double dt;             /* time step, h; > 0. 0.25 for 15-minute data */
} pdm_params;

/* Interface version compiled into the library. Compare with PDM_CORE_ABI_VERSION. */
PDM_CORE_API int32_t pdm_core_abi_version(void);

/* Number of doubles in the state array for these parameters:
   6 + 4 * (floor(td / dt) + 1). Returns -1 if dt is not positive or td is negative.
   State layout:
     [0] soil storage, mm
     [1] surface store 1          [2] surface store 2 (cascade only; otherwise 0)
     [3] groundwater store 1      [4] groundwater store 2 (cascade only; otherwise 0)
     [5] step counter
     then four delay queues of n = floor(td / dt) + 1 values each, in this order:
     surface volume, groundwater volume, surface endpoint flow, groundwater endpoint flow.
   Stores are in mm and must be >= 0, except an exponential store, whose storage is a signed
   coordinate. */
PDM_CORE_API int64_t pdm_state_length(const pdm_params* params);

/* Fills state with the standard initial state: soil at soil_fraction of Smax, all routing
   stores and delay queues at zero, step 0. soil_fraction must lie in [0, 1]. */
PDM_CORE_API int32_t pdm_initial_state(const pdm_params* params, double soil_fraction,
                                       double* state, int64_t state_length,
                                       char* message, int64_t message_length);

/* Name of flux column j (0 to PDM_N_FLUX - 1), or a null pointer if j is out of range.
   The returned string is static; do not free it. */
PDM_CORE_API const char* pdm_flux_name(int32_t j);

/* Runs the model for n steps.
   rain, pet:  n depths in mm per interval, finite and >= 0.
   state:      state_length doubles (see pdm_state_length), updated in place on success.
   q_m3s:      n values written: mean flow over each interval, m3/s.
   q_end_m3s:  n values written: flow at the end of each interval, m3/s.
   fluxes:     null, or n * PDM_N_FLUX values written column by column, so column j occupies
               fluxes[j * n] to fluxes[j * n + n - 1]. Column names from pdm_flux_name().
   message:    null, or a buffer of message_length bytes that receives a null-terminated
               error description on failure.
   Returns PDM_OK, PDM_ERR_ARGUMENT or PDM_ERR_NUMERICAL. */
PDM_CORE_API int32_t pdm_run(const pdm_params* params, const double* rain, const double* pet,
                             int64_t n, double* state, int64_t state_length, double* q_m3s,
                             double* q_end_m3s, double* fluxes, char* message,
                             int64_t message_length);

#ifdef __cplusplus
}
#endif

#endif /* PDM_CORE_H */
