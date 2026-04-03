/**
# Typed Runtime Parameter Accessors

Provides typed helpers on top of `parse_params.h` for Basilisk entry points.

## Behavior

- Missing keys fall back to the supplied default and emit a warning
- Malformed values also fall back to the supplied default and emit a warning
- `param_bool()` accepts `1/0`, `true/false`, `yes/no`, and `on/off`
*/

#ifndef JUMPING_DROPS_PARAMS_H
#define JUMPING_DROPS_PARAMS_H

#include <stdbool.h>
#include <stdlib.h>
#include <strings.h>

#include "parse_params.h"

static void params_warn_default(const char *key, const char *reason, const char *fallback) {
  fprintf(stderr, "WARNING: %s for key '%s' in %s; using default %s\n",
          reason, key, params_source_path(), fallback);
}

static int params_has_key(const char *key) {
  return params_get_raw(key) != NULL;
}

static int param_int(const char *key, int default_value) {
  const char *raw = params_get_raw(key);
  char fallback[64];
  char *end = NULL;
  long value;

  snprintf(fallback, sizeof(fallback), "%d", default_value);

  if (!raw) {
    params_warn_default(key, "Missing integer parameter", fallback);
    return default_value;
  }

  value = strtol(raw, &end, 10);
  if (end == raw || *end != '\0') {
    params_warn_default(key, "Invalid integer parameter", fallback);
    return default_value;
  }

  return (int) value;
}

static double param_double(const char *key, double default_value) {
  const char *raw = params_get_raw(key);
  char fallback[64];
  char *end = NULL;
  double value;

  snprintf(fallback, sizeof(fallback), "%.17g", default_value);

  if (!raw) {
    params_warn_default(key, "Missing floating-point parameter", fallback);
    return default_value;
  }

  value = strtod(raw, &end);
  if (end == raw || *end != '\0') {
    params_warn_default(key, "Invalid floating-point parameter", fallback);
    return default_value;
  }

  return value;
}

static bool param_bool(const char *key, bool default_value) {
  const char *raw = params_get_raw(key);
  const char *fallback = default_value ? "true" : "false";

  if (!raw) {
    params_warn_default(key, "Missing boolean parameter", fallback);
    return default_value;
  }

  if (!strcasecmp(raw, "1") || !strcasecmp(raw, "true") ||
      !strcasecmp(raw, "yes") || !strcasecmp(raw, "on"))
    return true;

  if (!strcasecmp(raw, "0") || !strcasecmp(raw, "false") ||
      !strcasecmp(raw, "no") || !strcasecmp(raw, "off"))
    return false;

  params_warn_default(key, "Invalid boolean parameter", fallback);
  return default_value;
}

static const char *param_string(const char *key, const char *default_value) {
  const char *raw = params_get_raw(key);

  if (!raw) {
    params_warn_default(key, "Missing string parameter", default_value);
    return default_value;
  }

  return raw;
}

#endif
