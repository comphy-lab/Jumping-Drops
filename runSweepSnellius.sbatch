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

# ============================================================
# Jumping Drops - HPC Parameter Sweep Runner
# ============================================================
# This script runs parameter sweeps on Snellius HPC by delegating to the
# shared root runner scripts.
#
# IMPORTANT: This script runs MAIN SIMULATION ONLY (not initialization)
#
# WORKFLOW:
# 1. Local: Run initialization phase to create dumpInit
#    ./runSimulation.sh --init-only case.params
# 2. Local: Transfer dumpInit to HPC case directory
#    scp simulationCases/<CaseNo>/dumpInit hpc:Drop-Impact/simulationCases/<CaseNo>/
# 3. HPC: Run this script to execute main simulation with MPI
#    sbatch runSweepSnellius.sbatch
#
# BEFORE RUNNING:
# 1. Create dumpInit locally for each case (initialization phase)
# 2. Transfer dumpInit files to HPC case directories
# 3. Edit sweep.params to set parameter ranges and case numbers
# 4. Adjust SBATCH parameters above (especially --ntasks, --time)
# 5. Submit with: sbatch runSweepSnellius.sbatch
#
# SBATCH Parameters to Customize:
#   --ntasks: Number of MPI tasks per case (currently 48)
#   --time: Wall time for entire sweep (currently 100 hours)
#   --partition: Compute partition (currently genoa)
#   --mail-user: Email for job notifications
# Optional forwarded arguments when running directly:
#   --dry-run          Show generated cases without executing them
#   custom_sweep.params  Use a non-default sweep file
# ============================================================

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash runSweepSnellius.sbatch [runParameterSweep options] [sweep_file]

Snellius wrapper for the shared root sweep runner.
Always runs the shared sweep script in main-only MPI mode using srun.

Allowed forwarded options:
  -n, --dry-run        Show generated cases without running them
  -v, --verbose        Print extra progress information
  -c, --compile-only   Compile generated cases but do not run them
  -h, --help           Show this help message

Notes:
  - --skip-init, --mpi, and --cores are managed by this wrapper.
  - If no sweep file is given, the wrapper uses sweep.params from the submit directory.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

# ============================================================
# Configuration
# ============================================================
SCRIPT_DIR="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DEFAULT_SWEEP_FILE="${SCRIPT_DIR}/sweep.params"
RUNNER_OPTION_ARGS=()
RUNNER_SWEEP_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-init|--mpi|--cores)
            echo "ERROR: $1 is managed by runSweepSnellius.sbatch and must not be passed explicitly" >&2
            exit 1
            ;;
        --cores=*)
            echo "ERROR: --cores is managed by runSweepSnellius.sbatch and must not be passed explicitly" >&2
            exit 1
            ;;
        -*)
            RUNNER_OPTION_ARGS+=("$1")
            shift
            ;;
        *)
            if [ -n "$RUNNER_SWEEP_FILE" ]; then
                echo "ERROR: Only one sweep file may be passed to runSweepSnellius.sbatch" >&2
                exit 1
            fi
            RUNNER_SWEEP_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$RUNNER_SWEEP_FILE" ]; then
    RUNNER_SWEEP_FILE="$DEFAULT_SWEEP_FILE"
fi

# ============================================================
# Print Job Information
# ============================================================
echo "============================================="
echo "Jumping Drops - HPC Parameter Sweep"
echo "============================================="
echo "Job started at: $(date)"
echo "Running on node: $(hostname)"
echo "Project root: ${SCRIPT_DIR}"
echo "Working directory: $(pwd)"
echo "Job ID: ${SLURM_JOB_ID:-local-run}"
echo "Number of MPI tasks: ${SLURM_NTASKS:-1}"
echo "Partition: ${SLURM_JOB_PARTITION:-unknown}"
echo ""

# ============================================================
# Load Required Modules
# ============================================================
echo "Loading modules..."
if command -v module >/dev/null 2>&1; then
    module purge
    module load 2024
    module load OpenMPI/5.0.3-GCC-13.3.0
    echo "Modules loaded successfully"
else
    echo "Module command not available; skipping module setup"
fi
echo ""

# ============================================================
# Setup Basilisk Environment
# ============================================================
echo "Setting up Basilisk environment..."
if [ -f "${SCRIPT_DIR}/.project_config" ]; then
    source "${SCRIPT_DIR}/.project_config"
    echo "Basilisk environment loaded from .project_config"
    echo "BASILISK: ${BASILISK:-<unset>}"
else
    echo "ERROR: .project_config not found" >&2
    echo "       Copy .project_config.example and set the Basilisk path first." >&2
    exit 1
fi
echo ""

# ============================================================
# Validate Runner
# ============================================================
# Check sweep file exists
SWEEP_FILE="$RUNNER_SWEEP_FILE"
if [ ! -f "$SWEEP_FILE" ]; then
    echo "ERROR: Sweep file not found: $SWEEP_FILE" >&2
    exit 1
fi

if [ ! -f "${SCRIPT_DIR}/runParameterSweep.sh" ]; then
    echo "ERROR: runParameterSweep.sh not found in ${SCRIPT_DIR}" >&2
    exit 1
fi

echo "Sweep file: $SWEEP_FILE"
echo ""

# ============================================================
# Run Shared Sweep Runner
# ============================================================
echo "Delegating to runParameterSweep.sh in main-only MPI mode"
echo "MPI launcher: srun -n ${SLURM_NTASKS:-1}"
echo ""

export MPI_LAUNCHER="srun"
export MPI_LAUNCHER_NFLAG="-n"

bash "${SCRIPT_DIR}/runParameterSweep.sh" \
    --skip-init \
    --mpi \
    --cores "${SLURM_NTASKS:-1}" \
    "${RUNNER_OPTION_ARGS[@]}" \
    "$RUNNER_SWEEP_FILE"
