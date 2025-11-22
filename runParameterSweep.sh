#!/bin/bash
# runParameterSweep.sh - Run parameter sweep with auto-incrementing CaseNo
# Generates parameter combinations and runs simulations in simulationCases/<CaseNo>/

set -e  # Exit on error

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source parameter parsing library
if [ -f "${SCRIPT_DIR}/src-local/parse_params.sh" ]; then
    source "${SCRIPT_DIR}/src-local/parse_params.sh"
else
    echo "ERROR: src-local/parse_params.sh not found" >&2
    exit 1
fi

# ============================================================
# Usage Information
# ============================================================
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [sweep_file]

Run parameter sweep with auto-incrementing CaseNo.
Creates case folders in simulationCases/<CaseNo>/ for each parameter combination.
Cases run sequentially (one at a time).

Options:
    -n, --dry-run        Show parameter combinations without running
    -v, --verbose        Verbose output
    -c, --compile-only   Compile only, don't run simulations
    -m, --mpi            Enable MPI parallel execution for all cases
    --cores N            Number of MPI cores (default: 4, requires --mpi)
    -h, --help          Show this help message

Parameter sweep file (default):
    $0 sweep.params

If no sweep file specified, uses sweep.params from current directory.

Sweep file format:
    BASE_CONFIG=default.params
    CASE_START=1000
    CASE_END=1011
    SWEEP_We=1.0,10.0,100.0
    SWEEP_Ohd=1e-4,1e-3,1e-2

CaseNo auto-increments from CASE_START for each parameter combination.

Examples:
    # Run sweep with default file (serial)
    $0

    # Dry run to see parameter combinations
    $0 --dry-run

    # Run sweep with MPI parallel execution (4 cores per case)
    $0 --mpi

    # Run sweep with 8 cores per case
    $0 --mpi --cores 8

    # Run custom sweep file
    $0 custom_sweep.params

For more information, see README.md
EOF
}

# ============================================================
# Parse Command Line Options
# ============================================================
DRY_RUN=0
VERBOSE=0
COMPILE_ONLY=0
MPI_ENABLED=0
MPI_CORES=4

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run)
            DRY_RUN=1
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

# ============================================================
# Determine Sweep File
# ============================================================
SWEEP_FILE="${1:-sweep.params}"

if [ ! -f "$SWEEP_FILE" ]; then
    echo "ERROR: Sweep file not found: $SWEEP_FILE" >&2
    exit 1
fi

echo "========================================="
echo "Drop Impact - Parameter Sweep"
echo "========================================="
echo "Sweep file: $SWEEP_FILE"
[ $DRY_RUN -eq 1 ] && echo "Mode: Dry run (no execution)"
echo ""

# ============================================================
# Parse Sweep Configuration
# ============================================================
# Source the sweep file to get variables
source "$SWEEP_FILE"

# Validate required variables
if [ -z "$BASE_CONFIG" ]; then
    echo "ERROR: BASE_CONFIG not defined in sweep file" >&2
    exit 1
fi

if [ -z "$CASE_START" ] || [ -z "$CASE_END" ]; then
    echo "ERROR: CASE_START and CASE_END must be defined in sweep file" >&2
    exit 1
fi

# Validate CaseNo range
if [ "$CASE_START" -lt 1000 ] || [ "$CASE_START" -gt 9999 ]; then
    echo "ERROR: CASE_START must be 4-digit (1000-9999), got: $CASE_START" >&2
    exit 1
fi

if [ "$CASE_END" -lt "$CASE_START" ] || [ "$CASE_END" -gt 9999 ]; then
    echo "ERROR: CASE_END must be >= CASE_START and <= 9999, got: $CASE_END" >&2
    exit 1
fi

if [ ! -f "$BASE_CONFIG" ]; then
    echo "ERROR: Base configuration file not found: $BASE_CONFIG" >&2
    exit 1
fi

echo "Base configuration: $BASE_CONFIG"
echo "Case number range: $CASE_START to $CASE_END"
echo ""

# ============================================================
# Extract Sweep Variables
# ============================================================
SWEEP_VARS=()
SWEEP_VALUES=()

# Read sweep file and extract SWEEP_* variables
while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue

    # Match SWEEP_* variables
    if [[ "$key" =~ ^[[:space:]]*SWEEP_([^=]+) ]]; then
        var_name="${BASH_REMATCH[1]}"
        # Remove inline comments and whitespace
        value=$(echo "$value" | sed 's/#.*//' | xargs)

        SWEEP_VARS+=("$var_name")
        SWEEP_VALUES+=("$value")
    fi
done < "$SWEEP_FILE"

