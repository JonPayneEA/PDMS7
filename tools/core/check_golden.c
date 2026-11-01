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
// Dependencies: C99 and the PDM core (src/pdm_core.h, src/pdm_core.c)
// ============================================================ //

   Written in plain C to prove that the interface in pdm_core.h works from C, and
   therefore from any language with a C foreign function interface. Build and run from the
   package root (see tools/core/README.md):

     gcc -std=c99 -O2 -I src src/pdm_core.c tools/core/check_golden.c -lm -o check_golden
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

static pdm_pack_params pack_params_from(const table* t, int row) {
  pdm_pack_params p;
  p.precipitation_factor = cell(t, row, "precipitation_factor");
  p.lower_rate_h = cell(t, row, "lower_rate_h");
  p.upper_rate_h = cell(t, row, "upper_rate_h");
  p.retention_fraction = cell(t, row, "retention_fraction");
  p.melt_factor_mmh_c = cell(t, row, "melt_factor_mmh_c");
  p.adc_alpha = cell(t, row, "adc_alpha");
  p.adc_depth_mm = cell(t, row, "adc_depth_mm");
  p.melt_threshold_c = cell(t, row, "melt_threshold_c");
  p.snow_threshold_c = cell(t, row, "snow_threshold_c");
  p.drain_threshold_c = cell(t, row, "drain_threshold_c");
  p.max_step_min = cell(t, row, "max_step_min");
  p.areal_depletion = (int32_t)cell(t, row, "areal_depletion");
  p.reserved = 0;
  return p;
}

static int find_row(const table* t, const char* label) {
  for (int i = 0; i < t->nrow; ++i) {
    if (strcmp(t->labels[i], label) == 0) return i;
  }
  fprintf(stderr, "missing case %s\n", label);
  exit(2);
}

/* Compares n_cols columns of got (column by column, n rows) with a CSV table. */
static double compare_columns(const double* got, const table* want, int n_cols, long n,
                              const char* (*name_of)(int32_t), int* names_ok) {
  double worst = 0;
  double* col = malloc(sizeof(double) * (size_t)n);
  *names_ok = want->ncol == n_cols;
  for (int j = 0; *names_ok && j < n_cols; ++j) {
    *names_ok = strcmp(want->names[j], name_of(j)) == 0;
    for (long i = 0; *names_ok && i < n; ++i) col[i] = want->values[i * want->ncol + j];
    if (*names_ok) worst = fmax(worst, scaled_error(got + (size_t)j * (size_t)n, col, n));
  }
  free(col);
  return worst;
}

