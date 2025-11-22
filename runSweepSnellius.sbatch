#!/bin/bash
#SBATCH --job-name=dropImpactSweep
#SBATCH --nodes=1
#SBATCH --ntasks=48
#SBATCH --cpus-per-task=1
#SBATCH --time=100:00:00
#SBATCH --partition=genoa
#SBATCH --mail-type=ALL
#SBATCH --mail-user=vatsal.sanjay@comphy-lab.org
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err
#SBATCH --chdir=/gpfs/work2/0/nctt0620/vatsal/2025-11-17-DropImpact/Drop-Impact

# ============================================================
# Drop Impact - HPC Parameter Sweep Runner
# ============================================================
# This script runs parameter sweeps on Snellius HPC.
# Each case runs sequentially but uses MPI parallelization.
#
# BEFORE RUNNING:
# 1. Edit sweep.params to set parameter ranges and case numbers
# 2. Adjust SBATCH parameters above (especially --ntasks, --time)
# 3. Submit with: sbatch runSweepSnellius.sbatch
#
# SBATCH Parameters to Customize:
#   --ntasks: Number of MPI tasks per case (currently 192)
#   --time: Wall time for entire sweep (currently 100 hours)
#   --partition: Compute partition (currently genoa)
#   --mail-user: Email for job notifications
# ============================================================

set -e  # Exit on error (but we'll handle case failures gracefully)

# ============================================================
# Configuration
# ============================================================
# Use SLURM_SUBMIT_DIR (directory where sbatch was called) as the project root
SCRIPT_DIR="${SLURM_SUBMIT_DIR}"
SWEEP_FILE="${SCRIPT_DIR}/sweep.params"

# ============================================================
# Print Job Information
# ============================================================
echo "============================================="
echo "Drop Impact - HPC Parameter Sweep"
echo "============================================="
echo "Job started at: $(date)"
echo "Running on node: $(hostname)"
echo "Working directory: $(pwd)"
echo "Job ID: ${SLURM_JOB_ID}"
echo "Number of MPI tasks: ${SLURM_NTASKS}"
echo "Partition: ${SLURM_JOB_PARTITION}"
echo ""

# ============================================================
# Load Required Modules
# ============================================================
echo "Loading modules..."
module purge
module load 2024
module load OpenMPI/5.0.3-GCC-13.3.0
echo "Modules loaded successfully"
echo ""

# ============================================================
# Setup Basilisk Environment
# ============================================================
echo "Setting up Basilisk environment..."
if [ -f "${SCRIPT_DIR}/.project_config" ]; then
    source "${SCRIPT_DIR}/.project_config"
    echo "Basilisk environment loaded from .project_config"
    echo "BASILISK: $BASILISK"
else
    echo "ERROR: .project_config not found" >&2
    exit 1
fi
echo ""

# ============================================================
# Validate Environment
# ============================================================
# Source parameter parsing library
if [ -f "${SCRIPT_DIR}/src-local/parse_params.sh" ]; then
    source "${SCRIPT_DIR}/src-local/parse_params.sh"
else
    echo "ERROR: src-local/parse_params.sh not found" >&2
    exit 1
fi

# Check sweep file exists
if [ ! -f "$SWEEP_FILE" ]; then
    echo "ERROR: Sweep file not found: $SWEEP_FILE" >&2
    exit 1
fi

echo "Sweep file: $SWEEP_FILE"
echo ""

# ============================================================
# Parse Sweep Configuration
# ============================================================
echo "Parsing sweep configuration..."

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
echo "Generating parameter combinations..."
echo "DEBUG: SCRIPT_DIR = $SCRIPT_DIR"
echo "DEBUG: Creating temp directory..."

# Create temporary directory for generated parameter files
# HPC note: Don't use /tmp - use local work directory instead
TEMP_DIR="${SCRIPT_DIR}/.sweep_tmp_$$"
echo "DEBUG: TEMP_DIR = $TEMP_DIR"