if [ ${#SWEEP_VARS[@]} -eq 0 ]; then
    echo "ERROR: No SWEEP_* variables found in $SWEEP_FILE" >&2
    exit 1
fi

echo "Sweep variables:"
for i in "${!SWEEP_VARS[@]}"; do
    echo "  ${SWEEP_VARS[$i]} = ${SWEEP_VALUES[$i]}"
done
echo ""

# ============================================================
# Generate Parameter Combinations
# ============================================================
# Create temporary directory for generated parameter files
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sweep.XXXXXX")
trap "rm -rf $TEMP_DIR" EXIT

CASE_NUM=$CASE_START
COMBINATION_COUNT=0

# Recursive function to generate all combinations
generate_combinations() {
    local depth=$1
    shift
    local current_values=("$@")

    if [ $depth -eq ${#SWEEP_VARS[@]} ]; then
        # Base case: all variables assigned, create parameter file
        local case_file="${TEMP_DIR}/case_$(printf "%04d" $CASE_NUM).params"

        # Copy base config
        cp "$BASE_CONFIG" "$case_file"

        # Override CaseNo
        if grep -q "^CaseNo=" "$case_file"; then
            sed -i.bak "s|^CaseNo=.*|CaseNo=${CASE_NUM}|" "$case_file"
        else
            echo "CaseNo=${CASE_NUM}" >> "$case_file"
        fi
        rm -f "${case_file}.bak"

        # Override with sweep values
        for i in "${!SWEEP_VARS[@]}"; do
            local var="${SWEEP_VARS[$i]}"
            local val="${current_values[$i]}"

            if grep -q "^${var}=" "$case_file"; then
                sed -i.bak "s|^${var}=.*|${var}=${val}|" "$case_file"
            else
                echo "${var}=${val}" >> "$case_file"
            fi
            rm -f "${case_file}.bak"
        done

        ((COMBINATION_COUNT++))

        # Print summary
        if [ $DRY_RUN -eq 1 ] || [ $VERBOSE -eq 1 ]; then
            echo "Case $CASE_NUM:"
            for i in "${!SWEEP_VARS[@]}"; do
                echo "  ${SWEEP_VARS[$i]} = ${current_values[$i]}"
            done
            echo ""
        fi

        ((CASE_NUM++))
        return
    fi

    # Recursive case: iterate through values for current variable
    local values="${SWEEP_VALUES[$depth]}"
    IFS=',' read -ra value_array <<< "$values"

    for val in "${value_array[@]}"; do
        val=$(echo "$val" | xargs)  # Trim whitespace
        generate_combinations $((depth + 1)) "${current_values[@]}" "$val"
    done
}

# Start recursion
generate_combinations 0

echo "Generated $COMBINATION_COUNT parameter combinations"

# Check if number of combinations matches the range
EXPECTED_COUNT=$((CASE_END - CASE_START + 1))
if [ $COMBINATION_COUNT -ne $EXPECTED_COUNT ]; then
    echo "WARNING: Generated $COMBINATION_COUNT combinations, but CASE_END suggests $EXPECTED_COUNT" >&2
    echo "         Consider adjusting CASE_END in sweep file" >&2
fi

if [ $COMBINATION_COUNT -gt $EXPECTED_COUNT ]; then
    echo "ERROR: Too many combinations ($COMBINATION_COUNT) for range $CASE_START-$CASE_END" >&2
    exit 1
fi

echo ""

# Exit if dry run
if [ $DRY_RUN -eq 1 ]; then
    echo "Dry run complete. No simulations executed."
    exit 0
fi

# ============================================================
# Run Simulations
# ============================================================
echo "========================================="
echo "Running Simulations"
echo "========================================="

# Build list of parameter files
PARAM_FILES=()
for case_file in "$TEMP_DIR"/case_*.params; do
    PARAM_FILES+=("$case_file")
done

# Build flags to pass to runSimulation.sh
RUN_FLAGS=""
if [ $COMPILE_ONLY -eq 1 ]; then
    RUN_FLAGS="$RUN_FLAGS --compile-only"
fi
if [ $MPI_ENABLED -eq 1 ]; then
    RUN_FLAGS="$RUN_FLAGS --mpi --cores $MPI_CORES"
fi

# Run simulations sequentially (one at a time)
echo "Running $COMBINATION_COUNT simulations sequentially"
if [ $MPI_ENABLED -eq 1 ]; then
    echo "Each case will use MPI with $MPI_CORES cores"
fi
echo ""

for param_file in "${PARAM_FILES[@]}"; do
    ./runSimulation.sh $RUN_FLAGS "$param_file"
done

echo ""
echo "========================================="
echo "Parameter Sweep Complete"
echo "========================================="
echo "Total cases: $COMBINATION_COUNT"
echo "Case range: $CASE_START to $((CASE_START + COMBINATION_COUNT - 1))"
echo "Output location: simulationCases/"
echo ""