/* PACK alone, PACK invalid parameter sets, and PACK feeding PDM. Returns the failure count. */
static int check_snow(const char* dir, const table* pdm_cases) {
  char path[1024], message[256];
  table forcing, cases, invalid, snow;
  int failures = 0;
  snprintf(path, sizeof(path), "%s/pack_forcing.csv", dir);
  if (!read_table(path, 0, &forcing)) return 1;
  long n = forcing.nrow;
  double* precip = malloc(sizeof(double) * (size_t)n);
  double* temp = malloc(sizeof(double) * (size_t)n);
  double* pet = malloc(sizeof(double) * (size_t)n);
  double* effective = malloc(sizeof(double) * (size_t)n);
  double* fluxes = malloc(sizeof(double) * (size_t)n * PDM_PACK_N_FLUX);
  double* pdm_fluxes = malloc(sizeof(double) * (size_t)n * PDM_N_FLUX);
  double* q = malloc(sizeof(double) * (size_t)n);
  double* q_end = malloc(sizeof(double) * (size_t)n);
  for (long i = 0; i < n; ++i) {
    precip[i] = forcing.values[i * 3];
    temp[i] = forcing.values[i * 3 + 1];
    pet[i] = forcing.values[i * 3 + 2];
  }

  snprintf(path, sizeof(path), "%s/pack_cases.csv", dir);
  if (!read_table(path, 1, &cases)) return 1;
  for (int c = 0; c < cases.nrow; ++c) {
    const char* name = cases.labels[c];
    pdm_pack_params p = pack_params_from(&cases, c);
    table init, final_state, want;
    double state[PDM_PACK_STATE_LENGTH], worst = 0;
    int names_ok = 0;
    snprintf(path, sizeof(path), "%s/%s_pack_initial_state.csv", dir, name);
    read_table(path, 0, &init);
    snprintf(path, sizeof(path), "%s/%s_pack_final_state.csv", dir, name);
    read_table(path, 0, &final_state);
    snprintf(path, sizeof(path), "%s/%s_pack_fluxes.csv", dir, name);
    read_table(path, 0, &want);
    for (int i = 0; i < PDM_PACK_STATE_LENGTH; ++i) state[i] = init.values[i];
    int32_t code = pdm_pack_run(&p, precip, temp, n, cell(&cases, c, "dt"), state, effective,
                                fluxes, message, (int64_t)sizeof(message));
    int ok = code == PDM_OK;
    if (ok) worst = compare_columns(fluxes, &want, PDM_PACK_N_FLUX, n, pdm_pack_flux_name,
                                    &names_ok);
    ok = ok && names_ok;
    if (ok) worst = fmax(worst, scaled_error(state, final_state.values, PDM_PACK_STATE_LENGTH));
    ok = ok && worst <= TOLERANCE;
    printf("%s pack %-15s largest scaled error %.3g%s%s\n", ok ? "PASS" : "FAIL", name, worst,
           code == PDM_OK ? "" : ": ", code == PDM_OK ? "" : message);
    failures += !ok;
    free_table(&init);
    free_table(&final_state);
    free_table(&want);
  }

  snprintf(path, sizeof(path), "%s/pack_invalid_cases.csv", dir);
  if (!read_table(path, 1, &invalid)) return 1;
  for (int c = 0; c < invalid.nrow; ++c) {
    pdm_pack_params p = pack_params_from(&invalid, c);
    double state[PDM_PACK_STATE_LENGTH] = {0, 0, 0, 0, 0}, r1[1] = {1}, t1[1] = {0}, e1[1];
    int32_t code = pdm_pack_run(&p, r1, t1, 1, 1.0, state, e1, NULL, message,
                                (int64_t)sizeof(message));
    int ok = code == (int32_t)cell(&invalid, c, "expected_code") && message[0] != '\0';
    printf("%s pack %-20s code %d: %s\n", ok ? "PASS" : "FAIL", invalid.labels[c], code,
           message);
    failures += !ok;
  }

  snprintf(path, sizeof(path), "%s/snow_cases.csv", dir);
  if (!read_table(path, 1, &snow)) return 1;
  for (int c = 0; c < snow.nrow; ++c) {
    const char* name = snow.labels[c];
    char pack_case[64], pdm_case[64];
    table pack_init, pdm_init, want, want_pdm_state, want_pack_state;
    /* The case table has text columns, so read the case names from the raw file. */
    snprintf(path, sizeof(path), "%s/snow_cases.csv", dir);
    {
      FILE* f = fopen(path, "r");
      char line[512];
      int row = -1;
      while (fgets(line, sizeof(line), f) != NULL) {
        if (row == c) {
          line[strcspn(line, "\r\n")] = '\0';
          strtok(line, ",");
          strncpy(pack_case, strtok(NULL, ","), 63);
          pack_case[63] = '\0';
          strncpy(pdm_case, strtok(NULL, ","), 63);
          pdm_case[63] = '\0';
          break;
        }
        row++;
      }
      fclose(f);
    }
    pdm_pack_params pk = pack_params_from(&cases, find_row(&cases, pack_case));
    pdm_params pd = params_from(pdm_cases, find_row(pdm_cases, pdm_case));
    snprintf(path, sizeof(path), "%s/%s_pack_initial_state.csv", dir, pack_case);
    read_table(path, 0, &pack_init);
    snprintf(path, sizeof(path), "%s/%s_initial_state.csv", dir, pdm_case);
    read_table(path, 0, &pdm_init);
    snprintf(path, sizeof(path), "%s/%s_fluxes.csv", dir, name);
    read_table(path, 0, &want);
    snprintf(path, sizeof(path), "%s/%s_final_state.csv", dir, name);
    read_table(path, 0, &want_pdm_state);
    snprintf(path, sizeof(path), "%s/%s_pack_final_state.csv", dir, name);
    read_table(path, 0, &want_pack_state);
    double pack_state[PDM_PACK_STATE_LENGTH], worst = 0;
    long len = (long)pdm_state_length(&pd);
    double* pdm_state = malloc(sizeof(double) * (size_t)len);
    int names_ok = 0;
    for (int i = 0; i < PDM_PACK_STATE_LENGTH; ++i) pack_state[i] = pack_init.values[i];
    for (long i = 0; i < len; ++i) pdm_state[i] = pdm_init.values[i];
    int32_t code = pdm_snow_run(&pd, &pk, precip, temp, pet, n, pdm_state, len, pack_state, q,
                                q_end, pdm_fluxes, NULL, message, (int64_t)sizeof(message));
    int ok = code == PDM_OK;
    if (ok) worst = compare_columns(pdm_fluxes, &want, PDM_N_FLUX, n, pdm_flux_name, &names_ok);
    ok = ok && names_ok;
    if (ok) {
      worst = fmax(worst, scaled_error(pdm_state, want_pdm_state.values, len));
      worst = fmax(worst, scaled_error(pack_state, want_pack_state.values,
                                       PDM_PACK_STATE_LENGTH));
    }
    ok = ok && worst <= TOLERANCE;
    printf("%s snow %-15s largest scaled error %.3g%s%s\n", ok ? "PASS" : "FAIL", name, worst,
           code == PDM_OK ? "" : ": ", code == PDM_OK ? "" : message);
    failures += !ok;
    free(pdm_state);
    free_table(&pack_init);
    free_table(&pdm_init);
    free_table(&want);
    free_table(&want_pdm_state);
    free_table(&want_pack_state);
  }

  free(precip);
  free(temp);
  free(pet);
  free(effective);
  free(fluxes);
  free(pdm_fluxes);
  free(q);
  free(q_end);
  free_table(&forcing);
  free_table(&cases);
  free_table(&invalid);
  free_table(&snow);
  return failures;
}

