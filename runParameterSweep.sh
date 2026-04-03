#!/bin/bash
# runParameterSweep.sh - Generate deterministic case files and run them sequentially.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/src-local/parse_params.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/src-local/parse_params.sh"
else
  echo "ERROR: src-local/parse_params.sh not found" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: ./runParameterSweep.sh [OPTIONS] [sweep_file]

Run a deterministic parameter sweep from a sweep.params-style file.
Each generated case gets a 4-digit CaseNo, a generated case.params file,
and is executed sequentially via runSimulation.sh.

Options:
  -n, --dry-run        Show generated cases without running them
  --skip-init          Run only the main phase for each generated case
  -v, --verbose        Print extra progress information
  -c, --compile-only   Compile generated cases but do not run them
  -m, --mpi            Enable MPI for every generated case
  --cores N            Number of MPI ranks per case (default: 4)
  -h, --help           Show this help message

Examples:
  ./runParameterSweep.sh
  ./runParameterSweep.sh --dry-run sweep.params
  ./runParameterSweep.sh --mpi --cores 8 sweep.params
EOF
}

DRY_RUN=0
SKIP_INIT=0
VERBOSE=0
COMPILE_ONLY=0
MPI_ENABLED=0
MPI_CORES=4

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-init)
      SKIP_INIT=1
      shift
      ;;
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -c|--compile-only)
      COMPILE_ONLY=1
      shift
      ;;
    -m|--mpi)
      MPI_ENABLED=1
      shift
      ;;
    --cores)
      if [ $# -lt 2 ]; then
        echo "ERROR: --cores requires a positive integer" >&2
        exit 1
      fi
      MPI_CORES="$2"
      if ! [[ "$MPI_CORES" =~ ^[0-9]+$ ]] || [ "$MPI_CORES" -lt 1 ]; then
        echo "ERROR: --cores requires a positive integer, got: $MPI_CORES" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

SWEEP_FILE="${1:-sweep.params}"
if [ ! -f "$SWEEP_FILE" ]; then
  echo "ERROR: Sweep file not found: $SWEEP_FILE" >&2
  exit 1
fi

SWEEP_FILE_ABS="$(cd "$(dirname "$SWEEP_FILE")" && pwd)/$(basename "$SWEEP_FILE")"
SWEEP_DIR="$(dirname "$SWEEP_FILE_ABS")"

echo "========================================="
echo "Jumping Drops - Parameter Sweep"
echo "========================================="
echo "Sweep file: $SWEEP_FILE_ABS"
[ "$DRY_RUN" -eq 1 ] && echo "Mode: Dry run"
echo

# shellcheck disable=SC1090
source "$SWEEP_FILE_ABS"

if [ -z "${BASE_CONFIG:-}" ]; then
  echo "ERROR: BASE_CONFIG not defined in $SWEEP_FILE_ABS" >&2
  exit 1
fi

if [ -z "${CASE_START:-}" ] || [ -z "${CASE_END:-}" ]; then
  echo "ERROR: CASE_START and CASE_END must be defined in $SWEEP_FILE_ABS" >&2
  exit 1
fi

validate_case_no "$CASE_START" || exit 1
validate_case_no "$CASE_END" || exit 1

if [ "$CASE_END" -lt "$CASE_START" ]; then
  echo "ERROR: CASE_END must be >= CASE_START" >&2
  exit 1
fi

if [[ "$BASE_CONFIG" = /* ]]; then
  BASE_CONFIG_PATH="$BASE_CONFIG"
else
  BASE_CONFIG_PATH="${SWEEP_DIR}/${BASE_CONFIG}"
fi

if [ ! -f "$BASE_CONFIG_PATH" ]; then
  echo "ERROR: Base configuration file not found: $BASE_CONFIG_PATH" >&2
  exit 1
fi

require_params "$BASE_CONFIG_PATH" CaseNo Oh Bo MAXlevel tmax || exit 1

SWEEP_VARS=()
SWEEP_VALUES=()

while IFS='=' read -r key value; do
  key="$(trim_whitespace "${key%%#*}")"
  value="$(trim_whitespace "${value%%#*}")"

  [ -z "$key" ] && continue

  if [[ "$key" =~ ^SWEEP_([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
    SWEEP_VARS+=("${BASH_REMATCH[1]}")
    SWEEP_VALUES+=("$value")
  fi
done < "$SWEEP_FILE_ABS"

if [ "${#SWEEP_VARS[@]}" -eq 0 ]; then
  echo "ERROR: No SWEEP_* variables found in $SWEEP_FILE_ABS" >&2
  exit 1
fi

echo "Base configuration: $BASE_CONFIG_PATH"
echo "Case range: $CASE_START to $CASE_END"
echo "Sweep variables:"
for i in "${!SWEEP_VARS[@]}"; do
  echo "  ${SWEEP_VARS[$i]} = ${SWEEP_VALUES[$i]}"
done
echo

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jumping-drops-sweep.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

CASE_NUM="$CASE_START"
COMBINATION_COUNT=0
CASE_FILES=()

generate_combinations() {
  local depth="$1"
  shift
  local current_values=("$@")
  local case_file
  local values
  local value_array=()
  local val
  local i

  if [ "$depth" -eq "${#SWEEP_VARS[@]}" ]; then
    case_file="${TEMP_DIR}/case_$(printf "%04d" "$CASE_NUM").params"
    cp "$BASE_CONFIG_PATH" "$case_file"

    set_param_in_file "$case_file" "CaseNo" "$CASE_NUM"
    for i in "${!SWEEP_VARS[@]}"; do
      set_param_in_file "$case_file" "${SWEEP_VARS[$i]}" "${current_values[$i]}"
    done

    CASE_FILES+=("$case_file")
    COMBINATION_COUNT=$((COMBINATION_COUNT + 1))

    if [ "$DRY_RUN" -eq 1 ] || [ "$VERBOSE" -eq 1 ]; then
      echo "Case $(printf "%04d" "$CASE_NUM"):"
      for i in "${!SWEEP_VARS[@]}"; do
        echo "  ${SWEEP_VARS[$i]} = ${current_values[$i]}"
      done
      echo
    fi

    CASE_NUM=$((CASE_NUM + 1))
    return
  fi

  values="${SWEEP_VALUES[$depth]}"
  IFS=',' read -r -a value_array <<< "$values"

  for val in "${value_array[@]}"; do
    val="$(trim_whitespace "$val")"
    if [ "${#current_values[@]}" -eq 0 ]; then
      generate_combinations $((depth + 1)) "$val"
    else
      generate_combinations $((depth + 1)) "${current_values[@]}" "$val"
    fi
  done
}

generate_combinations 0

EXPECTED_COUNT=$((CASE_END - CASE_START + 1))
if [ "$COMBINATION_COUNT" -ne "$EXPECTED_COUNT" ]; then
  echo "ERROR: Generated $COMBINATION_COUNT combinations, but CASE_START/CASE_END require $EXPECTED_COUNT" >&2
  exit 1
fi

echo "Generated $COMBINATION_COUNT parameter combinations"
echo

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete. No simulations executed."
  exit 0
fi

echo "========================================="
echo "Running Simulations"
echo "========================================="
echo "Total cases: $COMBINATION_COUNT"
if [ "$MPI_ENABLED" -eq 1 ]; then
  echo "MPI ranks per case: $MPI_CORES"
fi
if [ "$SKIP_INIT" -eq 1 ]; then
  echo "Init phase: skipped"
fi
echo

for param_file in "${CASE_FILES[@]}"; do
  require_params "$param_file" CaseNo Oh Bo MAXlevel tmax || exit 1
  CASE_NO="$(get_param "CaseNo")"
  validate_case_no "$CASE_NO" || exit 1

  RUN_ARGS=()
  if [ "$SKIP_INIT" -eq 1 ]; then
    RUN_ARGS+=("--main-only")
  elif [ -f "${SCRIPT_DIR}/simulationCases/${CASE_NO}/dumpInit" ]; then
    echo "Case $CASE_NO: dumpInit found, running main phase only"
    RUN_ARGS+=("--main-only")
  else
    echo "Case $CASE_NO: running init + main"
  fi

  [ "$COMPILE_ONLY" -eq 1 ] && RUN_ARGS+=("--compile-only")
  [ "$MPI_ENABLED" -eq 1 ] && RUN_ARGS+=("--mpi" "--cores" "$MPI_CORES")
  [ "$VERBOSE" -eq 1 ] && RUN_ARGS+=("--verbose")

  "${SCRIPT_DIR}/runSimulation.sh" "${RUN_ARGS[@]}" "$param_file"
done

echo
echo "========================================="
echo "Parameter Sweep Complete"
echo "========================================="
echo "Total cases: $COMBINATION_COUNT"
echo "Case range: $CASE_START to $CASE_END"
echo "Output location: ${SCRIPT_DIR}/simulationCases"