mkdir -p "$TEMP_DIR" || {
    echo "ERROR: Failed to create temp directory: $TEMP_DIR" >&2
    exit 1
}
echo "DEBUG: Temp directory created successfully"

trap "rm -rf $TEMP_DIR" EXIT

CASE_NUM=$CASE_START
COMBINATION_COUNT=0
CASE_FILES=()

# Recursive function to generate all combinations
generate_combinations() {
    echo "DEBUG: generate_combinations called with depth=$1" >&2
    local depth=$1
    shift
    local current_values=("$@")
    echo "DEBUG: depth=$depth, SWEEP_VARS array size=${#SWEEP_VARS[@]}" >&2

    if [ $depth -eq ${#SWEEP_VARS[@]} ]; then
        echo "DEBUG: Base case reached, creating case file" >&2
        # Base case: all variables assigned, create parameter file
        local case_file="${TEMP_DIR}/case_$(printf "%04d" $CASE_NUM).params"
        echo "DEBUG: case_file=$case_file" >&2
        echo "DEBUG: BASE_CONFIG=$BASE_CONFIG" >&2
        echo "DEBUG: Checking if BASE_CONFIG exists..." >&2
        ls -la "$BASE_CONFIG" >&2 || echo "DEBUG: BASE_CONFIG file not found!" >&2

        # Copy base config
        echo "DEBUG: Copying base config..." >&2
        cp "$BASE_CONFIG" "$case_file" || {
            echo "ERROR: Failed to copy $BASE_CONFIG to $case_file" >&2
            exit 1
        }
        echo "DEBUG: Copy successful" >&2

        # Override CaseNo
        echo "DEBUG: Overriding CaseNo to ${CASE_NUM}..." >&2
        if grep -q "^CaseNo=" "$case_file"; then
            echo "DEBUG: CaseNo found, using sed to replace..." >&2
            sed -i'.bak' "s|^CaseNo=.*|CaseNo=${CASE_NUM}|" "$case_file" || {
                echo "ERROR: sed failed" >&2
                exit 1
            }
            echo "DEBUG: sed completed" >&2
        else
            echo "DEBUG: CaseNo not found, appending..." >&2
            echo "CaseNo=${CASE_NUM}" >> "$case_file"
        fi
        echo "DEBUG: Removing backup file..." >&2
        rm -f "${case_file}.bak"
        echo "DEBUG: CaseNo override complete" >&2

        # Override with sweep values
        echo "DEBUG: Overriding sweep values..." >&2
        for i in "${!SWEEP_VARS[@]}"; do
            local var="${SWEEP_VARS[$i]}"
            local val="${current_values[$i]}"
            echo "DEBUG: Processing var=$var, val=$val" >&2

            if grep -q "^${var}=" "$case_file"; then
                echo "DEBUG: Found $var in file, replacing with sed..." >&2
                sed -i'.bak' "s|^${var}=.*|${var}=${val}|" "$case_file" || {
                    echo "ERROR: sed failed for $var" >&2
                    exit 1
                }
                echo "DEBUG: sed completed for $var" >&2
            else
                echo "DEBUG: $var not found, appending..." >&2
                echo "${var}=${val}" >> "$case_file"
            fi
            echo "DEBUG: Removing backup file for $var..." >&2
            rm -f "${case_file}.bak"
            echo "DEBUG: Completed $var" >&2
        done
        echo "DEBUG: All sweep values overridden" >&2

        CASE_FILES+=("$case_file")
        ((COMBINATION_COUNT++)) || true

        # Print summary
        echo "Case $CASE_NUM:"
        for i in "${!SWEEP_VARS[@]}"; do
            echo "  ${SWEEP_VARS[$i]} = ${current_values[$i]}"
        done
        echo ""

        ((CASE_NUM++)) || true
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
echo "DEBUG: About to start recursion with CASE_START=$CASE_START"
echo "DEBUG: SWEEP_VARS=(${SWEEP_VARS[@]})"
echo "DEBUG: SWEEP_VALUES=(${SWEEP_VALUES[@]})"
generate_combinations 0

echo "DEBUG: Recursion completed"
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

# ============================================================
# Run Simulations
# ============================================================
echo "============================================="
echo "Running $COMBINATION_COUNT Simulations"
echo "============================================="
echo "Each case runs with ${SLURM_NTASKS} MPI tasks"
echo ""

# Counters for tracking
SUCCESSFUL_CASES=0
FAILED_CASES=0

for param_file in "${CASE_FILES[@]}"; do
    # Parse parameter file to get CaseNo
    parse_param_file "$param_file"
    CASE_NO=$(get_param "CaseNo")

    if [ -z "$CASE_NO" ]; then
        echo "ERROR: CaseNo not found in $param_file" >&2
        ((FAILED_CASES++)) || true
        continue
    fi

    CASE_DIR="${SCRIPT_DIR}/simulationCases/${CASE_NO}"

    echo "========================================="
    echo "Case $CASE_NO ($(date))"
    echo "========================================="

    # Create case directory
    if [ ! -d "$CASE_DIR" ]; then
        echo "Creating case directory: $CASE_DIR"
        mkdir -p "$CASE_DIR"
    else
        echo "Case directory exists (will use restart if available)"
    fi

    # Copy parameter file to case directory
    cp "$param_file" "$CASE_DIR/case.params"
    echo "Parameter file copied to case directory"

    # Copy source file to case directory
    SRC_FILE_ORIG="${SCRIPT_DIR}/simulationCases/dropImpact.c"
    SRC_FILE_LOCAL="$CASE_DIR/dropImpact.c"
    EXECUTABLE="$CASE_DIR/dropImpact"

    if [ ! -f "$SRC_FILE_ORIG" ]; then
        echo "ERROR: Source file $SRC_FILE_ORIG not found" >&2
        ((FAILED_CASES++)) || true
        continue
    fi

    cp "$SRC_FILE_ORIG" "$SRC_FILE_LOCAL"
    echo "Source file copied to case directory"

    # Change to case directory for compilation
    cd "$CASE_DIR"

    # Compile with MPI
    echo "Compiling with MPI..."
    if CC99='mpicc -std=c99 -D_GNU_SOURCE=1' qcc -I../../src-local \
        -Wall -O2 -D_MPI=1 -disable-dimensions \
        dropImpact.c -o dropImpact -lm 2>&1; then
        echo "Compilation successful"
    else
        echo "ERROR: Compilation failed for case $CASE_NO" >&2
        ((FAILED_CASES++)) || true
        cd "$SCRIPT_DIR"
        continue
    fi

    # Check for restart file
    if [ -f "restart" ]; then
        echo "Restart file found - simulation will resume from checkpoint"
    fi

    # Run simulation with srun
    echo "Running simulation with ${SLURM_NTASKS} MPI tasks..."
    echo "Command: srun -n ${SLURM_NTASKS} ./dropImpact case.params"
    echo ""

    if srun -n ${SLURM_NTASKS} ./dropImpact case.params; then
        echo ""
        echo "Case $CASE_NO completed successfully"
        ((SUCCESSFUL_CASES++)) || true
    else
        EXIT_CODE=$?
        echo ""
        echo "ERROR: Case $CASE_NO failed with exit code $EXIT_CODE" >&2
        ((FAILED_CASES++)) || true
    fi

    # Return to root directory
    cd "$SCRIPT_DIR"
    echo ""
done

# ============================================================
# Final Summary
# ============================================================
echo "============================================="
echo "Parameter Sweep Complete"
echo "============================================="
echo "Job completed at: $(date)"
echo "Total cases: $COMBINATION_COUNT"
echo "Successful: $SUCCESSFUL_CASES"
echo "Failed: $FAILED_CASES"
echo "Output location: simulationCases/"
echo "============================================="
echo ""

# Exit with error if any cases failed
if [ $FAILED_CASES -gt 0 ]; then
    echo "WARNING: $FAILED_CASES case(s) failed. Check logs for details." >&2
    exit 1
fi

exit 0