/* Reads the text in column col of data row row (0-based) of a CSV file. */
static void text_cell(const char* path, int row, int col, char* out, size_t size) {
  FILE* f = fopen(path, "r");
  char line[MAX_LINE];
  int r = -1;
  out[0] = '\0';
  while (f != NULL && fgets(line, sizeof(line), f) != NULL) {
    if (r == row) {
      char* tok;
      int c = 0;
      line[strcspn(line, "\r\n")] = '\0';
      for (tok = strtok(line, ","); tok != NULL; tok = strtok(NULL, ","), ++c) {
        if (c == col) {
          strncpy(out, tok, size - 1);
          out[size - 1] = '\0';
          break;
        }
      }
      break;
    }
    r++;
  }
  if (f != NULL) fclose(f);
}

/* State correction and ARMA error prediction. Returns the failure count. */
static int check_updating(const char* dir, const table* pdm_cases) {
  char path[1024], message[256], pdm_case[64];
  table cases, expected, history, forecast, arma;
  int failures = 0;
  snprintf(path, sizeof(path), "%s/correction_cases.csv", dir);
  if (!read_table(path, 1, &cases)) return 1;
  snprintf(path, sizeof(path), "%s/correction_expected.csv", dir);
  if (!read_table(path, 1, &expected)) return 1;
  for (int c = 0; c < cases.nrow; ++c) {
    const char* name = cases.labels[c];
    table init, want_state;
    pdm_state_updater u;
    pdm_correction out;
    snprintf(path, sizeof(path), "%s/correction_cases.csv", dir);
    text_cell(path, c, 1, pdm_case, sizeof(pdm_case));
    pdm_params pd = params_from(pdm_cases, find_row(pdm_cases, pdm_case));
    u.scheme = (int32_t)cell(&cases, c, "scheme");
    u.soil_proportional = (int32_t)cell(&cases, c, "soil_proportional");
    u.gb = cell(&cases, c, "gb");
    u.gs = cell(&cases, c, "gs");
    u.gg = cell(&cases, c, "gg");
    u.beta1 = cell(&cases, c, "beta1");
    u.beta2 = cell(&cases, c, "beta2");
    int32_t expected_code = (int32_t)cell(&cases, c, "expected_code");
    snprintf(path, sizeof(path), "%s/%s_final_state.csv", dir, pdm_case);
    read_table(path, 0, &init);
    long len = (long)pdm_state_length(&pd);
    double* state = malloc(sizeof(double) * (size_t)len);
    for (long i = 0; i < len; ++i) state[i] = init.values[i];
    int32_t code = pdm_correct_state(&pd, &u, cell(&cases, c, "observed_m3s"), state, len, &out,
                                     message, (int64_t)sizeof(message));
    int ok;
    double worst = 0;
    if (expected_code != 0) {
      int unchanged = 1;
      for (long i = 0; i < len; ++i) unchanged = unchanged && state[i] == init.values[i];
      ok = code == expected_code && unchanged && message[0] != '\0';
      printf("%s %-24s code %d: %s\n", ok ? "PASS" : "FAIL", name, code, message);
    } else {
      int row = find_row(&expected, name);
      double got[4], want[4];
      got[0] = out.correction_mm;
      got[1] = out.q_corrected_m3s;
      got[2] = out.innovation_mmh;
      got[3] = out.alpha;
      want[0] = cell(&expected, row, "correction_mm");
      want[1] = cell(&expected, row, "q_corrected_m3s");
      want[2] = cell(&expected, row, "innovation_mmh");
      want[3] = cell(&expected, row, "alpha");
      ok = code == PDM_OK;
      if (ok) {
        snprintf(path, sizeof(path), "%s/%s_corrected_state.csv", dir, name);
        read_table(path, 0, &want_state);
        worst = scaled_error(state, want_state.values, len);
        for (int k = 0; k < 4; ++k) worst = fmax(worst, scaled_error(&got[k], &want[k], 1));
        free_table(&want_state);
      }
      ok = ok && worst <= TOLERANCE;
      printf("%s %-24s largest scaled error %.3g%s%s\n", ok ? "PASS" : "FAIL", name, worst,
             code == PDM_OK ? "" : ": ", code == PDM_OK ? "" : message);
    }
    failures += !ok;
    free(state);
    free_table(&init);
  }

  snprintf(path, sizeof(path), "%s/arma_history.csv", dir);
  if (!read_table(path, 0, &history)) return 1;
  snprintf(path, sizeof(path), "%s/arma_forecast.csv", dir);
  if (!read_table(path, 0, &forecast)) return 1;
  snprintf(path, sizeof(path), "%s/arma_cases.csv", dir);
  if (!read_table(path, 1, &arma)) return 1;
  long nh = history.nrow, nf = forecast.nrow;
  double* obs = malloc(sizeof(double) * (size_t)nh);
  double* sim = malloc(sizeof(double) * (size_t)nh);
  double* updated = malloc(sizeof(double) * (size_t)nf);
  double* error_fc = malloc(sizeof(double) * (size_t)nf);
  double* innov = malloc(sizeof(double) * (size_t)nh);
  double* col = malloc(sizeof(double) * (size_t)(nh > nf ? nh : nf));
  for (long i = 0; i < nh; ++i) {
    obs[i] = history.values[i * 2];
    sim[i] = history.values[i * 2 + 1];
  }
  for (int c = 0; c < arma.nrow; ++c) {
    const char* name = arma.labels[c];
    double ar[3], ma[2], worst = 0;
    table want, want_innov;
    ar[0] = cell(&arma, c, "ar1");
    ar[1] = cell(&arma, c, "ar2");
    ar[2] = cell(&arma, c, "ar3");
    ma[0] = cell(&arma, c, "ma1");
    ma[1] = cell(&arma, c, "ma2");
    int32_t code = pdm_update_forecast(
      ar, (int32_t)cell(&arma, c, "p"), ma, (int32_t)cell(&arma, c, "q"),
      (int32_t)cell(&arma, c, "scale"), cell(&arma, c, "offset"), obs, sim, nh,
      forecast.values, nf, updated, error_fc, innov, message, (int64_t)sizeof(message));
    int ok = code == PDM_OK;
    if (ok) {
      snprintf(path, sizeof(path), "%s/%s_arma.csv", dir, name);
      read_table(path, 0, &want);
      snprintf(path, sizeof(path), "%s/%s_arma_innovations.csv", dir, name);
      read_table(path, 0, &want_innov);
      for (long i = 0; i < nf; ++i) col[i] = want.values[i * 2];
      worst = fmax(worst, scaled_error(updated, col, nf));
      for (long i = 0; i < nf; ++i) col[i] = want.values[i * 2 + 1];
      worst = fmax(worst, scaled_error(error_fc, col, nf));
      worst = fmax(worst, scaled_error(innov, want_innov.values, nh));
      free_table(&want);
      free_table(&want_innov);
    }
    ok = ok && worst <= TOLERANCE;
    printf("%s %-24s largest scaled error %.3g%s%s\n", ok ? "PASS" : "FAIL", name, worst,
           code == PDM_OK ? "" : ": ", code == PDM_OK ? "" : message);
    failures += !ok;
  }
  free(obs);
  free(sim);
  free(updated);
  free(error_fc);
  free(innov);
  free(col);
  free_table(&cases);
  free_table(&expected);
  free_table(&history);
  free_table(&forecast);
  free_table(&arma);
  return failures;
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

  failures += check_snow(dir, &cases);
  failures += check_updating(dir, &cases);

  free(rain);
  free(pet);
  free_table(&forcing);
  free_table(&cases);
  free_table(&invalid);
  printf("%s: %d failure(s)\n", failures == 0 ? "ALL PASSED" : "FAILED", failures);
  return failures == 0 ? 0 : 1;
}
