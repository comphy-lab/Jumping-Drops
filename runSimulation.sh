#!/bin/bash
# runSimulation.sh - Run a single Jumping Drops case from the repository root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QCC_FLAGS="${QCC_FLAGS:-}"
MPI_LAUNCHER="${MPI_LAUNCHER:-mpirun}"
MPI_LAUNCHER_NFLAG="${MPI_LAUNCHER_NFLAG:--np}"

if [ -f "${SCRIPT_DIR}/.project_config" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.project_config"
else
  echo "ERROR: .project_config not found" >&2
  echo "       Copy .project_config.example or create a local project config first." >&2
  exit 1
fi

if [ -f "${SCRIPT_DIR}/src-local/parse_params.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/src-local/parse_params.sh"
else
  echo "ERROR: src-local/parse_params.sh not found" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: ./runSimulation.sh [OPTIONS] [params_file]

Run a single jumping-drops case from the repository root.
The script creates or reuses simulationCases/<CaseNo>/, copies the parameter
file to case.params, compiles the required executable(s), and passes case.params
to the compiled binary.

Options:
  -c, --compile-only   Compile but do not execute the case
  --init-only          Run only the STL initialization phase
  --main-only          Run only the main simulation phase
  -d, --debug          Compile with -g -DTRASH=1
  -m, --mpi            Enable MPI for the main phase
  --cores N            Number of MPI ranks (default: 4)
  -v, --verbose        Print the executed compile/run commands
  -h, --help           Show this help message

Examples:
  ./runSimulation.sh
  ./runSimulation.sh --init-only default.params
  ./runSimulation.sh --main-only --mpi --cores 8 default.params
EOF
}

COMPILE_ONLY=0
INIT_ONLY=0
MAIN_ONLY=0
DEBUG_FLAGS=""
VERBOSE=0
MPI_ENABLED=0
MPI_CORES=4

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--compile-only)
      COMPILE_ONLY=1
      shift
      ;;
    --init-only)
      INIT_ONLY=1
      shift
      ;;
    --main-only)
      MAIN_ONLY=1
      shift
      ;;
    -d|--debug)
      DEBUG_FLAGS="-g -DTRASH=1"
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
    -v|--verbose)
      VERBOSE=1
      shift
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

if [ "$INIT_ONLY" -eq 1 ] && [ "$MAIN_ONLY" -eq 1 ]; then
  echo "ERROR: Cannot specify both --init-only and --main-only" >&2
  exit 1
fi

if [ "$MPI_ENABLED" -eq 1 ]; then
  if ! command -v mpicc >/dev/null 2>&1; then
    echo "ERROR: mpicc not found. MPI compilation requires mpicc." >&2
    exit 1
  fi
  if ! command -v "$MPI_LAUNCHER" >/dev/null 2>&1; then
    echo "ERROR: MPI launcher '$MPI_LAUNCHER' not found." >&2
    exit 1
  fi
fi

PARAM_FILE="${1:-default.params}"
if [ ! -f "$PARAM_FILE" ]; then
  echo "ERROR: Parameter file not found: $PARAM_FILE" >&2
  exit 1
fi

PARAM_FILE_ABS="$(cd "$(dirname "$PARAM_FILE")" && pwd)/$(basename "$PARAM_FILE")"

require_params "$PARAM_FILE_ABS" CaseNo Oh Bo MAXlevel tmax || exit 1
CASE_NO="$(get_param "CaseNo")"
validate_case_no "$CASE_NO" || exit 1

OH_VALUE="$(get_param "Oh")"
BO_VALUE="$(get_param "Bo")"
MAXLEVEL_VALUE="$(get_param "MAXlevel")"
TMAX_VALUE="$(get_param "tmax")"

CASE_DIR="${SCRIPT_DIR}/simulationCases/${CASE_NO}"
CASE_PARAM_FILE="${CASE_DIR}/case.params"

PHASE_MODE="both"
if [ "$INIT_ONLY" -eq 1 ]; then
  PHASE_MODE="init"
elif [ "$MAIN_ONLY" -eq 1 ]; then
  PHASE_MODE="main"
fi

echo "========================================="
echo "Jumping Drops Simulation - Single Case"
echo "========================================="
echo "Case Number: $CASE_NO"
echo "Case Directory: $CASE_DIR"
echo "Parameter File: $PARAM_FILE_ABS"
echo "Phase Mode: $PHASE_MODE"
echo "Parameters: Oh=$OH_VALUE, Bo=$BO_VALUE, MAXlevel=$MAXLEVEL_VALUE, tmax=$TMAX_VALUE"
if [ "$MPI_ENABLED" -eq 1 ]; then
  echo "Execution Mode: MPI Parallel ($MPI_CORES cores)"
else
  echo "Execution Mode: Serial"
fi
echo

mkdir -p "$CASE_DIR"

if [ "$PARAM_FILE_ABS" != "$CASE_PARAM_FILE" ]; then
  cp "$PARAM_FILE_ABS" "$CASE_PARAM_FILE"
