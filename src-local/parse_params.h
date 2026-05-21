/**
# Low-Level Runtime Parameter Parser

Parses `key=value` runtime parameter files for Basilisk entry points.

## Contract

- Reads from `argv[1]` when provided, otherwise falls back to `case.params`
- Ignores blank lines and `#` comments
- Trims surrounding whitespace around keys and values
- Stores the last value seen for a duplicated key
*/

#ifndef JUMPING_DROPS_PARSE_PARAMS_H
#define JUMPING_DROPS_PARSE_PARAMS_H

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  char *key;
  char *value;
} jd_param_entry;

static jd_param_entry *jd_params = NULL;
static size_t jd_param_count = 0;
static size_t jd_param_capacity = 0;
static char *jd_param_source = NULL;

static char *jd_strdup_local(const char *src) {
  size_t n = strlen(src) + 1;
  char *dst = (char *) malloc(n);
  if (!dst) {
    fprintf(stderr, "ERROR: Out of memory while copying parameter text\n");
    exit(1);
  }
  memcpy(dst, src, n);
  return dst;
}

static char *jd_trim_inplace(char *text) {
  char *start = text;
  char *end;

  while (*start && isspace((unsigned char) *start))
    start++;

  if (*start == '\0')
    return start;

  end = start + strlen(start) - 1;
  while (end > start && isspace((unsigned char) *end)) {
    *end = '\0';
    end--;
  }

  return start;
}

static int jd_valid_key(const char *key) {
  size_t i;

  if (!key || !key[0])
    return 0;
  if (!(isalpha((unsigned char) key[0]) || key[0] == '_'))
    return 0;

  for (i = 1; key[i] != '\0'; i++)
    if (!(isalnum((unsigned char) key[i]) || key[i] == '_'))
      return 0;

  return 1;
}

static void jd_params_reset(void) {
  size_t i;

  for (i = 0; i < jd_param_count; i++) {
    free(jd_params[i].key);
    free(jd_params[i].value);
  }

  free(jd_params);
  jd_params = NULL;
  jd_param_count = 0;
  jd_param_capacity = 0;

  free(jd_param_source);
  jd_param_source = NULL;
}

static void jd_params_reserve(size_t required) {
  jd_param_entry *resized;
  size_t new_capacity = jd_param_capacity ? jd_param_capacity : 16;

  while (new_capacity < required)
    new_capacity *= 2;

  if (new_capacity == jd_param_capacity)
    return;

  resized = (jd_param_entry *) realloc(jd_params, new_capacity * sizeof(jd_param_entry));
  if (!resized) {
    fprintf(stderr, "ERROR: Out of memory while expanding parameter storage\n");
    exit(1);
  }

  jd_params = resized;
  jd_param_capacity = new_capacity;
}

static long jd_params_find_index(const char *key) {
  size_t i;

  for (i = 0; i < jd_param_count; i++)
    if (strcmp(jd_params[i].key, key) == 0)
      return (long) i;

  return -1;
}

static void jd_params_store(const char *key, const char *value, const char *source) {
  long idx = jd_params_find_index(key);

  if (idx >= 0) {
    fprintf(stderr, "WARNING: Duplicate key '%s' in %s; overriding previous value\n",
            key, source);
    free(jd_params[idx].value);
    jd_params[idx].value = jd_strdup_local(value);
    return;
  }

  jd_params_reserve(jd_param_count + 1);
  jd_params[jd_param_count].key = jd_strdup_local(key);
  jd_params[jd_param_count].value = jd_strdup_local(value);
  jd_param_count++;
}

static int params_init_from_file(const char *path) {
  FILE *fp;
  char line[4096];

  if (!path || !path[0]) {
    fprintf(stderr, "ERROR: No parameter file path provided\n");
    return 0;
  }

  fp = fopen(path, "r");
  if (!fp) {
    fprintf(stderr, "ERROR: Could not open parameter file '%s'\n", path);
    return 0;
  }

  jd_params_reset();
  jd_param_source = jd_strdup_local(path);

  while (fgets(line, sizeof(line), fp)) {
    char *hash = strchr(line, '#');
    char *equals;
    char *key;
    char *value;

    if (hash)
      *hash = '\0';

    key = jd_trim_inplace(line);
    if (!key[0])
      continue;

    equals = strchr(key, '=');
    if (!equals)
      continue;

    *equals = '\0';
    value = jd_trim_inplace(equals + 1);
    key = jd_trim_inplace(key);

    if (!key[0])
      continue;

    if (!jd_valid_key(key)) {
      fprintf(stderr, "WARNING: Skipping invalid parameter key '%s' in %s\n", key, path);
      continue;
    }

    jd_params_store(key, value, path);
  }

  fclose(fp);
  return 1;
}

static int params_init_from_argv(int argc, char *argv[]) {
  const char *path = (argc > 1 && argv[1] && argv[1][0]) ? argv[1] : "case.params";
  return params_init_from_file(path);
}

static const char *params_get_raw(const char *key) {
  long idx = jd_params_find_index(key);
  if (idx < 0)
    return NULL;
  return jd_params[idx].value;
}

static const char *params_source_path(void) {
  return jd_param_source ? jd_param_source : "<unset>";
}

#endif
