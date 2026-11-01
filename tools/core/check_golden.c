/* ============================================================ //
// Tool:         check_golden
// Description:  Checks the PDM core against the golden files, with no R involved
// Flode Module: standalone; target reach.hydro
// Author:       Claude Code (AI-generated); human maintainer attribution not supplied
// Created:      2026-10-31
// Modified:     2026-10-31 - Initial standalone checker
// Tier:         3
// Inputs:       CSV files in inst/golden
// Outputs:      Pass or fail per case on stdout; exit status 0 only if every case passes
// Dependencies: C99 and the PDM core (src/pdm_core.h, src/pdm_core.cpp)
// ============================================================ //

   Written in C, not C++, to prove that the interface in pdm_core.h works from plain C, and
   therefore from any language with a C foreign function interface. Build and run from the
   package root (see tools/core/README.md):

     g++ -std=c++11 -O2 -c src/pdm_core.cpp -o pdm_core.o
     gcc -std=c99 -O2 -I src -c tools/core/check_golden.c -o check_golden.o
     g++ check_golden.o pdm_core.o -o check_golden
     ./check_golden inst/golden
*/

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pdm_core.h"

#define MAX_COLS 48
#define MAX_LINE 8192
#define TOLERANCE 1e-12

/* A CSV table with a header. The first column may be text (kept in labels). */
typedef struct {
  int ncol, nrow;
  char names[MAX_COLS][64];
  char (*labels)[64];
  double* values; /* row-major, nrow * ncol; the text column holds 0 */
} table;

static int read_table(const char* path, int text_first, table* t) {
  FILE* f = fopen(path, "r");
  char line[MAX_LINE];
  int cap = 256;
  if (f == NULL) {
    fprintf(stderr, "cannot open %s\n", path);
    return 0;
  }
  memset(t, 0, sizeof(*t));
  if (fgets(line, sizeof(line), f) == NULL) {
    fclose(f);
    return 0;
  }
  line[strcspn(line, "\r\n")] = '\0';
  for (char* tok = strtok(line, ","); tok != NULL && t->ncol < MAX_COLS;
       tok = strtok(NULL, ",")) {
    strncpy(t->names[t->ncol], tok, 63);
    t->ncol++;
  }
  t->values = malloc(sizeof(double) * (size_t)cap * (size_t)t->ncol);
  t->labels = malloc(sizeof(*t->labels) * (size_t)cap);
  while (fgets(line, sizeof(line), f) != NULL) {
    int j = 0;
    line[strcspn(line, "\r\n")] = '\0';
    if (line[0] == '\0') continue;
    if (t->nrow == cap) {
      cap *= 2;
      t->values = realloc(t->values, sizeof(double) * (size_t)cap * (size_t)t->ncol);
      t->labels = realloc(t->labels, sizeof(*t->labels) * (size_t)cap);
    }
    for (char* tok = strtok(line, ","); tok != NULL && j < t->ncol; tok = strtok(NULL, ",")) {
      double* cell = &t->values[(size_t)t->nrow * (size_t)t->ncol + (size_t)j];
      if (j == 0 && text_first) {
        strncpy(t->labels[t->nrow], tok, 63);
        t->labels[t->nrow][63] = '\0';
        *cell = 0;
      } else {
        *cell = strtod(tok, NULL);
      }
      j++;
    }
    t->nrow++;
  }
  fclose(f);
  return 1;
}

static void free_table(table* t) {
  free(t->values);
  free(t->labels);
}

static double cell(const table* t, int row, const char* name) {
  for (int j = 0; j < t->ncol; ++j) {
    if (strcmp(t->names[j], name) == 0) return t->values[(size_t)row * (size_t)t->ncol + (size_t)j];
  }
  fprintf(stderr, "missing column %s\n", name);
  exit(2);
}

static pdm_route route_from(const table* t, int row, const char* prefix) {
  char name[96];
  pdm_route r;
#define FIELD(f) (snprintf(name, sizeof(name), "%s%s", prefix, f), cell(t, row, name))
  r.type = (int32_t)FIELD("type");
  r.smith = (int32_t)FIELD("smith");
  r.k1 = FIELD("k1");
  r.k2 = FIELD("k2");
  r.k = FIELD("k");
  r.m = FIELD("m");
  r.rtol = FIELD("rtol");
  r.atol = FIELD("atol");
  r.a = FIELD("a");
  r.gamma = FIELD("gamma");
#undef FIELD
  return r;
}

static pdm_params params_from(const table* t, int row) {
  pdm_params p;
  p.distribution = (int32_t)cell(t, row, "distribution");
  p.recharge = (int32_t)cell(t, row, "recharge");
  p.cmin = cell(t, row, "cmin");
  p.cmax = cell(t, row, "cmax");
  p.b = cell(t, row, "b");
  p.mean = cell(t, row, "mean");
  p.meanlog = cell(t, row, "meanlog");
  p.sdlog = cell(t, row, "sdlog");
  p.kg = cell(t, row, "kg");
  p.bg = cell(t, row, "bg");
  p.st = cell(t, row, "st");
  p.alpha = cell(t, row, "alpha");
  p.beta = cell(t, row, "beta");
  p.qsat = cell(t, row, "qsat");
  p.surface = route_from(t, row, "surface.");
  p.groundwater = route_from(t, row, "groundwater.");
  p.be = cell(t, row, "be");
  p.fc = cell(t, row, "fc");
  p.td = cell(t, row, "td");
  p.qc = cell(t, row, "qc");
  p.area_km2 = cell(t, row, "area_km2");
  p.dt = cell(t, row, "dt");
  return p;
}