fi

cd "$CASE_DIR"

echo "========================================="
echo "Compilation"
echo "========================================="

if [ "$PHASE_MODE" = "init" ] || [ "$PHASE_MODE" = "both" ]; then
  if [ ! -f "../jumpingDrops_init.c" ]; then
    echo "ERROR: Source file ../jumpingDrops_init.c not found" >&2
    exit 1
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    echo "Command: qcc -I../../src-local -O2 -Wall -disable-dimensions ${DEBUG_FLAGS} ${QCC_FLAGS} ../jumpingDrops_init.c -o jumpingDrops_init -lm"
  fi

  qcc -I../../src-local \
    -O2 -Wall -disable-dimensions \
    ${DEBUG_FLAGS} ${QCC_FLAGS} \
    ../jumpingDrops_init.c -o jumpingDrops_init -lm
fi

if [ "$PHASE_MODE" = "main" ] || [ "$PHASE_MODE" = "both" ]; then
  if [ ! -f "../jumpingDrops_main.c" ]; then
    echo "ERROR: Source file ../jumpingDrops_main.c not found" >&2
    exit 1
  fi

  if [ "$MPI_ENABLED" -eq 1 ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
      if [ "$VERBOSE" -eq 1 ]; then
        echo "Command: CC99='mpicc -std=c99' qcc -I../../src-local -Wall -O2 -D_MPI=1 -disable-dimensions ${DEBUG_FLAGS} ${QCC_FLAGS} ../jumpingDrops_main.c -o jumpingDrops_main -lm"
      fi

      CC99='mpicc -std=c99' qcc -I../../src-local \
        -Wall -O2 -D_MPI=1 -disable-dimensions \
        ${DEBUG_FLAGS} ${QCC_FLAGS} \
        ../jumpingDrops_main.c -o jumpingDrops_main -lm
    else
      if [ "$VERBOSE" -eq 1 ]; then
        echo "Command: CC99='mpicc -std=c99 -D_GNU_SOURCE=1' qcc -I../../src-local -Wall -O2 -D_MPI=1 -disable-dimensions ${DEBUG_FLAGS} ${QCC_FLAGS} ../jumpingDrops_main.c -o jumpingDrops_main -lm"
      fi

      CC99='mpicc -std=c99 -D_GNU_SOURCE=1' qcc -I../../src-local \
        -Wall -O2 -D_MPI=1 -disable-dimensions \
        ${DEBUG_FLAGS} ${QCC_FLAGS} \
        ../jumpingDrops_main.c -o jumpingDrops_main -lm
    fi
  else
    if [ "$VERBOSE" -eq 1 ]; then
      echo "Command: qcc -I../../src-local -O2 -Wall -disable-dimensions ${DEBUG_FLAGS} ${QCC_FLAGS} ../jumpingDrops_main.c -o jumpingDrops_main -lm"
    fi

    qcc -I../../src-local \
      -O2 -Wall -disable-dimensions \
      ${DEBUG_FLAGS} ${QCC_FLAGS} \
      ../jumpingDrops_main.c -o jumpingDrops_main -lm
  fi
fi

if [ "$COMPILE_ONLY" -eq 1 ]; then
  echo
  echo "Compile-only mode: stopping before execution"
  exit 0
fi

echo
echo "========================================="
echo "Execution"
echo "========================================="

if [ "$PHASE_MODE" = "init" ] || [ "$PHASE_MODE" = "both" ]; then
  echo "Phase 1: Initialization (STL -> dumpInit)"
  if [ "$VERBOSE" -eq 1 ]; then
    echo "Command: ./jumpingDrops_init case.params"
  fi

  ./jumpingDrops_init case.params

  if [ ! -f "dumpInit" ]; then
    echo "ERROR: dumpInit was not created" >&2
    exit 1
  fi

  cp dumpInit dump
fi

if [ "$PHASE_MODE" = "main" ] || [ "$PHASE_MODE" = "both" ]; then
  if [ ! -f "dump" ]; then
    echo "ERROR: dump file not found. Run the initialization phase first." >&2
    exit 1
  fi

  echo "Phase 2: Main Simulation"
  if [ "$MPI_ENABLED" -eq 1 ]; then
    if [ "$VERBOSE" -eq 1 ]; then
      echo "Command: $MPI_LAUNCHER $MPI_LAUNCHER_NFLAG $MPI_CORES ./jumpingDrops_main case.params"
    fi
    "$MPI_LAUNCHER" "$MPI_LAUNCHER_NFLAG" "$MPI_CORES" ./jumpingDrops_main case.params
  else
    if [ "$VERBOSE" -eq 1 ]; then
      echo "Command: ./jumpingDrops_main case.params"
    fi
    ./jumpingDrops_main case.params
  fi
fi

echo
echo "========================================="
echo "Summary"
echo "========================================="
echo "Completed $PHASE_MODE phase(s) for case $CASE_NO"
echo "Output location: $CASE_DIR"