/* Largest error relative to max(1, largest absolute expected value). */
static double scaled_error(const double* got, const double* want, long n) {
  double scale = 1, err = 0;
  for (long i = 0; i < n; ++i) scale = fmax(scale, fabs(want[i]));
  for (long i = 0; i < n; ++i) err = fmax(err, fabs(got[i] - want[i]));
  return err / scale;
}

int main(int argc, char** argv) {
  const char* dir = argc > 1 ? argv[1] : "inst/golden";
  char path[1024];
  table forcing, cases, invalid;
  int failures = 0;

  if (pdm_core_abi_version() != PDM_CORE_ABI_VERSION) {
    printf("FAIL abi version: library %d, header %d\n", pdm_core_abi_version(),
           PDM_CORE_ABI_VERSION);
    return 1;
  }
  printf("pdm_core interface version %d, sizeof(pdm_params) = %u bytes\n",
         pdm_core_abi_version(), (unsigned)sizeof(pdm_params));

  snprintf(path, sizeof(path), "%s/forcing.csv", dir);
  if (!read_table(path, 0, &forcing)) return 2;
  long n = forcing.nrow;
  double* rain = malloc(sizeof(double) * (size_t)n);
  double* pet = malloc(sizeof(double) * (size_t)n);
  for (long i = 0; i < n; ++i) {
    rain[i] = forcing.values[i * 2];
    pet[i] = forcing.values[i * 2 + 1];
  }

  snprintf(path, sizeof(path), "%s/cases.csv", dir);
  if (!read_table(path, 1, &cases)) return 2;
  for (int c = 0; c < cases.nrow; ++c) {
    const char* name = cases.labels[c];
    pdm_params p = params_from(&cases, c);
    table init, final_state, fluxes;
    char message[256];
    snprintf(path, sizeof(path), "%s/%s_initial_state.csv", dir, name);
    read_table(path, 0, &init);
    snprintf(path, sizeof(path), "%s/%s_final_state.csv", dir, name);
    read_table(path, 0, &final_state);
    snprintf(path, sizeof(path), "%s/%s_fluxes.csv", dir, name);
    read_table(path, 0, &fluxes);

    long len = (long)pdm_state_length(&p);
    double* state = malloc(sizeof(double) * (size_t)len);
    double* q = malloc(sizeof(double) * (size_t)n);
    double* q_end = malloc(sizeof(double) * (size_t)n);
    double* out = malloc(sizeof(double) * (size_t)n * PDM_N_FLUX);
    double* want = malloc(sizeof(double) * (size_t)n);
    double worst = 0;
    int ok = len == init.nrow;
    for (long i = 0; ok && i < len; ++i) state[i] = init.values[i];

    if (ok) {
      int32_t code = pdm_run(&p, rain, pet, n, state, len, q, q_end, out, message,
                             (int64_t)sizeof(message));
      ok = code == PDM_OK;
      if (!ok) printf("  %s returned %d: %s\n", name, code, message);
    }
    for (int j = 0; ok && j < PDM_N_FLUX; ++j) {
      ok = strcmp(fluxes.names[j], pdm_flux_name(j)) == 0;
      for (long i = 0; ok && i < n; ++i) want[i] = fluxes.values[i * fluxes.ncol + j];
      if (ok) worst = fmax(worst, scaled_error(out + (size_t)j * (size_t)n, want, n));
    }
    if (ok) worst = fmax(worst, scaled_error(state, final_state.values, len));
    ok = ok && worst <= TOLERANCE;
    printf("%s %-20s largest scaled error %.3g\n", ok ? "PASS" : "FAIL", name, worst);
    failures += !ok;
    free(state);
    free(q);
    free(q_end);
    free(out);
    free(want);
    free_table(&init);
    free_table(&final_state);
    free_table(&fluxes);
  }

  snprintf(path, sizeof(path), "%s/invalid_cases.csv", dir);
  if (!read_table(path, 1, &invalid)) return 2;
  for (int c = 0; c < invalid.nrow; ++c) {
    pdm_params p = params_from(&invalid, c);
    int32_t expected = (int32_t)cell(&invalid, c, "expected_code");
    double state[64] = {0};
    double q[1], q_end[1], r1[1] = {1}, e1[1] = {0.1};
    char message[256];
    long len = (long)pdm_state_length(&p);
    if (len < 0 || len > 64) len = 10;
    int32_t code = pdm_run(&p, r1, e1, 1, state, len, q, q_end, NULL, message,
                           (int64_t)sizeof(message));
    int unchanged = 1;
    for (int i = 0; i < 64; ++i) unchanged = unchanged && state[i] == 0;
    int ok = code == expected && unchanged && message[0] != '\0';
    printf("%s %-20s code %d: %s\n", ok ? "PASS" : "FAIL", invalid.labels[c], code, message);
    failures += !ok;
  }

  free(rain);
  free(pet);
  free_table(&forcing);
  free_table(&cases);
  free_table(&invalid);
  printf("%s: %d failure(s)\n", failures == 0 ? "ALL PASSED" : "FAILED", failures);
  return failures == 0 ? 0 : 1;
}
